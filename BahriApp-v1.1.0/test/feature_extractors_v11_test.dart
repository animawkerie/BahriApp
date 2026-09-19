// BahriApp v1.1 — unit tests for the corrected feature extractors.
//
// Requested by Reviewer 2: "a small set of unit tests for the feature extractors
// would complement them."
//
// Every test below encodes a property that the v1.0 implementation violated, so
// the suite fails against v1.0 by construction and passes against v1.1. It is
// the Dart mirror of section 16.3 of the reviewer-response analysis notebook.
//
// Run with:  flutter test test/feature_extractors_v11_test.dart

import 'dart:math';

import 'package:flutter/widgets.dart' show Offset, Size;
import 'package:flutter_test/flutter_test.dart';

import 'package:bahri_app/services/v11/gyro_pipeline_v11.dart';
import 'package:bahri_app/services/v11/feature_extractors_v11.dart';

void main() {
  // =========================================================================
  group('GyroPipelineV11 (R1-9, R1-10, R1-11)', () {
    test('rotation about z alone accumulates no roll or pitch', () {
      final p = GyroPipelineV11(thrSpeedRadS: 0.0);
      for (var k = 0; k <= 100; k++) {
        p.step(0.0, 0.0, 1.0, k * 5000); // 5 ms steps, in microseconds
      }
      final s = p.step(0.0, 0.0, 1.0, 101 * 5000)!;
      expect(s.rollDeg.abs(), lessThan(1e-6));
      expect(s.pitchDeg.abs(), lessThan(1e-6));
    });

    test('constant rate integrates to the correct cumulative angle', () {
      final p = GyroPipelineV11(thrSpeedRadS: 0.0);
      GyroSample? last;
      for (var k = 0; k <= 200; k++) {
        // 201 samples -> 200 intervals of 5 ms = 1.000 s at 1 rad/s
        final s = p.step(1.0, 0.0, 0.0, k * 5000);
        if (s != null) last = s;
      }
      expect(last!.cumRotXRad, closeTo(1.0, 1e-6));
    });

    test('samples outside the Delta-t window are rejected, not divided by', () {
      final p = GyroPipelineV11(thrSpeedRadS: 0.0, dtMinS: 1e-3, dtMaxS: 0.1);
      p.step(1, 0, 0, 0);
      p.step(1, 0, 0, 1); //       1 us -> below dtMin
      p.step(1, 0, 0, 5000001); // 5 s   -> above dtMax
      expect(p.samplesDtRejected, 2);
    });

    test('nothing is emitted below the angular-speed threshold', () {
      final p = GyroPipelineV11(thrSpeedRadS: 10.0);
      for (var k = 0; k <= 50; k++) {
        expect(p.step(0.01, 0.01, 0.01, k * 5000), isNull);
      }
    });

    test('thresholds are per-dimension, not one scalar for three units', () {
      // The v1.0 defect: the scalar 20 was compared against rad/s AND rad/s^2.
      final p = GyroPipelineV11(thrSpeedRadS: 100.0, thrAccelRadS2: 1.0);
      p.step(0.0, 0.0, 0.0, 0);
      final s = p.step(0.5, 0.0, 0.0, 10000)!; // 0.5 rad/s, 50 rad/s^2
      expect(s.angularSpeed, lessThan(100.0));
      expect(s.angularAccel.abs(), greaterThan(1.0));
    });

    test('omegaDirection is an axis direction, not an orientation', () {
      final d = GyroPipelineV11.omegaDirection(0.0, 1.0, 0.0);
      expect(d[0], closeTo(90.0, 1e-6));
    });

    test('calibrate returns a percentile of the observed signal', () {
      final speeds = List<double>.generate(1000, (i) => i / 1000.0);
      final thr = GyroPipelineV11.calibrate(speeds, targetRetention: 0.30);
      expect(thr, closeTo(0.70, 0.01));
    });

    test('angular speed uses all three axes', () {
      // v1.0's tiltSpeed used two axes while movementMagnitude used three,
      // so the two velocity terms were not mutually comparable (R2).
      final p = GyroPipelineV11(thrSpeedRadS: 0.0);
      p.step(0, 0, 0, 0);
      final s = p.step(3.0, 4.0, 12.0, 5000)!;
      expect(s.angularSpeed, closeTo(13.0, 1e-9));
    });
  });

  // =========================================================================
  group('SwipeFeaturesV11 (R1-4, R1-12)', () {
    List<SwipePoint> line({int n = 11, double length = 100.0, double dur = 0.1}) =>
        List.generate(
            n, (i) => SwipePoint(length * i / (n - 1), 0.0, dur * i / (n - 1)));

    test('a straight line has unit straightness', () {
      final f = SwipeFeaturesV11.extract(line(), 1000.0);
      expect(f['straightnessIndex'], closeTo(1.0, 1e-9));
    });

    test('path length exceeds the chord for a curved swipe', () {
      final f = SwipeFeaturesV11.extract([
        const SwipePoint(0, 0, 0.0),
        const SwipePoint(50, 40, 0.05),
        const SwipePoint(100, 0, 0.1),
      ], 1000.0);
      expect(f['pathLength_px']!, greaterThan(f['straightLineDistance_px']!));
      expect(f['straightnessIndex']!, lessThan(1.0));
    });

    test('straightness can fall below the v1.0 hard floor of 1/sqrt(2)', () {
      // v1.0's "straightness" was the L2/L1 ratio of the same two points, so it
      // was bounded in [0.7071, 1] and could not express real curvature.
      final f = SwipeFeaturesV11.extract([
        const SwipePoint(0, 0, 0.0),
        const SwipePoint(30, 60, 0.03),
        const SwipePoint(60, -60, 0.06),
        const SwipePoint(90, 0, 0.09),
      ], 1000.0);
      expect(f['straightnessIndex']!, lessThan(1 / sqrt(2)));
    });

    test('speed is a length over a time', () {
      final f = SwipeFeaturesV11.extract(line(length: 100.0, dur: 0.1), 1000.0);
      expect(f['meanSpeed_px_s'], closeTo(1000.0, 1e-6));
    });

    test('screen normalisation removes device scale', () {
      final small = SwipeFeaturesV11.extract(line(length: 100.0), 800.0);
      final large = SwipeFeaturesV11.extract(
          line(length: 100.0).map((p) => SwipePoint(2 * p.x, 2 * p.y, p.tS)).toList(),
          1600.0);
      expect(small['snPathLength'], closeTo(large['snPathLength']!, 1e-9));
    });

    test('zero duration is rejected', () {
      expect(
        () => SwipeFeaturesV11.extract(
            [const SwipePoint(0, 0, 0.0), const SwipePoint(10, 0, 0.0)], 1000.0),
        throwsArgumentError,
      );
    });

    test('fling velocity is reported separately from path geometry', () {
      // v1.0 assigned the fling velocity to fields named endX/endY and then
      // used them as coordinates, mixing px with px/s.
      final f = SwipeFeaturesV11.extract(line(), 1000.0,
          flingVx: 300.0, flingVy: 400.0);
      expect(f['flingSpeed_px_s'], closeTo(500.0, 1e-9));
      expect(f['pathLength_px'], closeTo(100.0, 1e-9));
    });
  });

  // =========================================================================
  group('TapFeaturesV11 (R1-4)', () {
    test('tap rate is never truncated to zero', () {
      // v1.0: 1 ~/ duration == 0 for any duration above 1 ms.
      final f = TapFeaturesV11.extract(
        pressUs: 0,
        releaseUs: 80000,
        pressPos: const Offset(10, 10),
        releasePos: const Offset(10, 10),
        targetCentre: const Offset(10, 10),
        screenSize: const Size(400, 800),
      );
      expect(f['tapRate_hz'], closeTo(12.5, 1e-9));
    });

    test('drift uses the y axis', () {
      // v1.0 subtracted .dx where .dy was meant, so vertical drift read as zero
      // and the reported drift had an implausible 102 px floor.
      final f = TapFeaturesV11.extract(
        pressUs: 0,
        releaseUs: 50000,
        pressPos: const Offset(100, 100),
        releasePos: const Offset(100, 106),
        targetCentre: const Offset(100, 100),
        screenSize: const Size(400, 800),
      );
      expect(f['withinTapDrift_px'], closeTo(6.0, 1e-9));
    });

    test('within-tap drift and targeting error are distinct features', () {
      final f = TapFeaturesV11.extract(
        pressUs: 0,
        releaseUs: 50000,
        pressPos: const Offset(120, 100),
        releasePos: const Offset(123, 104),
        targetCentre: const Offset(100, 100),
        screenSize: const Size(400, 800),
      );
      expect(f['withinTapDrift_px'], closeTo(5.0, 1e-9));
      expect(f['targetingError_px'], closeTo(20.0, 1e-9));
    });

    test('non-positive duration is rejected', () {
      expect(
        () => TapFeaturesV11.extract(
          pressUs: 1000,
          releaseUs: 1000,
          pressPos: Offset.zero,
          releasePos: Offset.zero,
          targetCentre: Offset.zero,
          screenSize: const Size(400, 800),
        ),
        throwsArgumentError,
      );
    });
  });

  // =========================================================================
  group('KeystrokeSessionVectorV11 (R1-13, R2)', () {
    KeyEvent ev(double pressMs, double holdMs) => KeyEvent(
          pressUs: (pressMs * 1000).round(),
          releaseUs: ((pressMs + holdMs) * 1000).round(),
          keyText: 'a',
          keyType: 'textKey',
        );

    test('negative hold times are rejected, not averaged in', () {
      // The released corpus contains hold times down to -1040 ms, produced by
      // a wall-clock step under DateTime.now().
      final v = KeystrokeSessionVectorV11.build([
        ev(0, 100),
        const KeyEvent(
            pressUs: 500000, releaseUs: 400000, keyText: 'b', keyType: 'textKey'),
        ev(1000, 120),
      ]);
      expect(v['n_rejected'], 1.0);
      expect(v['hold_ms_median'], closeTo(110.0, 1e-6));
    });

    test('pauses are segmented out of flight time', () {
      // v1.0 recorded a 37-minute gap as a single flight time.
      final v =
          KeystrokeSessionVectorV11.build([ev(0, 100), ev(200, 100), ev(600000, 100)]);
      expect(v['flight_ms_median']!, lessThan(KeystrokeSessionVectorV11.pauseMs));
    });

    test('key rate is finite for a sub-second session', () {
      // v1.0 divided by Duration.inSeconds, i.e. by zero here.
      final v = KeystrokeSessionVectorV11.build([ev(0, 50), ev(100, 50)]);
      expect(v['keyRate_hz']!.isFinite, isTrue);
      expect(v['keyRate_hz']!, greaterThan(0));
    });

    test('coefficient of variation is undefined rather than negative', () {
      final v = KeystrokeSessionVectorV11.build([ev(0, 100)]);
      expect(v['hold_ms_cv']!.isNaN || v['hold_ms_cv']! >= 0, isTrue);
    });

    test('an empty session does not throw', () {
      final v = KeystrokeSessionVectorV11.build([]);
      expect(v['n_events'], 0.0);
    });

    test('a composed fidel logs two physical key events', () {
      // Base tap then order tap: two hold times, one intervening flight time
      // that measures the Ge'ez order-selection decision.
      final v = KeystrokeSessionVectorV11.build([
        const KeyEvent(
            pressUs: 0,
            releaseUs: 90000,
            keyText: 'ሀ',
            keyType: 'textKey',
            compositionRole: 'base'),
        const KeyEvent(
            pressUs: 400000,
            releaseUs: 480000,
            keyText: 'ሁ',
            keyType: 'textKey',
            compositionRole: 'order'),
      ]);
      expect(v['n_events'], 2.0);
      expect(v['flight_ms_median'], closeTo(310.0, 1e-6));
    });
  });

  // =========================================================================
  group('GaitFeaturesV11 (R1-4)', () {
    test('orientation uses three axes: flat device reads zero tilt', () {
      final o = GaitFeaturesV11.orientation(0.0, 0.0, 9.81);
      expect(o['pitch'], closeTo(0.0, 1e-6));
      expect(o['roll'], closeTo(0.0, 1e-6));
    });

    test('orientation detects a 90 degree tilt', () {
      final o = GaitFeaturesV11.orientation(9.81, 0.0, 0.0);
      expect(o['pitch'], closeTo(-90.0, 1e-4));
    });

    test('equal components do not produce the v1.0 constant', () {
      // v1.0 fed three near-equal magnitudes into a formula expecting three
      // axes, and got pitch = -19.8 deg for all 489 sessions in the corpus.
      final o = GaitFeaturesV11.orientation(5.66, 5.66, 5.66);
      expect((o['pitch']! + 19.82).abs(), greaterThan(1.0));
    });

    test('jerk is not structurally signed', () {
      // v1.0 sampled jerk only at the downward zero-crossing, so 100% of
      // released values are negative.
      final t = List<double>.generate(100, (i) => i * 0.01);
      final m = t.map((x) => 9.81 + sin(2 * pi * 2 * x)).toList();
      final f = GaitFeaturesV11.stepFeatures(m, t);
      expect(f['jerkSignBalance']!, greaterThan(0.3));
      expect(f['jerkSignBalance']!, lessThan(0.7));
    });

    test('gravity is removed', () {
      final t = List<double>.generate(50, (i) => i * 0.01);
      final f = GaitFeaturesV11.stepFeatures(List.filled(50, 9.80665), t);
      expect(f['meanLinearAccel_ms2'], closeTo(0.0, 1e-6));
    });
  });
}
