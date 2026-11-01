import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

import '../models/capture_view.dart';

/// A side face is about 90 degrees from the front; below this turn the photo
/// is the front again. Matches SIDE_MIN_TURN_DEG in the Worker.
const double kSideMinTurnDeg = 45;

/// LEFT and RIGHT face opposite ways, about 180 degrees apart; closer than
/// this they show the same side. Matches SIDES_MIN_APART_DEG in the Worker.
const double kSidesMinApartDeg = 90;

/// Past this turn from STRAIGHT the camera faces the back face, not a side
/// (Worker SIDE_MAX_TURN_DEG).
const double kSideMaxTurnDeg = 135;

/// More than this much unmeasured time and the heading is not trusted.
const Duration kMaxLostTime = Duration(seconds: 2);

/// A heading needs a live gyroscope: at least this many samples, the last one
/// no older than [kMaxGyroSilence]. A sensor that registered but never reports
/// (or stops) would otherwise freeze the heading and refuse every side photo.
const int kMinGyroSamples = 5;
const Duration kMaxGyroSilence = Duration(milliseconds: 500);

double wrap180(double deg) => ((deg + 180) % 360 + 360) % 360 - 180;

/// The phone's turn about the vertical at one capture. Headings are
/// comparable only within one [session] (one run of the capture screen).
class CaptureHeading {
  const CaptureHeading(this.yawDeg, this.session);

  final double yawDeg;
  final String session;

  /// Fields added to the view's constraint evidence for the Worker.
  Map<String, Object> toJson() => {
    'yaw_deg': (yawDeg * 10).roundToDouble() / 10,
    'yaw_session': session,
  };

  /// Reads a heading back from a view's constraint evidence; null when the
  /// evidence has none (gallery photos, older captures).
  static CaptureHeading? fromEvidence(String? evidence) {
    if (evidence == null) return null;
    try {
      final decoded = jsonDecode(evidence);
      if (decoded is! Map) return null;
      final yaw = decoded['yaw_deg'];
      final session = decoded['yaw_session'];
      if (yaw is! num || !yaw.isFinite || session is! String) return null;
      return CaptureHeading(yaw.toDouble(), session);
    } on FormatException {
      return null;
    }
  }
}

/// Why a photo for [view] taken at [heading] cannot be that side face, given
/// the headings already recorded for the other views; null when it can be, or
/// when there is nothing comparable. The Worker applies the same rule.
String? sideHeadingProblem(
  CaptureView view,
  CaptureHeading? heading,
  Map<CaptureView, CaptureHeading?> recorded,
) {
  if (view == CaptureView.straight || heading == null) return null;
  final side = view.name.toUpperCase();
  final straight = recorded[CaptureView.straight];
  if (straight != null && straight.session == heading.session) {
    final turn = wrap180(heading.yawDeg - straight.yawDeg).abs();
    if (turn < kSideMinTurnDeg) {
      return 'The phone turned only ${turn.round()}° since the STRAIGHT '
          'photo, so this is the front face again. Walk around the corner to '
          "the block's $side side and photograph that face square-on.";
    }
    if (turn > kSideMaxTurnDeg) {
      return 'The phone turned ${turn.round()}° since the STRAIGHT photo, so '
          'this is the back of the block. The $side side face is about a '
          'quarter turn from the front.';
    }
  }
  final otherView = view == CaptureView.left
      ? CaptureView.right
      : CaptureView.left;
  final other = recorded[otherView];
  if (other != null && other.session == heading.session) {
    final apart = wrap180(heading.yawDeg - other.yawDeg).abs();
    if (apart < kSidesMinApartDeg) {
      return 'This faces the same way as the ${otherView.name.toUpperCase()} '
          'photo (${apart.round()}° apart), so it shows the same side. The '
          '$side side is on the opposite end of the block.';
    }
  }
  return null;
}

/// Integrates the gyroscope about the vertical (taken from the accelerometer),
/// so the turn is the same whether the phone is held upright or sideways.
/// Positive is counter-clockwise seen from above. Pure, for tests.
class YawIntegrator {
  YawIntegrator({this.maxStep = const Duration(milliseconds: 200)});

  /// Longest interval integrated at once; a longer gap between gyroscope
  /// samples is counted as lost time, because the turn inside it is unknown.
  final Duration maxStep;

  double _yawDeg = 0;
  List<double>? _up;
  DateTime? _last;
  Duration _lost = Duration.zero;

  double get yawDeg => _yawDeg;
  Duration get lost => _lost;
  bool get hasGravity => _up != null;

