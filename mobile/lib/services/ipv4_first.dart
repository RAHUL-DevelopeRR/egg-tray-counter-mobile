import 'dart:async';
import 'dart:io';

/// Which address families a connection may use. The app uses [ipv4First];
/// the network test forces one family at a time.
enum FamilyMode { ipv4First, ipv4Only, ipv6Only }

/// One connection attempt to one address: what the network test reports and
/// what every new app connection logs. Never holds request data.
class DialAttempt {
  DialAttempt({required this.family, required this.address});

  final String family;
  final String address;
  int? tcpMs;
  int? tlsMs;

  /// `tcp_connect` or `tls` when the attempt failed, `cancelled` when the
  /// race was over before it finished, else null.
  String? failedPhase;
  String? error;

  /// The one connection the race handed out. A connection that completed
  /// after another one won is [discarded] (and closed), never won.
  bool won = false;
  bool discarded = false;

  Map<String, Object?> toJson() => {
    'family': family,
    'address': address,
    'tcp_ms': tcpMs,
    'tls_ms': tlsMs,
    'failed_phase': failedPhase,
    'error': error,
    'won': won,
    'discarded': discarded,
  };
}

/// IPv4-first dialling over both address families, independent of sockets so
/// the ordering can be tested with fake lookups and dials.
///
/// IPv4 gets [headStart]; IPv6 joins as soon as IPv4 has no addresses, an
/// IPv4 attempt fails, or the head start runs out. Both then run in parallel
/// and the first connection wins; later ones are discarded. On the Jio link
/// IPv6 lost half its packets while IPv4 lost none (13 Oct), and Dart's own
/// 250 ms TCP-only stagger never falls back after a failed TLS handshake.
/// AAAA answers are never filtered: on NAT64 networks they are the only way.
class FamilyRace<T> {
  FamilyRace({
    required this.host,
    required this.lookup,
    required this.dial,
    required this.discard,
    this.onWin,
    this.mode = FamilyMode.ipv4First,
    this.headStart = const Duration(milliseconds: 1500),
  }) {
    // Errors reach whoever awaits [result]; a cancelled race nobody awaits
    // must not surface as an uncaught error.
    _winner.future.ignore();
  }

  final String host;
  final Future<List<InternetAddress>> Function(InternetAddressType type) lookup;
  final Future<T> Function(InternetAddress address) dial;

  /// A connection that completed after the race was decided or cancelled.
  final void Function(T connection) discard;

  /// The connection the race hands out, just before [result] completes.
  final void Function(T connection)? onWin;
  final FamilyMode mode;
  final Duration headStart;

  final _winner = Completer<T>();
  final List<Object> _dialErrors = [];
  final List<Object> _lookupErrors = [];
  bool _cancelled = false;
  bool _started = false;
  bool _won = false;
  Timer? _timer;

  Future<T> get result => _winner.future;

  /// True once a connection has been handed out.
  bool get won => _won;

  /// True once the race is won, failed or cancelled: an attempt still
  /// running is no longer needed.
  bool get settled => _cancelled || _winner.isCompleted;

  Future<T> start() {
    if (!_started) {
      _started = true;
      unawaited(_run());
    }
    return result;
  }

  /// Stops all attempts; a connection that completes later is discarded.
  void cancel() {
    if (_winner.isCompleted) return;
    _cancelled = true;
    _timer?.cancel();
    _winner.completeError(
      SocketException('Connection attempt to $host cancelled'),
    );
  }

  Future<void> _run() async {
    final v4 = mode == FamilyMode.ipv6Only
        ? Future.value(const <InternetAddress>[])
        : _lookup(InternetAddressType.IPv4);
    final v6 = mode == FamilyMode.ipv4Only
        ? Future.value(const <InternetAddress>[])
        : _lookup(InternetAddressType.IPv6);
    final openV6 = Completer<void>();
    void startV6() {
      if (!openV6.isCompleted) openV6.complete();
    }

    final v4Run = v4.then((addresses) => _family(addresses, startV6));
    if (mode == FamilyMode.ipv4First) {
      _timer = Timer(headStart, startV6);
      unawaited(v4Run.whenComplete(startV6));
    } else {
      startV6();
    }
    await openV6.future;
    _timer?.cancel();
    final v6Run = settled
        ? Future.value(false)
        : v6.then((addresses) => _family(addresses, null));
    await Future.wait([v4Run, v6Run]);
    if (!settled) _winner.completeError(_failure());
  }

  Future<List<InternetAddress>> _lookup(InternetAddressType type) async {
    try {
      return await lookup(type);
    } on Object catch (error) {
      _lookupErrors.add(error);
      return const [];
    }
  }

