import 'dart:async';
import 'dart:io';

import 'package:egg_tray_counter/services/device_auth.dart';
import 'package:egg_tray_counter/services/ipv4_first.dart';
import 'package:egg_tray_counter/services/network_probe.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/loopback_tls.dart';

final _v4a = InternetAddress('192.0.2.10');
final _v4b = InternetAddress('192.0.2.11');
final _v6 = InternetAddress('2001:db8::10');
// A DNS64-synthesised address: must be tried like any other AAAA answer.
final _nat64 = InternetAddress('64:ff9b::c000:20a');

/// Fake dialling: records the order of attempts and answers per address.
class _Dialer {
  _Dialer(this.answers);

  final Map<InternetAddress, Future<String> Function()> answers;
  final List<String> dialled = [];
  final List<String> discarded = [];
  final Stopwatch clock = Stopwatch()..start();
  final Map<String, int> startedAtMs = {};

  Future<String> dial(InternetAddress address) {
    dialled.add(address.address);
    startedAtMs[address.address] = clock.elapsedMilliseconds;
    return answers[address]!();
  }
}

FamilyRace<String> _race(
  _Dialer dialer, {
  List<InternetAddress> a = const [],
  List<InternetAddress> aaaa = const [],
  Object? aError,
  FamilyMode mode = FamilyMode.ipv4First,
  Duration headStart = const Duration(seconds: 5),
  List<InternetAddressType>? lookups,
}) => FamilyRace<String>(
  host: 'api.example.test',
  lookup: (type) async {
    lookups?.add(type);
    if (type == InternetAddressType.IPv4) {
      if (aError != null) throw aError;
      return a;
    }
    return aaaa;
  },
  dial: dialer.dial,
  discard: dialer.discarded.add,
  mode: mode,
  headStart: headStart,
);

Future<String> _after(int ms, String value) =>
    Future.delayed(Duration(milliseconds: ms), () => value);

Future<String> _failAfter(int ms) => Future.delayed(
  Duration(milliseconds: ms),
  () => throw const SocketException('Network is unreachable'),
);

