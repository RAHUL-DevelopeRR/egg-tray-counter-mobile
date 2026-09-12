import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/egg_counter_app.dart';
import 'services/history_database.dart';
import 'services/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final settings = SettingsStore();
  final database = HistoryDatabase();
  runApp(EggCounterApp(settings: settings, history: database));
}
