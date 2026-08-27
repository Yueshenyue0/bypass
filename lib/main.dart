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

  // Frida 默认端口 + 常见调试端口
  static const List<int> _fridaPorts = [27042, 27043, 27044, 27045];
  // 常见注入/框架特征字符串
  static const List<String> _mapsSignatures = [
    'frida',
    'gum-js-loop',
    'gmain',
    'linjector',
    'xposed',
    'XposedBridge',
    'substrate',
    'Substrate',
    'riru',
    'zygisk',
    'lsposed',
    'edxposed',
    'whale',
    'dex2jar',
    'jdwp',
    'android_server',
    'frida-server',
    'magisk',
  ];
  // 常见 hook/注入框架包名与文件
  static const List<String> _xposedPaths = [
    '/data/local/tmp/frida-server',
    '/data/local/tmp/frida-server64',
    '/data/local/tmp/re.frida.server',
    '/data/local/tmp/linjector',
    '/system/lib/libsubstrate.so',
    '/system/lib/libxposed_art.so',
    '/system/framework/XposedBridge.jar',
    '/sdcard/frida-server',
    '/data/data/de.robv.android.xposed.installer',
    '/data/data/com.saurik.substrate',
    '/data/data/io.github.lsposed.lsposed',
  ];

  /// 综合检测，任一命中返回 true（存在威胁）
  static Future<bool> checkAll() async {
    if (await _checkVpn()) return true;
    if (await _checkFridaPort()) return true;
    if (await _checkMapsFile()) return true;
    if (await _checkInjectionFiles()) return true;
    if (await _checkSystemProxy()) return true;
    return false;
  }

  /// 1. VPN 连接检测（用 vpn_connection_detector，准确率 ~95%，能检测第三方VPN）
  static Future<bool> _checkVpn() async {
    try {
      final active = await VpnConnectionDetector.isVpnActive();
      if (active) return true;
    } catch (_) {}
    // 兜底：connectivity_plus 也查一次
    try {
      final results = await cc.Connectivity().checkConnectivity();
      for (final r in results) {
        if (r == cc.ConnectivityResult.vpn) return true;
      }
    } catch (_) {}
    return false;
  }

  /// 2. Frida 默认端口扫描（仅 Android）
  static Future<bool> _checkFridaPort() async {
    if (!Platform.isAndroid) return false;
    for (final port in _fridaPorts) {
      try {
        final socket = await Socket.connect('127.0.0.1', port,
            timeout: const Duration(milliseconds: 300));
        socket.destroy();
        return true; // 端口被占用 = Frida server 在跑
      } catch (_) {}
    }
    return false;
  }

  /// 3. 扫描 /proc/self/maps 找注入特征（Android）
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

  /// 4. 常见注入文件 / Xposed 数据目录检测
  static Future<bool> _checkInjectionFiles() async {
    if (!Platform.isAndroid) return false;
    for (final path in _xposedPaths) {
      try {
        if (await File(path).exists()) return true;
      } catch (_) {}
    }
    return false;
  }

  /// 5. 系统代理检测（Android）
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
    // 每次恢复前台重新检测，防止中途开 VPN/hook
    if (state == AppLifecycleState.resumed) {
      _runSecurityCheck();
    }
  }

  Future<void> _runSecurityCheck() async {
    if (_checking) return;
    _checking = true;
    try {
      final attacked = await SecurityChecker.checkAll();
      if (attacked && mounted) {
        _exitDueToAttack();
      }
    } finally {
      _checking = false;
    }
  }

  /// 检测到威胁：弹不可关闭对话框强制退出
  Future<void> _exitDueToAttack() async {
    if (!mounted) return;
    // 二次确认，防误报
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
  static const String _baseUrl = 'https://xn--qiv605b.top/bypass?url=';
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

    // 直接用正确域名请求（xn--qiv605b.top 已验证可解析）
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
            _buildJsonTree(_parsedJson),
          ] else
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