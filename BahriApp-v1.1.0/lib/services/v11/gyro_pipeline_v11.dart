// BahriApp v1.1 — corrected gyroscope acquisition pipeline.
//
// Replaces the significance filter and the roll/pitch computation in
// lib/services/gyroGame_services.dart (v1.0), addressing reviewer comments
// R1-9 (dimensionally inconsistent 20.0 threshold), R1-10 (accelerometer tilt
// formulas applied to angular-velocity inputs) and R1-11 (unspecified units
// and Delta-t handling).
//
// UNITS CONTRACT — every quantity below is explicit about its dimension.
//   omegaX, omegaY, omegaZ : rad/s    as delivered by Android TYPE_GYROSCOPE
//   elapsedUs              : us       monotonic, from a session Stopwatch
//   dt                     : s        admissible window [dtMinS, dtMaxS]
//   angularSpeed           : rad/s
//   angularAccel           : rad/s^2
//   angularJerk            : rad/s^3
//   roll, pitch            : degrees  complementary-filter orientation estimate
//   omegaAzimuth/Elevation : degrees  direction of the instantaneous rotation axis
//
// WHY A MONOTONIC CLOCK. v1.0 used DateTime.now(), which is wall-clock and can
// step backwards on an NTP correction. That produced negative hold and flight
// times in the released corpus (minimum -1040 ms). Stopwatch.elapsedMicroseconds
// is monotonic and gives microsecond resolution, where v1.0's
// Duration.inMilliseconds truncated to 1 ms — coarser than the realised
// sampling interval on most devices in the pilot cohort.

import 'dart:math';

/// One retained gyroscope sample with its derived features.
class GyroSample {
  final int elapsedUs;
  final double dtS;
  final double omegaX, omegaY, omegaZ;
  final double angularSpeed; // rad/s, three-axis magnitude
  final double angularAccel; // rad/s^2
  final double angularJerk; // rad/s^3
  final double rollDeg, pitchDeg; // fused orientation
  final double omegaAzimuthDeg, omegaElevationDeg;
  final double cumRotXRad, cumRotYRad, cumRotZRad;

  const GyroSample({
    required this.elapsedUs,
    required this.dtS,
    required this.omegaX,
    required this.omegaY,
    required this.omegaZ,
    required this.angularSpeed,
    required this.angularAccel,
    required this.angularJerk,
    required this.rollDeg,
    required this.pitchDeg,
    required this.omegaAzimuthDeg,
    required this.omegaElevationDeg,
    required this.cumRotXRad,
    required this.cumRotYRad,
    required this.cumRotZRad,
  });

  Map<String, dynamic> toJson() => {
        'elapsedUs': elapsedUs,
        'dtS': dtS,
        'omegaX': omegaX,
        'omegaY': omegaY,
        'omegaZ': omegaZ,
        'angularSpeed_rad_s': angularSpeed,
        'angularAccel_rad_s2': angularAccel,
        'angularJerk_rad_s3': angularJerk,
        'roll_deg': rollDeg,
        'pitch_deg': pitchDeg,
        // NOTE: these two replace the v1.0 columns named `roll` and `pitch`,
        // which were retracted as orientation estimates. See omegaDirection().
        'omegaAzimuth_deg': omegaAzimuthDeg,
        'omegaElevation_deg': omegaElevationDeg,
        'cumRotationX_rad': cumRotXRad,
        'cumRotationY_rad': cumRotYRad,
        'cumRotationZ_rad': cumRotZRad,
      };
}

/// Per-session instrument metadata.
///
/// v1.0 recorded none of this, which is why the BYOD device-heterogeneity
/// question (R1-12) had to be answered by reconstruction from the exported
/// data rather than by direct measurement. Recording it prospectively means
/// future deployments can control for device and sampling-rate differences.
class SessionInstrumentMeta {
  final double realisedRateHz;
  final double rateJitterP95OverP05;
  final int samplesSeen, samplesKept, samplesDtRejected;
  final double sensorFullScaleRadS;
  final double screenDiagonalPx, screenWidthPx, screenHeightPx;
  final double devicePixelRatio;
  final String androidRelease, deviceModel, deviceManufacturer;
  final String appVersion;

  const SessionInstrumentMeta({
    required this.realisedRateHz,
    required this.rateJitterP95OverP05,
    required this.samplesSeen,
    required this.samplesKept,
    required this.samplesDtRejected,
    required this.sensorFullScaleRadS,
    required this.screenDiagonalPx,
    required this.screenWidthPx,
    required this.screenHeightPx,
    required this.devicePixelRatio,
    required this.androidRelease,
    required this.deviceModel,
    required this.deviceManufacturer,
    this.appVersion = '1.1.0',
  });

