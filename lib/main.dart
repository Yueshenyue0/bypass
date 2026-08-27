import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:vpn_connection_detector/vpn_connection_detector.dart';
import 'package:connectivity_plus/connectivity_plus.dart' as cc;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BypassApp());
}

/// 强安全检测：VPN / 代理 / Frida / Xposed / 注入 / 调试特征
class SecurityChecker {
  SecurityChecker._();

  static const List<int> _fridaPorts = [27042, 27043, 27044, 27045];
  static const List<String> _mapsSignatures = [
    'frida', 'gum-js-loop', 'gmain', 'linjector', 'xposed',
    'XposedBridge', 'substrate', 'Substrate', 'riru', 'zygisk',
    'lsposed', 'edxposed', 'whale', 'dex2jar', 'jdwp',
    'android_server', 'frida-server', 'magisk',
  ];
  static const List<String> _xposedPaths = [
    '/data/local/tmp/frida-server', '/data/local/tmp/frida-server64',
    '/data/local/tmp/re.frida.server', '/data/local/tmp/linjector',
    '/system/lib/libsubstrate.so', '/system/lib/libxposed_art.so',
    '/system/framework/XposedBridge.jar', '/sdcard/frida-server',
    '/data/data/de.robv.android.xposed.installer',
    '/data/data/com.saurik.substrate', '/data/data/io.github.lsposed.lsposed',
  ];

  static Future<bool> checkAll() async {
    if (await _checkVpn()) return true;
    if (await _checkFridaPort()) return true;
    if (await _checkMapsFile()) return true;
    if (await _checkInjectionFiles()) return true;
    if (await _checkSystemProxy()) return true;
    return false;
  }

