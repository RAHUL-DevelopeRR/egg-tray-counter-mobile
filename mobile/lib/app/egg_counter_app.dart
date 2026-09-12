import 'package:flutter/material.dart';

import '../features/home/home_screen.dart';
import '../services/history_database.dart';
import '../services/settings_store.dart';

class EggCounterApp extends StatelessWidget {
  const EggCounterApp({
    required this.settings,
    required this.history,
    super.key,
  });

  final SettingsStore settings;
  final HistoryDatabase history;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF63E6A5);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Egg Tray Counter',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
          surface: const Color(0xFF111A1D),
        ),
        scaffoldBackgroundColor: const Color(0xFF081113),
        cardTheme: const CardThemeData(
          color: Color(0xFF111A1D),
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
      home: HomeScreen(settings: settings, history: history),
    );
  }
}
