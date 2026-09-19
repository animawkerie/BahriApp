// BahriApp v1.1 — corrected feature extractors for swipe, tap, keystroke and gait.
//
// Each class below replaces a v1.0 counterpart whose defects were established by
// auditing the released corpus against the source. The defect each class fixes is
// documented inline so that reviewers and downstream users can see exactly what
// changed and why.

import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart' show Offset, Size;

// ===========================================================================
// SWIPE
// ===========================================================================
//
// v1.0 DEFECT (lib/services/swipe_data_collection.dart)
//   endCollecting() assigned the recogniser's FLING VELOCITY to fields named
//   endX / endY:
//       'endX': details.velocity.pixelsPerSecond.dx,   // px/s, not a coordinate
//       'distance': sqrt(pow(vx - initialX, 2) + pow(vy - initialY, 2)),
//   so distance, speed, acceleration, deceleration, jerk, angle, areaCoverage,
//   fingerOrientation and movementVariability all mixed px with px/s. In the
//   released corpus the median "distance" is 2,524 px on screens whose recovered
//   diagonal is 892 px — 2.8 screen diagonals for a single swipe.
//
//   updateCollecting() was also an empty stub, so no intermediate touch points
//   were ever retained and no genuine path feature could be computed.
//
// v1.1 retains the full point sequence and derives every path feature from it.
// The fling velocity is kept, correctly named, as a legitimate extra feature.

class SwipePoint {
  final double x, y; // logical px
  final double tS; // seconds since gesture start, monotonic
  const SwipePoint(this.x, this.y, this.tS);

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'tS': tS};
}

class SwipeFeaturesV11 {
  /// [points] must be in capture order with at least two entries.
  /// [screenDiagonalPx] normalises for device form factor (R1-12).
  static Map<String, double> extract(
    List<SwipePoint> points,
    double screenDiagonalPx, {
    double flingVx = 0.0,
    double flingVy = 0.0,
  }) {
    if (points.length < 2) {
      throw ArgumentError('a swipe needs at least two sampled points');
    }
    final duration = points.last.tS - points.first.tS;
    if (duration <= 0) {
      throw ArgumentError('non-positive swipe duration');
    }

    double pathLen = 0.0, peakSpeed = 0.0, peakAccel = 0.0;
    double sumAccel = 0.0, sumJerk = 0.0;
    int nAccel = 0, nJerk = 0;
    double? prevV, prevA;
    double minX = points.first.x, maxX = points.first.x;
    double minY = points.first.y, maxY = points.first.y;

    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      final seg = sqrt(pow(b.x - a.x, 2) + pow(b.y - a.y, 2));
      final dt = max(b.tS - a.tS, 1e-9);
      pathLen += seg;

      final v = seg / dt;
      peakSpeed = max(peakSpeed, v);
      if (prevV != null) {
        final acc = (v - prevV) / dt;
        sumAccel += acc;
        nAccel++;
        peakAccel = max(peakAccel, acc.abs());
        if (prevA != null) {
          sumJerk += (acc - prevA) / dt;
          nJerk++;
        }
        prevA = acc;
      }
      prevV = v;

      minX = min(minX, b.x);
      maxX = max(maxX, b.x);
      minY = min(minY, b.y);
      maxY = max(maxY, b.y);
    }

    final dx = points.last.x - points.first.x;
    final dy = points.last.y - points.first.y;
    final chord = sqrt(dx * dx + dy * dy);
    final meanSpeed = pathLen / duration;

    return {
      // path geometry, from the real trajectory
      'pathLength_px': pathLen,
      'straightLineDistance_px': chord,
      'straightnessIndex': pathLen > 0 ? chord / pathLen : 1.0,
      'bboxArea_px2': (maxX - minX) * (maxY - minY),
      'direction_deg': atan2(dy, dx) * 180.0 / pi,
      // kinematics, dimensionally consistent
      'duration_s': duration,
      'meanSpeed_px_s': meanSpeed,
      'peakSpeed_px_s': peakSpeed,
      'meanAccel_px_s2': nAccel > 0 ? sumAccel / nAccel : 0.0,
      'peakAccel_px_s2': peakAccel,
      'meanJerk_px_s3': nJerk > 0 ? sumJerk / nJerk : 0.0,
      // fling velocity, correctly named (this is what v1.0 stored as endX/endY)
      'flingSpeed_px_s': sqrt(flingVx * flingVx + flingVy * flingVy),
      'flingDirection_deg': atan2(flingVy, flingVx) * 180.0 / pi,
      // screen-normalised, for cross-device comparability
      'snPathLength': pathLen / screenDiagonalPx,
      'snMeanSpeed': meanSpeed / screenDiagonalPx,
      'snPeakAccel': peakAccel / screenDiagonalPx,
      'nSampledPoints': points.length.toDouble(),
    };
  }
}

