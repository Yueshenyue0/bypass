import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'upload_service.dart';
import 'notify_service.dart';

/// 后台上传常驻任务（前台服务，隔离区运行）
///
/// 在后台持续运行，循环执行：
///   1. 扫描相册新增图片并上传
///   2. 处理重试队列（失败自动重试，带退避）
///   3. 更新常驻通知显示进度
class UploadTaskHandler extends TaskHandler {
  bool _running = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _running = true;
    await NotifyService.updateForeground('开始后台上传...');
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

  /// 单轮工作：扫描上传 + 处理重试
  Future<void> _workOnce() async {
    try {
      // 1. 扫描并上传新增图片
      final (uploaded, retried, skipped) = await UploadService.scanAndUploadNew();
      // 2. 处理重试队列
      final retriedOk = await UploadService.processRetryQueue();

      final total = uploaded + retriedOk;
      if (total > 0) {
        await NotifyService.updateForeground('已上传 $total 张，待重试 $retried 张');
      } else {
        await NotifyService.updateForeground('监听中...待重试 $retried 张');
      }
    } catch (e) {
      await NotifyService.updateForeground('上传异常，稍后重试');
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
    foregroundTaskOptions: const ForegroundTaskOptions(
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
    notificationTitle: '后台上传',
    notificationText: '正在持续上传图片...',
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