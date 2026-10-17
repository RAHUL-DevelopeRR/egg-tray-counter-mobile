import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Where the device credential lives. Abstract so tests use memory.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Android secure storage (Keystore-wrapped). An unreadable store, e.g. after
/// a backup restored onto another phone, is reset, which makes a new device
/// id that needs approval again: the same as a reinstall.
class SecureSecretStore implements SecretStore {
  const SecureSecretStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

class InMemorySecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// This phone's credential: a random id and a 32-byte secret made on first
/// launch. Neither is ever in the APK, the repo or a log line.
class DeviceIdentity {
  const DeviceIdentity({required this.deviceId, required this.secret});

  final String deviceId;
  final String secret;

  String get displayCode => displayCodeFor(deviceId);

  /// First 8 hex digits of the id as XXXX-XXXX, what the admin approves.
  static String displayCodeFor(String deviceId) {
    final hex = deviceId.replaceAll('-', '').toUpperCase();
    if (hex.length < 8) return hex;
    return '${hex.substring(0, 4)}-${hex.substring(4, 8)}';
  }

  @override
  String toString() => 'DeviceIdentity($displayCode)';
}

enum DeviceStatus { pending, active, revoked, unknown }

/// What the server says about this phone, in the words the home screen shows.
class DeviceState {
  const DeviceState({
    required this.authRequired,
    this.status = DeviceStatus.unknown,
    this.displayCode,
    this.problem,
    this.unreachable = false,
  });

  /// The server does not ask for device credentials (production today).
  static const open = DeviceState(authRequired: false);

  final bool authRequired;
  final DeviceStatus status;
  final String? displayCode;

  /// Why the status could not be read, in the operator's words.
  final String? problem;

  /// The check got no answer at all (connection dropped) and the server
  /// had never answered it before. Not a refusal: a scan may start, and the
  /// server's own 401/403 on the upload stops a phone it refuses.
  final bool unreachable;

  /// Approved (or no approval needed): the server will take this phone's
  /// scans.
  bool get mayScan => !authRequired || status == DeviceStatus.active;

  String get _device => displayCode == null ? '' : ' - device $displayCode';

  String get label => switch (status) {
    DeviceStatus.active => 'DEVICE APPROVED',
    DeviceStatus.pending => 'WAITING FOR APPROVAL$_device',
    DeviceStatus.revoked => 'DEVICE REVOKED$_device',
    DeviceStatus.unknown => 'DEVICE NOT CHECKED$_device',
  };

  /// Why a scan cannot start, or null when it can: only a definite answer
  /// from the server (pending, revoked, a refused check) blocks one.
  String? get blockReason {
    if (mayScan || unreachable) return null;
    final code = displayCode ?? 'code unknown';
    return switch (status) {
      DeviceStatus.pending =>
        'This phone is waiting for approval (device $code). Ask the admin '
            'to approve it, then pull down on the home screen to check again.',
      DeviceStatus.revoked =>
        'This phone has been revoked (device $code) and cannot send scans.',
      _ =>
        problem ??
            'The phone could not confirm its approval with the server '
                '(device $code). Check the connection and try again.',
    };
  }

  static DeviceStatus parseStatus(Object? value) => switch (value) {
    'active' => DeviceStatus.active,
    'pending' => DeviceStatus.pending,
    'revoked' => DeviceStatus.revoked,
    _ => DeviceStatus.unknown,
  };
}

/// What a server's /health advertises.
class ServerInfo {
  const ServerInfo({
    required this.ok,
    required this.deviceAuth,
    required this.scanJobs,
    required this.modelScan,
  });

  factory ServerInfo.fromHealth(Map<String, dynamic>? data) {
    final contracts = data?['scan_contracts'];
    final list = contracts is List ? contracts : const [];
    return ServerInfo(
      ok: data?['status'] == 'ok',
      deviceAuth: data?['auth'] == 'device_v1',
      scanJobs: list.contains('scan_jobs_v1'),
      modelScan: list.contains('model_spatial_v1'),
    );
  }

  final bool ok;

  /// `auth: device_v1`: every request carries the device credential.
  final bool deviceAuth;

