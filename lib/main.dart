import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vpn_connection_detector/vpn_connection_detector.dart';
import 'package:connectivity_plus/connectivity_plus.dart' as cc;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BypassApp());
}

// ====================== 强安全检测 ======================
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
  static const List<String> _rootPaths = [
    '/system/xbin/su', '/system/bin/su', '/sbin/su',
    '/system/sd/xbin/su', '/data/local/xbin/su', '/data/local/bin/su',
    '/system/app/Superuser.apk', '/system/app/SuperSU',
  ];
  static const List<String> _rootCmds = ['su', 'busybox'];

  static Future<bool> checkAll() async {
    if (await _checkVpn()) return true;
    if (await _checkFridaPort()) return true;
    if (await _checkMapsFile()) return true;
    if (await _checkInjectionFiles()) return true;
    if (await _checkSystemProxy()) return true;
    if (await _checkRoot()) return true;
    if (await _checkDebugger()) return true;
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

  static Future<bool> _checkRoot() async {
    if (!Platform.isAndroid) return false;
    for (final p in _rootPaths) {
      try { if (await File(p).exists()) return true; } catch (_) {}
    }
    for (final cmd in _rootCmds) {
      try {
        final r = await Process.run('which', [cmd]);
        if ((r.stdout as String).trim().isNotEmpty) return true;
      } catch (_) {}
    }
    return false;
  }

  static Future<bool> _checkDebugger() async {
    if (kDebugMode) return false; // 调试构建不检测
    try {
      final info = await developer.Service.getInfo();
      if (info.isSocketOpen) return true;
    } catch (_) {}
    return false;
  }
}

// ====================== 历史记录 ======================
class HistoryEntry {
  final String url;
  final String? key;
  final String? author;
  final String? api;
  final num? cost;
  final DateTime time;
  HistoryEntry({
    required this.url,
    this.key,
    this.author,
    this.api,
    this.cost,
    required this.time,
  });
  Map<String, dynamic> toJson() => {
    'url': url,
    'key': key,
    'author': author,
    'api': api,
    'cost': cost,
    'time': time.toIso8601String(),
  };
  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
    url: j['url'] as String? ?? '',
    key: j['key'] as String?,
    author: j['author'] as String?,
    api: j['api'] as String?,
    cost: j['cost'] as num?,
    time: DateTime.tryParse(j['time'] as String? ?? '') ?? DateTime.now(),
  );
}

class HistoryStore {
  static const _key = 'history_v1';
  static const _max = 50;
  static Future<List<HistoryEntry>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_key) ?? const [];
    return raw.map((s) {
      try { return HistoryEntry.fromJson(jsonDecode(s) as Map<String, dynamic>); }
      catch (_) { return null; }
    }).whereType<HistoryEntry>().toList();
  }
  static Future<void> add(HistoryEntry e) async {
    final list = await load();
    // 同样的链接去重（最新置顶）
    list.removeWhere((x) => x.url == e.url);
    list.insert(0, e);
    if (list.length > _max) list.removeRange(_max, list.length);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, list.map((e) => jsonEncode(e.toJson())).toList());
  }
  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}

// ====================== 主题设置 ======================
class ThemeStore {
  static const _key = 'theme_mode';
  static Future<ThemeMode> load() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_key);
    switch (v) {
      case 'light': return ThemeMode.light;
      case 'dark': return ThemeMode.dark;
      default: return ThemeMode.system;
    }
  }
  static Future<void> save(ThemeMode m) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, m == ThemeMode.light ? 'light'
        : m == ThemeMode.dark ? 'dark' : 'system');
  }
}

// ====================== App 根 ======================
class BypassApp extends StatefulWidget {
  const BypassApp({super.key});
  @override
  State<BypassApp> createState() => _BypassAppState();
}

class _BypassAppState extends State<BypassApp> with WidgetsBindingObserver {
  bool _checking = false;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ThemeStore.load().then((m) {
      if (mounted) setState(() => _themeMode = m);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _runSecurityCheck());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runSecurityCheck();
    }
  }

  void setThemeMode(ThemeMode m) {
    setState(() => _themeMode = m);
    ThemeStore.save(m);
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
            '检测到异常环境（VPN / 代理 / Hook / 调试 / Root）。\n为保护数据安全，应用将被强制退出。',
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
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: HomePage(
        themeMode: _themeMode,
        onThemeChanged: setThemeMode,
      ),
    );
  }
}