  /// Tries one family's addresses in order. [onFailure] lets IPv6 start at
  /// once when IPv4 has nothing or its first attempt fails.
  Future<bool> _family(
    List<InternetAddress> addresses,
    void Function()? onFailure,
  ) async {
    if (addresses.isEmpty) {
      onFailure?.call();
      return false;
    }
    for (final address in addresses) {
      if (settled) return false;
      try {
        final connection = await dial(address);
        if (settled) {
          discard(connection);
          return false;
        }
        _won = true;
        onWin?.call(connection);
        _winner.complete(connection);
        return true;
      } on Object catch (error) {
        _dialErrors.add(error);
        onFailure?.call();
      }
    }
    return false;
  }

  Object _failure() {
    if (_dialErrors.isNotEmpty) return _dialErrors.last;
    if (_lookupErrors.isNotEmpty) return _lookupErrors.first;
    final family = switch (mode) {
      FamilyMode.ipv4Only => 'IPv4 ',
      FamilyMode.ipv6Only => 'IPv6 ',
      FamilyMode.ipv4First => '',
    };
    return SocketException("Failed host lookup: no ${family}address for '$host'");
  }
}

/// `HttpClient.connectionFactory` with IPv4 first. For a direct https request
/// HttpClient uses the returned socket as it is, so TLS happens here, inside
/// each per-family attempt, with `host:` set so SNI and the certificate check
/// use the host name rather than the address (measured: an IP-literal socket
/// without it fails the handshake). [context] replaces the system trust store
/// and [tcpConnect] replaces `Socket.connect` (tests only).
///
/// Closing attempts: once `SecureSocket.secure(tcp)` starts, `tcp` no longer
/// owns the socket (`tcp.destroy()` then does nothing) and nothing public can
/// close it until the handshake ends. So an attempt is not secured at all
/// once the race is over; a handshake abandoned on timeout or cancel is
/// closed the moment it completes; and on Android a handshake that never
/// completes is bounded by keepalive and TCP_USER_TIMEOUT (a dead path closes
/// within about 20 s). A peer that keeps acknowledging but never answers the
/// handshake still holds the socket until it closes its side.
Future<ConnectionTask<Socket>> connectIpv4First(
  Uri uri,
  String? proxyHost,
  int? proxyPort, {
  FamilyMode mode = FamilyMode.ipv4First,
  Duration headStart = const Duration(milliseconds: 1500),
  Duration tcpTimeout = const Duration(seconds: 4),
  Duration tlsTimeout = const Duration(seconds: 5),
  SecurityContext? context,
  Future<Socket> Function(InternetAddress address, int port)? tcpConnect,
  void Function(DialAttempt attempt)? onAttempt,
}) async {
  if (proxyHost != null) {
    // Through a proxy HttpClient sends CONNECT and secures the tunnel itself.
    return Socket.startConnect(proxyHost, proxyPort!);
  }
  final host = uri.host;
  final secure = uri.isScheme('https');
  final port = uri.hasPort ? uri.port : (secure ? 443 : 80);
  // Connected attempts waiting for the race's verdict; each is logged once
  // the verdict is known (won or discarded), so a loser is never "won".
  final decided = Map<Socket, DialAttempt>.identity();
  late final FamilyRace<Socket> race;

  Never fail(
    DialAttempt attempt,
    String phase,
    Object error, [
    Object? thrown,
  ]) {
    attempt
      ..failedPhase = phase
      ..error = shortError(error);
    onAttempt?.call(attempt);
    throw thrown ?? error;
  }

  Future<Socket> dial(InternetAddress address) async {
    final attempt = DialAttempt(
      family: address.type == InternetAddressType.IPv6 ? 'ipv6' : 'ipv4',
      address: address.address,
    );
    final clock = Stopwatch()..start();
    final Socket tcp;
    try {
      tcp = await (tcpConnect != null
          ? tcpConnect(address, port)
          : Socket.connect(address, port, timeout: tcpTimeout));
    } on Object catch (error) {
      attempt.tcpMs = clock.elapsedMilliseconds;
      fail(attempt, 'tcp_connect', error);
    }
    attempt.tcpMs = clock.elapsedMilliseconds;
    if (race.settled) {
      // Won, failed or cancelled while this one connected: close it while
      // it can still be closed, before any handshake starts.
      tcp.destroy();
      fail(
        attempt,
        'cancelled',
        SocketException('Connection attempt to $host no longer needed'),
      );
    }
    if (!secure) {
      decided[tcp] = attempt;
      return tcp;
    }
    final bounded = boundHandshake(tcp);
    clock.reset();
    final handshake = SecureSocket.secure(tcp, host: host, context: context);
    final SecureSocket tls;
    try {
      tls = await handshake.timeout(tlsTimeout);
    } on Object catch (error) {
      closeWhenDone(handshake);
      attempt.tlsMs = clock.elapsedMilliseconds;
      fail(
        attempt,
        'tls',
        error,
        error is TimeoutException
            ? SocketException('TLS handshake with $host timed out')
            : null,
      );
    }
    attempt.tlsMs = clock.elapsedMilliseconds;
    // A connection the race no longer needs goes back as it is: the race
    // discards (closes) it.
    if (bounded && !race.settled && !unboundHandshake(tls)) {
      // The handshake's limits would cut a slow upload short: not usable.
      tls.destroy();
      fail(
        attempt,
        'tls',
        SocketException('Could not reset the socket options for $host'),
      );
    }
    decided[tls] = attempt;
    return tls;
  }

  race = FamilyRace<Socket>(
    host: host,
    lookup: (type) => InternetAddress.lookup(host, type: type),
    dial: dial,
    discard: (socket) {
      socket.destroy();
      final attempt = decided.remove(socket);
      if (attempt != null) onAttempt?.call(attempt..discarded = true);
    },
    onWin: (socket) {
      final attempt = decided.remove(socket);
      if (attempt != null) onAttempt?.call(attempt..won = true);
    },
    mode: mode,
    headStart: headStart,
  );
  return ConnectionTask.fromSocket(race.start(), () {
    // HttpClient cancels on its connection timeout or on close(force: true).
    if (race.won) return;
    // A TCP connect still running sees the cancel and closes its socket; a
    // handshake still running is discarded or closed when it ends.
    race.cancel();
  });
}

