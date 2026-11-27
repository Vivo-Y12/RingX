/// Ringx app shell: dark racing theme and the three-section navigation.
library;

import 'package:flutter/material.dart';

import 'core/engine.dart';
import 'ui/home_screen.dart';
import 'ui/mapping_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/templates_screen.dart';

class RingxApp extends StatelessWidget {
  const RingxApp({super.key, required this.engine, this.profileLoadError});

  final MapperEngine engine;

  /// Non-null when the saved profile could not be loaded (defaults used).
  final String? profileLoadError;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFF5A524), // Ringx amber
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'RingX Receiver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF0E1116),
        fontFamily: 'Segoe UI',
        navigationRailTheme: NavigationRailThemeData(
          backgroundColor: const Color(0xFF12151B),
          indicatorColor: scheme.primary.withValues(alpha: 0.2),
          selectedIconTheme: IconThemeData(color: scheme.primary),
          unselectedIconTheme: const IconThemeData(color: Color(0xFF7A8089)),
        ),
        dividerColor: const Color(0xFF23262E),
      ),
      home: RingxShell(engine: engine, profileLoadError: profileLoadError),
    );
  }
}

class RingxShell extends StatefulWidget {
  const RingxShell({super.key, required this.engine, this.profileLoadError});

  final MapperEngine engine;
  final String? profileLoadError;

  @override
  State<RingxShell> createState() => _RingxShellState();
}

class _RingxShellState extends State<RingxShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screens = [
      HomeScreen(engine: widget.engine),
      const TemplatesScreen(),
      MappingScreen(engine: widget.engine),
      SettingsScreen(engine: widget.engine),
    ];
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.primary, width: 4),
                    ),
                    child: const Icon(Icons.sports_esports_outlined,
                        size: 20, color: Color(0xFF7A8089)),
                  ),
                  const SizedBox(height: 6),
                  Text('RingX',
                      style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                ],
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Dashboard'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view),
                label: Text('Templates'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.keyboard_command_key),
                selectedIcon: Icon(Icons.keyboard),
                label: Text('Mappings'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                if (widget.profileLoadError != null)
                  Material(
                    color: const Color(0xFF2A2313),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.warning_amber_rounded,
                          color: Color(0xFFF5A524)),
                      title: Text(
                        widget.profileLoadError!,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                Expanded(child: screens[_index]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
