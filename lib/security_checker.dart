import 'dart:io';
import 'package:flutter/foundation.dart';
import 'verify_bridge.dart';

/// 安全检测：Frida / Xposed / Root / libapp.so 完整性
/// 注：已移除 VPN / 代理 / 抓包检测，避免对正常用户误报
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
    if (await _checkFridaPort()) return true;
    if (await _checkMapsFile()) return true;
    if (await _checkInjectionFiles()) return true;
    if (await _checkRoot()) return true;
    if (_checkAppIntegrity()) return true; // libapp.so 被篡改
    return false;
  }

  /// 通过 libverify.so 校验 libapp.so 完整性（0=正常 1=篡改 -1=校验出错）
  static bool _checkAppIntegrity() {
    try {
      final r = VerifyBridge.verifyApkIntegrity();
      if (r == 1) {
        debugPrint('[Security] libapp.so INTEGRITY CHECK FAILED');
        return true;
      }
    } catch (e) {
      debugPrint('[Security] integrity check error: $e');
    }
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
}
