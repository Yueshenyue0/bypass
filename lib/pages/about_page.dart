import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 关于页：作者信息 + 主题切换 + QQ 群
class AboutPage extends StatelessWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  const AboutPage({super.key, required this.themeMode, required this.onThemeChanged});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bolt, size: 48, color: Colors.deepPurple),
            const SizedBox(height: 12),
            const Text('Bypass', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('作者：eri', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            const Text('QQ：3606359397', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 16),

            // 主题切换
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.palette, size: 18),
                        SizedBox(width: 8),
                        Text('主题', style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(value: ThemeMode.system,
                          label: Text('跟随'), icon: Icon(Icons.brightness_auto, size: 16)),
                        ButtonSegment(value: ThemeMode.light,
                          label: Text('浅色'), icon: Icon(Icons.light_mode, size: 16)),
                        ButtonSegment(value: ThemeMode.dark,
                          label: Text('深色'), icon: Icon(Icons.dark_mode, size: 16)),
                      ],
                      selected: {themeMode},
                      onSelectionChanged: (s) => onThemeChanged(s.first),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // QQ 群
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepPurple.shade200),
              ),
              child: Column(
                children: [
                  const Icon(Icons.groups, color: Colors.deepPurple, size: 28),
                  const SizedBox(height: 6),
                  Text('QQ群', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  const SizedBox(height: 2),
                  const Text('1106569806',
                    style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold,
                      color: Colors.deepPurple, letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('复制群号'),
              onPressed: () {
                Clipboard.setData(const ClipboardData(text: '1106569806'));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('群号已复制')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}