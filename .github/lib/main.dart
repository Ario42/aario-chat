import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

/// Public relay used as the "server". No account or setup needed.
/// If it is blocked on your network, change it to another ntfy server.
const String kServer = 'https://ntfy.sh';

/// Secret room name. Anyone who knows it can read the chat, so keep it private.
const String kTopic = 'ario-azar-906pdr7lpulk7fs1e1yqnobaypv9';

/// The only two accounts that can log in.
const Map<String, String> kUsers = {
  'ario': 'ario1388',
  'azar': 'azar1364',
};

const int kMaxStoredMessages = 500;

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class ChatMessage {
  final String id;
  final String from;
  final String text;
  final int ts;

  ChatMessage({
    required this.id,
    required this.from,
    required this.text,
    required this.ts,
  });

  Map<String, dynamic> toJson() => {'id': id, 'from': from, 'text': text, 'ts': ts};

  static ChatMessage? fromJson(dynamic j) {
    if (j is! Map) return null;
    final id = j['id'];
    final from = j['from'];
    final text = j['text'];
    final ts = j['ts'];
    if (id is! String || from is! String || text is! String || ts is! int) {
      return null;
    }
    if (!kUsers.containsKey(from)) return null;
    return ChatMessage(id: id, from: from, text: text, ts: ts);
  }
}

// ---------------------------------------------------------------------------
// Chat service (send + live receive through ntfy)
// ---------------------------------------------------------------------------

class ChatService {
  final void Function(ChatMessage) onMessage;
  final void Function(bool) onStatus;

  http.Client? _client;
  bool _running = false;
  String _since = 'all';

  ChatService({required this.onMessage, required this.onStatus});

  Future<void> start() async {
    _running = true;
    while (_running) {
      try {
        _client = http.Client();
        final req = http.Request(
          'GET',
          Uri.parse('$kServer/$kTopic/json?since=$_since'),
        );
        final resp = await _client!.send(req).timeout(const Duration(seconds: 20));
        if (resp.statusCode != 200) {
          throw Exception('status ${resp.statusCode}');
        }
        onStatus(true);
        await for (final line in resp.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (!_running) break;
          if (line.trim().isEmpty) continue;
          try {
            final ev = jsonDecode(line);
            if (ev is Map && ev['event'] == 'message') {
              if (ev['id'] is String) _since = ev['id'] as String;
              final body = ev['message'];
              if (body is String) {
                final msg = ChatMessage.fromJson(jsonDecode(body));
                if (msg != null) onMessage(msg);
              }
            }
          } catch (_) {
            // ignore malformed lines
          }
        }
      } catch (_) {
        // fall through to reconnect
      } finally {
        _client?.close();
        _client = null;
      }
      if (_running) {
        onStatus(false);
        await Future.delayed(const Duration(seconds: 3));
      }
    }
  }

  void stop() {
    _running = false;
    _client?.close();
  }

  Future<bool> send(ChatMessage m) async {
    try {
      final r = await http
          .post(
            Uri.parse('$kServer/$kTopic'),
            headers: {'Content-Type': 'text/plain; charset=utf-8'},
            body: jsonEncode(m.toJson()),
          )
          .timeout(const Duration(seconds: 15));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ArioChatApp());
}

class ArioChatApp extends StatelessWidget {
  const ArioChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ario Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2E7D6B),
      ),
      home: const Gate(),
    );
  }
}

/// Decides between login screen and chat screen (remembers the login).
class Gate extends StatefulWidget {
  const Gate({super.key});

  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  String? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final p = await SharedPreferences.getInstance();
    final u = p.getString('user');
    setState(() {
      _user = (u != null && kUsers.containsKey(u)) ? u : null;
      _loading = false;
    });
  }

  Future<void> _login(String user) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('user', user);
    setState(() => _user = user);
  }

  Future<void> _logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('user');
    setState(() => _user = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_user == null) return LoginScreen(onLogin: _login);
    return ChatScreen(user: _user!, onLogout: _logout);
  }
}

// ---------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------

class LoginScreen extends StatefulWidget {
  final Future<void> Function(String user) onLogin;
  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtl = TextEditingController();
  final _passCtl = TextEditingController();
  String? _error;

