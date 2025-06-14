import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import 'server.dart';
import 'settings_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Needed for SharedPreferences before runApp
  await startServer(); // Start server with stored/default settings
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _logMessage = "Waiting for files...";
  String _sendProgressMessage = "";
  final TextEditingController _clientTargetIpController = TextEditingController(text: '192.168.1.100');
  final TextEditingController _clientTargetPortController = TextEditingController(text: '8080');

  final SettingsService _settingsService = SettingsService();
  late TextEditingController _serverListenIpController;
  late TextEditingController _serverListenPortController;
  String _currentServerStatus = "Loading server settings...";
  bool _useRandomPortForServer = false;

  @override
  void initState() {
    super.initState();
    _serverListenIpController = TextEditingController();
    _serverListenPortController = TextEditingController();
    _loadServerSettingsAndStatus();

    onFileReceivedRequest = (String filename, List<int> bytes) async {
      final BuildContext? dialogContext = navigatorKey.currentContext;
      if (dialogContext == null) {
        print("Error: Navigator context not available to show dialog for $filename.");
        if (mounted) setState(() => _logMessage = "❌ Error: Could not show confirmation for: $filename");
        return;
      }
      final bool accepted = await _showConfirmationDialog(dialogContext, filename);
      if (accepted) {
        try {
          final Directory dir = await getApplicationDocumentsDirectory();
          final String filePath = '${dir.path}/$filename';
          final File file = File(filePath);
          await file.writeAsBytes(bytes);
          print("✅ File saved: $filename at $filePath");
          if (mounted) setState(() => _logMessage = "✅ Saved file: $filename\nAt: $filePath");
        } catch (e) {
          print("❌ Error saving file $filename: $e");
          if (mounted) setState(() => _logMessage = "❌ Error saving file $filename: $e");
        }
      } else {
        print("❌ File rejected: $filename");
        if (mounted) setState(() => _logMessage = "❌ File rejected: $filename");
      }
    };
  }

  Future<void> _loadServerSettingsAndStatus() async {
    final host = await _settingsService.getServerHost();
    final port = await _settingsService.getServerPort();
    if (mounted) {
      setState(() {
        _serverListenIpController.text = host;
        if (port == 0) {
          _serverListenPortController.text = ""; // Clear it or set placeholder
          _useRandomPortForServer = true; // Check the box
        } else {
          _serverListenPortController.text = port.toString();
          _useRandomPortForServer = false;
        }
        _updateServerStatusMessage();
      });
    }
  }


  void _updateServerStatusMessage() {
    // This needs to be more robust. The actual listening port is in _server.port after server starts.
    // This is just a predictive message.
    if (!isServerRunning) {
      _currentServerStatus = "Server is stopped.";
    } else {
      _currentServerStatus = "Server listening on http://$serverAddress:$serverPort";
    }
  }

  Future<void> _saveServerSettingsAndRestart() async {
    final String newHost = _serverListenIpController.text.trim();
    int? newPort;

    if (_useRandomPortForServer) {
      await _settingsService.setServerPortToRandom(); // Signal to use random on next generic start
      newPort = 0; // Convention for "pick random"
      print("ℹ️ Server will use a random port on next start.");
    } else {
      newPort = int.tryParse(_serverListenPortController.text.trim());
      if (newPort == null || newPort <= 0 || newPort > 65535) {
        _showSnackBar("Invalid port number. Must be between 1 and 65535.");
        return;
      }
      await _settingsService.setServerPort(newPort);
    }

    if (newHost.isEmpty) {
      _showSnackBar("Server IP/Host cannot be empty. Use '0.0.0.0' to listen on all interfaces.");
      return;
    }
    await _settingsService.setServerHost(newHost);

    if (mounted) {
      setState(() {
        _currentServerStatus = "Restarting server with new settings...";
      });
    }
    // Pass the explicit desire for random if the checkbox is checked for *this specific restart*
    await restartServer(useRandomPort: _useRandomPortForServer);
    // After server starts, _server.port will have the actual port
    if (mounted) {
      setState(() {
        _loadServerSettingsAndStatus(); // Reload and update UI to show actual port
      });
    }
    _showSnackBar("Server settings saved and server (re)started.");
  }

  Future<bool> _showConfirmationDialog(BuildContext dialogContext, String filename) async {
    return await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Incoming File"),
          content: Text("Do you want to accept \"$filename\"?"),
          actions: <Widget>[
            TextButton(
                child: const Text("Reject"),
                onPressed: () => Navigator.of(context).pop(false)),
            TextButton(
                child: const Text("Accept"),
                onPressed: () => Navigator.of(context).pop(true)),
          ],
        );
      },
    ) ??
        false;
  }

  Future<void> _pickAndSendFiles() async {
    if (mounted) setState(() => _sendProgressMessage = "Picking files...");

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );

    if (result != null && result.files.isNotEmpty) {
      if (mounted) {
        setState(() => _sendProgressMessage = "Preparing to send ${result.files.length} file(s)...");
      }

      final String serverIp = _clientTargetIpController.text.trim(); // Use client controller
      final String serverPort = _clientTargetPortController.text.trim(); // Use client controller

      if (serverIp.isEmpty || serverPort.isEmpty) {
        if (mounted) setState(() => _sendProgressMessage = "❌ Error: Target Server IP and Port cannot be empty.");
        _showSnackBar("Target Server IP and Port cannot be empty.");
        return;
      }

      final String serverUrl = 'http://$serverIp:$serverPort/upload';

      for (PlatformFile platformFile in result.files) {
        try {
          if (mounted) {
            setState(() => _sendProgressMessage = "Sending ${platformFile.name}...");
          }
          List<int>? fileBytes;
          if (platformFile.path != null) {
            final file = File(platformFile.path!);
            fileBytes = await file.readAsBytes();
          } else if (platformFile.bytes != null) {
            fileBytes = platformFile.bytes;
          }

          if (fileBytes == null) {
            if (mounted) setState(() => _sendProgressMessage = "❌ Error reading ${platformFile.name}");
            continue;
          }

          var request = http.Request('POST', Uri.parse(serverUrl));
          request.headers['x-filename'] = platformFile.name;
          request.headers['Content-Type'] = 'application/octet-stream';
          request.bodyBytes = Uint8List.fromList(fileBytes);

          final response = await http.Client().send(request).timeout(const Duration(seconds: 60));
          final responseBody = await response.stream.bytesToString();

          if (response.statusCode == 200) {
            if (mounted) setState(() => _sendProgressMessage = "✅ ${platformFile.name} sent!\nServer: $responseBody");
          } else {
            if (mounted) setState(() => _sendProgressMessage = "❌ Error sending ${platformFile.name}: ${response.statusCode}\nServer: $responseBody");
          }
        } catch (e) {
          if (mounted) setState(() => _sendProgressMessage = "❌ Exception sending ${platformFile.name}: $e");
        }
      }
      if (mounted) setState(() => _sendProgressMessage = "Finished sending all selected files.");
    } else {
      if (mounted) setState(() => _sendProgressMessage = "File picking canceled.");
    }
  }

  void _showSnackBar(String message) {
    final SnackBar snackBar = SnackBar(content: Text(message));
    ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(snackBar);
  }


  @override
  void dispose() {
    _clientTargetIpController.dispose();
    _clientTargetPortController.dispose();
    _serverListenIpController.dispose();
    _serverListenPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'File Sharer (Sender & Receiver)',
      theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('File Sharer')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // --- Server Settings Section ---
              const Text('Server Settings (This App as Receiver):', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _serverListenIpController,
                decoration: const InputDecoration(
                  labelText: 'Listen on IP/Host (e.g., 0.0.0.0)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _serverListenPortController,
                decoration: const InputDecoration(
                  labelText: 'Listen on Port (e.g., 8080)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _saveServerSettingsAndRestart,
                child: const Text('Save Settings & Restart Server'),
              ),
              const SizedBox(height: 8),
              Text(_currentServerStatus, textAlign: TextAlign.center),
              const Divider(height: 32, thickness: 1),

              // --- Receiver Status Section ---
              const Text('Receiver Status:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
                child: Text(_logMessage, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 24),

              // --- Sender Section (Client) ---
              const Text('Send Files To:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _clientTargetIpController, // Renamed for clarity
                decoration: const InputDecoration(labelText: 'Target Server IP Address', border: OutlineInputBorder()),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _clientTargetPortController, // Renamed for clarity
                decoration: const InputDecoration(labelText: 'Target Server Port', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('Pick and Send Files'),
                onPressed: _pickAndSendFiles,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), textStyle: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 12),
              if (_sendProgressMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
                  child: Text(_sendProgressMessage, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}