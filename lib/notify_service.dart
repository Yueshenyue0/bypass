import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// 通知 + 前台服务保活
class NotifyService {
  NotifyService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// 初始化（App 启动时调用一次）
  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);

    // Android 13+ 请求通知权限
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // 精确闹钟权限（非必须，跳过）
  }

  /// 绕过成功通知
  static Future<void> showSuccess(String key) async {
    const androidDetails = AndroidNotificationDetails(
      'bypass_success',
      '绕过成功',
      channelDescription: '绕过成功时通知',
      importance: Importance.high,
      priority: Priority.high,
      color: Color(0xFF673AB7),
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      1001,
      '绕过成功',
      'Key 已生成，点击复制',
      details,
      payload: key, // 携带 key 供点击回调使用
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

  /// 启动前台服务（保活，显示常驻通知）
  static Future<void> startForegroundTask() async {
    await FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'bypass_foreground',
        channelName: 'Bypass 保活服务',
        channelDescription: '保持 Bypass 后台运行，及时接收绕过结果',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'ic_launcher',
          backgroundColor: '#673AB7',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    FlutterForegroundTask.startService(
      notificationTitle: 'Bypass 运行中',
      notificationText: '后台等待绕过结果中...',
      callback: startCallback,
    );
  }
}

/// 前台任务回调（后台 isolate 中运行）
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

class MyTaskHandler extends TaskHandler {
  @override
  void onStart(DateTime timestamp, TaskStarter starter) {
    // 后台定期运行（每 interval 一次）
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 可选：在这里做心跳
  }

  @override
  void onDestroy(DateTime timestamp) {}
}