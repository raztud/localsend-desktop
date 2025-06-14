import 'dart:io';
import 'dart:typed_data'; // For Uint8List
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart'; // Import file_picker
import 'package:http/http.dart' as http; // Import http

import 'server.dart'; // Make sure server.dart is in the same directory or adjust path

// Create a GlobalKey for the NavigatorState
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(const MyApp());
  startServer(); // Start the server part of the app
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _logMessage = "Waiting for files...";
  String _sendProgressMessage = ""; // To show progress/status of sending files
  final TextEditingController _serverIpController = TextEditingController(text: '192.168.1.100'); // Default IP, change as needed
  final TextEditingController _serverPortController = TextEditingController(text: '8080'); // Default Port

  @override
  void initState() {
    super.initState();

    // --- Receiver Logic (from previous steps) ---
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

  // --- Sender Logic ---
  Future<void> _pickAndSendFiles() async {
    if (mounted) setState(() => _sendProgressMessage = "Picking files...");

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true, // Allow multiple files to be selected
      type: FileType.any, // Or specify FileType.custom with allowedExtensions
    );

    if (result != null && result.files.isNotEmpty) {
      if (mounted) {
        setState(() => _sendProgressMessage = "Preparing to send ${result.files.length} file(s)...");
      }

      final String serverIp = _serverIpController.text.trim();
      final String serverPort = _serverPortController.text.trim();

      if (serverIp.isEmpty || serverPort.isEmpty) {
        if (mounted) setState(() => _sendProgressMessage = "❌ Error: Server IP and Port cannot be empty.");
        _showSnackBar("Server IP and Port cannot be empty.");
        return;
      }

      final String serverUrl = 'http://$serverIp:$serverPort/upload';

      for (PlatformFile platformFile in result.files) {
        try {
          if (mounted) {
            setState(() => _sendProgressMessage = "Sending ${platformFile.name}...");
          }
          print("Sending file: ${platformFile.name} to $serverUrl");

          List<int>? fileBytes;
          if (platformFile.path != null) { // For mobile and desktop
            final file = File(platformFile.path!);
            fileBytes = await file.readAsBytes();
          } else if (platformFile.bytes != null) { // For web
            fileBytes = platformFile.bytes;
          }

          if (fileBytes == null) {
            print("❌ Could not read bytes for ${platformFile.name}");
            if (mounted) setState(() => _sendProgressMessage = "❌ Error reading ${platformFile.name}");
            continue; // Skip to next file
          }

          var request = http.Request('POST', Uri.parse(serverUrl));
          request.headers['x-filename'] = platformFile.name; // Send filename in header
          request.headers['Content-Type'] = 'application/octet-stream'; // Common for binary data
          request.bodyBytes = Uint8List.fromList(fileBytes); // Set the file bytes as the body

          // You can also use http.MultipartRequest if your server expects multipart/form-data
          // var request = http.MultipartRequest('POST', Uri.parse(serverUrl));
          // request.files.add(http.MultipartFile.fromBytes(
          //   'file', // Field name expected by the server
          //   fileBytes,
          //   filename: platformFile.name,
          // ));
          // request.headers['x-filename'] = platformFile.name; // Still useful if server checks this

          final response = await http.Client().send(request).timeout(const Duration(seconds: 60)); // Added timeout

          final responseBody = await response.stream.bytesToString();
          if (response.statusCode == 200) {
            print("✅ File ${platformFile.name} sent successfully. Server response: $responseBody");
            if (mounted) {
              setState(() => _sendProgressMessage = "✅ ${platformFile.name} sent!\nServer: $responseBody");
            }
          } else {
            print("❌ Error sending ${platformFile.name}: ${response.statusCode} - $responseBody");
            if (mounted) {
              setState(() => _sendProgressMessage = "❌ Error sending ${platformFile.name}: ${response.statusCode}\nServer: $responseBody");
            }
          }
        } catch (e) {
          print("❌ Exception sending ${platformFile.name}: $e");
          if (mounted) {
            setState(() => _sendProgressMessage = "❌ Exception sending ${platformFile.name}: $e");
          }
        }
      }
      if (mounted) setState(() => _sendProgressMessage = "Finished sending all selected files.");
    } else {
      // User canceled the picker
      if (mounted) setState(() => _sendProgressMessage = "File picking canceled.");
      print("File picking canceled.");
    }
  }

  void _showSnackBar(String message) {
    final SnackBar snackBar = SnackBar(content: Text(message));
    ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(snackBar);
  }

  @override
  void dispose() {
    _serverIpController.dispose();
    _serverPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'File Sharer (Sender & Receiver)',
      theme: ThemeData(
        primarySwatch: Colors.indigo, // Changed theme color a bit
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('File Sharer'),
        ),
        body: SingleChildScrollView( // To prevent overflow if content is too much
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // --- Receiver Section ---
                const Text(
                  'Receiver Status:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _logMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(height: 24),

                // --- Sender Section ---
                const Text(
                  'Send Files:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _serverIpController,
                  decoration: const InputDecoration(
                    labelText: 'Target Server IP Address',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _serverPortController,
                  decoration: const InputDecoration(
                    labelText: 'Target Server Port',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Pick and Send Files'),
                  onPressed: _pickAndSendFiles,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(height: 12),
                if (_sendProgressMessage.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _sendProgressMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}