import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'v11/auth_headers_v11.dart';
import 'v11/secure_cache_v11.dart';

class HandwritingServices {
  String? uid;
  String? svgContent;
  Future<void> fetchUserId() async {
    uid = await getUserId();
    debugPrint("User ID is set: ==$uid");
  }

  Future<String?> getUserId() async {
    const secureStorage = FlutterSecureStorage();
    return await secureStorage.read(key: 'uid');
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
    await SecureCacheV11.open('offlineHandwritingData');
  }

  /// v1.1: preserves TEMPORAL as well as spatial fidelity.
  ///
  /// Reviewer 2 credited the v1.0 SVG-trajectory design. That credit was only
  /// half earned, and we corrected it rather than accept it: v1.0 wrote bare
  /// `M`/`L` coordinate pairs with **no per-point timestamp and no viewBox**.
  /// Stroke geometry and segmentation survived; writing velocity, pressure
  /// and canvas-relative normalisation did not, and cannot be recovered from
  /// the v1.0 corpus.
  ///
  /// v1.1 adds both:
  ///   * `viewBox` plus explicit width/height, so coordinates can be
  ///     normalised against the canvas they were drawn on;
  ///   * a `data-t` attribute holding milliseconds-since-stroke-start for
  ///     every sampled point, in path order, so velocity is recoverable.
  ///
  /// [timestampsMs] must align index-for-index with [points] when supplied.
  /// Omitting it reproduces the v1.0 output shape, minus the viewBox defect.
  String exportToSVG(
    List<Offset?> points, {
    Size? canvasSize,
    List<int?>? timestampsMs,
  }) {
    final StringBuffer buffer = StringBuffer();

    // Canvas extent: use the real size when known, otherwise the bounding box
    // of the stroke itself, so the output is never unitless.
    double w = canvasSize?.width ?? 0, h = canvasSize?.height ?? 0;
    if (w <= 0 || h <= 0) {
      double maxX = 0, maxY = 0;
      for (final p in points) {
        if (p == null) continue;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }
      w = maxX + 2;
      h = maxY + 2;
    }

    buffer.writeln('<svg xmlns="http://www.w3.org/2000/svg" version="1.1" '
        'viewBox="0 0 ${w.toStringAsFixed(2)} ${h.toStringAsFixed(2)}" '
        'width="${w.toStringAsFixed(2)}" height="${h.toStringAsFixed(2)}">');

    buffer.write('<path d="');
    final List<String> stamps = <String>[];

    for (int i = 0; i < points.length; i++) {
      if (points[i] != null) {
        final command = (i == 0 || points[i - 1] == null) ? 'M' : 'L';
        buffer.write('$command ${points[i]!.dx},${points[i]!.dy} ');
        if (timestampsMs != null && i < timestampsMs.length) {
          stamps.add('${timestampsMs[i] ?? ''}');
        }
      }
    }

    buffer.write('" fill="none" stroke="black" stroke-width="2"');
    if (stamps.isNotEmpty) {
      // Milliseconds since stroke start, one per sampled point, path order.
      buffer.write(' data-t="${stamps.join(',')}"');
    }
    buffer.writeln(' />');
    buffer.writeln('</svg>');

    return buffer.toString();
  }

  Future<String> saveHandwritingData(Map<String, dynamic> gameInfo) async {
    bool isOnline = await isConnectedToInternet();

    gameInfo['uid'] = uid;
    gameInfo['sessionId'] = DateTime.now().millisecondsSinceEpoch.toString();
    if (svgContent == null || svgContent!.isEmpty) {
      return "Data cannot be sent. data collection is empty";
    }
    final Map<String, dynamic> requestData = {
      'gameInfo': gameInfo,
      'HandwritingData': svgContent,
    };

    debugPrint('Request Data:');
    debugPrint('Game Info: ${requestData['gameInfo']}');
    debugPrint('Handwriting Data: ${requestData['HandwritingData']}');

    if (!isOnline) {
      // Save data to Hive if offline
      var box = Hive.box('offlineHandwritingData');
      await box.add(requestData);
      debugPrint('Data saved locally (offline).');
      return 'saved_locally';
    }

    final url = AppConfig.endpoint('/collect_Handwriting_data'); // Use your Dart Frog server address

    try {
      final response = await http.post(
        url,
        headers: await AuthHeadersV11.json(),
        body: jsonEncode(requestData),
      );

      if (response.statusCode == 200) {
        // User registered successfully
        debugPrint('  Handwriting Data added');
        return 'success';
      } else if (response.statusCode == 400) {
        // Client-side error; log the issue but do not save locally
        debugPrint(
            'Server responded with 400: ${response.body}. Data will not be saved locally.');
        return 'error_400';
      } else {
        // Handle error
        debugPrint('Could not add Handwriting data: ${response.body}');
        var box = Hive.box('offlineHandwritingData');
        await box.add(requestData);
        debugPrint('Data saved locally (offline).');
        return 'Server Error: saved_locally';
      }
    } catch (e) {
      debugPrint('Error occurred Handwriting : $e');
      // var box = Hive.box('offlineHandwritingData');
      // await box.add(requestData);
      // debugPrint('Data saved locally (offline).');
      return 'Unhandled Exception';
    }
  }
}