  Map<String, dynamic> toJson() => {
        'realisedRateHz': realisedRateHz,
        'rateJitterP95OverP05': rateJitterP95OverP05,
        'samplesSeen': samplesSeen,
        'samplesKept': samplesKept,
        'samplesDtRejected': samplesDtRejected,
        'sensorFullScaleRadS': sensorFullScaleRadS,
        'screenDiagonalPx': screenDiagonalPx,
        'screenWidthPx': screenWidthPx,
        'screenHeightPx': screenHeightPx,
        'devicePixelRatio': devicePixelRatio,
        'androidRelease': androidRelease,
        'deviceModel': deviceModel,
        'deviceManufacturer': deviceManufacturer,
        'appVersion': appVersion,
      };
}

class GyroPipelineV11 {
  // --- Thresholds -----------------------------------------------------------
  //
  // R1-9 is correct: v1.0 compared a single scalar 20 against two angular
  // velocities (rad/s) and one angular acceleration (rad/s^2). Reviewer 2's
  // arithmetic is also correct: 20 rad/s = 1146 deg/s, far above anything the
  // tilt task produces. Audit of the released corpus showed 98.53% of samples
  // were retained, 98.41% of them by the acceleration term alone — the filter
  // was very nearly a no-op.
  //
  // v1.1 gives each dimension its own threshold. The default speed threshold is
  // the 70th percentile of angular speed measured across the pilot corpus
  // (1.63 rad/s = 93 deg/s), i.e. it is data-derived and reproducible, not a
  // development placeholder. Call [calibrate] to re-derive it for a new cohort.
  final double thrSpeedRadS; // rad/s
  final double? thrAccelRadS2; // rad/s^2, null disables this term
  final double? thrJerkRadS3; // rad/s^3, null disables this term

  // --- Delta-t contract (R1-11) --------------------------------------------
  // Samples whose interval falls outside this window are dropped and counted,
  // never divided by. dtMinS guards against division blow-up at very high
  // realised rates; dtMaxS rejects intervals that span an app pause.
  final double dtMinS, dtMaxS;

  /// Complementary-filter weight on the integrated gyroscope term.
  final double alpha;

  GyroPipelineV11({
    this.thrSpeedRadS = 1.63,
    this.thrAccelRadS2,
    this.thrJerkRadS3,
    this.dtMinS = 1e-4,
    this.dtMaxS = 0.25,
    this.alpha = 0.98,
  });

  int? _lastUs;
  double? _lastSpeed, _lastAccel;
  double _roll = 0.0, _pitch = 0.0;
  double _cumX = 0.0, _cumY = 0.0, _cumZ = 0.0;
  int samplesSeen = 0, samplesKept = 0, samplesDtRejected = 0;
  final List<double> _dtLog = <double>[];

  void reset() {
    _lastUs = null;
    _lastSpeed = null;
    _lastAccel = null;
    _roll = 0.0;
    _pitch = 0.0;
    _cumX = _cumY = _cumZ = 0.0;
    samplesSeen = samplesKept = samplesDtRejected = 0;
    _dtLog.clear();
  }

  /// Data-driven threshold selection. Returns the angular-speed value that
  /// retains [targetRetention] of [speeds].
  ///
  /// Report both the percentile and the resulting retention rate alongside any
  /// dataset produced with it — that is what makes the threshold reproducible,
  /// and it is the specific thing the v1.0 constant could not offer.
  static double calibrate(List<double> speeds, {double targetRetention = 0.30}) {
    if (speeds.isEmpty) return 0.0;
    final s = List<double>.from(speeds)..sort();
    final idx = ((1.0 - targetRetention) * (s.length - 1)).round();
    return s[idx.clamp(0, s.length - 1)];
  }

  /// Direction of the instantaneous rotation axis, in degrees.
  ///
  /// This is what v1.0 stored under the names `roll` and `pitch`. It is a
  /// legitimate descriptor of how a participant rotates the device, but it is
  /// NOT an orientation, and the released v1.0 columns are renamed accordingly
  /// (omegaAzimuth, omegaElevation) rather than silently reinterpreted.
  static List<double> omegaDirection(double wx, double wy, double wz) => [
        atan2(wy, wz) * 180.0 / pi,
        atan2(-wx, sqrt(wy * wy + wz * wz)) * 180.0 / pi,
      ];