/// Drop-in collector that actually records the trajectory.
class SwipeCollectorV11 {
  final List<SwipePoint> _points = <SwipePoint>[];
  final Stopwatch _sw = Stopwatch();
  double _initialPressure = 0.0;

  void onStart(DragStartDetails d) {
    _points.clear();
    _sw
      ..reset()
      ..start();
    _points.add(SwipePoint(d.globalPosition.dx, d.globalPosition.dy, 0.0));
  }

  /// v1.0 left this method empty. Retaining the trajectory is the single change
  /// that makes path length, curvature and true kinematics recoverable.
  void onUpdate(DragUpdateDetails d) {
    _points.add(SwipePoint(
      d.globalPosition.dx,
      d.globalPosition.dy,
      _sw.elapsedMicroseconds / 1e6,
    ));
  }

  Map<String, double> onEnd(DragEndDetails d, double screenDiagonalPx) {
    _sw.stop();
    final v = d.velocity.pixelsPerSecond;
    final f = SwipeFeaturesV11.extract(_points, screenDiagonalPx,
        flingVx: v.dx, flingVy: v.dy);
    f['initialPressure'] = _initialPressure;
    return f;
  }

  set initialPressure(double p) => _initialPressure = p;

  List<SwipePoint> get trajectory => List.unmodifiable(_points);
}

// ===========================================================================
// TAP
// ===========================================================================
//
// v1.0 DEFECTS (lib/services/pic_pick_services.dart)
//   1. int calculateTapSpeed(...) => 1 ~/ calculateTapDuration(...);
//      Dart's ~/ is integer division, so any duration above 1 ms yields exactly
//      zero. 99.29% of the released TapSpeed values are 0.
//   2. calculateTapDrift used intended.dx - actual.dy in the second term where
//      .dy - .dy was meant, giving a median drift of 421 px with a floor of
//      102 px — impossible for a stationary press.
//   3. calculateTapLatency was passed tapReleaseTime as screenResponseTime, so
//      Latency reduced to a duplicate of TapDuration (r = 0.999997).

class TapFeaturesV11 {
  static Map<String, double> extract({
    required int pressUs,
    required int releaseUs,
    required Offset pressPos,
    required Offset releasePos,
    required Offset targetCentre,
    required Size screenSize,
  }) {
    final durationMs = (releaseUs - pressUs) / 1000.0;
    if (durationMs <= 0) {
      throw ArgumentError('non-positive tap duration');
    }
    // within-tap slippage: the finger moving while pressed
    final dx = releasePos.dx - pressPos.dx;
    final dy = releasePos.dy - pressPos.dy; // .dy, not .dx
    // targeting error: how far the press landed from the intended target
    final ex = pressPos.dx - targetCentre.dx;
    final ey = pressPos.dy - targetCentre.dy;

    return {
      'duration_ms': durationMs,
      'tapRate_hz': 1000.0 / durationMs, // floating point, never truncated
      'withinTapDrift_px': sqrt(dx * dx + dy * dy),
      'targetingError_px': sqrt(ex * ex + ey * ey),
      'normalizedX': pressPos.dx / screenSize.width,
      'normalizedY': pressPos.dy / screenSize.height,
    };
  }
}

// ===========================================================================
// KEYSTROKE
// ===========================================================================
//
// v1.0 DEFECTS (keystroke_services.dart, freetext_service.dart,
//               password_entry_services.dart — three near-identical copies)
//   1. DateTime.now() is wall-clock; NTP steps produced negative hold times
//      (min -1040 ms) and negative flight times in the released corpus.
//   2. calculateKPR/KRR divided by Duration.inSeconds, which truncates: any
//      session shorter than one second divided by zero.
//   3. interKeyTime duplicated flightTime, so AverageInterkeyTime,
//      AverageSeekTime and AverageKeyReleaseDuration were three names for one
//      quantity (pairwise r >= 0.9975).
//   4. No pause segmentation: a 37-minute gap was stored as one flight time.
//   5. KPV/KRV were coefficients of variation with an unguarded mean, so they
//      went negative when the mean did.
//
// v1.1 uses one shared implementation on a monotonic clock, with explicit
// plausibility bounds and pause segmentation.

