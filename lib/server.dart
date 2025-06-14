import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'settings_service.dart';

Function(String filename, List<int> fileBytes)? onFileReceivedRequest;

HttpServer? _httpServerInstance;
bool isServerRunning() => _httpServerInstance != null;
String? getServerAddress() => _httpServerInstance?.address.host;
int? getServerPort() => _httpServerInstance?.port;

Future<void> startServer({String? host, int? portOverride}) async {
  await stopServer();

  final settings = SettingsService(); // Still useful for persisting choices
  String hostToUse = host ?? await settings.getServerHost();
  int portToUse;

  if (portOverride != null) {
    portToUse = portOverride; // Directly use the provided port (0 means random for shelf_io.serve)
  } else {
    // Fallback to settings if no override, 0 means random
    portToUse = await settings.getServerPort();
  }

  // If port is 0, shelf_io.serve will pick an available one.
  // If you need to generate random within a specific range *before* calling serve:
  if (portToUse == 0) { // If port is 0, generate a new random one
    portToUse = settings.generateRandomPortInRange(); // Use method from SettingsService
    print("ℹ️ Using newly generated random port for this start: $portToUse");
  }


  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(_handleRequest);

  try {
    _httpServerInstance = await shelf_io.serve(handler, hostToUse, portToUse);
    print('✅ Server listening on http://${_httpServerInstance!.address.host}:${_httpServerInstance!.port}');

    // Persist the actual host and port used if they were dynamically determined or different
    await settings.setServerHost(_httpServerInstance!.address.host); // Could be different if '0.0.0.0' was used
    await settings.setServerPort(_httpServerInstance!.port);

  } catch (e) {
    _httpServerInstance = null; // Ensure it's null on failure
    print('❌ Error starting server on $hostToUse:$portToUse: $e');
    if (e is SocketException && portToUse != 0 /*&& e.osError?.errorCode == 48*/) { // Port in use
      print("⚠️ Port $portToUse is already in use. Trying a different random port...");
      await Future.delayed(const Duration(milliseconds: 100));
      // Force a new random port by passing 0 as override
      await startServer(host: hostToUse, portOverride: 0);
    }
  }
}

Future<void> stopServer() async {
  if (_httpServerInstance != null) {
    await _httpServerInstance!.close(force: true);
    _httpServerInstance = null;
    print('ℹ️ Server stopped.');
  }
}

Future<void> restartServer({String? hostOverride, int? portOverride}) async {
  print('🔄 Restarting server...');
  await startServer(host: hostOverride, portOverride: portOverride);
}

Future<Response> _handleRequest(Request request) async {
  if (request.method == 'POST' && request.url.path == 'upload') {
    final filename = request.headers['x-filename'];
    if (filename == null || filename.isEmpty) {
      return Response.badRequest(body: 'Missing or empty "x-filename" header');
    }

    final List<int> bytes = await request.read().expand((chunk) => chunk).toList();

    if (bytes.isEmpty) {
      return Response.badRequest(body: 'Received empty file content');
    }
    if (onFileReceivedRequest != null) {
      Future.microtask(() => onFileReceivedRequest!(filename, bytes));
      return Response.ok('File received by server, awaiting user confirmation in UI.');
    } else {
      print('⚠️ onFileReceivedRequest callback is not set. File cannot be processed by UI.');
      return Response.internalServerError(body: 'File received, but UI callback not configured.');
    }
  }
  return Response.notFound('Not Found. Use POST to /upload with x-filename header.');
}

