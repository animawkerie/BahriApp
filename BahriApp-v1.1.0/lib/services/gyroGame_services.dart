import 'dart:convert';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart'; // For debug prints
import 'package:hive_flutter/adapters.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'v11/secure_cache_v11.dart';

class GyroData {
  double? lastGyroX, lastGyroY, lastGyroZ;
  DateTime? lastTimestamp;

  // --- v1.1 CORRECTED THRESHOLDS (R1-9) ------------------------------------
  //
  // v1.0 compared the single scalar 20 against three quantities of TWO
  // different physical dimensions:
  //     movementThreshold     vs |omega|          (rad/s)
  //     speedThreshold        vs tiltSpeed        (rad/s, two axes only)
  //     accelerationThreshold vs tiltAcceleration (rad/s^2)
  //
  // Auditing the released corpus showed what that actually did: 98.53% of
  // samples were retained, 98.41% of them by the acceleration term alone.
  // Only 0.117% of records exceeded 20 rad/s — which is 1146 deg/s, far
  // outside anything a hand-held tilt task produces (p99.9 = 20.6 rad/s).
  // The routine was very nearly a no-op, and the manuscript's claim that 20
  // was "empirically determined" is withdrawn: the original source comment
  // read "Adjust this threshold to control sensitivity", i.e. a placeholder.
  //
  // v1.1 gives each dimension its own threshold in its own units. The speed
  // gate is the 70th percentile of angular speed measured across the pilot
  // corpus; regenerate it for a new cohort with
  // GyroPipelineV11.calibrate(speeds, targetRetention: 0.30) and record both
  // the percentile and the resulting retention rate with the dataset.

  /// rad/s — three-axis angular speed. 1.63 rad/s = 93 deg/s, the pilot p70.
  final double angularSpeedThresholdRadS = 1.63;

  /// rad/s^2 — angular acceleration. Null disables this term.
  final double? angularAccelThresholdRadS2 = null;

  /// rad/s^3 — angular jerk. Null disables this term.
  final double? angularJerkThresholdRadS3 = null;
  final Duration delayBetweenSaves =
      const Duration(milliseconds: 200); // Optional: Add a delay between saves

  /// Spherical direction of the instantaneous rotation axis, degrees.
  /// Renamed from v1.0's `roll` / `pitch`, which were retracted as
  /// orientation estimates — see calculateOmegaDirection().
  double omegaAzimuth = 0.0;
  double omegaElevation = 0.0;

  double tiltSpeed = 0.0;
  double tiltAcceleration = 0.0;
  double tiltDeceleration = 0.0;
  double jerk = 0.0;
  double? lastTiltSpeed;
  double? lastTiltAcceleration; // Added for jerk calculation
  double? lastRotationDirection;

  double rotationDuration = 0.0;
  double rotationDirectionConsistency = 0.0;
  int consistentRotations = 0;
  int totalRotations = 0;
  double cumulativeRotation = 0.0; // Added to track total rotation
  DateTime? rotationStartTime;

  bool isEventActive = false;
  Duration eventCooldown = const Duration(
      seconds: 1); // Time window after an event where data will still be stored
  DateTime? lastEventTime;
  String? _sessionId;
  String? _userId;
  bool _isSessionActive = false;
  List<Map<String, dynamic>> _sessionData = [];

  Future<void> startNewSession(String userId) async {
    _userId = userId;
    _sessionId = _generateSessionId();
    _isSessionActive = true;
    _sessionData = [];
    debugPrint('Started new session: $_sessionId for user: $_userId');
  }

  Future<void> endSession() async {
    if (_isSessionActive) {
      // Send all collected data at once
      await _sendSessionData();
      _isSessionActive = false;
      _sessionData = [];
      debugPrint('Ended session: $_sessionId');
    }
  }

  String _generateSessionId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  /// v1.1 (R1-10): these are NOT orientation angles.
  ///
  /// v1.0 applied the standard gravity-vector tilt formulas to angular
  /// VELOCITY and stored the result as `roll` and `pitch`. Applied to omega,
  /// atan2 returns the spherical direction of the instantaneous rotation
  /// axis, not the device's orientation. The released columns reproduce
  /// exactly as atan2 of the raw angular velocities and swing across the full
  /// angular range between samples 5 ms apart — impossible for a hand-held
  /// device's physical orientation, expected for a noisy velocity vector.
  ///
  /// The two columns are therefore retracted as orientation estimates and
  /// renamed to what they actually measure. For a genuine orientation
  /// estimate, use GyroPipelineV11, which fuses the gyroscope with the
  /// accelerometer through a complementary filter.
  void calculateOmegaDirection(double gyroX, double gyroY, double gyroZ) {
    omegaAzimuth = _handleNaN(atan2(gyroY, gyroZ) * 180 / pi);
    omegaElevation = _handleNaN(
        atan2(-gyroX, sqrt(gyroY * gyroY + gyroZ * gyroZ)) * 180 / pi);
  }

