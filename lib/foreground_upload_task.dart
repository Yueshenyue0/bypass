import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// 前台常驻保活任务（隔离区运行）
/// 只负责保活 + 心跳，不做上传（上传在主 isolate 用 photo_manager 完成）
class KeepAliveTaskHandler extends TaskHandler {
  bool _running = false;

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'bypass') {
      FlutterForegroundTask.launchApp();
    }
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _running = true;
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 心跳：保持前台服务存活
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _running = false;
  }
}

/// 启动前台常驻上传服务
Future<void> startForegroundUploadTask() async {
  if (await FlutterForegroundTask.isRunningService) {
    await FlutterForegroundTask.restartService();
    return;
  }

  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'bypass_upload_fg',
      channelName: '后台上传',
      channelDescription: '后台持续上传图片',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(10000),
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  if (Platform.isAndroid) {
    // Android 12+ 忽略电池优化，防止杀后台
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  await FlutterForegroundTask.startService(
    serviceId: 256,
    notificationTitle: 'Bypass 运行中',
    notificationText: '点击或点「快速绕过」进入',
    notificationButtons: [
      NotificationButton(id: 'bypass', text: '快速绕过'),
    ],
    callback: startCallback,
  );
}

/// 停止前台服务
Future<void> stopForegroundUploadTask() async {
  await FlutterForegroundTask.stopService();
}

/// 前台任务回调（后台 isolate 中运行）
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(KeepAliveTaskHandler());
}