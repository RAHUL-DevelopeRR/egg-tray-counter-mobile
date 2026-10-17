import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:egg_tray_counter/models/capture_view.dart';
import 'package:egg_tray_counter/models/scan_session.dart';

/// One request the fake server saw. The body is read only when the answer
/// asks for it ([readBody]), which is what makes dio report the upload as
/// fully sent.
class SeenRequest {
  SeenRequest(this.options, this._stream);

  final RequestOptions options;
  final Stream<Uint8List>? _stream;
  List<int>? body;

  String get method => options.method;
  String get path => options.uri.path;
  String get route => '$method $path';
  Map<String, dynamic> get headers => options.headers;

  Map<String, dynamic> get json =>
      jsonDecode(utf8.decode(body!)) as Map<String, dynamic>;
}

/// Reads the whole request body, as a server that received it would.
Future<List<int>> readBody(SeenRequest request) async {
  if (request.body != null) return request.body!;
  final bytes = <int>[];
  final stream = request._stream;
  if (stream != null) {
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
  }
  return request.body = bytes;
}

typedef Answer = Future<ResponseBody> Function(SeenRequest request);

/// A scripted Worker: each route answers from its list in order and the last
/// answer repeats. Unknown routes answer 404.
class FakeServer implements HttpClientAdapter {
  FakeServer(this.routes);

  final Map<String, List<Answer>> routes;
  final Map<String, int> _served = {};
  final List<SeenRequest> requests = [];

  List<SeenRequest> calls(String route) =>
      requests.where((r) => r.route == route).toList();

  List<String> get log => [for (final r in requests) r.route];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final request = SeenRequest(options, requestStream);
    requests.add(request);
    final answers = routes[request.route];
    if (answers == null || answers.isEmpty) {
      await readBody(request);
      return json(detail('not_found'), 404);
    }
    final index = _served[request.route] ?? 0;
    _served[request.route] = index + 1;
    return answers[index < answers.length ? index : answers.length - 1](
      request,
    );
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(
  Object body,
  int status, {
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
    ...headers,
  },
);

/// Answers [body] with [status] after reading the request body.
Answer reply(
  Object body, [
  int status = 200,
  Map<String, List<String>> headers = const {},
]) => (request) async {
  await readBody(request);
  return json(body, status, headers: headers);
};

/// Fails before any of the body was read: the upload never completed.
Answer dropBeforeBody() => (request) async => throw DioException.connectionError(
  requestOptions: request.options,
  reason: 'Connection reset by peer',
  error: const SocketException('Connection reset by peer'),
);

/// Takes [took] on [clock] and then fails without an answer: a request on a
/// link that drops it only after a connect or receive timeout.
Answer slowDrop(NoWait clock, Duration took) => (request) async {
  clock.advance(took);
  throw DioException.connectionTimeout(
    timeout: took,
    requestOptions: request.options,
  );
};

/// Reads the whole body, then no answer comes: the result was lost.
Answer timeoutAfterBody() => (request) async {
  await readBody(request);
  throw DioException.receiveTimeout(
    timeout: const Duration(seconds: 90),
    requestOptions: request.options,
  );
};

const openHealth = {
  'status': 'ok',
  'scan_contract': 'cell_identity_v1',
  'scan_contracts': ['cell_identity_v1', 'model_spatial_v1'],
};

const jobsHealth = {
  'status': 'ok',
  'scan_contract': 'cell_identity_v1',
  'scan_contracts': ['cell_identity_v1', 'model_spatial_v1', 'scan_jobs_v1'],
  'auth': 'device_v1',
};

Map<String, dynamic> detail(String code, [String message = 'm']) => {
  'detail': {'code': code, 'message': message},
};

/// A model_spatial_v1 count response for [scanId].
Map<String, dynamic> scanBody(
  String scanId, {
  int totalTrays = 59,
  Map<String, String> cellIds = const {'left': 'A1'},
}) => {
  'scan_id': scanId,
  'status': 'rescan_required',
  'accepted': false,
  'physical_stack_count': null,
  'total_trays': null,
  'eggs_per_tray': 30,
  'total_eggs': null,
  'processing': {
    'mode': 'model_spatial_v1',
    'latency_ms': 50,
    'model_version': 'projec-mutta/2',
  },
  'cell_ids': cellIds,
  'views': {
    'left': {'quality': 0, 'accepted': false, 'reason': 'x'},
    'right': {'quality': 0, 'accepted': false, 'reason': 'x'},
    'straight': {'quality': 0, 'accepted': false, 'reason': 'x'},
  },
  'stacks': <Object>[],
  'rescan': {'recommended_view': 'straight', 'reason': 'x'},
  'block': {
    'contract': 'block_model_v1',
    'status': 'estimated',
    'width': 1,
    'depth': 1,
    'faces_used': ['straight'],
    'typical_layers': totalTrays,
    'cells': [
      {'x': 0, 'y': 0, 'status': 'observed', 'layers': totalTrays},
    ],
    'observed_trays': totalTrays,
    'computed_trays': 0,
    'total_trays': totalTrays,
    'total_eggs': totalTrays * 30,
    'fully_observed': true,
    'faces_consistent': true,
    'conflicts': <Object>[],
    'rescan_cells': <Object>[],
    'note': 'n',
  },
  'job': {
    'scan_id': scanId,
    'status': 'done',
    'attempt': 1,
    'replayed': false,
    'pipeline_version': 'test',
  },
};

/// A complete session whose three photos are small files in [dir]; LEFT
/// carries cell ID A1 and every view has evidence.
ScanSession photoSession(Directory dir, String scanId) {
  final session = ScanSession(scanId: scanId);
  for (final view in CaptureView.values) {
    final file = File('${dir.path}/${view.name}-$scanId.jpg')
      ..writeAsBytesSync(List<int>.generate(2048, (i) => i % 251));
    session.setPath(
      view,
      file.path,
      cellId: view == CaptureView.left ? 'A1' : '',
      evidence: '{"view":"${view.name}"}',
    );
  }
  return session;
}

/// Records the pauses instead of waiting them out, and keeps a fake clock
/// that the pauses (and [advance], for time spent in requests) move on.
class NoWait {
  final List<Duration> waits = [];
  final DateTime start = DateTime.utc(2026, 10, 15, 8);
  late DateTime now = start;

  Future<void> call(Duration duration) async {
    waits.add(duration);
    now = now.add(duration);
  }

  void advance(Duration duration) => now = now.add(duration);

  /// For `ApiClient(now: ...)`.
  DateTime clock() => now;

  Duration get elapsed => now.difference(start);
}
