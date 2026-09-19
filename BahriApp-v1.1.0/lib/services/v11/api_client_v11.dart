// BahriApp v1.1 — authenticated HTTPS client.
//
// v1.0 DEFECTS (R1-6, R1-7)
//   * All 24 endpoints used plain HTTP to a hard-coded IPv4 address. No TLS.
//   * The authToken was stored at login but never attached to an upload, so
//     the collection endpoints accepted anonymous writes.
//   * Nothing deduplicated sessions server-side, so a retried upload could
//     pollute the corpus with a replay.
//
// v1.1 routes every request through this client, which enforces HTTPS, pins
// the server certificate, attaches the bearer token, sets an idempotency key
// so retries deduplicate, and refuses to start if the configuration would put
// participant data in the clear.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../config/app_config.dart';

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  const ApiException(this.message, [this.statusCode]);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClientV11 {
  static const _tokenKey = 'bahri_auth_token';
  static const _refreshKey = 'bahri_refresh_token';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static ApiClientV11? _instance;
  static ApiClientV11 get instance => _instance ??= ApiClientV11._();

  late final http.Client _client;

  ApiClientV11._() {
    AppConfig.assertValid();
    _client = _buildClient();
  }

  /// Certificate pinning: compare the SHA-256 of the DER-encoded leaf against
  /// the configured pin. An unpinned build (empty pin) is allowed only for a
  /// local development stack.
  http.Client _buildClient() {
    final ctx = HttpClient();
    ctx.connectionTimeout = AppConfig.requestTimeout;

    final pin = AppConfig.certPinSha256;
    if (pin.isNotEmpty) {
      ctx.badCertificateCallback = (X509Certificate cert, String host, int port) {
        final digest = sha256.convert(cert.der).toString();
        final expected =
            base64Decode(pin).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        return digest == expected;
      };
    } else if (!AppConfig.allowInsecureTransport) {
      // No pin and not explicitly insecure: rely on the platform trust store,
      // but never silently accept a bad certificate.
      ctx.badCertificateCallback = (_, __, ___) => false;
    }
    return IOClient(ctx);
  }

  // --- token handling -------------------------------------------------------

  Future<String?> get token => _storage.read(key: _tokenKey);

  Future<void> saveTokens({required String access, String? refresh}) async {
    await _storage.write(key: _tokenKey, value: access);
    if (refresh != null) await _storage.write(key: _refreshKey, value: refresh);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshKey);
  }

  Future<Map<String, String>> _headers({String? idempotencyKey}) async {
    final t = await token;
    return {
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      'X-App-Version': AppConfig.appVersion,
      // v1.0 stored this and then never sent it. That is the whole defect.
      if (t != null && t.isNotEmpty) 'Authorization': 'Bearer $t',
      if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
    };
  }

  /// Deterministic key so a retried upload is deduplicated server-side rather
  /// than creating a duplicate session (the "replayed sessions" threat).
  static String idempotencyKey({
    required String participantId,
    required String sessionId,
    required String modality,
  }) =>
      sha256.convert(utf8.encode('$participantId|$sessionId|$modality')).toString();

  // --- requests -------------------------------------------------------------

  Future<Map<String, dynamic>> postJson(
    String path,
    Object body, {
    String? idempotencyKey,
  }) async {
    final uri = AppConfig.endpoint(path);
    late http.Response res;
    try {
      res = await _client
          .post(uri, headers: await _headers(idempotencyKey: idempotencyKey), body: jsonEncode(body))
          .timeout(AppConfig.requestTimeout);
    } on TimeoutException {
      throw const ApiException('request timed out');
    } on SocketException catch (e) {
      throw ApiException('network unavailable: ${e.message}');
    } on HandshakeException catch (e) {
      // A pinning failure lands here. Never fall back to plaintext.
      throw ApiException('TLS handshake failed (certificate pin?): ${e.message}');
    }

    if (res.statusCode == 401) {
      await clearTokens();
      throw const ApiException('authentication required', 401);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.body, res.statusCode);
    }
    if (res.body.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(res.body);
    return decoded is Map<String, dynamic> ? decoded : {'data': decoded};
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    final uri = AppConfig.endpoint(path);
    final res =
        await _client.get(uri, headers: await _headers()).timeout(AppConfig.requestTimeout);
    if (res.statusCode == 401) {
      await clearTokens();
      throw const ApiException('authentication required', 401);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.body, res.statusCode);
    }
    final decoded = jsonDecode(res.body);
    return decoded is Map<String, dynamic> ? decoded : {'data': decoded};
  }

  /// Upload one modality session. Returns the server-assigned receipt id, which
  /// the caller uses to purge the local encrypted cache entry.
  Future<String> uploadSession({
    required String path,
    required String participantId,
    required String sessionId,
    required String modality,
    required Map<String, dynamic> payload,
    Map<String, dynamic>? instrumentMeta,
  }) async {
    final body = <String, dynamic>{
      'participantId': participantId,
      'sessionId': sessionId,
      'modality': modality,
      'appVersion': AppConfig.appVersion,
      if (instrumentMeta != null) 'instrument': instrumentMeta,
      'payload': payload,
    };
    final res = await postJson(
      path,
      body,
      idempotencyKey: idempotencyKey(
        participantId: participantId,
        sessionId: sessionId,
        modality: modality,
      ),
    );
    return (res['receiptId'] ?? res['id'] ?? sessionId).toString();
  }

  void close() => _client.close();
}