  void _submit() {
    final u = _userCtl.text.trim().toLowerCase();
    final p = _passCtl.text;
    if (kUsers[u] != null && kUsers[u] == p) {
      widget.onLogin(u);
    } else {
      setState(() => _error = 'نام کاربری یا رمز عبور اشتباه است');
    }
  }

  @override
  void dispose() {
    _userCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.chat_bubble_rounded,
                      size: 72, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  const Text(
                    'Ario Chat',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _userCtl,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passCtl,
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text('Login', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat
// ---------------------------------------------------------------------------

class ChatScreen extends StatefulWidget {
  final String user;
  final VoidCallback onLogout;
  const ChatScreen({super.key, required this.user, required this.onLogout});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final Set<String> _ids = {};
  final _inputCtl = TextEditingController();
  late final ChatService _service;
  bool _online = false;
  Timer? _saveTimer;

  String get _other => widget.user == 'ario' ? 'azar' : 'ario';

  @override
  void initState() {
    super.initState();
    _service = ChatService(onMessage: _add, onStatus: _setOnline);
    _loadHistory().then((_) => _service.start());
  }

  @override
  void dispose() {
    _service.stop();
    _saveTimer?.cancel();
    _inputCtl.dispose();
    super.dispose();
  }

  void _setOnline(bool v) {
    if (mounted) setState(() => _online = v);
  }

  Future<void> _loadHistory() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('history');
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      for (final j in list) {
        final m = ChatMessage.fromJson(j);
        if (m != null && _ids.add(m.id)) _messages.add(m);
      }
      _messages.sort((a, b) => a.ts.compareTo(b.ts));
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () async {
      final p = await SharedPreferences.getInstance();
      final recent = _messages.length > kMaxStoredMessages
          ? _messages.sublist(_messages.length - kMaxStoredMessages)
          : _messages;
      await p.setString(
          'history', jsonEncode(recent.map((m) => m.toJson()).toList()));
    });
  }

  void _add(ChatMessage m) {
    if (!_ids.add(m.id)) return;
    if (!mounted) return;
    setState(() {
      _messages.add(m);
      _messages.sort((a, b) => a.ts.compareTo(b.ts));
    });
    _scheduleSave();
  }

  String _newId() {
    final r = Random.secure();
    final rand = List.generate(6, (_) => r.nextInt(36).toRadixString(36)).join();
    return '${DateTime.now().microsecondsSinceEpoch}-$rand';
  }

  Future<void> _send() async {
    final text = _inputCtl.text.trim();
    if (text.isEmpty) return;
    _inputCtl.clear();
    final m = ChatMessage(
      id: _newId(),
      from: widget.user,
      text: text,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    _add(m); // show immediately
    final ok = await _service.send(m);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ارسال نشد؛ اینترنت را بررسی کنید')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final reversed = _messages.reversed.toList();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              child: Text(_other[0].toUpperCase()),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_other, style: const TextStyle(fontSize: 17)),
                Text(
                  _online ? 'connected' : 'connecting...',
                  style: TextStyle(
                    fontSize: 12,
                    color: _online ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: widget.onLogout,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: reversed.isEmpty
                ? const Center(child: Text('هنوز پیامی نیست'))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    itemCount: reversed.length,
                    itemBuilder: (_, i) => _Bubble(
                      msg: reversed[i],
                      mine: reversed[i].from == widget.user,
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtl,
                      minLines: 1,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: 'پیام...',
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage msg;
  final bool mine;
  const _Bubble({required this.msg, required this.mine});

  static bool _isRtl(String s) =>
      RegExp(r'[֐-ࣿﭐ-﷿ﹰ-﻿]').hasMatch(s);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = DateTime.fromMillisecondsSinceEpoch(msg.ts);
    final time =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final rtl = _isRtl(msg.text);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: mine ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment:
                  rtl ? Alignment.centerRight : Alignment.centerLeft,
              child: Text(
                msg.text,
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 2),
            Text(time,
                style: TextStyle(
                    fontSize: 11, color: cs.onSurface.withOpacity(0.55))),
          ],
        ),
      ),
    );
  }
}
