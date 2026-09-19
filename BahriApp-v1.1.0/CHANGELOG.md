# Changelog

## [1.1.0] — 2026-09-19

Corrects defects found by auditing the v1.0 acquisition code against the v1.0
released corpus, following peer review of the accompanying SoftwareX article
(SOFTX-D-26-00834). Two defects were identified by reviewers; the rest were
found by the audit their comments prompted, and are disclosed here rather than
left for downstream users to discover.

**If you hold v1.0 data, read [MIGRATION.md](MIGRATION.md).**
**If you are assessing this software's security, read [SECURITY.md](SECURITY.md).**

### Retracted

Eighteen of the 165 exported feature columns are invalid as previously
defined. Four can be recomputed from surviving raw fields; fourteen cannot,
because the necessary inputs were never stored. Full list, with reasons, in
[docs/data_dictionary.md](docs/data_dictionary.md).

- **Swipe (10 columns)** — `distance`, `speed`, `acceleration`,
  `deceleration`, `jerk`, `angle`, `areaCoverage`, `fingerOrientation`,
  `movementVariability`, `SN Swipe Time of Day Impact`. The collector assigned
  the drag recogniser's fling velocity (px/s) to fields named `endX`/`endY`
  and then used them as coordinates (px). Median exported "distance" is
  2,524 px on screens with a recovered 892 px diagonal — 2.8 screen diagonals
  per swipe.
- **Tap (2)** — `TapSpeed` (integer division, zero in 99.29 % of records) and
  `Latency` (reduces to a duplicate of `TapDuration`, r = 0.999997). Both are
  recomputable.
- **Gait (4)** — `orientation_pitch`, `orientation_roll`, `orientation_yaw`,
  `jerk`. Not recomputable: the orientation routine indexed a magnitude time
  series as three axis components, giving one constant orientation per session
  across all 489 sessions, and the raw axes were never stored.
- **Gyroscope (2)** — `roll` and `pitch` are retracted *as orientation
  estimates* and renamed `omegaAzimuth` / `omegaElevation`. They remain valid
  as the direction of the instantaneous rotation axis.

### Fixed — acquisition algorithms

- **Gyroscope significance filter** (reviewer R1-9, R2). v1.0 compared the
  single scalar `20` against two angular velocities (rad/s) and one angular
  acceleration (rad/s²) — quantities of two different dimensions. Audit: the
  filter retained 98.53 % of samples, 98.41 % of them by the acceleration term
  alone; only 0.117 % of records exceeded 20 rad/s (= 1146 °/s), against a
  99.9th percentile of 20.6 rad/s. It was close to a no-op. v1.1 gives each
  dimension its own threshold in its own units, with `calibrate()` deriving
  the speed gate from observed data (pilot p70 = 1.63 rad/s = 93 °/s).
  The claim that `20` was "empirically determined" is withdrawn — the original
  source comment read *"Adjust this threshold to control sensitivity"*.
- **Orientation estimators** (R1-10, R2). v1.0 applied gravity-vector tilt
  formulas to angular velocity. v1.1 adds a complementary filter fusing
  gyroscope integration with accelerometer tilt.
- **Δt handling** (R1-11). v1.0 computed Δt from `Duration.inMilliseconds`,
  which truncates, so the smallest representable interval was 1 ms — coarser
  than the realised sampling interval on most devices — and the `> 0` guard
  silently discarded faster samples. v1.1 uses microseconds with an explicit
  admissible window of [0.1 ms, 250 ms]; out-of-window samples are rejected
  **and counted**.
- **Monotonic clock.** All intra-session intervals now use
  `Stopwatch.elapsedMicroseconds`. v1.0 used wall-clock `DateTime.now()`,
  which could step backwards on an NTP correction — the released corpus
  contains hold times down to −1040 ms.
- **Swipe trajectory.** `updateCollecting()` was an empty stub, so no
  intermediate touch points were retained. v1.1 records the full point
  sequence, making path length, curvature and true kinematics computable.
