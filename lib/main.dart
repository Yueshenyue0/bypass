import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const BypassApp());
}

class BypassApp extends StatelessWidget {
  const BypassApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bypass',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          BypassPage(),
          AboutPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bolt),
            label: 'bypass',
          ),
          NavigationDestination(
            icon: Icon(Icons.info_outline),
            label: '关于',
          ),
        ],
      ),
    );
  }
}

class BypassPage extends StatefulWidget {
  const BypassPage({super.key});

  @override
  State<BypassPage> createState() => _BypassPageState();
}

class _BypassPageState extends State<BypassPage> {
  static const String _baseUrl = 'https://春秋.top/bypass?url=';
  static const Duration _cooldown = Duration(minutes: 1);

  final TextEditingController _controller = TextEditingController();
  String? _resultText;
  Map<String, dynamic>? _parsedJson;
  String? _error;
  bool _loading = false;
  DateTime? _lastRequestAt;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _doRequest() async {
    final now = DateTime.now();
    if (_lastRequestAt != null &&
        now.difference(_lastRequestAt!) < _cooldown) {
      final remaining = _cooldown - now.difference(_lastRequestAt!);
      final secs = remaining.inSeconds + 1;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请求太频繁，请 ${secs}s 后再试')),
      );
      return;
    }

    final input = _controller.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入链接')),
      );
      return;
    }

    final url = Uri.parse('$_baseUrl${Uri.encodeComponent(input)}');
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await http.get(url).timeout(const Duration(seconds: 20));
      setState(() {
        _loading = false;
        _lastRequestAt = DateTime.now();
        _resultText = resp.body;
        _error = null;
        _parsedJson = null;
        try {
          final decoded = jsonDecode(resp.body);
          if (decoded is Map<String, dynamic>) {
            _parsedJson = decoded;
          }
        } catch (_) {
          _parsedJson = null;
        }
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '请求失败: $e';
      });
    }
  }

  Widget _buildJsonTree(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: value.entries.map((e) {
          return Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${e.key}: ',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
                Expanded(child: _buildJsonTree(e.value)),
              ],
            ),
          );
        }).toList(),
      );
    } else if (value is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(value.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: _buildJsonTree(value[i]),
          );
        }),
      );
    } else {
      return Text(
        value.toString(),
        style: const TextStyle(color: Colors.black87),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 30),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: '输入链接',
              hintText: '例如 https://auth.platorelay.com',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _doRequest,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_loading ? '请求中...' : '解析'),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _buildResult(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return SingleChildScrollView(
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (_resultText == null) {
      return const Center(
        child: Text('解析结果会显示在这里', style: TextStyle(color: Colors.grey)),
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_parsedJson != null) ...[
            const Text(
              'JSON 解析:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildJsonTree(_parsedJson),
            const SizedBox(height: 16),
            const Divider(),
          ],
          const Text('原始返回:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SelectableText(_resultText!),
        ],
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.person, size: 64, color: Colors.deepPurple),
          const SizedBox(height: 16),
          const Text(
            'Bypass',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('作者：eri', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          const Text('QQ：3606359397', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 24),
          TextButton.icon(
            icon: const Icon(Icons.chat),
            label: const Text('联系作者'),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('QQ：3606359397')),
              );
            },
          ),
        ],
      ),
    );
  }
}