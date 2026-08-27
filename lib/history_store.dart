import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 一条历史记录
class HistoryEntry {
  final String url;
  final String? key;
  final String? author;
  final String? api;
  final num? cost;
  final DateTime time;
  HistoryEntry({
    required this.url,
    this.key,
    this.author,
    this.api,
    this.cost,
    required this.time,
  });
  Map<String, dynamic> toJson() => {
    'url': url,
    'key': key,
    'author': author,
    'api': api,
    'cost': cost,
    'time': time.toIso8601String(),
  };
  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
    url: j['url'] as String? ?? '',
    key: j['key'] as String?,
    author: j['author'] as String?,
    api: j['api'] as String?,
    cost: j['cost'] as num?,
    time: DateTime.tryParse(j['time'] as String? ?? '') ?? DateTime.now(),
  );
}

/// 历史记录存储（本地 SharedPreferences，最多保留 [_max] 条）
class HistoryStore {
  static const _key = 'history_v1';
  static const _max = 50;

  static Future<List<HistoryEntry>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_key) ?? const [];
    return raw.map((s) {
      try { return HistoryEntry.fromJson(jsonDecode(s) as Map<String, dynamic>); }
      catch (_) { return null; }
    }).whereType<HistoryEntry>().toList();
  }

  static Future<void> add(HistoryEntry e) async {
    final list = await load();
    // 同样的链接去重（最新置顶）
    list.removeWhere((x) => x.url == e.url);
    list.insert(0, e);
    if (list.length > _max) list.removeRange(_max, list.length);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, list.map((e) => jsonEncode(e.toJson())).toList());
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}