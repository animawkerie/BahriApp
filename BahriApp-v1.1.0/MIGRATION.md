# Migrating from v1.0 to v1.1

Two audiences:

- **[A. You hold v1.0 data](#a-if-you-hold-v10-data)** — what is still usable.
- **[B. You are deploying the code](#b-if-you-are-deploying-the-code)** — what changed.

---

## A. If you hold v1.0 data

The corpus remains usable. Most of it is unaffected. But eighteen columns are
invalid, and one export file has a timestamp defect you must work around.

### A1. Drop the retracted columns

```python
RETRACTED = {
    "Swipe_Data": ["distance", "speed", "acceleration", "deceleration", "jerk",
                   "angle", "areaCoverage", "fingerOrientation",
                   "movementVariability", "SN Swipe Time of Day Impact"],
    "Tap_Data":   ["TapSpeed", "Latency"],
    "Accelerometer_Data": ["orientation_pitch", "orientation_roll",
                           "orientation_yaw", "jerk"],
    "Gyroscope_Data": ["roll", "pitch"],   # see A4 — usable, but not as orientation
}

df = df.drop(columns=RETRACTED.get(modality, []), errors="ignore")
```

### A2. Recover the tap session key

`Tap_Data.csv` wrote its epoch columns in scientific notation, collapsing
4,150 real rounds into 537 apparent sessions. The ISO brackets survived:

```python
tap["session_key"] = tap["id"].astype(str) + "|" + tap["startTime"].astype(str)
assert tap["session_key"].nunique() == 4150
```

Do **not** use `sessionId`, `TapPressTime` or `TapReleaseTime` from this file
for anything time-resolved. Every other tap feature is intact.

### A3. Recompute the two tap features that can be repaired

```python
import numpy as np
tap["tapRate_hz"] = 1000.0 / tap["TapDuration"].replace(0, np.nan)
tap["withinTapDrift_px"] = np.hypot(
    tap["TapFinalGlobalLocationX"] - tap["TapInitialGlobalLocationX"],
    tap["TapFinalGlobalLocationY"] - tap["TapInitialGlobalLocationY"],
)
```

Median `tapRate_hz` ≈ 14.9 Hz; median corrected drift is sub-pixel, against
the 421 px median the v1.0 formula produced.

### A4. Reinterpret the gyroscope angles

`roll` and `pitch` are **not orientation**. Rename and treat them as the
direction of the instantaneous rotation axis:

```python
gyro = gyro.rename(columns={"roll": "omegaAzimuth", "pitch": "omegaElevation"})
```

Note too that the exported gyroscope stream passed a filter that retained
98.5 % of samples, so treat it as essentially unfiltered.

### A5. Screen device heterogeneity yourself

v1.0 recorded no device metadata. Recover the screen diagonal from the swipe
export, which stores both a raw and a normalised path scalar:

```python
swipe["screen_diagonal_px"] = swipe["distance"] / swipe["SN Swipe Length"]
```

This is valid even though `distance` itself is retracted: the ratio cancels
the unit error. It yields 71 distinct device profiles spanning 611–1468
logical px, and agrees with the tap export's `_targetSizeAre` at r = 0.78
across 224 shared participants.

Screen normalisation reduces but does not remove device dependence — a 6 %
residual persists across screen-diagonal quartiles. Model it; don't assume it
away.

### A6. Screen implausible keystroke records

```python
ks = ks[(ks.holdTime > 0) & (ks.holdTime <= 5000)]
ks = ks[(ks.flightTime >= 0) & (ks.flightTime <= 30000)]
```

The wall-clock bug produced hold times down to −1040 ms, and the absence of
pause segmentation left flight times up to 37 minutes.

### A7. What you cannot recover

| Feature | Why |
|---|---|
| Gait orientation (pitch/roll/yaw) | Raw three-axis samples were never stored |
| Gait jerk | Sampled only at downward zero-crossings |
| Swipe path length, curvature, true kinematics | `updateCollecting()` was an empty stub; intermediate touch points never retained |
| Handwriting velocity, canvas normalisation | SVG export has no per-point timestamps and no viewBox |

Each is fixed in v1.1 going forward, but no post-hoc repair is possible for
data already collected.

---

## B. If you are deploying the code

### B1. Configure the endpoint

v1.0 hard-coded `http://15.184.243.127:8080` in 30 places. That is gone.

```bash
cp .env.example .env     # edit; never commit the filled-in file
```

Build with the endpoint as a define:

```bash
flutter build apk --release \
  --dart-define=BAHRI_API_BASE=https://api.example.org \
  --dart-define=BAHRI_CERT_PIN_SHA256=<base64 pin>
```

`AppConfig.assertValid()` throws at startup if you point a release build at a
plain-HTTP host. For local development, and only there:

```bash
--dart-define=BAHRI_ALLOW_INSECURE=true
```

### B2. Add the dependency

`pubspec.yaml` gains `crypto: ^3.0.3` (certificate pinning, idempotency keys):

```bash
flutter pub get
```

### B3. Existing Hive caches will not open

v1.1 opens every offline box with `HiveAesCipher`. An unencrypted v1.0 cache
on an upgrading device **cannot be read** by v1.1.

The cache is a transient upload queue, not a store of record, so the simplest
correct path is to drain it before upgrading:

1. Ship v1.0 one last time, let devices sync on connectivity.
2. Then upgrade.

If you cannot, delete the boxes on first v1.1 run and accept the loss of any
unsynced queue. There is no migration path that preserves an unencrypted cache
into an encrypted one without first reading it in the clear, which defeats the
purpose.

### B4. Run the tests

```bash
flutter test test/feature_extractors_v11_test.dart
```

30 tests across 5 groups. Each encodes a property v1.0 violated, so the suite
fails against v1.0 by construction — that is how you confirm the merge worked.

### B5. Backend

`deploy/schema.sql` adds a unique constraint on
`(participant_id, session_id, modality)` and an `idempotency_key` index. The
client sends `Idempotency-Key` on every upload; your ingestion service must
honour it — return the existing receipt rather than inserting a duplicate.

`session_id` is `TEXT`, deliberately. Storing a 13-digit epoch as a numeric
type is what damaged the v1.0 tap export.

### B6. Dashboard credentials

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/service-account.json
```

The dashboard now shows a configuration error instead of crashing on a
missing hard-coded path.

### B7. Verify the export fix

`export_data.py` re-reads each file it writes and compares distinct-value
counts per epoch column, raising `RuntimeError` on a mismatch. A failed export
is better than a silently damaged one — the v1.0 tap defect was invisible
until someone counted sessions.
