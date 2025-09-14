import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'server.dart';

void main() {

  var isMobile = Platform.isIOS ||  Platform.isAndroid;
  runApp(
    
    isMobile? MobileApp():
    MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ServerManager _server = ServerManager();
  String? _serverUrl;

  @override
  void initState() {
    super.initState();
    _startServer();
  }

  Future<void> _startServer() async {
   var url= await _server.startServer();
    setState(() {
      _serverUrl = url;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Bridge Sky')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Server URL for mobile:'),
              Text(_serverUrl ?? 'Starting...'),
              ElevatedButton(
                onPressed: () => _server.stopServer(),
                child: Text('Stop Server'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _server.stopServer();
    super.dispose();
  }
}

class MobileApp extends StatefulWidget {
  const MobileApp({super.key});

  @override
  State<MobileApp> createState() => _MobileAppState();
}
class _MobileAppState extends State<MobileApp> {

  final TextEditingController _urlController = TextEditingController(text: 'http://192.168.1.100:8080');  // Default or user-input
  String _response = '';


final List<String> _discoveredServers = [];
String? _selectedServer;
String _enteredPin = '';
WebSocketChannel? _channel;  // For WebSocket connection

Future<void> _discoverServers() async {
  log("Loading...");
  setState(() => _discoveredServers.clear());
  try {
    final MDnsClient client = MDnsClient();
  await client.start();
  await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer('_myapp._tcp.local'))) {
    await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))) {
      await for (final IPAddressResourceRecord ip in client.lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(srv.target))) {
        final url = 'http://${ip.address.address}:${srv.port}';
        setState(() => _discoveredServers.add(url));
      }
    }
  }
  client.stop();
  } catch (e) {
      log("FINISH with Error ... $e");

  }
}


Future<void> _connectWithPin() async {
  // Send PIN to server for verification (add /verify endpoint on desktop)
  final response = await http.post(Uri.parse('$_selectedServer/verify'), body: {'pin': _enteredPin});
  if (response.statusCode == 200 && jsonDecode(response.body)['valid']) {
    // Connect WebSocket for chat/commands
    _channel = WebSocketChannel.connect(Uri.parse('ws://${_selectedServer!.replaceFirst('http://', '')}/ws'));
    // Listen for messages
    _channel!.stream.listen((message) {
      setState(() => _response = message);  // Update UI with chat responses
    });
  } else {
    setState(() => _response = 'Invalid PIN');
  }
}


  Future<void> _sendData() async {
    final url = _urlController.text;
    if (url.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse('$url/data'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': 'Hello from mobile!', 'timestamp': DateTime.now().toIso8601String()}),
      );
      if (response.statusCode == 200) {
        setState(() {
          _response = response.body;
        });
      } else {
        setState(() {
          _response = 'Error: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _response = 'Exception: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Mobile Client')),
        body: Padding(
          padding: EdgeInsets.all(16.0),
          child:
          Column(
  children: [
    ElevatedButton(onPressed: _discoverServers, child: Text('Discover Devices')),
    if (_discoveredServers.isNotEmpty)
      DropdownButton<String>(
        value: _selectedServer,
        hint: Text('Select Device'),
        items: _discoveredServers.map((url) => DropdownMenuItem(value: url, child: Text(url))).toList(),
        onChanged: (value) => setState(() => _selectedServer = value),
      ),
    if (_selectedServer != null)
      TextField(
        onChanged: (value) => _enteredPin = value,
        decoration: InputDecoration(labelText: 'Enter PIN from Desktop'),
      ),
    ElevatedButton(
      onPressed: _selectedServer != null && _enteredPin.length == 6 ? _connectWithPin : null,
      child: Text('Confirm & Connect'),
    ),
    // Existing UI...
  ],
)
          /*
          
           Column(
            children: [
              TextField(
                controller: _urlController,
                decoration: InputDecoration(labelText: 'Desktop Server URL'),
              ),
              ElevatedButton(
                onPressed: _sendData,
                child: Text('Send Data'),
              ),
              SizedBox(height: 20),
              Text('Response: $_response'),
            ],
          ),
       */
       
        ),
      ),
    );
  }
}