void main() {
  group('IPv4-first connector ordering', () {
    test('IPv4 is tried first and IPv6 is not dialled when IPv4 connects '
        'within the head start', () async {
      final dialer = _Dialer({
        _v4a: () => _after(20, 'v4'),
        _v6: () => _after(0, 'v6'),
      });
      final race = _race(dialer, a: [_v4a], aaaa: [_v6]);
      expect(await race.start(), 'v4');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(dialer.dialled, ['192.0.2.10']);
      expect(race.won, isTrue);
    });

    test('a failed IPv4 attempt starts IPv6 at once, not after the head '
        'start', () async {
      final dialer = _Dialer({
        _v4a: () => _failAfter(0),
        _v4b: () => _failAfter(0),
        _v6: () => _after(10, 'v6'),
      });
      final race = _race(dialer, a: [_v4a, _v4b], aaaa: [_v6]);
      final clock = Stopwatch()..start();
      expect(await race.start(), 'v6');
      expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
      expect(dialer.dialled.first, '192.0.2.10');
      expect(dialer.dialled, contains('2001:db8::10'));
    });

    test('no A records (or a failed A lookup) goes straight to IPv6, and a '
        'NAT64 AAAA answer is used', () async {
      for (final aError in [null, const SocketException('no A')]) {
        final dialer = _Dialer({_nat64: () => _after(5, 'nat64')});
        final race = _race(dialer, aaaa: [_nat64], aError: aError);
        final clock = Stopwatch()..start();
        expect(await race.start(), 'nat64');
        expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
        expect(dialer.dialled, ['64:ff9b::c000:20a']);
      }
    });

    test('a stalled IPv4 attempt lets IPv6 start when the head start runs '
        'out; the late IPv4 connection is discarded', () async {
      final stalled = Completer<String>();
      final dialer = _Dialer({
        _v4a: () => stalled.future,
        _v6: () => _after(5, 'v6'),
      });
      final race = _race(
        dialer,
        a: [_v4a],
        aaaa: [_v6],
        headStart: const Duration(milliseconds: 150),
      );
      expect(await race.start(), 'v6');
      expect(
        dialer.startedAtMs['2001:db8::10'],
        greaterThanOrEqualTo(dialer.startedAtMs['192.0.2.10']! + 140),
      );
      stalled.complete('late v4');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(dialer.discarded, ['late v4']);
    });

    test('when every family fails the last error is reported', () async {
      final dialer = _Dialer({
        _v4a: () => _failAfter(0),
        _v6: () => _failAfter(0),
      });
      final race = _race(dialer, a: [_v4a], aaaa: [_v6]);
      await expectLater(race.start(), throwsA(isA<SocketException>()));
      expect(dialer.dialled, ['192.0.2.10', '2001:db8::10']);
    });

    test('no address in any family is a lookup failure', () async {
      final race = _race(_Dialer({}), mode: FamilyMode.ipv6Only);
      await expectLater(
        race.start(),
        throwsA(
          isA<SocketException>().having(
            (e) => e.message,
            'message',
            contains('Failed host lookup'),
          ),
        ),
      );
    });

    test('forced families never look up or dial the other one', () async {
      final lookups = <InternetAddressType>[];
      final dialer = _Dialer({
        _v4a: () => _after(0, 'v4'),
        _v6: () => _after(0, 'v6'),
      });
      expect(
        await _race(
          dialer,
          a: [_v4a],
          aaaa: [_v6],
          mode: FamilyMode.ipv6Only,
          lookups: lookups,
        ).start(),
        'v6',
      );
      expect(lookups, [InternetAddressType.IPv6]);
      lookups.clear();
      expect(
        await _race(
          dialer,
          a: [_v4a],
          aaaa: [_v6],
          mode: FamilyMode.ipv4Only,
          lookups: lookups,
        ).start(),
        'v4',
      );
      expect(lookups, [InternetAddressType.IPv4]);
    });

    test('cancel stops the race and discards a connection that completes '
        'later', () async {
      final stalled = Completer<String>();
      final dialer = _Dialer({_v4a: () => stalled.future});
      final race = _race(dialer, a: [_v4a]);
      final result = race.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      race.cancel();
      await expectLater(result, throwsA(isA<SocketException>()));
      stalled.complete('late');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(dialer.discarded, ['late']);
      expect(race.won, isFalse);
    });

    test('only the connection handed out is reported as the winner; one that '
        'completes later is discarded', () async {
      final slow = Completer<String>();
      final dialer = _Dialer({
        _v4a: () => slow.future,
        _v6: () => _after(5, 'v6'),
      });
      final won = <String>[];
      final race = FamilyRace<String>(
        host: 'api.example.test',
        lookup: (type) async =>
            type == InternetAddressType.IPv4 ? [_v4a] : [_v6],
        dial: dialer.dial,
        discard: dialer.discarded.add,
        onWin: won.add,
        headStart: const Duration(milliseconds: 50),
      );
      expect(await race.start(), 'v6');
      expect(won, ['v6']);
      expect(race.settled, isTrue);
      slow.complete('v4');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(won, ['v6'], reason: 'the loser is never a winner');
      expect(dialer.discarded, ['v4']);
    });
  });

  group('connector sockets (loopback)', () {
    final localhost = InternetAddress.loopbackIPv4;

    test('a plain connection is logged once, as won, when the race hands it '
        'out', () async {
      final server = await HttpServer.bind(localhost, 0);
      server.listen((request) => request.response
        ..write('ok')
        ..close());
      final attempts = <DialAttempt>[];
      final client = ipv4FirstHttpClient(
        mode: FamilyMode.ipv4Only,
        onAttempt: attempts.add,
      );
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/health'),
        );
        final response = await request.close();
        await response.drain<void>();
        expect(response.statusCode, 200);
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
      expect(attempts, hasLength(1));
      expect(attempts.single.won, isTrue);
      expect(attempts.single.discarded, isFalse);
      expect(attempts.single.tcpMs, isNotNull);
      expect(attempts.single.toJson()['discarded'], isFalse);
    });

    test('a handshake that completes after the TLS timeout is closed when it '
        'does (it used to stay open)', () async {
      final server = await LoopbackServer.start(
        tlsDelay: const Duration(milliseconds: 700),
      );
      addTearDown(server.close);
      final attempts = <DialAttempt>[];
      final task = await connectIpv4First(
        Uri.parse('https://localhost:${server.port}/'),
        null,
        null,
        mode: FamilyMode.ipv4Only,
        tlsTimeout: const Duration(milliseconds: 200),
        context: loopbackClientContext(),
        onAttempt: attempts.add,
      );
      await expectLater(
        task.socket,
        throwsA(
          isA<SocketException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
      expect(attempts.single.failedPhase, 'tls');
      final peer = await server.firstPeer;
      // The server answers late; the client finishes and must then close.
      await peer.closed.future.timeout(const Duration(seconds: 5));
      expect(peer.handshakeDone, isTrue);
    });

    test('an attempt whose race was cancelled while TCP connected is closed '
        'before any TLS starts (it used to send a ClientHello and hang)', () async {
      final server = await LoopbackServer.start();
      addTearDown(server.close);
      final reached = Completer<void>();
      final release = Completer<void>();
      final task = await connectIpv4First(
        Uri.parse('https://localhost:${server.port}/'),
        null,
        null,
        mode: FamilyMode.ipv4Only,
        context: loopbackClientContext(),
        tcpConnect: (address, port) async {
          reached.complete();
          await release.future;
          return Socket.connect(address, port);
        },
      );
      final failed = expectLater(task.socket, throwsA(isA<SocketException>()));
      await reached.future;
      // HttpClient's connection timeout fires while TCP is connecting.
      task.cancel();
      release.complete();
      await failed;
      final peer = await server.firstPeer;
      await peer.closed.future.timeout(const Duration(seconds: 5));
      expect(peer.bytes, 0, reason: 'no ClientHello was sent');
    });

    test('the network probe measures a request over the forced family', () async {
      final server = await HttpServer.bind(localhost, 0);
      server.listen((request) => request.response
        ..write('{"status":"ok"}')
        ..close());
      addTearDown(() => server.close(force: true));
      final probe = NetworkProbe(
        baseUrl: 'http://127.0.0.1:${server.port}',
        deviceAuth: DeviceAuth(store: InMemorySecretStore()),
      );
      final ok = await probe.probe(
        'health',
        Uri.parse('http://127.0.0.1:${server.port}/health'),
        FamilyMode.ipv4Only,
        0,
      );
      expect(ok.outcome, 'ok');
      expect(ok.family, 'ipv4');
      expect(ok.status, 200);
      expect(ok.tcpMs, isNotNull);
      expect(ok.remote, '127.0.0.1');

      // Nothing listens on a port that was just freed: tcp_connect.
      final closed = await ServerSocket.bind(localhost, 0);
      final port = closed.port;
      await closed.close();
      final refused = await probe.probe(
        'health',
        Uri.parse('http://127.0.0.1:$port/health'),
        FamilyMode.ipv4Only,
        1,
      );
      expect(refused.outcome, 'tcp_connect');
      expect(refused.ok, isFalse);
    });
  });

  group('network test classification', () {
    DialAttempt attempt({String? failed, bool won = false}) =>
        DialAttempt(family: 'ipv4', address: '192.0.2.10')
          ..failedPhase = failed
          ..won = won;

    test('the furthest phase reached decides the class', () {
      const socket = SocketException('x');
      expect(NetworkProbe.classifyFailure(socket, []), 'dns');
      expect(
        NetworkProbe.classifyFailure(socket, [attempt(failed: 'tcp_connect')]),
        'tcp_connect',
      );
      expect(
        NetworkProbe.classifyFailure(socket, [
          attempt(failed: 'tcp_connect'),
          attempt(failed: 'tls'),
        ]),
        'tls',
      );
      expect(
        NetworkProbe.classifyFailure(TimeoutException('t'), [attempt(won: true)]),
        'timeout',
      );
      expect(
        NetworkProbe.classifyFailure(const HttpException('closed'), [
          attempt(won: true),
        ]),
        'dropped',
      );
      expect(
        NetworkProbe.classifyFailure(
          const SocketException('HTTP connection timed out'),
          [],
        ),
        'timeout',
      );
    });

    test('colo and ip are read from a /cdn-cgi/trace body', () {
      final trace = NetworkProbe.parseTrace(
        'fl=12f\nh=zero-x.live\nip=2409:40f4::1\nts=1\nvisit_scheme=https\n'
        'colo=MAA\nloc=IN\n',
      );
      expect(trace.colo, 'MAA');
      expect(trace.ip, '2409:40f4::1');
    });

    test('the summary groups by target and family', () {
      final summaries = ProbeSummary.of([
        const ProbeResult(
          target: 'health',
          family: 'ipv4',
          index: 0,
          outcome: 'ok',
          totalMs: 300,
          tcpMs: 100,
          tlsMs: 150,
          remote: '192.0.2.10',
        ),
        const ProbeResult(
          target: 'health',
          family: 'ipv4',
          index: 1,
          outcome: 'tls',
          totalMs: 5000,
        ),
        const ProbeResult(
          target: 'health',
          family: 'ipv6',
          index: 0,
          outcome: 'ok',
          totalMs: 500,
        ),
      ]);
      expect(summaries, hasLength(2));
      final v4 = summaries.first;
      expect(v4.okCount, 1);
      expect(v4.outcomes, {'ok': 1, 'tls': 1});
      expect(v4.meanTcpMs, 100);
      expect(v4.meanTotalMs, 300);
      expect(v4.remotes, {'192.0.2.10'});
    });
  });
}
