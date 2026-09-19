// BahriApp v1.1 — authenticated request headers.
//
// v1.0 DEFECT (R1-6)
//   UserServices wrote the session token at login:
//       await _secureStorage.write(key: 'authToken', value: token);
//   and then no upload ever read it back. Every collection endpoint was called
//   with a bare
//       headers: {'Content-Type': 'application/json'}
//   so the server had no way to tell a genuine participant upload from an
//   anonymous one. The token existed; it was simply never sent.
//
// v1.1 routes every request's headers through [AuthHeadersV11.json], which
// attaches the bearer token and an idempotency key. Existing call sites change
// from
//       headers: {'Content-Type': 'application/json'},
// to
//       headers: await AuthHeadersV11.json(),
// which is the smallest edit that closes the hole. New code should prefer
// ApiClientV11, which also enforces TLS and certificate pinning.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../config/app_config.dart';

class AuthHeadersV11 {
  static const _tokenKey = 'authToken';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Headers for a JSON request, carrying the stored bearer token when present.
  ///
  /// [idempotencyKey] lets the server deduplicate a retried upload instead of
  /// recording a duplicate session — the "replayed sessions" threat in the
  /// manuscript's threat model. Build it with [sessionKey].
  static Future<Map<String, String>> json({String? idempotencyKey}) async {
    String? token;
    try {
      token = await _storage.read(key: _tokenKey);
    } catch (_) {
      // Keystore unavailable (e.g. device locked during a background sync).
      // Proceed unauthenticated rather than losing the payload; the server
      // rejects it with 401 and the queue retries later.
      token = null;
    }
    return {
      'Content-Type': 'application/json',
      'X-App-Version': AppConfig.appVersion,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
    };
  }

  /// Stable per-session key, so a retry of the same session deduplicates.
  static String sessionKey({
    required String participantId,
    required String sessionId,
    required String modality,
  }) =>
      sha256
          .convert(utf8.encode('$participantId|$sessionId|$modality'))
          .toString();

  static Future<bool> get hasToken async {
    final t = await _storage.read(key: _tokenKey);
    return t != null && t.isNotEmpty;
  }

  static Future<void> clear() => _storage.delete(key: _tokenKey);
}
