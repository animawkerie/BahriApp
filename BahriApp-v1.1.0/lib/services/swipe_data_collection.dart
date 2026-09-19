import 'dart:math';

import 'package:flutter/material.dart';

/// v1.1 (R1-4, R1-12): records the real swipe trajectory.
///
/// TWO v1.0 DEFECTS ARE FIXED HERE.
///
/// 1. `updateCollecting()` was an empty stub, so no intermediate touch point
///    was ever retained. Every path-derived feature in the released corpus
///    was therefore computed from just two points.
///
/// 2. The recogniser's FLING VELOCITY (px/s) was assigned to fields named
///    `endX` / `endY` and then used as if it were a COORDINATE (px):
///
///        'endX': details.velocity.pixelsPerSecond.dx,
///        'distance': sqrt(pow(vx - initialX, 2) + pow(vy - initialY, 2)),
///
///    Nine derived columns therefore mixed px with px/s. In the released
///    corpus the median "distance" is 2,524 px on screens whose recovered
///    diagonal is 892 px — 2.8 screen diagonals for a single swipe.
///
/// The fling velocity itself is a legitimate feature; it is kept here under
/// an honest name. Path geometry now comes from the trajectory.
class SwipeDataCollector {
  Offset? _initialPosition;
  double? _initialPressure;
  final Stopwatch _sw = Stopwatch();
  final List<List<double>> _points = <List<double>>[]; // [x, y, tSeconds]

  void startCollecting(DragStartDetails details) {
    _initialPosition = details.globalPosition;
    _initialPressure = null;
    _points.clear();
    _sw
      ..reset()
      ..start();
    _points.add([details.globalPosition.dx, details.globalPosition.dy, 0.0]);
  }

  /// v1.0 left this empty. Retaining the trajectory is the single change that
  /// makes path length, curvature and true kinematics recoverable.
  void updateCollecting(DragUpdateDetails details) {
    _points.add([
      details.globalPosition.dx,
      details.globalPosition.dy,
      _sw.elapsedMicroseconds / 1e6,
    ]);
  }

  void endCollecting(
      DragEndDetails details, Function(Map<String, dynamic>) onComplete,
      {double screenDiagonalPx = 0.0}) {
    _sw.stop();
    final duration = _points.isNotEmpty ? _points.last[2] : 0.0;
    final v = details.velocity.pixelsPerSecond;

    // Path geometry from the real trajectory.
    double pathLen = 0.0, peakSpeed = 0.0;
    for (var i = 1; i < _points.length; i++) {
      final a = _points[i - 1], b = _points[i];
      final seg = sqrt(pow(b[0] - a[0], 2) + pow(b[1] - a[1], 2));
      final dt = max(b[2] - a[2], 1e-9);
      pathLen += seg;
      peakSpeed = max(peakSpeed, seg / dt);
    }
    final chord = _points.length >= 2
        ? sqrt(pow(_points.last[0] - _points.first[0], 2) +
            pow(_points.last[1] - _points.first[1], 2))
        : 0.0;

    final data = <String, dynamic>{
      'initialX': _initialPosition!.dx,
      'initialY': _initialPosition!.dy,
      'initialPressure': _initialPressure ?? 0.5,
      'duration': duration,

      // Fling velocity, correctly named. v1.0 stored these as endX / endY.
      'flingVelocityX': v.dx,
      'flingVelocityY': v.dy,
      'flingSpeed_px_s': v.distance,
      'flingDirection_deg': atan2(v.dy, v.dx) * 180 / pi,

      // Path geometry, dimensionally consistent.
      'pathLength_px': pathLen,
      'straightLineDistance_px': chord,
      'straightnessIndex': pathLen > 0 ? chord / pathLen : 1.0,
      'meanSpeed_px_s': duration > 0 ? pathLen / duration : 0.0,
      'peakSpeed_px_s': peakSpeed,
      'nSampledPoints': _points.length,

      // Full trajectory, so downstream users are never again limited to the
      // two points v1.0 happened to keep.
      'trajectory': _points,
    };

    if (screenDiagonalPx > 0) {
      data['snPathLength'] = pathLen / screenDiagonalPx;
      data['snMeanSpeed'] =
          duration > 0 ? (pathLen / duration) / screenDiagonalPx : 0.0;
      data['screenDiagonalPx'] = screenDiagonalPx;
    }

    onComplete(data);
  }

  List<List<double>> get trajectory => List.unmodifiable(_points);
}

class DataCollectionService {
  // Method to calculate the screen diagonal length
  double getScreenDiagonal(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    return sqrt(size.width * size.width + size.height * size.height);
  }