  /// Accelerometer sample in m/s² (device axes). At rest it points up.
  void addAccelerometer(double x, double y, double z) {
    final norm = math.sqrt(x * x + y * y + z * z);
    // Shaking or free fall says nothing about where up is.
    if (norm < 4 || norm > 16) return;
    final sample = [x / norm, y / norm, z / norm];
    final up = _up;
    _up = up == null
        ? sample
        : _unit([for (var i = 0; i < 3; i++) up[i] * 0.9 + sample[i] * 0.1]);
  }

  /// Gyroscope sample in rad/s (device axes) at [at].
  void addGyroscope(double x, double y, double z, DateTime at) {
    final last = _last;
    _last = at;
    final up = _up;
    if (last == null || up == null) return;
    var step = at.difference(last);
    if (step <= Duration.zero) return;
    if (step > maxStep) {
      _lost += step - maxStep;
      step = maxStep;
    }
    final rate = x * up[0] + y * up[1] + z * up[2];
    _yawDeg += rate * step.inMicroseconds / 1e6 * 180 / math.pi;
  }

  static List<double> _unit(List<double> v) {
    final norm = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    return norm == 0 ? v : [v[0] / norm, v[1] / norm, v[2] / norm];
  }
}

/// Runs a [YawIntegrator] on the device sensors for one scan, retakes
/// included, so every photo of the scan is comparable. Every [start] after a
/// [stop] begins a new session. While the app is in the background Android
/// stops the gyroscope; that gap counts as lost time and the heading stops
/// being trusted, instead of silently missing the turn made meanwhile.
class HeadingTracker {
  HeadingTracker({
    Stream<GyroscopeEvent> Function()? gyroscope,
    Stream<AccelerometerEvent> Function()? accelerometer,
    math.Random? random,
    DateTime Function()? clock,
  }) : _gyroscope =
           gyroscope ??
           (() => gyroscopeEventStream(
             samplingPeriod: SensorInterval.gameInterval,
           )),
       // The rate LiveFramePreflight asks for: the plugin keeps one native
       // accelerometer listener, and the last rate requested wins for both.
       _accelerometer =
           accelerometer ??
           (() => accelerometerEventStream(
             samplingPeriod: SensorInterval.uiInterval,
           )),
       _random = random ?? math.Random.secure(),
       _clock = clock ?? DateTime.now;

  final Stream<GyroscopeEvent> Function() _gyroscope;
  final Stream<AccelerometerEvent> Function() _accelerometer;
  final math.Random _random;
  final DateTime Function() _clock;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  YawIntegrator _yaw = YawIntegrator();
  String? _session;
  bool _failed = false;
  int _gyroSamples = 0;
  DateTime? _lastGyroArrival;

  /// The heading now; null when there is no live gyroscope, no reading of up
  /// yet, or too much unmeasured time in this session.
  CaptureHeading? get current {
    final session = _session;
    final arrival = _lastGyroArrival;
    if (session == null ||
        _failed ||
        !_yaw.hasGravity ||
        _yaw.lost > kMaxLostTime ||
        _gyroSamples < kMinGyroSamples ||
        arrival == null ||
        _clock().difference(arrival) > kMaxGyroSilence) {
      return null;
    }
    return CaptureHeading(_yaw.yawDeg, session);
  }

  void start() {
    if (_session != null) return;
    _yaw = YawIntegrator();
    _failed = false;
    _gyroSamples = 0;
    _lastGyroArrival = null;
    _session = List.generate(
      10,
      (_) => '0123456789abcdefghijklmnopqrstuvwxyz'[_random.nextInt(36)],
    ).join();
    // No gyroscope: captures carry no heading, and the Worker gives a block
    // more than one stack deep no total.
    try {
      _accelSub = _accelerometer().listen(
        (e) => _yaw.addAccelerometer(e.x, e.y, e.z),
        onError: (Object _) => _failed = true,
      );
      _gyroSub = _gyroscope().listen(
        _onGyroscope,
        onError: (Object _) => _failed = true,
      );
    } on Object {
      _failed = true;
    }
  }

  void _onGyroscope(GyroscopeEvent event) {
    _gyroSamples++;
    _lastGyroArrival = _clock();
    _yaw.addGyroscope(event.x, event.y, event.z, event.timestamp);
  }

  Future<void> stop() async {
    _session = null;
    final gyro = _gyroSub, accel = _accelSub;
    _gyroSub = null;
    _accelSub = null;
    await gyro?.cancel();
    await accel?.cancel();
  }
}
