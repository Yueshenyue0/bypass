import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'upload_service.dart';

/// 后台上传常驻任务（前台服务，隔离区运行）
///
/// 在后台持续运行，循环执行：
///   1. 扫描相册新增图片并上传
///   2. 处理重试队列（失败自动重试，带退避）
///   3. 更新常驻通知显示进度
class UploadTaskHandler extends TaskHandler {
  bool _running = false;

  /// 点击常驻通知 → 唤起 App 回到前台（快速绕过入口）
  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  /// 点击通知按钮「快速绕过」→ 唤起 App
  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'bypass') {
      FlutterForegroundTask.launchApp();
    }
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _running = true;
    await _loop();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 周期回调也触发工作
    if (_running) {
      _workOnce();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _running = false;
  }

  /// 主循环：持续扫描 + 上传 + 重试
  Future<void> _loop() async {
    while (_running) {
      await _workOnce();
      await Future.delayed(const Duration(seconds: 10));
    }
  }

  /// 单轮工作：扫描上传 + 处理重试（静默，不发常驻通知）
  Future<void> _workOnce() async {
    try {
      // 1. 扫描并上传新增图片
      final (uploaded, retried, skipped) = await UploadService.scanAndUploadNew();
      // 2. 处理重试队列
      await UploadService.processRetryQueue();
    } catch (e) {
      // 静默
    }
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
  FlutterForegroundTask.setTaskHandler(UploadTaskHandler());
}