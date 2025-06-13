import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'server.dart'; // Make sure server.dart is in the same directory or adjust path

// Create a GlobalKey for the NavigatorState
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  // Ensure Flutter bindings are initialized if you are calling platform-specific code
  // before runApp, though in this specific setup it's not strictly necessary
  // for path_provider and server start after runApp.
  // WidgetsFlutterBinding.ensureInitialized();

  runApp(const MyApp());
  startServer(); // Assuming startServer is defined in server.dart
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _logMessage = "Waiting for files...";

  @override
  void initState() {
    super.initState();

    // Assign the callback that will be triggered by the server
    onFileReceivedRequest = (String filename, List<int> bytes) async {
      // Use the navigatorKey.currentContext, which should be valid
      // if the MaterialApp has been built.
      final BuildContext? dialogContext = navigatorKey.currentContext;

      if (dialogContext == null) {
        print("Error: Navigator context not available to show dialog for $filename.");
        if (mounted) {
          setState(() {
            _logMessage = "❌ Error: Could not show confirmation for: $filename";
          });
        }
        return;
      }

      final bool accepted = await _showConfirmationDialog(dialogContext, filename);

      if (accepted) {
        try {
          final Directory dir = await getApplicationDocumentsDirectory();
          final String filePath = '${dir.path}/$filename';
          final File file = File(filePath);
          await file.writeAsBytes(bytes);

          print("✅ File saved: $filename at $filePath"); // Log to console
          if (mounted) {
            setState(() {
              _logMessage = "✅ Saved file: $filename\nAt: $filePath";
            });
          }
        } catch (e) {
          print("❌ Error saving file $filename: $e");
          if (mounted) {
            setState(() {
              _logMessage = "❌ Error saving file $filename: $e";
            });
          }
        }
      } else {
        print("❌ File rejected: $filename");
        if (mounted) {
          setState(() {
            _logMessage = "❌ File rejected: $filename";
          });
        }
      }
    };
  }

  Future<bool> _showConfirmationDialog(BuildContext dialogContext, String filename) async {
    // Ensure the dialog is shown using the correct context
    return await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: false, // User must make a choice
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Incoming File"),
          content: Text("Do you want to accept \"$filename\"?"),
          actions: <Widget>[
            TextButton(
              child: const Text("Reject"),
              onPressed: () {
                Navigator.of(context).pop(false); // Dismiss dialog and return false
              },
            ),
            TextButton(
              child: const Text("Accept"),
              onPressed: () {
                Navigator.of(context).pop(true); // Dismiss dialog and return true
              },
            ),
          ],
        );
      },
    ) ??
        false; // If dialog is dismissed otherwise, default to false
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // Assign the GlobalKey to the MaterialApp
      title: 'File Receiver',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Receive Files'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _logMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}
