import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'v11/auth_headers_v11.dart';
import 'v11/secure_cache_v11.dart';

class TapDataCollectionService {
  int calculateTapDuration(int tapPressTime, int tapReleaseTime) {
    return tapReleaseTime - tapPressTime;
  }

  int calculateTapLatency(int screenResponseTime, int tapPressTime) {
    return screenResponseTime - tapPressTime;
  }

  double calculateTapSpeed(int tapPressTime, int tapReleaseTime) {
    // v1.1 (R1-4): v1.0 used `1 ~/ duration`. Dart's ~/ is INTEGER division,
    // so any duration above 1 ms yielded exactly 0 — 99.29% of released
    // TapSpeed values are zero. Returns taps per second as a double.
    final durationMs = calculateTapDuration(tapPressTime, tapReleaseTime);
    if (durationMs <= 0) return double.nan;
    return 1000.0 / durationMs;
  }

  /// v1.1 (R1-4): the second term used `.dx` where `.dy` was intended.
  ///
  /// The v1.0 formula was
  ///     sqrt((intended.dx - actual.dx)^2 + (intended.dx - actual.dy)^2)
  ///                                         ^^^ wrong axis
  /// which produced a median drift of 421 px with a 102 px floor across the
  /// released corpus — a finger cannot slip 102 px on every single tap. The
  /// corrected value is sub-pixel to a few px, which is what within-tap
  /// slippage actually looks like.
  double calculateTapDrift(
      Offset intededTapLocation, Offset actualTapLocation) {
    return sqrt(pow(intededTapLocation.dx - actualTapLocation.dx, 2) +
        pow(intededTapLocation.dy - actualTapLocation.dy, 2));
  }

  double calculateTapDistance(
      Offset globalIntialLocation, Offset globalFinalLocation) {
    return (globalFinalLocation - globalIntialLocation).distance;
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
    await SecureCacheV11.open('offlineTapData');
  }

  Future<String> saveTapData(
      List<Map<String, dynamic>> tapData, Map<String, dynamic> gameInfo) async {
    bool isOnline = await isConnectedToInternet();
    //if (!isOnline) return 'fail';
    gameInfo['sessionId'] = DateTime.now().millisecondsSinceEpoch.toString();
    if (tapData.isEmpty) {
      return "Data cannot be sent. data collection is empty";
    }
    final Map<String, dynamic> requestData = {
      'gameInfo': gameInfo,
      'tapData': tapData,
    };

    debugPrint('Request Data:');
    debugPrint('Game Info: ${requestData['gameInfo']}');
    debugPrint('Tap Data: ${requestData['tapData']}');

    if (!isOnline) {
      // Save data to Hive if offline
      var box = Hive.box('offlineTapData');
      await box.add(requestData);
      debugPrint('Tap Data saved locally (offline).');
      return 'Tap Data saved_locally';
    }
    final url = AppConfig.endpoint('/collect_tap_data'); // Use your Dart Frog server address

    try {
      final response = await http.post(
        url,
        headers: await AuthHeadersV11.json(),
        body: jsonEncode(requestData),
      );

      if (response.statusCode == 200) {
        // User registered successfully
        debugPrint('Tap Data Successfully added');
        return 'success';
      } else if (response.statusCode == 400) {
        // Client-side error; log the issue but do not save locally
        debugPrint(
            'Server responded with 400: ${response.body}. Data will not be saved locally.');
        return 'error_400';
      } else {
        // Handle error
        debugPrint('Could not add tap data: ${response.body}');
        var box = Hive.box('offlineTapData');
        await box.add(requestData);
        debugPrint('Tap Data saved locally (offline).');
        return 'Tap Data saved_locally';
      }
    } catch (e) {
      // debugPrint('Error occurred: $e');
      // var box = Hive.box('offlineTapData');
      // await box.add(requestData);
      // debugPrint('Tap Data saved locally (offline).');
      return 'Unhandled Exception';
    }
  }
}
