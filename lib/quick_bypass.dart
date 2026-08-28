import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'notify_service.dart';

/// 快速绕过：从通知输入链接 → 发起请求 → 复制 Key
class QuickBypass {
  QuickBypass._();

  static const String _baseUrl = 'https://xn--qiv605b.top/bypass?url=';
  static const Duration _timeout = Duration(seconds: 200);

  /// 处理通知输入：发起请求并自动复制 Key
  static Future<void> handleLinkInput(String? input) async {
    var s = (input ?? '').trim();
    if (s.isEmpty) {
      await NotifyService.showInfo('快速绕过', '链接为空，请输入链接');
      return;
    }
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) {
      await NotifyService.showInfo('快速绕过', '链接格式无效');
      return;
    }

    try {
      final url = Uri.parse('$_baseUrl${Uri.encodeComponent(s)}');
      await NotifyService.showInfo('快速绕过', '正在请求，请稍候...');
      final resp = await http.get(url).timeout(_timeout);
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is Map<String, dynamic> && decoded['success'] == true) {
        final key = decoded['key'] as String? ?? '';
        if (key.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: key));
          await NotifyService.showSuccess(key);
        } else {
          await NotifyService.showInfo('快速绕过', '请求成功但未返回 Key');
        }
      } else {
        final msg = decoded is Map<String, dynamic>
            ? (decoded['error'] as String? ?? '处理失败')
            : '返回格式异常';
        await NotifyService.showInfo('快速绕过', msg);
      }
    } on TimeoutException {
      await NotifyService.showInfo('快速绕过', '请求超时');
    } catch (e) {
      await NotifyService.showInfo('快速绕过', '网络异常，请检查连接');
    }
  }
}