  // Method to calculate screen area
  double getScreenArea(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    return size.width * size.height;
  }

  //non normalized metrics yes!
  double calculateSwipePathStraightness(
      double initialX, double initialY, double endX, double endY) {
    double straightDistance =
        sqrt(pow(endX - initialX, 2) + pow(endY - initialY, 2));
    double actualDistance = (endX - initialX).abs() + (endY - initialY).abs();
    return straightDistance / actualDistance;
  }

  double calculateSwipeAngle(
      double initialX, double initialY, double endX, double endY) {
    return atan2(endY - initialY, endX - initialX) * (180 / pi);
  }

  double calculateSwipeSpeed(double distance, double duration) {
    return distance / duration;
  }

  double calculateSwipeAcceleration(double speed, double duration) {
    return speed / duration;
  }

  double calculateSwipeJerk(double acceleration, double duration) {
    return acceleration / duration;
  }

  double calculateSwipeDistance(
      double initialX, double initialY, double endX, double endY) {
    return sqrt(pow(endX - initialX, 2) + pow(endY - initialY, 2));
  }

  double calculateSwipeDuration(int startTime, int endTime) {
    return (endTime - startTime) / 1000.0; // convert milliseconds to seconds
  }

  double calculateSwipeDeceleration(double speed, double duration) {
    // Assuming the swipe starts at max speed and decelerates to 0
    return speed / duration; // Simplified deceleration calculation
  }

  double calculateSwipeAreaCoverage(double startX, double startY, double endX,
      double endY, double screenArea) {
    double swipeWidth = (endX - startX).abs();
    double swipeHeight = (endY - startY).abs();
    double swipeArea = swipeWidth * swipeHeight;
    return swipeArea / screenArea;
  }

  double calculateSwipeFingerOrientation(
      double initialX, double initialY, double endX, double endY) {
    return atan2(endY - initialY, endX - initialX) * (180 / pi);
  }

  double calculateSwipeFingerMovementVariability(
      double initialX, double initialY, double endX, double endY) {
    // This is a simplified version that assumes variability is the difference between straight and actual path lengths
    double straightDistance =
        sqrt(pow(endX - initialX, 2) + pow(endY - initialY, 2));
    double actualDistance = (endX - initialX).abs() + (endY - initialY).abs();
    return (actualDistance - straightDistance).abs();
  }

  double calculateTimeOfDayImpact() {
    DateTime now = DateTime.now();
    // Assume some variation based on time; this is highly simplified
    return now.hour + (now.minute / 60.0);
  }
  // Screen-normalized metrics yes!

  double calculateSNSL(double swipeLength, BuildContext context) {
    return swipeLength / getScreenDiagonal(context);
  }

  double calculateSNSS(double swipeSpeed, BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    return swipeSpeed / (size.width * size.height);
  }

  double calculateSNSA(double swipeAngle, BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    return swipeAngle * (size.height / size.width);
  }

  double calculateSNSD(double swipeDuration, double screenResponseTime) {
    return swipeDuration / screenResponseTime;
  }
  //will do something about pressure later on
  /*double calculateSNSP(double swipePressure, double screenSensitivity) {
    return swipePressure / screenSensitivity;
  }*/

  double calculateSNSPC(double swipePathCurvature, BuildContext context) {
    return swipePathCurvature / getScreenDiagonal(context);
  }

  double calculateSNSPL(double actualSwipePathLength, BuildContext context) {
    return actualSwipePathLength / getScreenDiagonal(context);
  }

  double calculateSNSA_Acceleration(
      double swipeAcceleration, BuildContext context) {
    return swipeAcceleration / getScreenDiagonal(context);
  }

  double calculateSNSD_Deceleration(
      double swipeDeceleration, BuildContext context) {
    return swipeDeceleration / getScreenDiagonal(context);
  }

  double calculateSNSJ(double swipeJerk, BuildContext context) {
    return swipeJerk / getScreenDiagonal(context);
  }

  double calculateSPSAC(double swipeArea, BuildContext context) {
    return swipeArea / getScreenArea(context);
  }

  double calculateSNSS_Straightness(
      double swipeStraightness, BuildContext context) {
    return swipeStraightness / getScreenDiagonal(context);
  }

  double calculateSNSFO(double fingerOrientation, BuildContext context) {
    return fingerOrientation / getScreenDiagonal(context);
  }

  double calculateSNSFMV(
      double fingerMovementVariability, BuildContext context) {
    return fingerMovementVariability / getScreenDiagonal(context);
  }

  double calculateSNSTDI(
      double timeOfDaySwipePerformance, double screenPerformanceIndex) {
    return timeOfDaySwipePerformance / screenPerformanceIndex;
  }
}