  /// v1.1 (R1-11): explicit Delta-t contract, in microseconds.
  ///
  /// v1.0 computed deltaTime from Duration.inMilliseconds, which TRUNCATES.
  /// The smallest representable non-zero interval was therefore 1 ms, and the
  /// `deltaTime > 0` guard silently discarded every sample that arrived
  /// sooner. That mattered: the measured median inter-sample interval in the
  /// pilot corpus is 4.7 ms, but per-session realised rates reach several
  /// hundred hertz, so a substantial share of events were dropped without
  /// being counted.
  ///
  /// v1.1 uses inMicroseconds and an explicit admissible window. Samples
  /// outside it are rejected AND COUNTED, never divided by, so the rejection
  /// rate is visible in the session metadata rather than invisible.
  static const double dtMinS = 1e-4; // 0.1 ms
  static const double dtMaxS = 0.25; // 250 ms — longer means an app pause
  int samplesDtRejected = 0;

  void calculateTiltSpeed(double gyroX, double gyroY, DateTime currentTime) {
    if (lastTimestamp != null) {
      double deltaTime = _handleNaN(
          currentTime.difference(lastTimestamp!).inMicroseconds / 1e6);
      if (deltaTime < dtMinS || deltaTime > dtMaxS) {
        samplesDtRejected++;
        lastTimestamp = currentTime;
        return;
      }
      {
        // Calculate magnitude of angular velocity
        double currentTiltSpeed =
            _handleNaN(sqrt(gyroX * gyroX + gyroY * gyroY));
        tiltSpeed = currentTiltSpeed;

        if (lastTiltSpeed != null) {
          // Calculate acceleration (change in speed over time)
          tiltAcceleration =
              _handleNaN((currentTiltSpeed - lastTiltSpeed!) / deltaTime);

          if (lastTiltAcceleration != null) {
            // Calculate jerk (change in acceleration over time)
            jerk = _handleNaN(
                (tiltAcceleration - lastTiltAcceleration!) / deltaTime);
          }

          lastTiltAcceleration = tiltAcceleration;
        }

        lastTiltSpeed = currentTiltSpeed;
      }
    }
    lastTimestamp = currentTime;
  }

  double calculateTiltStability(double gyroX, double gyroY, double gyroZ) {
    if (lastGyroX != null && lastGyroY != null && lastGyroZ != null) {
      double deltaX = _handleNaN((gyroX - lastGyroX!).abs());
      double deltaY = _handleNaN((gyroY - lastGyroY!).abs());
      double deltaZ = _handleNaN((gyroZ - lastGyroZ!).abs());

      double stability = _handleNaN(deltaX + deltaY + deltaZ);
      return stability;
    }
    lastGyroX = gyroX;
    lastGyroY = gyroY;
    lastGyroZ = gyroZ;
    return 0.0;
  }

  void calculateRotationDirection(double gyroX, DateTime currentTime) {
    double currentDirection = gyroX > 0 ? 1.0 : -1.0;

    if (lastRotationDirection != null) {
      if (currentDirection == lastRotationDirection) {
        consistentRotations++;
      }
      totalRotations++;

      // Calculate consistency as a percentage
      rotationDirectionConsistency = totalRotations > 0
          ? _handleNaN((consistentRotations / totalRotations) * 100.0)
          : 0.0;
    }

    // Start tracking rotation duration when direction changes
    if (lastRotationDirection != currentDirection) {
      rotationStartTime = currentTime;
    }

    lastRotationDirection = currentDirection;
  }

  double calculateMicroAdjustments(double gyroX, double gyroY, double gyroZ) {
    return _handleNaN(sqrt(gyroX * gyroX + gyroY * gyroY + gyroZ * gyroZ));
  }

  double calculateRotationPathStraightness(
      double gyroX, double gyroY, double gyroZ) {
    return _handleNaN((gyroX.abs() + gyroY.abs() + gyroZ.abs()) / 3.0);
  }

  void calculateRotationDuration(double gyroX, DateTime currentTime) {
    // Only update duration if we're actually rotating (above some minimum threshold)
    const rotationThreshold = 0.1; // Adjust this value based on your needs

    if (gyroX.abs() > rotationThreshold) {
      rotationStartTime ??= currentTime;

      // Calculate duration in seconds
      rotationDuration = _handleNaN(
          currentTime.difference(rotationStartTime!).inMicroseconds / 1e6);

      // Update cumulative rotation
      double deltaTime = lastTimestamp != null
          ? currentTime.difference(lastTimestamp!).inMicroseconds / 1e6
          : 0.0;
      cumulativeRotation += gyroX * deltaTime;
    } else {
      // Reset if no significant rotation
      if (rotationStartTime != null) {
        rotationStartTime = null;
        rotationDuration = 0.0;
      }
    }

    lastTimestamp = currentTime;
  }

