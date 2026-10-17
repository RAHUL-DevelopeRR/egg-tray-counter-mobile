import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import 'app/egg_counter_app.dart';
import 'services/device_auth.dart';
import 'services/history_database.dart';
import 'services/pending_scans.dart';
import 'services/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Use the Android Photo Picker (media index) rather than the system Files
  // app: the Files app is broken on at least one field phone and lists nothing.
  final picker = ImagePickerPlatform.instance;
  if (picker is ImagePickerAndroid) picker.useAndroidPhotoPicker = true;
  // The device credential is made on first launch, whatever the server; it is
  // sent only to a server that asks for it.
  unawaited(DeviceAuth.shared.identity().then((_) {}, onError: (_) {}));
  final settings = SettingsStore();
  final database = HistoryDatabase();
  runApp(
    EggCounterApp(
      settings: settings,
      history: database,
      pendingScans: DiskPendingScanStore(database: database),
    ),
  );
}
