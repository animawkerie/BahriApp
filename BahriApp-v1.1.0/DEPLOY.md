# Deploying BahriApp v1.1.0

Start to finish. Roughly 30 minutes with a Flutter toolchain already installed.

## 0. Before anything

**Two things this package cannot do for you:**

1. **`pubspec.lock` is not included.** The v1.0 `.gitignore` had a blanket
   `*.lock` rule, so it was never committed. Run `flutter pub get` (step 2)
   to generate it, then **commit it** — the manuscript states that transitive
   versions are pinned there, and that must be true before you resubmit.

2. **No Dart toolchain was available when this package was built**, so the
   Dart sources were not compiled and `flutter test` was not run. The
   arithmetic of every corrected extractor *was* verified — `analysis/
   verify_extractor_logic.py` runs the same 30 assertions in Python and all
   pass — but you must run `flutter analyze` and `flutter test` yourself
   (step 3) before shipping. Expect to fix import paths if your package name
   is not `bahri_app`.

## 1. Configure

```bash
cp .env.example .env
$EDITOR .env
```

At minimum set `BAHRI_API_BASE` (must be `https://`) and, for the dashboard,
`GOOGLE_APPLICATION_CREDENTIALS`.

## 2. Install dependencies

```bash
flutter pub get          # generates pubspec.lock — commit it
```

v1.1 adds one dependency: `crypto: ^3.0.3`, used for certificate pinning and
idempotency keys.

## 3. Verify

```bash
flutter analyze
flutter test test/feature_extractors_v11_test.dart      # 30 tests, 5 groups
bash tools/audit_v10_defects.sh                          # 15 checks, all CLEAR
python3 analysis/verify_extractor_logic.py               # 30 assertions
```

The unit tests fail against v1.0 by construction — each encodes a property the
old code violated. That is how you confirm the merge actually took effect.

## 4. Backend

Either point `BAHRI_API_BASE` at your existing Dart Frog service, or bring up
the local stack:

```bash
cd deploy
mkdir -p certs
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout certs/server.key -out certs/server.crt -days 365 -subj "/CN=localhost"
docker compose --env-file ../.env up -d
cd ..
```

Apply `deploy/schema.sql` to your production database if you are not using the
compose stack. It adds the unique constraint that makes retried uploads
idempotent, and keeps identifiers in a table the export path never joins.

## 5. Build

```bash
# Debug, against the local stack (10.0.2.2 is the host from an emulator)
flutter run -d <device> --dart-define=BAHRI_API_BASE=https://10.0.2.2:8443

# Release
flutter build apk --release \
  --dart-define=BAHRI_API_BASE=https://api.example.org \
  --dart-define=BAHRI_CERT_PIN_SHA256=$(openssl s_client -connect api.example.org:443 \
      </dev/null 2>/dev/null | openssl x509 -outform DER \
      | openssl dgst -sha256 -binary | base64)
```

`AppConfig.assertValid()` throws at startup if a release build points at a
plain-HTTP host. That is deliberate: it is the check whose absence made the
v1.0 encryption claim untrue.

## 6. Upgrading devices that already ran v1.0

v1.1 opens every Hive box encrypted, so an existing **unencrypted v1.0 cache
cannot be read**. The cache is a transient upload queue, not a store of
record, so drain it first:

1. Ship v1.0 once more and let devices sync.
2. Then roll out v1.1.

If that is not possible, delete the boxes on first v1.1 run and accept the
loss of any unsynced queue. There is no migration that preserves an
unencrypted cache into an encrypted one without first reading it in the clear.

See [MIGRATION.md](MIGRATION.md) for the data-side migration.

## 7. Before collecting real data

Work through the checklist in [SECURITY.md](SECURITY.md#deployment-checklist).
The items that are most often missed:

- `BAHRI_JWT_SECRET` still set to the template value
- database encryption at rest not enabled by the hosting provider
- no tested withdrawal procedure

## What is in this package

| Path | Contents |
|---|---|
| `lib/services/v11/` | Corrected extractors, encrypted cache, API client, auth headers |
| `lib/config/app_config.dart` | Build-time configuration with a startup validity check |
| `lib/services/*.dart` | v1.0 services, patched in place — 15 defect classes closed |
| `test/feature_extractors_v11_test.dart` | 30 unit tests |
| `deploy/` | docker-compose, PostgreSQL schema, TLS proxy |
| `docs/` | Data dictionary (incl. the 18 retracted columns), comparison protocol |
| `analysis/` | Audit notebook, figures, logic verifier |
| `example_data/` | Synthetic sample data + generator |
| `tools/audit_v10_defects.sh` | Repeatable defect sweep |
| `CHANGELOG.md` · `MIGRATION.md` · `SECURITY.md` | Release notes, migration, security disclosure |