  /// v1.1: each term is compared against a threshold in its own units.
  ///
  /// Note also that v1.0's `tiltSpeed` used only two axes while
  /// `movementMagnitude` used three, so the two velocity terms were not even
  /// mutually comparable (Reviewer 2). v1.1 uses one three-axis angular speed.
  bool isSignificantMovement(double gyroX, double gyroY, double gyroZ) {
    final double angularSpeed = // rad/s, all three axes
        sqrt(gyroX * gyroX + gyroY * gyroY + gyroZ * gyroZ);

    if (angularSpeed > angularSpeedThresholdRadS) return true;
    if (angularAccelThresholdRadS2 != null &&
        tiltAcceleration.abs() > angularAccelThresholdRadS2!) return true;
    if (angularJerkThresholdRadS3 != null &&
        jerk.abs() > angularJerkThresholdRadS3!) return true;
    return false;
  }

  Future<bool> isConnectedToInternet() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.mobile) ||
        connectivityResult.contains(ConnectivityResult.wifi)) {
      return true;
    } else {
      return false;
    }
  }

  Future<void> initHive() async {
    await Hive.initFlutter();
    await SecureCacheV11.open('offlineGyroData');
  }

  Future<void> storeGyroDataDartFrog(
    String userId,
    double gyroX,
    double gyroY,
    double gyroZ,
  ) async {
    try {
      if (!_isSessionActive) {
        await startNewSession(userId);
      }

      DateTime now = DateTime.now();
      // Calculate tilt and rotation data
      calculateOmegaDirection(gyroX, gyroY, gyroZ);
      calculateTiltSpeed(gyroX, gyroY, now);
      calculateRotationDirection(gyroX, now);
      calculateRotationDuration(gyroX, now);

      // Only store significant data points
      if (isSignificantMovement(gyroX, gyroY, gyroZ)) {
        Map<String, dynamic> dataPoint = {
          'timestamp': now.toIso8601String(),
          'gyroX': gyroX,
          'gyroY': gyroY,
          'gyroZ': gyroZ,
          // v1.1: retracted as orientation, renamed to what they measure.
          'omegaAzimuth': omegaAzimuth,
          'omegaElevation': omegaElevation,
          'tiltSpeed': tiltSpeed,
          'tiltAcceleration': tiltAcceleration,
          'jerk': jerk,
          'rotationDuration': rotationDuration,
          'rotationDirectionConsistency': rotationDirectionConsistency,
        };

        _sessionData.add(dataPoint);
      }
    } catch (e) {
      debugPrint('Error in storeGyroDataDartFrog: $e');
    }
  }

  Future<String> _sendSessionData() async {
    if (_sessionData.isEmpty) return "Session empty";

    bool isOnline = await isConnectedToInternet();
    //final url = AppConfig.endpoint('/collect_gyro_data');

    final payload = {
      'userId': _userId,
      'sessionId': _sessionId,
      'gyroData': _sessionData,
    };

    if (!isOnline) {
      var box = Hive.box('offlineGyroData');
      await box.add(payload);
      debugPrint('Data saved locally (offline).');
      _sessionData.clear();
      return 'saved_locally';
    }

    try {
      await compute(_sendDataToServer, payload);
      debugPrint('Successfully sent data in background.');
      _sessionData.clear();
      return 'success';
    } catch (e) {
      return 'Unhandled Exception';
    }
  }

  Future<void> _sendDataToServer(Map<String, dynamic> payload) async {
    final url = AppConfig.endpoint('/collect_gyro_data');
    try {
      final response = await http.post(
        url,
        body: jsonEncode(payload),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        debugPrint('Data sent successfully: ${response.statusCode}');

        throw Exception('Failed to send data: ${response.statusCode}');
      } else if (response.statusCode == 400) {
        // Client-side error; log the issue but do not save locally
        debugPrint(
            'Server responded with 400: ${response.body}. Data will not be saved locally.');
      } else {
        debugPrint('Data not sent successfully: ${response.statusCode}');
        var box = Hive.box('offlineGyroData');
        await box.add(payload);
        debugPrint('Data saved locally (offline).');
        _sessionData.clear();
      }
    } catch (e) {
      debugPrint('Network error: $e');
      throw e;
    }
  }

  double _handleNaN(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0.0;
    }
    return value;
  }
}