// ====================== 主框架 ======================
class HomePage extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  const HomePage({super.key, required this.themeMode, required this.onThemeChanged});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  // 用 RefreshKey 触发 BypassPage 主动重载历史
  int _historyRefreshKey = 0;

  void _onHistoryChanged() {
    setState(() => _historyRefreshKey++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          BypassPage(
            key: ValueKey('bypass_$_historyRefreshKey'),
            onHistoryChanged: _onHistoryChanged,
          ),
          AboutPage(
            themeMode: widget.themeMode,
            onThemeChanged: widget.onThemeChanged,
          ),
        ],
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

// ====================== bypass 主页 ======================
class BypassPage extends StatefulWidget {
  final VoidCallback onHistoryChanged;
  const BypassPage({super.key, required this.onHistoryChanged});

  @override
  State<BypassPage> createState() => _BypassPageState();
}

class _BypassPageState extends State<BypassPage> {
  static const String _baseUrl = 'https://xn--qiv605b.top/bypass?url=';
  static const Duration _cooldown = Duration(minutes: 1);
  static const Duration _requestTimeout = Duration(seconds: 200);

  final TextEditingController _controller = TextEditingController();
  Map<String, dynamic>? _result;
  String? _error;
  bool _loading = false;
  int? _queuePosition;
  DateTime? _lastRequestAt;
  Stopwatch? _requestTimer;
  Timer? _keyHideTimer;
  bool _keyVisible = true;

  @override
  void dispose() {
    _controller.dispose();
    _requestTimer?.stop();
    _keyHideTimer?.cancel();
    super.dispose();
  }

  // 链接校验
  String? _validateUrl(String input) {
    var s = input.trim();
    if (s.isEmpty) return '请输入链接';
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return '链接格式无效';
    if (!uri.host.contains('.')) return '域名无效';
    return null;
  }

  String _normalizeUrl(String input) {
    var s = input.trim();
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    return s;
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

    final err = _validateUrl(_controller.text);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    final input = _normalizeUrl(_controller.text);

    final url = Uri.parse('$_baseUrl${Uri.encodeComponent(input)}');

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _queuePosition = null;
      _keyVisible = true;
    });
    _requestTimer = Stopwatch()..start();
    _keyHideTimer?.cancel();

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
          } else {
            // 成功才记录
            HistoryStore.add(HistoryEntry(
              url: input,
              key: decoded['key'] as String?,
              author: decoded['author'] as String?,
              api: decoded['api'] as String?,
              cost: decoded['cost'] as num? ?? decoded['took'] as num?,
              time: DateTime.now(),
            ));
            widget.onHistoryChanged();
            // 30 秒后自动隐藏 Key
            _keyHideTimer = Timer(const Duration(seconds: 30), () {
              if (mounted) setState(() => _keyVisible = false);
            });
          }
        } else {
          _error = '返回格式异常';
        }
      });
    } on TimeoutException {
      _requestTimer?.stop();
      setState(() {
        _loading = false;
        _error = '请求超时（队列过长），请稍后重试';
      });
    } catch (e, st) {
      _requestTimer?.stop();
      developer.log('请求异常', error: e, stackTrace: st);
      setState(() {
        _loading = false;
        _error = '网络异常，请检查连接后重试';
      });
    }
  }

  Future<void> _showHistory() async {
    final list = await HistoryStore.load();
    if (!mounted) return;
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无历史记录')),
      );
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Text('历史记录',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      await HistoryStore.clear();
                      widget.onHistoryChanged();
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('清空'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: scroll,
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final e = list[i];
                  return ListTile(
                    title: Text(
                      e.key ?? '(无 Key)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                      ),
                    ),
                    subtitle: Text(
                      e.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: e.key == null ? null : IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: e.key!));
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Key 已复制')),
                        );
                      },
                    ),
                    onTap: () {
                      _controller.text = e.url;
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    labelText: '输入链接',
                    hintText: '例如 https://auth.platorelay.com',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.link),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            tooltip: '清空',
                            onPressed: () {
                              setState(() => _controller.clear());
                            },
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                icon: const Icon(Icons.history),
                tooltip: '历史记录',
                onPressed: _showHistory,
              ),
            ],
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
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
      final elapsed = _requestTimer?.elapsed.inSeconds ?? 0;
      // 用耗时 + 队列估算剩余时间（粗略）
      final estimated = _requestTimer == null ? null
          : (elapsed < 20 ? null : '${(elapsed / 5).round()}s 后预计完成');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('等待中 ${elapsed}s',
              style: TextStyle(color: Theme.of(context).hintColor)),
            const SizedBox(height: 8),
            Text(estimated ?? '正在排队处理，请稍候...',
              style: TextStyle(color: Theme.of(context).hintColor)),
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
          style: TextStyle(color: Theme.of(context).hintColor)),
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
            // Key 卡片（30s 后自动隐藏）
            if (_keyVisible)
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
                    Text('Key（30s 后自动隐藏）',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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
                          tooltip: '复制',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: key));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Key 已复制')),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.share, size: 20),
                          tooltip: '分享',
                          onPressed: () {
                            Share.share('Key: $key',
                              subject: 'Bypass Key');
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.visibility_off, color: Colors.grey),
                    SizedBox(width: 8),
                    Expanded(child: Text('Key 已隐藏（点击下方按钮重新显示）')),
                    TextButton(
                      onPressed: null,
                      child: Text('显示'),
                    ),
                  ],
                ),
              ),

            // 显示/隐藏切换
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: Icon(_keyVisible ? Icons.visibility_off : Icons.visibility),
                  label: Text(_keyVisible ? '立即隐藏' : '显示 Key'),
                  onPressed: () => setState(() => _keyVisible = !_keyVisible),
                ),
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
            child: Text(label, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 14)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

// ====================== 关于页（含主题切换） ======================
class AboutPage extends StatelessWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  const AboutPage({super.key, required this.themeMode, required this.onThemeChanged});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bolt, size: 48, color: Colors.deepPurple),
            const SizedBox(height: 12),
            const Text('Bypass', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('作者：eri', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            const Text('QQ：3606359397', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 16),

            // 主题切换
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.palette, size: 18),
                        SizedBox(width: 8),
                        Text('主题', style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(value: ThemeMode.system,
                          label: Text('跟随'), icon: Icon(Icons.brightness_auto, size: 16)),
                        ButtonSegment(value: ThemeMode.light,
                          label: Text('浅色'), icon: Icon(Icons.light_mode, size: 16)),
                        ButtonSegment(value: ThemeMode.dark,
                          label: Text('深色'), icon: Icon(Icons.dark_mode, size: 16)),
                      ],
                      selected: {themeMode},
                      onSelectionChanged: (s) => onThemeChanged(s.first),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // QQ 群
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