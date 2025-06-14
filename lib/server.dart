import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'settings_service.dart';

Function(String filename, List<int> fileBytes)? onFileReceivedRequest;

HttpServer? _server;

Future<void> startServer() async {
  await stopServer(); // Stop existing server if any

  final settings = SettingsService();
  final host = await settings.getServerHost();
  final port = await settings.getServerPort();

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(_handleRequest);

  try {
    _server = await shelf_io.serve(handler, host, port);
    print('✅ Server listening on http://${_server!.address.host}:$port');
  } catch (e) {
    print('❌ Error starting server on $host:$port: $e');
    // Optionally, reset to defaults or notify user
  }
}

Future<void> stopServer() async {
  if (_server != null) {
    await _server!.close(force: true);
    _server = null;
    print('ℹ️ Server stopped.');
  }
}

Future<void> restartServer() async {
  print('🔄 Restarting server with new settings...');
  await startServer();
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

    return Response.ok('Request received, awaiting user confirmation');
  }

  return Response.notFound('Not Found');
}
