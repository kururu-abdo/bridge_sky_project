// lib/main.dart (Mobile, updated with server and symmetric features)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'server_manager.dart';

void main() {
  runApp(const MobileApp());
}

class MobileApp extends StatelessWidget {
  const MobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile Client',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[100],
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      ),
      home: const MobileHomePage(),
    );
  }
}

class MobileHomePage extends StatefulWidget {
  const MobileHomePage({super.key});

  @override
  State<MobileHomePage> createState() => _MobileHomePageState();
}

class _MobileHomePageState extends State<MobileHomePage> {
  final ServerManager _server = ServerManager();
  String _status = 'Starting...';
  final List<String> _chatMessages = [];
  late StreamSubscription _chatSub;
  late StreamSubscription _statusSub;
  List<String> _discoveredPeers = [];
  String? _selectedPeer;
  final TextEditingController _pinController = TextEditingController();
  String? _peerUrl;
  final TextEditingController _messageController = TextEditingController();
  WebSocketChannel? _channel;
  List<String> _localFiles = [];
  List<String> _peerFiles = [];
  String _response = '';

  @override
  void initState() {
    super.initState();
    _server.startServer();
    _statusSub = _server.statusStream.listen((msg) {
      setState(() => _status = msg);
    });
    _chatSub = _server.chatStream.listen((msg) {
      setState(() => _chatMessages.add(msg));
    });
  }

  Future<void> _discoverPeers() async {
    setState(() => _discoveredPeers.clear());
    final MDnsClient client = MDnsClient();
    await client.start();
    await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer('_myapp._tcp.local'))) {
      await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))) {
        await for (final IPAddressResourceRecord ip in client.lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(srv.target))) {
          final url = 'http://${ip.address.address}:${srv.port}';
          if (!_discoveredPeers.contains(url)) {
            setState(() => _discoveredPeers.add(url));
          }
        }
      }
    }
    client.stop();
  }

  Future<void> _connectToPeer() async {
    final pin = _pinController.text;
    if (pin.length != 6 || _selectedPeer == null) return;
    try {
      final response = await http.post(
        Uri.parse('$_selectedPeer/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'pin': pin}),
      );
      if (response.statusCode == 200 && jsonDecode(response.body)['valid']) {
        setState(() {
          _peerUrl = _selectedPeer;
          _response = 'Connected to peer!';
        });
        final wsUrl = 'ws://${_selectedPeer!.replaceFirst('http://', '')}/ws';
        _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
        _chatSub = _channel!.stream.listen((message) {
          setState(() => _chatMessages.add('Peer: $message'));
        });
      } else {
        setState(() => _response = 'Invalid PIN');
      }
    } catch (e) {
      setState(() => _response = 'Connection error: $e');
    }
  }

  void _sendMessage() {
    if (_channel != null && _messageController.text.isNotEmpty) {
      _channel!.sink.add(jsonEncode({'message': _messageController.text}));
      setState(() => _chatMessages.add('Me: ${_messageController.text}'));
      _messageController.clear();
    }
  }

  void _sendCommand(String command) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({'command': command}));
    }
  }

  Future<void> _uploadFileToPeer() async {
    if (_peerUrl == null) return;
    final result = await FilePicker.platform.pickFiles();
    if (result != null) {
      final file = result.files.first;
      var request = http.MultipartRequest('POST', Uri.parse('$_peerUrl/upload'));
      request.files.add(await http.MultipartFile.fromPath('file', file.path!));
      final response = await request.send();
      setState(() => _response = 'Upload to peer status: ${response.statusCode}');
    }
  }

  Future<void> _listLocalFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    setState(() => _localFiles = dir.listSync().map((e) => e.path.split(Platform.pathSeparator).last).toList());
  }

  Future<void> _listPeerFiles() async {
    if (_peerUrl == null) return;
    final response = await http.get(Uri.parse('$_peerUrl/files'));
    if (response.statusCode == 200) {
      setState(() => _peerFiles = List<String>.from(jsonDecode(response.body)));
    }
  }

  Future<void> _downloadFromPeer(String filename) async {
    if (_peerUrl == null) return;
    final response = await http.get(Uri.parse('$_peerUrl/download/$filename'));
    if (response.statusCode == 200) {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(response.bodyBytes);
      setState(() => _response = 'Downloaded from peer: $filename');
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _messageController.dispose();
    _chatSub.cancel();
    _statusSub.cancel();
    _channel?.sink.close();
    _server.stopServer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mobile App'),
        actions: [
          IconButton(
            icon: const Icon(Icons.stop),
            onPressed: _server.stopServer,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text('Status:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_status),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.search),
                      label: const Text('Discover Peers'),
                      onPressed: _discoverPeers,
                    ),
                    if (_discoveredPeers.isNotEmpty)
                      DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedPeer,
                        hint: const Text('Select Peer'),
                        items: _discoveredPeers.map((url) => DropdownMenuItem(value: url, child: Text(url))).toList(),
                        onChanged: (value) => setState(() => _selectedPeer = value),
                      ),
                    if (_selectedPeer != null)
                      TextField(
                        controller: _pinController,
                        decoration: const InputDecoration(labelText: 'Enter 6-digit PIN'),
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                      ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.link),
                      label: const Text('Connect to Peer'),
                      onPressed: _connectToPeer,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text('Chat', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    SizedBox(
                      height: 200,
                      child: ListView.builder(
                        itemCount: _chatMessages.length,
                        itemBuilder: (context, index) => ListTile(title: Text(_chatMessages[index])),
                      ),
                    ),
                    TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(labelText: 'Message'),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.send),
                      label: const Text('Send'),
                      onPressed: _sendMessage,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text('Controls (Send to Peer)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.power_settings_new),
                          label: const Text('Shutdown Peer'),
                          onPressed: () => _sendCommand('shutdown'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.bedtime),
                          label: const Text('Sleep Peer'),
                          onPressed: () => _sendCommand('sleep'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text('File Sharing', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Send File to Peer'),
                      onPressed: _uploadFileToPeer,
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('List Local Files'),
                      onPressed: _listLocalFiles,
                    ),
                    if (_localFiles.isNotEmpty)
                      SizedBox(
                        height: 150,
                        child: ListView.builder(
                          itemCount: _localFiles.length,
                          itemBuilder: (context, index) => ListTile(
                            title: Text(_localFiles[index]),
                          ),
                        ),
                      ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('List Peer Files'),
                      onPressed: _listPeerFiles,
                    ),
                    if (_peerFiles.isNotEmpty)
                      SizedBox(
                        height: 150,
                        child: ListView.builder(
                          itemCount: _peerFiles.length,
                          itemBuilder: (context, index) => ListTile(
                            title: Text(_peerFiles[index]),
                            trailing: IconButton(
                              icon: const Icon(Icons.download),
                              onPressed: () => _downloadFromPeer(_peerFiles[index]),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Status: $_response', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}