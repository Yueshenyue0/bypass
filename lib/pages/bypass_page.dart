import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import '../history_store.dart';
import '../notify_service.dart';

/// bypass 主功能页
class BypassPage extends StatefulWidget {
  const BypassPage({super.key});

  @override
  State<BypassPage> createState() => BypassPageState();
}

class BypassPageState extends State<BypassPage> {
  static const String _baseUrl = 'https://xn--qiv605b.top/bypass?url=';
  static const Duration _cooldown = Duration(minutes: 1);
  static const Duration _requestTimeout = Duration(seconds: 200);

  final TextEditingController _controller = TextEditingController();
  Map<String, dynamic>? _result;
  String? _error;
  bool _loading = false;
  int? _queuePosition;
  DateTime? _lastRequestAt;
  Stopwatch? _requestTimer;
  Timer? _ticker; // 加载期间每秒刷新计时
  int _historyVersion = 0;

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.dispose();
    _requestTimer?.stop();
    super.dispose();
  }

  // 链接校验
  String? _validateUrl(String input) {
    var s = input.trim();
    if (s.isEmpty) return '请输入链接';
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return '链接格式无效';
    if (!uri.host.contains('.')) return '域名无效';
    return null;
  }

  String _normalizeUrl(String input) {
    var s = input.trim();
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    return s;
  }

  Future<void> _doRequest() async {
    final now = DateTime.now();
    if (_lastRequestAt != null && now.difference(_lastRequestAt!) < _cooldown) {
      final remaining = _cooldown - now.difference(_lastRequestAt!);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请求太频繁，请 ${remaining.inSeconds + 1}s 后再试')),
      );
      return;
    }

    final err = _validateUrl(_controller.text);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    final input = _normalizeUrl(_controller.text);

    final url = Uri.parse('$_baseUrl${Uri.encodeComponent(input)}');

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _queuePosition = null;
    });
    _requestTimer = Stopwatch()..start();
    // 加载期间每秒刷新一次（等待时长 + 队列位置实时显示）
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _loading) setState(() {});
    });

    try {
      final resp = await http.get(url).timeout(_requestTimeout);
      _requestTimer?.stop();
      _ticker?.cancel();
      setState(() {
        _loading = false;
        _lastRequestAt = DateTime.now();
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic>) {
          _result = decoded;
          _queuePosition = decoded['position'] as int?;
          if (decoded['success'] == false) {
            _error = decoded['error'] as String? ?? '未知错误';
          } else {
            // 成功才记录，存历史（只存不重建页面，Key 保持显示）
            HistoryStore.add(HistoryEntry(
              url: input,
              key: decoded['key'] as String?,
              author: decoded['author'] as String?,
              api: decoded['api'] as String?,
              cost: decoded['cost'] as num? ?? decoded['took'] as num?,
              time: DateTime.now(),
            ));
            _historyVersion++;
            // 绕过成功弹通知 + 震动反馈
            final nKey = decoded['key'] as String?;
            if (nKey != null && nKey.isNotEmpty) {
              NotifyService.showSuccess(nKey);
            }
            HapticFeedback.mediumImpact();
          }
        } else {
          _error = '返回格式异常';
        }
      });
    } on TimeoutException {
      _requestTimer?.stop();
      _ticker?.cancel();
      setState(() {
        _loading = false;
        _error = '请求超时（队列过长），请稍后重试';
      });
    } catch (e, st) {
      _requestTimer?.stop();
      _ticker?.cancel();
      developer.log('请求异常', error: e, stackTrace: st);
      setState(() {
        _loading = false;
        _error = '网络异常，请检查连接后重试';
      });
    }
  }

  // 复制整个返回 JSON
  void _copyResult() {
    if (_result == null) return;
    Clipboard.setData(ClipboardData(text: jsonEncode(_result)));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('完整返回已复制')),
    );
  }

  Future<void> _showHistory() async {
    final list = await HistoryStore.load();
    if (!mounted) return;
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无历史记录')),
      );
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Text('历史记录',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      await HistoryStore.clear();
                      setState(() => _historyVersion++);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('清空'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: scroll,
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final e = list[i];
                  return ListTile(
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            e.key ?? '(无 Key)',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          e.timeText,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      e.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: e.key == null ? null : IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: e.key!));
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Key 已复制')),
                        );
                      },
                    ),
                    onTap: () {
                      _controller.text = e.url;
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    labelText: '输入链接',
                    hintText: '例如 https://auth.platorelay.com',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.link),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            tooltip: '清空',
                            onPressed: () {
                              setState(() => _controller.clear());
                            },
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                icon: const Icon(Icons.history),
                tooltip: '历史记录',
                onPressed: _showHistory,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _doRequest,
              icon: _loading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_loading ? '请求中...' : 'bypass'),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _buildResult(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    if (_loading) {
      final elapsed = _requestTimer?.elapsed.inSeconds ?? 0;
      final estimated = _requestTimer == null ? null
          : (elapsed < 20 ? null : '${(elapsed / 5).round()}s 后预计完成');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('等待中 ${elapsed}s',
              style: TextStyle(color: Theme.of(context).hintColor)),
            const SizedBox(height: 8),
            Text(estimated ?? '正在排队处理，请稍候...',
              style: TextStyle(color: Theme.of(context).hintColor)),
          ],
        ),
      );
    }
    if (_error != null) {
      return SingleChildScrollView(
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (_result == null) {
      return Center(
        child: Text('解析结果会显示在这里',
          style: TextStyle(color: Theme.of(context).hintColor)),
      );
    }

    final success = _result!['success'] == true;
    final key = _result!['key'] as String?;
    final author = _result!['author'] as String?;
    final api = _result!['api'] as String?;
    final position = _result!['position'] as int?;

    // 耗时字段：兼容 took / cost 两种命名，统一转成秒数文本
    final tookRaw = _result!['took'] ?? _result!['cost'] ?? _result!['time'] ?? 0;
    final tookNum = (tookRaw is num) ? tookRaw.toDouble() : double.tryParse('$tookRaw') ?? 0;
    final tookText = tookNum > 0 ? (tookNum >= 1 ? '${tookNum.toStringAsFixed(1)}s' : '${(tookNum * 1000).round()}ms') : '-';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (position != null && position > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.queue, size: 18,
                    color: Theme.of(context).colorScheme.tertiary),
                  const SizedBox(width: 6),
                  Text('当前在队列第 $position 位',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          if (success && key != null) ...[
            // Key 卡片（一直显示，可复制/分享；深色模式自动适配主题色）
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Key',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(key,
                          style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        tooltip: '复制',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: key));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Key 已复制')),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.share, size: 20),
                        tooltip: '分享',
                        onPressed: () {
                          Share.share('Key: $key', subject: 'Bypass Key');
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          if (!success) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                    color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_result!['error'] as String? ?? '处理失败',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          _infoRow('作者', author ?? '-'),
          _infoRow('API', api ?? '-'),
          _infoRow('耗时', tookText),
          if (position != null) _infoRow('排队位置', position.toString()),

          const SizedBox(height: 12),
          // 复制完整返回
          OutlinedButton.icon(
            icon: const Icon(Icons.content_copy, size: 18),
            label: const Text('复制完整返回'),
            onPressed: _copyResult,
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 14)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}