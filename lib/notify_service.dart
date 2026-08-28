import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// 通知服务（绕过成功时弹系统通知 + 常驻上传进度通知 + 快速绕过可输入通知）
class NotifyService {
  NotifyService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// 通知点击回调（由 main.dart 注入，用于点击通知后复制 key 等）
  static void Function(String? payload)? onNotificationTap;

  /// 通知内输入回调（用户在"快速绕过"通知里输入链接并发送时触发）
  static void Function(String? actionId, String? input)? onQuickInput;

  /// 初始化（App 启动时调用一次）
  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // 若 action 是快速绕过且带有输入文本，触发快速请求回调
        if (details.actionId == 'quick_bypass' || details.input != null) {
          onQuickInput?.call(details.actionId, details.input);
        }
        onNotificationTap?.call(details.payload);
      },
    );

    // Android 13+ 请求通知权限
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // 前台服务通知权限（flutter_foreground_task）
    final NotificationPermission p =
        await FlutterForegroundTask.checkNotificationPermission();
    if (p != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  /// 发送一条支持通知内输入的"快速绕过"通知
  /// 用户在通知里输入链接并点发送后，通过 [onQuickInput] 拿到输入
  static Future<void> showQuickLinkNotification() async {
    final androidDetails = AndroidNotificationDetails(
      'bypass_quick',
      '快速绕过',
      channelDescription: '在通知里输入链接快速绕过',
      importance: Importance.high,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction(
          'quick_bypass',
          '发送',
          // 带输入框：展开通知后出现输入栏
          inputs: const [
            AndroidNotificationActionInput(
              label: '输入链接',
            ),
          ],
          showsUserInterface: false,
        ),
      ],
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(1201, '快速绕过', '展开输入链接，点「发送」直接绕过', details);
  }

  /// 查询 Android 通知权限是否已授予（Android 13+ 用 isNotificationsEnabled）
  static Future<bool?> notificationPermission() async {
    try {
      final impl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await impl?.areNotificationsEnabled();
    } catch (_) {
      return null;
    }
  }

  /// 请求 Android 通知权限
  static Future<void> requestNotificationPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
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

  // ====== 常驻保活通知已由 flutter_foreground_task 自身提供，不再重复发 ======
}