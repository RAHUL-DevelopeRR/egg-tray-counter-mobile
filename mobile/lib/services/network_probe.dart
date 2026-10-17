import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'device_auth.dart';
import 'ipv4_first.dart';

/// One measured request of the network test. Logged as one `EGGNET {json}`
/// line; holds addresses, timings and the outcome, never credentials.
class ProbeResult {
  const ProbeResult({
    required this.target,
    required this.family,
    required this.index,
    required this.outcome,
    required this.totalMs,
    this.status,
    this.tcpMs,
    this.tlsMs,
    this.remote,
    this.colo,
    this.ip,
    this.detail,
  });

  /// `health`, `trace` (Cloudflare control) or `upload`.
  final String target;

  /// `ipv4`, `ipv6` or `auto` (the app's IPv4-first connector).
  final String family;
  final int index;

  /// dns, tcp_connect, tls, timeout, dropped (connection lost after TLS,
  /// before a full answer), `http_<status>` or ok.
  final String outcome;
  final int totalMs;
  final int? status;
  final int? tcpMs;
  final int? tlsMs;
  final String? remote;
  final String? colo;
  final String? ip;
  final String? detail;

  bool get ok => outcome == 'ok';

  Map<String, Object?> toJson() => {
    'target': target,
    'family': family,
    'i': index,
    'class': outcome,
    'status': status,
    'tcp_ms': tcpMs,
    'tls_ms': tlsMs,
    'total_ms': totalMs,
    'remote': remote,
    'colo': ?colo,
    'ip': ?ip,
    'detail': ?detail,
  };
}

/// Network test: GET /health forced over IPv4 and over IPv6 through the
/// same connector the app uses, Cloudflare's /cdn-cgi/trace on a domain
/// served from India as a control, and (for an approved phone) uploads of
/// about 500 KB that the server discards. Every request opens a fresh
/// connection so each one measures DNS, TCP and TLS.
class NetworkProbe {
  NetworkProbe({
    required this.baseUrl,
    required this.deviceAuth,
    this.healthPerFamily = 20,
    this.tracePerFamily = 10,
    this.uploads = 3,
    this.uploadBytes = 500 * 1024,
  });

  static final controlTrace = Uri.parse('https://zero-x.live/cdn-cgi/trace');

  final String baseUrl;
  final DeviceAuth deviceAuth;
  final int healthPerFamily;
  final int tracePerFamily;
  final int uploads;
  final int uploadBytes;
  bool _stopped = false;

  void stop() => _stopped = true;

  int plannedCount({required bool withUploads}) =>
      healthPerFamily * 2 + tracePerFamily * 2 + (withUploads ? uploads : 0);

  /// The families are interleaved so both see the same moment of the link.
  Stream<ProbeResult> run({required bool withUploads}) async* {
    final base = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final health = Uri.parse('$base/health');
    for (var i = 0; i < healthPerFamily && !_stopped; i++) {
      yield await probe('health', health, FamilyMode.ipv4Only, i);
      if (_stopped) break;
      yield await probe('health', health, FamilyMode.ipv6Only, i);
    }
    for (var i = 0; i < tracePerFamily && !_stopped; i++) {
      yield await probe('trace', controlTrace, FamilyMode.ipv4Only, i);
      if (_stopped) break;
      yield await probe('trace', controlTrace, FamilyMode.ipv6Only, i);
    }
    if (!withUploads) return;
    final identity = await deviceAuth.identity();
    final random = Random();
    final body = Uint8List(uploadBytes);
    for (var i = 0; i < body.length; i++) {
      body[i] = random.nextInt(256);
    }
    final upload = Uri.parse('$base/v1/diagnostics/upload');
    for (var i = 0; i < uploads && !_stopped; i++) {
      yield await probe(
        'upload',
        upload,
        FamilyMode.ipv4First,
        i,
        method: 'POST',
        body: body,
        headers: {
          'X-Device-Id': identity.deviceId,
          'Authorization': 'Device ${identity.secret}',
          'Content-Type': 'application/octet-stream',
        },
      );
    }
  }

