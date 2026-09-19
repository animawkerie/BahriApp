// BahriApp v1.1 — encrypted on-device cache.
//
// v1.0 DEFECT (R1-6)
//   All eight offline Hive boxes were opened with no encryptionCipher:
//       await Hive.openBox('offlineKeystrokeData');
//   so every cached behavioural session sat on the device as plaintext. An
//   attacker holding a lost or stolen participant device could read the whole
//   queue. The authToken was written to flutter_secure_storage at login but
//   never attached to any upload request, leaving the collection endpoints
//   effectively unauthenticated.
//
//   The manuscript described this as "end-to-end encryption". It was not
//   encryption of any kind. The claim is withdrawn; this file is the
//   remediation.
//
// v1.1 opens every box with a 256-bit AES cipher whose key is generated once
// per install and held in flutter_secure_storage, which is backed by the
// Android Keystore. Cached payloads are purged once the server acknowledges
// them, so the at-rest window is as short as connectivity allows.

import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

class SecureCacheV11 {
  static const _keyName = 'bahri_hive_key_v1';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Every box that holds behavioural payloads awaiting upload.
  static const List<String> offlineBoxes = <String>[
    'offlineKeystrokeData',
    'offlineKeystrokeFreeTextData',
    'offlineKeystrokePasswordTextData',
    'offlineHandwritingData',
    'offlineTapData',
    'offlineSwipeData',
    'offlineAcceloData',
    'offlineGyroData',
  ];

  static List<int>? _cipherKey;

  /// Generate on first run, then read back from the Keystore-backed store.
  static Future<List<int>> _key() async {
    if (_cipherKey != null) return _cipherKey!;
    var encoded = await _storage.read(key: _keyName);
    if (encoded == null) {
      final key = Hive.generateSecureKey(); // 256-bit, from a secure RNG
      encoded = base64UrlEncode(key);
      await _storage.write(key: _keyName, value: encoded);
    }
    _cipherKey = base64Url.decode(encoded);
    return _cipherKey!;
  }

  /// Open every offline box with encryption. Call once at startup, in place of
  /// the bare Hive.openBox calls in network_manager.dart.
  static Future<void> initAll() async {
    final cipher = HiveAesCipher(await _key());
    for (final name in offlineBoxes) {
      if (!Hive.isBoxOpen(name)) {
        await Hive.openBox(name, encryptionCipher: cipher);
      }
    }
  }

  /// Open one encrypted box by name.
  static Future<Box> open(String name) async {
    if (Hive.isBoxOpen(name)) return Hive.box(name);
    return Hive.openBox(name, encryptionCipher: HiveAesCipher(await _key()));
  }

  /// Purge acknowledged records. Call after the server confirms receipt, so
  /// that the at-rest exposure window closes as soon as possible.
  static Future<int> purgeAcknowledged(String boxName, Set<String> ackedKeys) async {
    final box = await open(boxName);
    var removed = 0;
    for (final k in ackedKeys) {
      if (box.containsKey(k)) {
        await box.delete(k);
        removed++;
      }
    }
    return removed;
  }

  /// Wipe everything — used on participant withdrawal, and on logout.
  static Future<void> wipeAll() async {
    for (final name in offlineBoxes) {
      final box = await open(name);
      await box.clear();
    }
  }

  /// Destroy the cache key as well. After this, any residue on disk is
  /// unreadable even if the box files survive deletion.
  static Future<void> wipeAllAndDestroyKey() async {
    await wipeAll();
    await _storage.delete(key: _keyName);
    _cipherKey = null;
  }

  /// Only for tests: deterministic key so a test can reopen a box.
  static void debugSetKey(List<int> key) => _cipherKey = key;

  static List<int> debugGenerateKey([int? seed]) {
    final rnd = Random(seed ?? DateTime.now().microsecondsSinceEpoch);
    return List<int>.generate(32, (_) => rnd.nextInt(256));
  }
}
