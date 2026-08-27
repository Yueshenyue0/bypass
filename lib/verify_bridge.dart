import 'dart:ffi';
import 'dart:io';
import 'package:flutter/services.dart' show PlatformException;
import 'package:ffi/ffi.dart';

/// 通过 dart:ffi 调用 libverify.so 校验 libapp.so 完整性
class VerifyBridge {
  VerifyBridge._();

  static DynamicLibrary? _lib;
  static bool _loaded = false;

  static DynamicLibrary _getLib() {
    if (_lib != null) return _lib!;
    // Android：libverify.so 被打进 APK 的 lib/<abi>/ 目录，直接用名字加载
    // （等同于 System.loadLibrary），最可靠
    _lib = DynamicLibrary.open('libverify.so');
    _loaded = true;
    return _lib!;
  }

  /// 校验结果：0=未篡改 1=被篡改 -1=校验出错（未注入/找不到so）
  static int verifyApkIntegrity() {
    if (!Platform.isAndroid) return 0;
    try {
      final lib = _getLib();
      final f = lib.lookupFunction<Int32 Function(), int Function()>(
        'verify_apk_integrity',
      );
      return f();
    } catch (_) {
      return -1;
    }
  }

  /// 获取当前 libapp.so 的 SHA-256（调试用）
  static String getLibappSha256() {
    if (!Platform.isAndroid) return '';
    try {
      final lib = _getLib();
      final f = lib.lookupFunction<
        void Function(Pointer<Utf8>, Int32),
        void Function(Pointer<Utf8>, int)
      >('verify_get_libapp_sha256');
      final buf = calloc<Uint8>(128);
      final ptr = buf.cast<Utf8>();
      f(ptr, 128);
      final s = ptr.toDartString();
      calloc.free(buf);
      return s;
    } catch (_) {
      return '';
    }
  }
}
