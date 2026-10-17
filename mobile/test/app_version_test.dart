import 'dart:io';

import 'package:egg_tray_counter/app/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the version the app reports is the pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec)?.group(1);
    expect(kAppVersion, version);
  });
}
