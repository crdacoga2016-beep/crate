import 'package:flutter/material.dart';

import '../player/mini_player.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  static const List<Widget> _screens = [
    HomeScreen(),
    LibraryScreen(),
    SearchScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;

    final content = Column(
      children: [
        Expanded(
          child: IndexedStack(index: _tab, children: _screens),
        ),
        const MiniPlayer(),
      ],
    );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _Rail(
              tab: _tab,
              extended: width >= 1220,
              onSelect: (i) => setState(() => _tab = i),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(child: content),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded),
            label: 'Música',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            label: 'Buscar',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.tab,
    required this.extended,
    required this.onSelect,
  });

  final int tab;
  final bool extended;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return NavigationRail(
      extended: extended,
      selectedIndex: tab,
      onDestinationSelected: onSelect,
      minWidth: 74,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [accent, const Color(0xFF4C1D95)],
                ),
              ),
              child: const Icon(Icons.graphic_eq_rounded, size: 20),
            ),
            if (extended) ...[
              const SizedBox(width: 10),
              const Text(
                'Crate',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ],
        ),
      ),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: Text('Inicio'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.library_music_outlined),
          selectedIcon: Icon(Icons.library_music_rounded),
          label: Text('Música'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.search_rounded),
          label: Text('Buscar'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings_rounded),
          label: Text('Ajustes'),
        ),
      ],
      trailing: const Padding(
        padding: EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: Text(
          'v0.5.0',
          style: TextStyle(fontSize: 10, color: Color(0xFF5A5A6A)),
        ),
      ),
    );
  }
}
