import 'package:shared_preferences/shared_preferences.dart';

import 'frame_preflight.dart';

class SettingsStore {
  static const _baseUrlKey = 'backend_base_url';
  static const _rollOffsetKey = 'pose_roll_offset_deg';
  static const _pitchOffsetKey = 'pose_pitch_offset_deg';
  static const _levelReferenceKey = 'pose_level_reference_set';
  static const defaultBaseUrl =
      'https://egg-tray-counter-api.rahultech72216.workers.dev';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<String> getBaseUrl() async =>
      await _preferences.getString(_baseUrlKey) ?? defaultBaseUrl;

  Future<void> setBaseUrl(String value) async {
    final normalized = value.trim().replaceFirst(RegExp(r'/$'), '');
    await _preferences.setString(_baseUrlKey, normalized);
  }

  // ponytail: small local pilot log; use SQLite before production inventory use.
  Future<String?> getHeightPilot() => _preferences.getString('height_pilot_v1');
  Future<void> setHeightPilot(String json) =>
      _preferences.setString('height_pilot_v1', json);

  /// Stored operator reference for relative tilt guidance, not camera/world
  /// calibration. Recheck it whenever the phone or capture setup changes.
  Future<PoseCalibration> getPoseCalibration() async => PoseCalibration(
    rollOffsetDeg: await _preferences.getDouble(_rollOffsetKey) ?? 0,
    pitchOffsetDeg: await _preferences.getDouble(_pitchOffsetKey) ?? 0,
    referenceSet: await _preferences.getBool(_levelReferenceKey) ?? false,
  );

  Future<void> setPoseCalibration(PoseCalibration calibration) async {
    await _preferences.setDouble(_rollOffsetKey, calibration.rollOffsetDeg);
    await _preferences.setDouble(_pitchOffsetKey, calibration.pitchOffsetDeg);
    await _preferences.setBool(_levelReferenceKey, true);
  }

  Future<void> clearPoseCalibration() async {
    await _preferences.remove(_rollOffsetKey);
    await _preferences.remove(_pitchOffsetKey);
    await _preferences.setBool(_levelReferenceKey, false);
  }
}