  /// One request on its own HttpClient (a fresh connection), classified.
  Future<ProbeResult> probe(
    String target,
    Uri uri,
    FamilyMode mode,
    int index, {
    String method = 'GET',
    List<int>? body,
    Map<String, String> headers = const {},
    Duration deadline = const Duration(seconds: 25),
  }) async {
    final attempts = <DialAttempt>[];
    final client = ipv4FirstHttpClient(mode: mode, onAttempt: attempts.add)
      ..connectionTimeout = const Duration(seconds: 12);
    final clock = Stopwatch()..start();
    final family = switch (mode) {
      FamilyMode.ipv4Only => 'ipv4',
      FamilyMode.ipv6Only => 'ipv6',
      FamilyMode.ipv4First => 'auto',
    };
    ProbeResult result({
      required String outcome,
      int? status,
      String? text,
      String? remote,
      String? detail,
    }) {
      final won = attempts.where((a) => a.won).lastOrNull;
      final trace = text == null ? null : parseTrace(text);
      return ProbeResult(
        target: target,
        family: family,
        index: index,
        outcome: outcome,
        totalMs: clock.elapsedMilliseconds,
        status: status,
        tcpMs: (won ?? attempts.lastOrNull)?.tcpMs,
        tlsMs: (won ?? attempts.lastOrNull)?.tlsMs,
        remote: remote ?? won?.address ?? attempts.lastOrNull?.address,
        colo: trace?.colo,
        ip: trace?.ip,
        detail: detail,
      );
    }

    try {
      final exchange = () async {
        final request = await client.openUrl(method, uri);
        headers.forEach(request.headers.set);
        if (body != null) {
          request.contentLength = body.length;
          request.add(body);
        }
        final response = await request.close();
        final text = await response.transform(utf8.decoder).join();
        return (
          status: response.statusCode,
          text: text,
          remote: response.connectionInfo?.remoteAddress.address,
        );
      }();
      final answer = await exchange.timeout(deadline);
      final ok = answer.status >= 200 && answer.status < 300;
      return result(
        outcome: ok ? 'ok' : 'http_${answer.status}',
        status: answer.status,
        text: target == 'trace' ? answer.text : null,
        remote: answer.remote,
      );
    } on Object catch (error) {
      return result(
        outcome: classifyFailure(error, attempts),
        detail: shortError(error),
      );
    } finally {
      client.close(force: true);
    }
  }

  /// The furthest phase reached decides the class: no address at all is
  /// dns; a connection that never finished TCP is tcp_connect; one that
  /// failed the TLS handshake is tls; a connection lost after TLS is
  /// dropped; running out of time anywhere else is timeout.
  static String classifyFailure(Object error, List<DialAttempt> attempts) {
    if (attempts.any((a) => a.won)) {
      return error is TimeoutException ? 'timeout' : 'dropped';
    }
    if (attempts.any((a) => a.failedPhase == 'tls')) return 'tls';
    if (attempts.any((a) => a.failedPhase == 'tcp_connect')) {
      return 'tcp_connect';
    }
    if (error is TimeoutException ||
        (error is SocketException && error.message.contains('timed out'))) {
      return 'timeout';
    }
    if (error is SocketException) return 'dns';
    if (error is HandshakeException || error is TlsException) return 'tls';
    return 'timeout';
  }

  /// `colo=` (the Cloudflare data centre) and `ip=` (the address the server
  /// saw) from a /cdn-cgi/trace body.
  static ({String? colo, String? ip}) parseTrace(String body) {
    String? colo;
    String? ip;
    for (final line in const LineSplitter().convert(body)) {
      if (line.startsWith('colo=')) colo = line.substring(5).trim();
      if (line.startsWith('ip=')) ip = line.substring(3).trim();
    }
    return (colo: colo, ip: ip);
  }
}

/// One row of the summary table: a target over one family.
class ProbeSummary {
  ProbeSummary(this.target, this.family);

  final String target;
  final String family;
  final List<ProbeResult> results = [];

  int get okCount => results.where((r) => r.ok).length;

  Map<String, int> get outcomes {
    final counts = <String, int>{};
    for (final r in results) {
      counts[r.outcome] = (counts[r.outcome] ?? 0) + 1;
    }
    return counts;
  }

  int? _mean(Iterable<int?> values) {
    final list = values.whereType<int>().toList();
    if (list.isEmpty) return null;
    return (list.reduce((a, b) => a + b) / list.length).round();
  }

  int? get meanTcpMs => _mean(results.where((r) => r.ok).map((r) => r.tcpMs));
  int? get meanTlsMs => _mean(results.where((r) => r.ok).map((r) => r.tlsMs));
  int? get meanTotalMs =>
      _mean(results.where((r) => r.ok).map((r) => r.totalMs));

  Set<String> get remotes => {
    for (final r in results)
      if (r.remote != null) r.remote!,
  };

  Set<String> get colos => {
    for (final r in results)
      if (r.colo != null) r.colo!,
  };

  static List<ProbeSummary> of(List<ProbeResult> results) {
    final groups = <String, ProbeSummary>{};
    for (final r in results) {
      groups
          .putIfAbsent(
            '${r.target}/${r.family}',
            () => ProbeSummary(r.target, r.family),
          )
          .results
          .add(r);
    }
    return groups.values.toList(growable: false);
  }
}
