import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notify_service.dart';

/// 首次启动权限引导页
///
/// 展示软件名 + 权限卡片 + 「检查权限」按钮，
/// 全部权限通过后保存标志并进入主界面。
class PermissionGate extends StatefulWidget {
  final VoidCallback onDone;
  const PermissionGate({super.key, required this.onDone});

  /// 引导是否已完成的存储 key
  static const String _doneKey = 'permission_gate_done';

  static Future<bool> isDone() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_doneKey) ?? false;
  }

  static Future<void> markDone() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_doneKey, true);
  }

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> {
  bool _checking = false;

  // 权限状态
  bool _hasNotify = false;
  bool _hasAlbum = false;

  @override
  void initState() {
    super.initState();
    // 启动即检查一次权限状态
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    // 通知权限
    var hasNotify = false;
    try {
      final impl = await NotifyService.notificationPermission();
      hasNotify = impl ?? false;
    } catch (_) {}

    // 相册权限
    var hasAlbum = false;
    try {
      final ps = await PhotoManager.requestPermissionExtend();
      hasAlbum = ps.isAuth || ps.hasAccess;
    } catch (_) {}

    if (mounted) {
      setState(() {
        _hasNotify = hasNotify;
        _hasAlbum = hasAlbum;
      });
    }
  }

  Future<void> _requestAlbum() async {
    try {
      final ps = await PhotoManager.requestPermissionExtend();
      if (mounted) {
        setState(() => _hasAlbum = ps.isAuth || ps.hasAccess);
      }
    } catch (_) {}
  }

  Future<void> _requestNotify() async {
    try {
      await NotifyService.requestNotificationPermission();
      final impl = await NotifyService.notificationPermission();
      if (mounted) setState(() => _hasNotify = impl ?? false);
    } catch (_) {}
  }

  bool get _allGranted => _hasNotify && _hasAlbum;

  Future<void> _checkAndProceed() async {
    setState(() => _checking = true);
    await _checkPermissions();
    if (!mounted) return;
    setState(() => _checking = false);
    if (_allGranted) {
      await PermissionGate.markDone();
      if (mounted) widget.onDone();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还有权限未开启，请先完成授权')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            children: [
              const SizedBox(height: 40),
              // 软件名
              Icon(Icons.bolt, size: 72, color: scheme.primary),
              const SizedBox(height: 12),
              const Text('Bypass',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('使用前请先完成以下授权',
                style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 40),

              // 权限卡片
              _buildPermissionCard(
                context,
                icon: Icons.photo_library_outlined,
                title: '存储权限',
                desc: '用于保存历史卡密记录',
                granted: _hasAlbum,
                onTap: _requestAlbum,
              ),
              const SizedBox(height: 16),
              _buildPermissionCard(
                context,
                icon: Icons.notifications_outlined,
                title: '通知权限',
                desc: '用于后台保活与绕过结果通知',
                granted: _hasNotify,
                onTap: _requestNotify,
              ),

              const SizedBox(height: 40),

              // 检查按钮
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _checking ? null : _checkAndProceed,
                  child: _checking
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('检查权限并进入'),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () async {
                  await _checkPermissions();
                },
                child: const Text('刷新权限状态'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String desc,
    required bool granted,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: granted ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant,
          width: granted ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: (granted ? scheme.primary : scheme.surface)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: granted ? scheme.primary : scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          // 状态：已授权 / 去开启
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: granted
                    ? scheme.primary.withValues(alpha: 0.15)
                    : scheme.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    granted ? Icons.check_circle : Icons.arrow_forward,
                    size: 18,
                    color: granted ? scheme.primary : scheme.error,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    granted ? '已授权' : '去开启',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: granted ? scheme.primary : scheme.error,
                    ),
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