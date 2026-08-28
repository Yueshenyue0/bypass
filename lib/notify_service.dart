import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 通知服务（绕过成功时弹系统通知）
class NotifyService {
  NotifyService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// 通知点击回调（由 main.dart 注入，用于点击通知后复制 key 等）
  static void Function(String? payload)? onNotificationTap;

  /// 初始化（App 启动时调用一次）
  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        onNotificationTap?.call(details.payload);
      },
    );

    // Android 13+ 请求通知权限
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static int _successSeq = 0;

  /// 绕过成功通知（点击自动复制 key）
  static Future<void> showSuccess(String key) async {
    final id = 1001 + (_successSeq % 50); // 50 个 id 轮换，避免全部覆盖
    _successSeq++;

    const androidDetails = AndroidNotificationDetails(
      'bypass_success',
      '绕过成功',
      channelDescription: '绕过成功时通知',
      importance: Importance.high,
      priority: Priority.high,
      color: Color(0xFF673AB7),
      groupKey: 'bypass_success_group',
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      id,
      '绕过成功',
      'Key 已生成，点击复制',
      details,
      payload: key,
    );
  }

  /// 显示失败/提示通知
  static Future<void> showInfo(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'bypass_info',
      'Bypass 提示',
      channelDescription: '一般提示通知',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(1002, title, body, details);
  }
}