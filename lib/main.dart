import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';

import 'server.dart';
import 'settings_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Needed for SharedPreferences before runApp
  // await startServer(); // Start server with stored/default settings
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
  // late TextEditingController _serverListenIpController;
  late TextEditingController _serverListenPortController;
  String _currentServerStatus = "Server not started...";
  bool _useRandomPortForServer = true;

  List<String> _availableIpAddresses = [];
  String? _selectedServerIp;
  bool _isLoadingIps = true;
  final NetworkInfo _networkInfo = NetworkInfo();

  @override
  void initState() {
    super.initState();
    _serverListenPortController = TextEditingController();
    _fetchNetworkInterfaces();
    _loadServerSettingsAndPortPreference();

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

  Future<void> _fetchNetworkInterfaces({bool selectFirst = false, String? preselectIp}) async {
    if (!mounted) return;
    setState(() {
      _isLoadingIps = true;
    });
    List<String> ips = [];
    try {
      // Always add 0.0.0.0 as an option to listen on all interfaces
      ips.add('0.0.0.0');

      // Get device's Wi-Fi IP (most common for local sharing)
      final wifiIP = await _networkInfo.getWifiIP();
      if (wifiIP != null && wifiIP.isNotEmpty && !ips.contains(wifiIP)) {
        ips.add(wifiIP);
      }
      // Note: network_info_plus primarily gives the main Wi-Fi IP.
      // For a more exhaustive list of all interface IPs (like on desktop),
      // you might need to use platform channels or other plugins like `dart_ping`'s
      // underlying mechanisms if they expose raw interface data, or specific desktop packages.
      // For mobile, getWifiIP() and '0.0.0.0' are usually sufficient.

    } catch (e) {
      print("Failed to get IP addresses: $e");
      if (mounted) _showSnackBar("Could not fetch network IP addresses.");
    }

    if (!mounted) return;
    setState(() {
      _availableIpAddresses = ips.toSet().toList(); // Ensure unique IPs
      if (preselectIp != null && _availableIpAddresses.contains(preselectIp)) {
        _selectedServerIp = preselectIp;
      } else if (selectFirst && _availableIpAddresses.isNotEmpty) {
        _selectedServerIp = _availableIpAddresses.first;
      } else if (_availableIpAddresses.isNotEmpty && !_availableIpAddresses.contains(_selectedServerIp)) {
        // If current selection is no longer valid, try to select 0.0.0.0 or first available
        _selectedServerIp = _availableIpAddresses.contains('0.0.0.0') ? '0.0.0.0' : _availableIpAddresses.first;
      }
      _isLoadingIps = false;
      _updateServerStatusMessage(); // Update status after IPs are loaded
    });
  }

  Future<void> _loadServerSettingsAndPortPreference() async {
    final storedHost = await _settingsService.getServerHost();
    final storedPort = await _settingsService.getServerPort();

    await _fetchNetworkInterfaces(preselectIp: storedHost);

    if (mounted) {
      setState(() {
        if (storedPort == 0) { // Indicates random or not set meaningfully
          _serverListenPortController.clear();
          _useRandomPortForServer = true;
        } else {
          _serverListenPortController.text = storedPort.toString();
          _useRandomPortForServer = false;
        }

        if (_selectedServerIp != null && _selectedServerIp!.isNotEmpty) {
          _startServerWithCurrentSettings();
        } else {
          _currentServerStatus = "Select a server IP to start.";
        }
        // _updateServerStatusMessage(); // This is called within _startServerWithCurrentSettings or if it doesn't start
      });
    }
  }


  void _updateServerStatusMessage() {
    if (!mounted) return;

    setState(() {
      if (!isServerRunning()) { // Use the getter from server.dart
        _currentServerStatus = _selectedServerIp == null || _selectedServerIp!.isEmpty
            ? "Server not started. Select IP."
            : "Server stopped. Ready to start on $_selectedServerIp.";
      } else {
        _currentServerStatus = "Server listening on http://${getServerAddress()}:${getServerPort()}";
      }
    });
  }

  Future<void> _startServerWithCurrentSettings() async {
    if (_selectedServerIp == null || _selectedServerIp!.isEmpty) {
      _showSnackBar("Please select a valid Server IP address.");
      _updateServerStatusMessage();
      return;
    }

    int? portToPassToServer;
    if (_useRandomPortForServer) {
      portToPassToServer = 0; // Server will pick a random one
    } else {
      final String portText = _serverListenPortController.text.trim();
      if (portText.isEmpty) {
        _showSnackBar("Port cannot be empty when 'Use Random Port' is unchecked. Please enter a port or select random.");
        _updateServerStatusMessage();
        return;
      }
      final int? enteredPort = int.tryParse(portText);

      if (enteredPort == null || enteredPort <= 0 || enteredPort > 65535) {
        _showSnackBar("Invalid port. Please enter a number between 1 and 65535, or select random.");
        _updateServerStatusMessage(); // Ensure status reflects that server didn't start
        return;
      }
      portToPassToServer = enteredPort;
    }

    if (mounted) {
      setState(() {
        _currentServerStatus = "Starting server on $_selectedServerIp (port: ${portToPassToServer == 0 ? 'Random' : portToPassToServer})...";
      });
    }

    await startServer(
      host: _selectedServerIp!,
      portOverride: portToPassToServer,
    );
    _updateServerStatusMessage(); // Update with actual listening address and port
  }


  Future<void> _saveServerSettingsAndRestart() async {
    if (_selectedServerIp == null || _selectedServerIp!.isEmpty) {
      _showSnackBar("Please select a Server IP address.");
      return;
    }

    final String newHost = _selectedServerIp!;
    int portToSaveAndPass; // Port to save in settings and pass to server

    await _settingsService.setServerHost(newHost);

    if (_useRandomPortForServer) {
      // Save 0 to settings to indicate random for next app launch
      await _settingsService.setServerPort(0);
      portToSaveAndPass = 0; // Tell server.dart to pick a new random one for this restart
    } else {
      final String portText = _serverListenPortController.text.trim();
      if (portText.isEmpty) {
        _showSnackBar("Port cannot be empty when 'Use Random Port' is unchecked. Please enter a port or select random to save.");
        return;
      }
      final int? enteredPort = int.tryParse(portText);
      if (enteredPort == null || enteredPort <= 0 || enteredPort > 65535) {
        _showSnackBar("Invalid port. Please enter a number between 1 and 65535, or select random.");
        return;
      }
      portToSaveAndPass = enteredPort;
      await _settingsService.setServerPort(portToSaveAndPass); // Save the specific port
    }

    // ... (setState for restarting message)
    if (mounted) {
      setState(() {
        _currentServerStatus = "Restarting server with new settings...";
      });
    }

    await restartServer(
      hostOverride: newHost,
      portOverride: portToSaveAndPass,
    );
    _updateServerStatusMessage(); // Update with actual details
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
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Listen on IP Address',
                        border: OutlineInputBorder(),
                      ),
                      value: _selectedServerIp,
                      items: _availableIpAddresses.map((String ip) {
                        return DropdownMenuItem<String>(
                          value: ip,
                          child: Text(ip),
                        );
                      }).toList(),
                      onChanged: _isLoadingIps ? null : (String? newValue) {
                        setState(() {
                          _selectedServerIp = newValue;
                          // If server is running and IP changes, it should be restarted
                          if (isServerRunning()) {
                            _saveServerSettingsAndRestart();
                          } else {
                            _updateServerStatusMessage();
                          }
                        });
                      },
                      hint: Text(_isLoadingIps ? 'Loading IPs...' : 'Select IP'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh IP Addresses',
                    onPressed: () => _fetchNetworkInterfaces(selectFirst: false, preselectIp: _selectedServerIp),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _serverListenPortController,
                decoration: InputDecoration(
                  labelText: 'Listen on Port',
                  border: OutlineInputBorder(),
                  hintText: _useRandomPortForServer ? "Random" : "1-65535",
                ),
                keyboardType: TextInputType.number,
                enabled: !_useRandomPortForServer,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: _useRandomPortForServer,
                    onChanged: (bool? value) {
                      setState(() {
                        _useRandomPortForServer = value ?? false;
                        if (_useRandomPortForServer) {
                          _serverListenPortController.clear();
                        } else {
                          // When unchecking "Use Random Port"
                          _settingsService.getServerPort().then((storedPort) {
                            if (storedPort != 0) { // If there was a specific port saved
                              _serverListenPortController.text = storedPort.toString();
                            } else {
                              _serverListenPortController.clear(); // Ensure it's clear for user input
                            }
                          });
                        }
                        // If server is running and port preference changes, it should be restarted
                        if (isServerRunning()) {
                          _saveServerSettingsAndRestart();
                        } else {
                          _updateServerStatusMessage();
                        }
                      });
                    },
                  ),
                  const Text('Use Random Port (49152-65535)'),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _selectedServerIp == null || _selectedServerIp!.isEmpty
                    ? null // Disable button if no IP selected
                    : (isServerRunning() ? _saveServerSettingsAndRestart : _startServerWithCurrentSettings),
                child: Text(isServerRunning() ? 'Save & Restart Server' : 'Start Server'),
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
                controller: _clientTargetIpController,
                decoration: const InputDecoration(labelText: 'Target Server IP Address', border: OutlineInputBorder()),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _clientTargetPortController,
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