class KeyEvent {
  final int pressUs, releaseUs; // monotonic, microseconds since session start
  final String keyText;
  final String keyType;

  /// 'base' | 'order' | 'standalone' — see the Amharic composition note below.
  final String compositionRole;

  const KeyEvent({
    required this.pressUs,
    required this.releaseUs,
    required this.keyText,
    required this.keyType,
    this.compositionRole = 'standalone',
  });
}

// AMHARIC (GE'EZ) COMPOSITION — what is logged and how hold/flight are defined.
//
// BahriApp suppresses the system keyboard and renders its own, so every logged
// event is a physical touch on a key the application drew. There is no
// transliteration IME and no OS-level composition.
//
// Amharic entry is two-tier. The primary layer holds 34 base fidels. Tapping a
// base both inserts that character — itself the 1st order (ግዕዝ) — and reveals a
// secondary row of its remaining orders. Tapping an order key replaces the base
// with the composed fidel. Therefore:
//
//   * a 1st-order fidel costs ONE physical key event;
//   * any other order costs TWO.
//
//   HOLD TIME  is defined per PHYSICAL key event: releaseUs - pressUs for that
//              single tap. It is never summed across the two taps of a
//              composed fidel.
//   FLIGHT TIME is the interval from one physical release to the next physical
//              press, including the base -> order transition inside a composed
//              fidel. That intra-fidel interval measures the order-selection
//              decision and has no analogue in Latin typing.
//
// v1.1 tags each event with compositionRole so downstream users can aggregate
// at either the physical-event level or the rendered-character level. In the
// pilot corpus the median Amharic session logs 1.44 physical text-key events
// per rendered character, against 0.94 for English.

class KeystrokeSessionVectorV11 {
  static const double pauseMs = 3000.0;
  static const double maxHoldMs = 5000.0;

  static Map<String, double> build(List<KeyEvent> events) {
    final ev = List<KeyEvent>.from(events)
      ..sort((a, b) => a.pressUs.compareTo(b.pressUs));

    final hold = <double>[], flight = <double>[], inter = <double>[];
    var rejected = 0, nText = 0;

    for (var i = 0; i < ev.length; i++) {
      final h = (ev[i].releaseUs - ev[i].pressUs) / 1000.0;
      if (h <= 0 || h > maxHoldMs) {
        rejected++;
        continue;
      }
      hold.add(h);
      if (ev[i].keyType == 'textKey') nText++;
      if (i > 0) {
        final f = (ev[i].pressUs - ev[i - 1].releaseUs) / 1000.0;
        if (f >= 0 && f <= pauseMs) {
          flight.add(f);
          inter.add((ev[i].pressUs - ev[i - 1].pressUs) / 1000.0);
        }
      }
    }

    final out = <String, double>{};
    out.addAll(_stats(hold, 'hold_ms'));
    out.addAll(_stats(flight, 'flight_ms'));
    out.addAll(_stats(inter, 'interkey_ms'));

    final activeS = (hold.fold<double>(0, (a, b) => a + b) +
            flight.fold<double>(0, (a, b) => a + b)) /
        1000.0;
    out['n_events'] = ev.length.toDouble();
    out['n_rejected'] = rejected.toDouble();
    out['n_text_keys'] = nText.toDouble();
    out['activeTypingTime_s'] = activeS;
    out['keyRate_hz'] = activeS > 0 ? hold.length / activeS : double.nan;
    out['typingSpeed_cpm'] = activeS > 0 ? nText / (activeS / 60.0) : double.nan;
    final mf = flight.isEmpty ? 0.0 : _median(flight);
    out['holdFlightRatio'] =
        (flight.isNotEmpty && mf > 0) ? _median(hold) / mf : double.nan;
    return out;
  }

  static double _median(List<double> v) {
    final s = List<double>.from(v)..sort();
    final n = s.length;
    if (n == 0) return double.nan;
    return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2.0;
  }

