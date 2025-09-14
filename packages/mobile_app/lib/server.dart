import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/material.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;
import 'dart:math' as math;
class ServerManager {
  HttpServer? _server;
  String? _localIp;
  final int port = 8080;

  Future<String> startServer() async {
    _localIp = await _getLocalIpAddress();
    final app = _createRouter();
    final handler = const shelf.Pipeline().addMiddleware(shelf.logRequests()).addHandler(app);
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    print('Server running at http://$_localIp:$port');
await _startMdnsBroadcast();


    return 'http://$_localIp:$port';
  }

  shelf_router.Router _createRouter() {
    final router = shelf_router.Router();
    router.get('/', (Request request) => Response.ok('Desktop server is running!'));



    
    router.post('/data', (Request request) async {
      final body = await request.readAsString();
      final data = jsonDecode(body);  // e.g., {'message': 'Hello from mobile'}
      print('Received from mobile: $data');
      // Process data here (e.g., update UI state)
      return Response.ok(jsonEncode({'response': 'Ack from desktop', 'received': data}), 
                         headers: {'Content-Type': 'application/json'});
    });
    return router;
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
      print('Error getting IP: $e');
    }
    return '127.0.0.1';  // Fallback
  }


String _generatePin() {
  return (math.Random().nextInt(900000) + 100000).toString();  // 6-digit PIN
}

Future<void> _startMdnsBroadcast() async {
  final MDnsClient client = MDnsClient();
  await client.start();
  final PtrResourceRecord ptr = PtrResourceRecord('_services._dns-sd._udp.local', 0, domainName: '_myapp._tcp.local');
  final SrvResourceRecord srv = SrvResourceRecord('_myapp._tcp.local', 0, port: port, target: '$_localIp.local', priority: 1, weight: 1);
  final IPAddressResourceRecord ip = IPAddressResourceRecord('$_localIp.local', 0, address: InternetAddress(_localIp!));
  // Broadcast (simplified; in practice, respond to queries)
  // For full broadcast, use a loop to announce periodically
  Timer.periodic(Duration(seconds: 30), (timer) async {
    // Announce service
  });
  // Note: multicast_dns handles queries; this is a basic setup.
}





  Future<void> stopServer() async {
    await _server?.close();
  }





  // bool isRunning(){
  // ///TODO: implement 
  // }
}