/// Closes a handshake's socket whenever it completes, however late; a failed
/// handshake has already closed its own.
void closeWhenDone(Future<SecureSocket> handshake) =>
    unawaited(handshake.then((socket) => socket.destroy(), onError: (_) {}));

// Linux/Android socket option numbers (dart:io has no names for them).
const _solSocket = 1;
const _soKeepalive = 9;
const _ipprotoTcp = 6;
const _tcpKeepidle = 4;
const _tcpKeepintvl = 5;
const _tcpKeepcnt = 6;
const _tcpUserTimeout = 18;

/// Limits for a socket about to be handed to `SecureSocket.secure`:
/// keepalive after 5 s idle (3 probes 5 s apart) closes a handshake whose
/// ClientHello was acknowledged on a path that then died; TCP_USER_TIMEOUT
/// (20 s) closes one whose ClientHello is never acknowledged. Android and
/// Linux only; false when nothing was set.
bool boundHandshake(Socket tcp) {
  if (!Platform.isAndroid && !Platform.isLinux) return false;
  if (_setAll(tcp, [
    RawSocketOption.fromInt(_solSocket, _soKeepalive, 1),
    RawSocketOption.fromInt(_ipprotoTcp, _tcpKeepidle, 5),
    RawSocketOption.fromInt(_ipprotoTcp, _tcpKeepintvl, 5),
    RawSocketOption.fromInt(_ipprotoTcp, _tcpKeepcnt, 3),
    RawSocketOption.fromInt(_ipprotoTcp, _tcpUserTimeout, 20000),
  ])) {
    return true;
  }
  // Half-applied limits must not outlive the handshake: undo them all.
  unboundHandshake(tcp);
  return false;
}

/// Puts the 0.4.11 defaults back after a completed handshake (no keepalive,
/// no user timeout): a slow upload or a long wait for the count must not be
/// cut off by the handshake's limits. False if any of it failed.
bool unboundHandshake(Socket socket) => _setAll(socket, [
  RawSocketOption.fromInt(_solSocket, _soKeepalive, 0),
  RawSocketOption.fromInt(_ipprotoTcp, _tcpUserTimeout, 0),
]);

/// Sets every option, going on past a failure; true when all were set.
bool _setAll(Socket socket, List<RawSocketOption> options) {
  var all = true;
  for (final option in options) {
    try {
      socket.setRawOption(option);
    } on Object {
      all = false;
    }
  }
  return all;
}

/// The app's HttpClient: IPv4-first connections, no proxy lookup, and idle
/// connections closed after 3 s so a connection on a bad path is not reused
/// for long (dio's own 3 s default is lost once createHttpClient is set).
HttpClient ipv4FirstHttpClient({
  FamilyMode mode = FamilyMode.ipv4First,
  SecurityContext? context,
  void Function(DialAttempt attempt)? onAttempt,
}) => HttpClient()
  ..idleTimeout = const Duration(seconds: 3)
  ..findProxy = ((_) => 'DIRECT')
  ..connectionFactory = (uri, proxyHost, proxyPort) => connectIpv4First(
    uri,
    proxyHost,
    proxyPort,
    mode: mode,
    context: context,
    onAttempt: onAttempt,
  );

// Exception type and first line, short enough for one log line.
String shortError(Object error) {
  final text = error.toString().split('\n').first;
  return text.length > 160 ? text.substring(0, 160) : text;
}
