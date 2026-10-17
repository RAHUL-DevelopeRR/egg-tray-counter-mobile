import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A throwaway self-signed certificate for `localhost` / 127.0.0.1, made for
/// these loopback tests only (openssl, EC P-256, valid to 2126). It protects
/// nothing and is trusted only by [loopbackClientContext].
const _certificatePem = '''
-----BEGIN CERTIFICATE-----
MIIBmzCCAUGgAwIBAgIUN7r9kM/V5Iai6Zzo3xcLusRG2yIwCgYIKoZIzj0EAwIw
FDESMBAGA1UEAwwJbG9jYWxob3N0MCAXDTI2MTAxNTEwMDgzMVoYDzIxMjYwOTIx
MTAwODMxWjAUMRIwEAYDVQQDDAlsb2NhbGhvc3QwWTATBgcqhkjOPQIBBggqhkjO
PQMBBwNCAASlIz2Hh3gYEoJvBsDoJWRpHR5AiWNmDZJvOxqY+IIC8idswnEistFL
r6OYHV25bA1lDACPehA6e4Tjc30aa9DQo28wbTAdBgNVHQ4EFgQUYYSvo7roTC4r
qMGXT6LRzIVQlbAwHwYDVR0jBBgwFoAUYYSvo7roTC4rqMGXT6LRzIVQlbAwDwYD
VR0TAQH/BAUwAwEB/zAaBgNVHREEEzARgglsb2NhbGhvc3SHBH8AAAEwCgYIKoZI
zj0EAwIDSAAwRQIgaZgZraJ5yU7nqZrbQiLzSrFN0LutNrj30diZ4ghOy4MCIQCC
knoJH+CtgtCJCdY9ngWILqwx2lR/NGJiRWh15uH9IQ==
-----END CERTIFICATE-----
''';

const _testOnlyKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgcjs9H/JM6wyiC7hS
oaqGc43wtJdAhaQfWMXa2PwRD6ihRANCAASlIz2Hh3gYEoJvBsDoJWRpHR5AiWNm
DZJvOxqY+IIC8idswnEistFLr6OYHV25bA1lDACPehA6e4Tjc30aa9DQ
-----END PRIVATE KEY-----
''';

/// Trusts only the loopback test certificate.
SecurityContext loopbackClientContext() =>
    SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(utf8.encode(_certificatePem));

SecurityContext _serverContext() => SecurityContext()
  ..useCertificateChainBytes(utf8.encode(_certificatePem))
  ..usePrivateKeyBytes(utf8.encode(_testOnlyKeyPem));

/// One TCP connection a [LoopbackServer] accepted.
class Peer {
  /// Bytes received before any TLS (a ClientHello is about 250).
  int bytes = 0;

  /// The server finished its side of a TLS handshake.
  bool handshakeDone = false;

  /// Completes when the client closes (or resets) the connection.
  final Completer<void> closed = Completer<void>();

  void _close() {
    if (!closed.isCompleted) closed.complete();
  }
}

/// A server on 127.0.0.1 that accepts TCP and then either never answers
/// (a dropped handshake, [tlsDelay] null) or completes TLS only after
/// [tlsDelay]. It records whether the client ever closes each connection.
class LoopbackServer {
  LoopbackServer._(this._server, this.tlsDelay);

  static Future<LoopbackServer> start({Duration? tlsDelay}) async {
    final server = LoopbackServer._(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
      tlsDelay,
    );
    server._server.listen(server._accept);
    return server;
  }

  final ServerSocket _server;
  final Duration? tlsDelay;
  final List<Peer> peers = [];
  final List<Socket> _sockets = [];
  final _firstPeer = Completer<Peer>();

  int get port => _server.port;

  Future<Peer> get firstPeer => _firstPeer.future;

  Future<void> _accept(Socket socket) async {
    final peer = Peer();
    peers.add(peer);
    _sockets.add(socket);
    if (!_firstPeer.isCompleted) _firstPeer.complete(peer);
    final delay = tlsDelay;
    if (delay == null) {
      socket.listen(
        (data) => peer.bytes += data.length,
        onDone: peer._close,
        onError: (_) => peer._close(),
      );
      return;
    }
    // The ClientHello waits unread in the socket until the handshake starts.
    await Future<void>.delayed(delay);
    try {
      final tls = await SecureSocket.secureServer(socket, _serverContext());
      peer.handshakeDone = true;
      _sockets.add(tls);
      tls.listen((_) {}, onDone: peer._close, onError: (_) => peer._close());
    } on Object {
      // The client went away during the handshake.
      peer._close();
    }
  }

  Future<void> close() async {
    for (final socket in _sockets) {
      socket.destroy();
    }
    await _server.close();
  }
}