  static double _percentile(List<double> sorted, double p) {
    if (sorted.isEmpty) return double.nan;
    final idx = (p * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
    return sorted[idx];
  }

  static Map<String, double> _stats(List<double> v, String prefix) {
    if (v.isEmpty) {
      return {
        for (final k in ['mean', 'median', 'sd', 'cv', 'p25', 'p75', 'iqr'])
          '${prefix}_$k': double.nan
      };
    }
    final s = List<double>.from(v)..sort();
    final mean = v.fold<double>(0, (a, b) => a + b) / v.length;
    double sd = 0.0;
    if (v.length > 1) {
      final ss = v.fold<double>(0, (a, b) => a + pow(b - mean, 2).toDouble());
      sd = sqrt(ss / (v.length - 1));
    }
    final p25 = _percentile(s, 0.25), p75 = _percentile(s, 0.75);
    return {
      '${prefix}_mean': mean,
      '${prefix}_median': _median(v),
      '${prefix}_sd': sd,
      // guarded: undefined rather than negative or infinite
      '${prefix}_cv': (v.length > 1 && mean > 0) ? sd / mean : double.nan,
      '${prefix}_p25': p25,
      '${prefix}_p75': p75,
      '${prefix}_iqr': p75 - p25,
    };
  }
}

// ===========================================================================
// GAIT
// ===========================================================================
//
// v1.0 DEFECT (accelerometerGame_service.dart)
//   getOrientation() read _accelerationData[0], [1], [2] as the x, y, z
//   components of gravity. _accelerationData is a time series of low-pass
//   filtered MAGNITUDES, so those were the first three magnitude samples of the
//   session. Consequence in the released corpus: exactly one orientation value
//   per session across all 489 sessions, clustered at pitch = -19.8 deg,
//   roll = 37.8 deg regardless of activity.
//
//   getJerk() was evaluated only at the downward zero-crossing that terminates a
//   step, so 100% of released jerk values are negative.
//
//   _maxDataEntries capped a session at 20 steps; 43.4% of sessions saturated it.

class GaitFeaturesV11 {
  static const double g = 9.80665;

  /// Correct tilt from the three components of the gravity vector.
  static Map<String, double> orientation(
    double ax,
    double ay,
    double az, {
    double? mx,
    double? my,
    double? mz,
  }) {
    final n = sqrt(ax * ax + ay * ay + az * az);
    if (n == 0) return {'pitch': 0.0, 'roll': 0.0, 'yaw': 0.0};
    final nx = ax / n, ny = ay / n, nz = az / n;
    final pitch = asin((nx * -1).clamp(-1.0, 1.0)) * 180.0 / pi;
    final roll = atan2(ny, nz) * 180.0 / pi;

    var yaw = 0.0;
    if (mx != null && my != null && mz != null) {
      final mn = sqrt(mx * mx + my * my + mz * mz);
      if (mn > 0) {
        final ux = mx / mn, uy = my / mn, uz = mz / mn;
        yaw = atan2(uy * nx - ux * ny, ux * nz - uz * nx) * 180.0 / pi;
      }
    }
    return {'pitch': pitch, 'roll': roll, 'yaw': yaw};
  }

  /// Signed jerk over the whole step cycle, plus gravity-removed magnitude.
  static Map<String, double> stepFeatures(
      List<double> magnitudes, List<double> timesS) {
    if (magnitudes.isEmpty) return {};
    final mean = magnitudes.fold<double>(0, (a, b) => a + b) / magnitudes.length;
    var peak = magnitudes.first, lo = magnitudes.first;
    for (final m in magnitudes) {
      peak = max(peak, m);
      lo = min(lo, m);
    }
    var ss = 0.0;
    for (final m in magnitudes) {
      ss += pow(m - mean, 2).toDouble();
    }
    final sd = magnitudes.length > 1 ? sqrt(ss / (magnitudes.length - 1)) : 0.0;

    var sumJerk = 0.0, peakAbsJerk = 0.0, nPos = 0, nJ = 0;
    for (var i = 1; i < magnitudes.length && i < timesS.length; i++) {
      final dt = max(timesS[i] - timesS[i - 1], 1e-9);
      final j = (magnitudes[i] - magnitudes[i - 1]) / dt;
      sumJerk += j;
      peakAbsJerk = max(peakAbsJerk, j.abs());
      if (j > 0) nPos++;
      nJ++;
    }

    return {
      'meanAccel_ms2': mean,
      'meanLinearAccel_ms2': mean - g, // gravity removed
      'peakAccel_ms2': peak,
      'minAccel_ms2': lo,
      'sdAccel_ms2': sd,
      'meanJerk_ms3': nJ > 0 ? sumJerk / nJ : 0.0,
      'peakAbsJerk_ms3': peakAbsJerk,
      // ~0.5 for a genuine oscillation; v1.0 forced this to 0.0 by construction
      'jerkSignBalance': nJ > 0 ? nPos / nJ : double.nan,
    };
  }
}
