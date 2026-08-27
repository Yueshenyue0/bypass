import 'package:flutter/material.dart';
import 'bypass_page.dart';
import 'about_page.dart';

/// 主框架：底部导航（bypass / 关于）
class HomePage extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  const HomePage({super.key, required this.themeMode, required this.onThemeChanged});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  final GlobalKey<BypassPageState> _bypassKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          BypassPage(key: _bypassKey),
          AboutPage(
            themeMode: widget.themeMode,
            onThemeChanged: widget.onThemeChanged,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bolt), label: 'bypass'),
          NavigationDestination(icon: Icon(Icons.info_outline), label: '关于'),
        ],
      ),
    );
  }
}