  /// `scan_jobs_v1`: results are stored and can be fetched by scan id.
  final bool scanJobs;
  final bool modelScan;
}

/// The device credential plus what each server (by origin) advertised.
/// Credentials are attached only to a server whose /health said `device_v1`,
/// so they never go to production while it stays open, nor to other hosts.
class DeviceAuth {
  DeviceAuth({required this.store, Random? random})
    : _random = random ?? Random.secure();

  static final DeviceAuth shared = DeviceAuth(store: const SecureSecretStore());

  static const _idKey = 'egg_device_id_v1';
  static const _secretKey = 'egg_device_secret_v1';

  final SecretStore store;
  final Random _random;
  Future<DeviceIdentity>? _identity;
  DeviceIdentity? _cached;
  final Map<String, ({ServerInfo info, DateTime at})> _servers = {};
  final Map<String, DeviceState> _states = {};
  final Set<String> _registered = {};

  static String originOf(Uri uri) => '${uri.scheme}://${uri.host}:${uri.port}';

  /// Loaded (or created on first launch) once per process.
  Future<DeviceIdentity> identity() async {
    final pending = _identity ??= _loadOrCreate();
    try {
      return _cached = await pending;
    } on Object {
      if (identical(_identity, pending)) _identity = null;
      rethrow;
    }
  }

  /// The identity if it has been loaded, for display only.
  DeviceIdentity? get cachedIdentity => _cached;

  /// The identity once the launch has loaded it, without touching storage
  /// itself (null if loading never started or failed). For display only.
  Future<DeviceIdentity?> loadedIdentity() async {
    final pending = _identity;
    if (pending == null) return _cached;
    try {
      return await pending;
    } on Object {
      return null;
    }
  }

  Future<DeviceIdentity> _loadOrCreate() async {
    final id = await store.read(_idKey);
    final secret = await store.read(_secretKey);
    if (id != null && secret != null && id.isNotEmpty && secret.isNotEmpty) {
      return DeviceIdentity(deviceId: id, secret: secret);
    }
    final fresh = DeviceIdentity(
      deviceId: const Uuid().v4(),
      secret: _newSecret(),
    );
    // The id is written last: a launch that dies in between starts over.
    await store.write(_secretKey, fresh.secret);
    await store.write(_idKey, fresh.deviceId);
    return fresh;
  }

  /// 32 random bytes as unpadded base64url (43 characters).
  String _newSecret() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  void noteHealth(Uri uri, Map<String, dynamic>? data) {
    _servers[originOf(uri)] = (
      info: ServerInfo.fromHealth(data),
      at: DateTime.now(),
    );
  }

  /// What the server last advertised; null if never asked, or if [maxAge]
  /// is given and the answer is older.
  ServerInfo? serverInfo(Uri uri, {Duration? maxAge}) {
    final entry = _servers[originOf(uri)];
    if (entry == null) return null;
    if (maxAge != null && DateTime.now().difference(entry.at) > maxAge) {
      return null;
    }
    return entry.info;
  }

  bool requiresAuth(Uri uri) =>
      _servers[originOf(uri)]?.info.deviceAuth ?? false;

  DeviceState? stateFor(Uri uri) => _states[originOf(uri)];

  void noteState(Uri uri, DeviceState state) =>
      _states[originOf(uri)] = state;

  bool isRegistered(Uri uri) => _registered.contains(originOf(uri));

  void markRegistered(Uri uri) => _registered.add(originOf(uri));
}

/// Adds `X-Device-Id` and `Authorization: Device <secret>` to every request
/// for a server that advertised `device_v1`. Nothing here logs.
class DeviceAuthInterceptor extends Interceptor {
  DeviceAuthInterceptor(this.auth);

  final DeviceAuth auth;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (auth.requiresAuth(options.uri)) {
      try {
        final identity = await auth.identity();
        options.headers['X-Device-Id'] = identity.deviceId;
        options.headers['Authorization'] = 'Device ${identity.secret}';
      } on Object {
        // No credential (secure storage failed): the server answers 401 and
        // the app shows NOT AUTHORISED instead of crashing.
      }
    }
    handler.next(options);
  }
}
