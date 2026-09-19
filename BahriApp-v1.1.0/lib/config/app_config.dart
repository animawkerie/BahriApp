// BahriApp v1.1 — build-time configuration.
//
// v1.0 DEFECT (R1-6, R1-16)
//   Every one of the 24 collection and authentication endpoints hard-coded a
//   plain-HTTP IPv4 address:
//       http://15.184.243.127:8080/...
//   That is not configurable, not reproducible for a third party, and carries
//   no transport security. The admin dashboard separately read a Google
//   service-account JSON from an absolute developer path
//   (E:/PhD Cyber/...), so nobody but the original developer could run it.
//
// v1.1 takes the host from a compile-time environment variable, so a third
// party can point the client at their own backend without editing source:
//
//   flutter run --dart-define=BAHRI_API_BASE=https://api.example.org
//   flutter build apk --dart-define-from-file=env.json
//
// See .env.example and deploy/docker-compose.yml for a working local stack.

class AppConfig {
  /// Base URL of the ingestion service. HTTPS is required in release builds;
  /// see [assertValid]. Override at build time with --dart-define.
  static const String apiBase = String.fromEnvironment(
    'BAHRI_API_BASE',
    defaultValue: 'https://localhost:8443',
  );

  /// SHA-256 pin of the server leaf certificate's public key, base64.
  /// Empty disables pinning (acceptable for a local development stack only).
  static const String certPinSha256 = String.fromEnvironment(
    'BAHRI_CERT_PIN_SHA256',
    defaultValue: '',
  );

  /// Set true only for a local development backend without TLS.
  static const bool allowInsecureTransport = bool.fromEnvironment(
    'BAHRI_ALLOW_INSECURE',
    defaultValue: false,
  );

  /// Request timeout for a single upload attempt.
  static const Duration requestTimeout = Duration(seconds: 30);

  /// Maximum sessions per batch upload from the offline queue.
  static const int syncBatchSize = 50;

  static const String appVersion = '1.1.0';

  /// Call once at startup. Fails fast rather than silently shipping data in
  /// the clear — the specific failure mode that made the v1.0 "end-to-end
  /// encryption" claim untrue.
  static void assertValid() {
    final isHttps = apiBase.startsWith('https://');
    if (!isHttps && !allowInsecureTransport) {
      throw StateError(
        'BAHRI_API_BASE must use https:// (got "$apiBase"). '
        'For a local development backend, build with '
        '--dart-define=BAHRI_ALLOW_INSECURE=true.',
      );
    }
    if (apiBase.endsWith('/')) {
      throw StateError('BAHRI_API_BASE must not end with a trailing slash.');
    }
  }

  static Uri endpoint(String path) =>
      Uri.parse('$apiBase${path.startsWith('/') ? path : '/$path'}');
}
