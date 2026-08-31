import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore {
  static const _baseUrlKey = 'backend_base_url';
  static const defaultBaseUrl =
      'https://egg-tray-counter-api.rahultech72216.workers.dev';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<String> getBaseUrl() async =>
      await _preferences.getString(_baseUrlKey) ?? defaultBaseUrl;

  Future<void> setBaseUrl(String value) async {
    final normalized = value.trim().replaceFirst(RegExp(r'/$'), '');
    await _preferences.setString(_baseUrlKey, normalized);
  }
}