  static Future<bool> _checkVpn() async {
    try {
      if (await VpnConnectionDetector.isVpnActive()) return true;
    } catch (_) {}
    try {
      final results = await cc.Connectivity().checkConnectivity();
      for (final r in results) {
        if (r == cc.ConnectivityResult.vpn) return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<bool> _checkFridaPort() async {
    if (!Platform.isAndroid) return false;
    for (final port in _fridaPorts) {
      try {
        final socket = await Socket.connect('127.0.0.1', port,
            timeout: const Duration(milliseconds: 300));
        socket.destroy();
        return true;
      } catch (_) {}
    }
    return false;
  }

  static Future<bool> _checkMapsFile() async {
    if (!Platform.isAndroid) return false;
    try {
      final maps = await File('/proc/self/maps').readAsString();
      final lower = maps.toLowerCase();
      for (final sig in _mapsSignatures) {
        if (lower.contains(sig)) return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<bool> _checkInjectionFiles() async {
    if (!Platform.isAndroid) return false;
    for (final path in _xposedPaths) {
      try { if (await File(path).exists()) return true; } catch (_) {}
    }
    return false;
  }

  static Future<bool> _checkSystemProxy() async {
    try {
      if (Platform.isAndroid) {
        final host = Platform.environment['http_proxy'];
        if (host != null && host.isNotEmpty) return true;
      }
    } catch (_) {}
    return false;
  }
}

class BypassApp extends StatefulWidget {
  const BypassApp({super.key});

  @override
  State<BypassApp> createState() => _BypassAppState();
}

class _BypassAppState extends State<BypassApp> with WidgetsBindingObserver {
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _runSecurityCheck());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runSecurityCheck();
    }
  }

  Future<void> _runSecurityCheck() async {
    if (_checking) return;
    _checking = true;
    try {
      final attacked = await SecurityChecker.checkAll();
      if (attacked && mounted) _exitDueToAttack();
    } finally { _checking = false; }
  }

  Future<void> _exitDueToAttack() async {
    if (!mounted) return;
    final again = await SecurityChecker.checkAll();
    if (!again) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(Icons.gpp_bad, color: Colors.red, size: 48),
          title: const Text('安全警告'),
          content: const Text(
            '检测到异常环境（VPN / 代理 / Hook / 调试框架）。\n为保护数据安全，应用将被强制退出。',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => exit(0),
              child: const Text('退出', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
    exit(0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

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
        children: const [BypassPage(), AboutPage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bolt), label: 'bypass'),
          NavigationDestination(icon: Icon(Icons.info_outline), label: '关于'),
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
  static const String _baseUrl = 'https://xn--qiv605b.top/bypass?url=';
  static const Duration _cooldown = Duration(minutes: 1);
  static const Duration _requestTimeout = Duration(seconds: 200); // 匹配后端最高等待 180s

  final TextEditingController _controller = TextEditingController();
  Map<String, dynamic>? _result;
  String? _error;
  bool _loading = false;
  int? _queuePosition;
  DateTime? _lastRequestAt;
  Stopwatch? _requestTimer;

  @override
  void dispose() {
    _controller.dispose();
    _requestTimer?.stop();
    super.dispose();
  }

  Future<void> _doRequest() async {
    final now = DateTime.now();
    if (_lastRequestAt != null && now.difference(_lastRequestAt!) < _cooldown) {
      final remaining = _cooldown - now.difference(_lastRequestAt!);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请求太频繁，请 ${remaining.inSeconds + 1}s 后再试')),
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
      _result = null;
      _queuePosition = null;
    });
    _requestTimer = Stopwatch()..start();

    try {
      final resp = await http.get(url).timeout(_requestTimeout);
      _requestTimer?.stop();
      setState(() {
        _loading = false;
        _lastRequestAt = DateTime.now();
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic>) {
          _result = decoded;
          _queuePosition = decoded['position'] as int?;
          if (decoded['success'] == false) {
            _error = decoded['error'] as String? ?? '未知错误';
          }
        } else {
          _error = '返回格式异常';
        }
      });
    } catch (e) {
      _requestTimer?.stop();
      setState(() {
        _loading = false;
        _error = '请求失败: $e';
      });
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
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_loading ? '请求中...' : 'bypass'),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            if (_requestTimer != null)
              Text(
                '等待中 ${_requestTimer!.elapsed.inSeconds}s',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            const SizedBox(height: 8),
            Text('正在排队处理，请稍候...',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return SingleChildScrollView(
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (_result == null) {
      return Center(
        child: Text('解析结果会显示在这里',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    final success = _result!['success'] == true;
    final key = _result!['key'] as String?;
    final author = _result!['author'] as String?;
    final api = _result!['api'] as String?;
    final took = _result!['took'];
    final cost = _result!['cost'];
    final position = _result!['position'] as int?;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 队列位置
          if (position != null && position > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.queue, size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 6),
                  Text('当前在队列第 $position 位',
                    style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

          if (success && key != null) ...[
            // key 显示 + 复制按钮
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.deepPurple.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Key', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(key,
                          style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold,
                            color: Colors.deepPurple.shade700, letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        tooltip: '复制 Key',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: key));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Key 已复制')),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          if (!success) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_result!['error'] as String? ?? '处理失败',
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // 详细信息
          _infoRow('作者', author ?? '-'),
          _infoRow('API', api ?? '-'),
          _infoRow('耗时', '${took ?? cost ?? 0}s'),
          if (position != null) _infoRow('排队位置', position.toString()),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bolt, size: 48, color: Colors.deepPurple),
            const SizedBox(height: 12),
            const Text(
              'Bypass',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('作者：eri', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            const Text('QQ：3606359397', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepPurple.shade200),
              ),
              child: Column(
                children: [
                  const Icon(Icons.groups, color: Colors.deepPurple, size: 28),
                  const SizedBox(height: 6),
                  Text('QQ群', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  const SizedBox(height: 2),
                  const Text('1106569806',
                    style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold,
                      color: Colors.deepPurple, letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('复制群号'),
              onPressed: () {
                Clipboard.setData(const ClipboardData(text: '1106569806'));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('群号已复制')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}