  /// Complementary filter. The gyroscope supplies the high-frequency term by
  /// integration; the accelerometer, when a reading is available, supplies the
  /// drift-free low-frequency term. This is the construction R1-10 identifies
  /// as the correct way to obtain orientation from these sensors.
  void _updateOrientation(double wx, double wy, double wz, double dt,
      {double? ax, double? ay, double? az}) {
    _roll += wx * dt * 180.0 / pi;
    _pitch += wy * dt * 180.0 / pi;

    if (ax != null && ay != null && az != null && !(ax == 0 && ay == 0 && az == 0)) {
      final accRoll = atan2(ay, az) * 180.0 / pi;
      final accPitch = atan2(-ax, sqrt(ay * ay + az * az)) * 180.0 / pi;
      _roll = alpha * _roll + (1 - alpha) * accRoll;
      _pitch = alpha * _pitch + (1 - alpha) * accPitch;
    }
    _roll = (_roll + 180.0) % 360.0 - 180.0;
    _pitch = _pitch.clamp(-90.0, 90.0);
  }

  static double _finite(double v) => (v.isNaN || v.isInfinite) ? 0.0 : v;

  /// Process one sensor event. Returns the retained sample, or null when the
  /// sample is the session's first, falls outside the Delta-t window, or does
  /// not meet any significance threshold.
  GyroSample? step(double omegaX, double omegaY, double omegaZ, int elapsedUs,
      {double? accelX, double? accelY, double? accelZ}) {
    samplesSeen++;
    omegaX = _finite(omegaX);
    omegaY = _finite(omegaY);
    omegaZ = _finite(omegaZ);

    final speed = sqrt(omegaX * omegaX + omegaY * omegaY + omegaZ * omegaZ);

    if (_lastUs == null) {
      _lastUs = elapsedUs;
      _lastSpeed = speed;
      return null;
    }

    final dt = (elapsedUs - _lastUs!) / 1e6; // microseconds -> seconds
    if (dt < dtMinS || dt > dtMaxS) {
      samplesDtRejected++;
      _lastUs = elapsedUs;
      _lastSpeed = speed;
      return null;
    }
    _dtLog.add(dt);

    final accel = (speed - _lastSpeed!) / dt;
    final jerk = _lastAccel == null ? 0.0 : (accel - _lastAccel!) / dt;

    _cumX += omegaX * dt;
    _cumY += omegaY * dt;
    _cumZ += omegaZ * dt;

    _updateOrientation(omegaX, omegaY, omegaZ, dt, ax: accelX, ay: accelY, az: accelZ);
    final dir = omegaDirection(omegaX, omegaY, omegaZ);

    // Each comparison is against a threshold in that quantity's own units.
    final significant = speed > thrSpeedRadS ||
        (thrAccelRadS2 != null && accel.abs() > thrAccelRadS2!) ||
        (thrJerkRadS3 != null && jerk.abs() > thrJerkRadS3!);

    _lastUs = elapsedUs;
    _lastSpeed = speed;
    _lastAccel = accel;

    if (!significant) return null;
    samplesKept++;

    return GyroSample(
      elapsedUs: elapsedUs,
      dtS: dt,
      omegaX: omegaX,
      omegaY: omegaY,
      omegaZ: omegaZ,
      angularSpeed: speed,
      angularAccel: accel,
      angularJerk: jerk,
      rollDeg: _roll,
      pitchDeg: _pitch,
      omegaAzimuthDeg: dir[0],
      omegaElevationDeg: dir[1],
      cumRotXRad: _cumX,
      cumRotYRad: _cumY,
      cumRotZRad: _cumZ,
    );
  }

  /// Realised sampling rate for this session, in Hz — recorded per session so
  /// that cross-device comparisons can control for it (R1-12).
  double get realisedRateHz {
    if (_dtLog.isEmpty) return 0.0;
    final s = List<double>.from(_dtLog)..sort();
    final median = s[s.length ~/ 2];
    return median > 0 ? 1.0 / median : 0.0;
  }

  double get rateJitterP95OverP05 {
    if (_dtLog.length < 20) return 1.0;
    final s = List<double>.from(_dtLog)..sort();
    final p05 = s[(0.05 * (s.length - 1)).round()];
    final p95 = s[(0.95 * (s.length - 1)).round()];
    return p05 > 0 ? p95 / p05 : 1.0;
  }

  double get retentionRate => samplesSeen == 0 ? 0.0 : samplesKept / samplesSeen;
}
