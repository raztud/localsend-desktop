import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'settings_service.dart';

Function(String filename, List<int> fileBytes)? onFileReceivedRequest;

HttpServer? _server;
bool get isServerRunning => _server != null;
String? get serverAddress => _server?.address.host;
int? get serverPort => _server?.port;

Future<void> startServer({bool useRandomPortOnThisStart = false}) async {
  await stopServer(); // Stop existing server if any

  final settings = SettingsService();
  final host = await settings.getServerHost();
  final port = await settings.getServerPort(preferRandom: useRandomPortOnThisStart);

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(_handleRequest);

  try {
    _server = await shelf_io.serve(handler, host, port);
    print('✅ Server listening on http://${_server!.address.host}:${_server!.port}');
    // If a random port was chosen by shelf_io.serve (if you passed port 0),
    // you might want to save it back.
    if (_server!.port != port && port == 0) { // If you passed 0 to serve and it picked one
      print("ℹ️ Server started on dynamically assigned port: ${_server!.port}. You might want to save this.");
      // await settings.setServerPort(_server!.port); // Optional: save the actual port
    } else if (_server!.port == port) {
      // If the port was specified (either from settings or randomly generated before calling serve)
      // and we want to ensure this chosen port is saved for next time:
      // await settings.setServerPort(port); // Uncomment if you want to persist a chosen random port
    }

  } catch (e) {
    print('❌ Error starting server on $host:$port: $e');
    if (e is SocketException && e.osError?.errorCode == 48 /* EADDRINUSE */) {
      print("⚠️ Port $port is already in use. Trying a different random port...");
      await Future.delayed(Duration(milliseconds: 100)); // Small delay
      await startServer(useRandomPortOnThisStart: true); // Force random on retry
    }
  }
}

Future<void> stopServer() async {
  if (_server != null) {
    await _server!.close(force: true);
    _server = null;
    print('ℹ️ Server stopped.');
  }
}

Future<void> restartServer({bool useRandomPort = false}) async {
  print('🔄 Restarting server...');
  await startServer(useRandomPortOnThisStart: useRandomPort);
}


Future<Response> _handleRequest(Request request) async {
  if (request.method == 'POST' && request.url.path == 'upload') {
    final filename = request.headers['x-filename'];
    if (filename == null) {
      return Response.badRequest(body: 'Missing "x-filename" header');
    }

    final bytes = await request.read().expand((i) => i).toList();

    // Ask UI for permission
    if (onFileReceivedRequest != null) {
      // Don't await this, let the UI handle it independently
      Future.microtask(() => onFileReceivedRequest!(filename, bytes));
      return Response.ok('File received by server, awaiting user confirmation in UI.');
    } else {
      // This case should ideally not happen if main.dart sets the callback
      print('⚠️ onFileReceivedRequest callback is not set. File cannot be processed by UI.');
      return Response.internalServerError(body: 'File received, but UI callback not configured.');
    }

  }

  return Response.notFound('Not Found');
}