- **Tap features.** Integer division corrected (`1 ~/ duration` → floating
  point); the axis typo in the drift formula fixed (`.dx` was used where `.dy`
  was meant, giving a median 421 px drift with a 102 px floor); within-tap
  drift and targeting error separated into distinct features.
- **Keystroke aggregation.** Pause segmentation at 3,000 ms (v1.0 recorded a
  37-minute gap as one flight time); guarded coefficients of variation
  (v1.0's went negative when the mean did); rates no longer divided by
  `Duration.inSeconds`, which truncated sub-second sessions to a division by
  zero. Three aliased metrics merged. The session vector grows from 11 scalars
  to 28 well-defined statistics.
- **Gait features.** Three-axis orientation from the true gravity vector;
  signed jerk across the full step cycle (v1.0 sampled only the downward
  zero-crossing, so 100 % of values were negative); gravity removed from
  magnitude; the 20-step `_maxDataEntries` cap removed (43.4 % of v1.0
  sessions saturated it).

### Fixed — export integrity

- **Tap timestamp defect.** The v1.0 exporter wrote three epoch columns in
  six-significant-digit scientific notation, collapsing 4,150 genuine game
  rounds into 537 apparent session identifiers and destroying about seven
  orders of magnitude of timestamp resolution. Only `Tap_Data.csv` was
  affected. v1.1 writes epoch columns as quoted strings and **verifies
  distinct-value counts after writing**, failing the export rather than
  distributing a damaged file.
- **Identifier removal.** The `Email` column is removed from the export path
  (6 sites in the dashboard controller, 1 in the Python exporter).

### Fixed — security

The v1.0 claim of end-to-end encryption was inaccurate and is withdrawn.
See [SECURITY.md](SECURITY.md) for the full audit.

- HTTPS enforced; 30 hard-coded plain-HTTP endpoints replaced with
  `AppConfig.endpoint()`, configured at build time. Optional certificate
  pinning.
- All eight offline Hive boxes now opened with `HiveAesCipher` under a
  256-bit key held in the Android Keystore.
- Bearer token attached to all 20 request sites. v1.0 stored the token at
  login and never sent it.
- Idempotency keys plus a server-side unique constraint prevent replayed
  uploads from duplicating sessions.
- Dashboard credentials read from `GOOGLE_APPLICATION_CREDENTIALS` instead of
  a hard-coded absolute developer path.

### Added

- `lib/services/v11/` — corrected extractors, secure cache, API client, auth
  headers.
- `lib/config/app_config.dart` — build-time configuration with a startup
  validity check.
- **30 unit tests** (`test/feature_extractors_v11_test.dart`), each encoding a
  property v1.0 violated, so the suite fails against v1.0 by construction.
- `SessionInstrumentMeta` — per-session device model, screen geometry,
  realised sampling rate and jitter. v1.0 recorded none of this, which is why
  device heterogeneity had to be reconstructed indirectly from the corpus.
- `compositionRole` tag on key events (`base` / `order` / `standalone`) for
  Ge'ez fidel composition.
- `deploy/` — docker-compose stack, PostgreSQL schema, TLS proxy config, so a
  third party can run the backend without author credentials.
- `docs/data_dictionary.md`, `docs/comparison_protocol.md`.
- `analysis/` — the reproducible audit notebook.
- `.env.example`, `SECURITY.md`, `MIGRATION.md`.

### Known limitations

- Android only; no iOS client.
- Four gait columns and all swipe trajectory features are unrecoverable from
  the v1.0 corpus.
- v1.0 handwriting SVG exports carry no per-point timestamps and no viewBox,
  so writing velocity and canvas-relative normalisation cannot be recovered.
  v1.1 adds both.
- The pilot had no non-gamified control arm, so its retention figures cannot
  establish that gamification reduced attrition.

---

## [1.0.0] — 2025

Initial release. Used to collect the pilot corpus (454 enrolled, 265
contributing, 341,606 records, 1 January – 7 May 2025). See the retractions
above before using data collected with this version.
