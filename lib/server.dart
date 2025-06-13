import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Function(String filename, List<int> fileBytes)? onFileReceivedRequest;

Future<void> startServer() async {
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(_handleRequest);

  final server = await shelf_io.serve(handler, '0.0.0.0', 8080);
  print('✅ Server listening on http://${server.address.host}:${server.port}');
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
