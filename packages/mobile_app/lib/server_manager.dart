// lib/server_manager.dart (Mobile, similar to desktop but without process_run and commands)
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;
import 'package:shelf_web_socket/shelf_web_socket.dart';

class ServerManager {
  HttpServer? _server;
  String? _localIp;
  final int port = 8080;
  String? _pin;
  final StreamController<String> _chatController = StreamController.broadcast();
  Stream<String> get chatStream => _chatController.stream;
  final StreamController<String> _statusController = StreamController.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  Future<void> startServer() async {
    _localIp = await _getLocalIpAddress();
    _pin = _generatePin();
    final app = _createRouter();
    final handler = const Pipeline().addMiddleware(logRequests()).addHandler(app);
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    await _startMdnsBroadcast();
    _statusController.add('Server running at http://$_localIp:$port with PIN: $_pin');
  }

  String _generatePin() {
    return (Random().nextInt(900000) + 100000).toString(); // 6-digit
  }

  Future<String> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting IP: $e');
    }
    return '127.0.0.1';
  }

  shelf_router.Router _createRouter() {
    final router = shelf_router.Router();

    router.get('/', (Request request) => Response.ok('Mobile server is running!'));

    router.post('/verify', (Request request) async {
      final body = await request.readAsString();
      final data = jsonDecode(body);
      if (data['pin'] == _pin) {
        return Response.ok(jsonEncode({'valid': true}));
      }
      return Response.forbidden(jsonEncode({'valid': false}));
    });

    router.all('/ws', webSocketHandler((webSocket, data) {
      webSocket.stream.listen((message) async {
        debugPrint('Received: $message');
        try {
          final data = jsonDecode(message);
          if (data['command'] != null) {
            // Mobile doesn't handle commands like shutdown, but can add if needed
            webSocket.sink.add(jsonEncode({'status': 'Command received: ${data['command']}'}));
          } else if (data['message'] != null) {
            _chatController.add('Peer: ${data['message']}');
            webSocket.sink.add(jsonEncode({'message': 'Echo: ${data['message']}'}));
          }
        } catch (e) {
          _chatController.add('Peer: $message');
          webSocket.sink.add('Echo: $message');
        }
      });
    }));

    router.get('/files', (Request request) async {
      final dir = await _getStorageDir();
      final files = dir.listSync().map((e) => e.path.split(Platform.pathSeparator).last).toList();
      return Response.ok(jsonEncode(files), headers: {'Content-Type': 'application/json'});
    });

    router.get('/download/<filename>', (Request request, String filename) async {
      final dir = await _getStorageDir();
      final file = File('${dir.path}${Platform.pathSeparator}$filename');
      if (await file.exists()) {
        final mimeType = lookupMimeType(filename) ?? 'application/octet-stream';
        return Response.ok(await file.readAsBytes(), headers: {'Content-Type': mimeType});
      }
      return Response.notFound('File not found');
    });

    router.post('/upload', (Request request) async {
      final boundary = request.headers['content-type']?.split('boundary=')[1];
      final transformer = MimeMultipartTransformer(boundary!);
      final parts = await request.read().transform(transformer).toList();
      for (var part in parts) {
        if (part.headers['content-disposition']!.contains('name="file"')) {
          final filename = RegExp(r'filename="([^"]*)"').firstMatch(part.headers['content-disposition']!)?.group(1);
          final dir = await _getStorageDir();
          final file = File('${dir.path}${Platform.pathSeparator}$filename');
          await file.writeAsBytes(await part.fold<List<int>>([], (p, e) => p..addAll(e)));
          _statusController.add('File uploaded: $filename');
          return Response.ok('File uploaded');
        }
      }
      return Response.badRequest(body:'No file');
    });

    return router;
  }

  Future<Directory> _getStorageDir() async => await getApplicationDocumentsDirectory();

  Future<void> _startMdnsBroadcast() async {
    final MDnsClient client = MDnsClient();
    await client.start();
    Timer.periodic(const Duration(seconds: 5), (timer) {
      // Periodic announcement
    });
  }

  Future<void> stopServer() async {
    await _server?.close();
    _chatController.close();
    _statusController.close();
  }
}