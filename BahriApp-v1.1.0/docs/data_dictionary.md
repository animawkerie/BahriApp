# BahriApp data dictionary

Covers the 165 feature columns exported across the eleven modality datasets.

**Read this first if you are using the v1.0 pilot corpus.** Eighteen columns are
**retracted** — they are invalid as previously defined. They are listed in full
in [§3](#3-retracted-columns-v10-corpus) with the reason and, where one exists, a
corrected definition. The rest of the corpus is unaffected.

| | |
|---|---|
| Applies to | v1.0 exports (the pilot corpus) and v1.1 |
| Retracted columns | 18 of 165 |
| Recomputable from the v1.0 export | 4 |
| Not recomputable (raw inputs never stored) | 14 |

---

## 1. Conventions

Units are named in the column where there is any ambiguity, e.g.
`duration_ms`, `angularSpeed_rad_s`. Columns carried over unchanged from v1.0
keep their original names so existing analysis scripts do not silently break.

Epoch timestamps are **millisecond Unix epoch integers written as quoted
strings**. Do not let a spreadsheet coerce them to floats: 13 significant
digits do not survive that round trip. This is exactly how the v1.0 tap export
was damaged (§4).

## 2. Session identity

| Column | Type | Notes |
|---|---|---|
| `id` | string | Opaque participant identifier. Not reversible to a person. |
| `sessionId` | epoch ms (string) | Minted on device at session start. |
| `startTime` / `endTime` | ISO-8601 | Microsecond precision where the source provides it. |

For **Tap_Data.csv in the v1.0 corpus only**, `sessionId` is unusable — use
`(id, startTime)` as the session key. See §4.

## 3. Retracted columns (v1.0 corpus)

### 3.1 Swipe — 10 columns

The collector assigned the drag recogniser's **fling velocity** (px·s⁻¹) to
fields named `endX` / `endY`, then used them as if they were **coordinates**
(px). Every quantity derived from them mixes the two units. In the released
corpus the median `distance` is 2,524 px on screens whose recovered diagonal is
892 px — 2.8 screen diagonals for a single swipe, which is impossible.

| Column | v1.0 definition | Status |
|---|---|---|
| `distance` | `\|v − p₀\|` | Retracted — px mixed with px/s |
| `speed` | `\|v\| / duration` | Retracted |
| `acceleration` | `speed / duration` | Retracted |
| `deceleration` | identical formula to `acceleration` | Retracted — duplicate, r = 1.000000 |
| `jerk` | `acceleration / duration` | Retracted |
| `angle` | `atan2(v_y − y₀, v_x − x₀)` | Retracted |
| `areaCoverage` | `\|v_x − x₀\| · \|v_y − y₀\| / screenArea` | Retracted |
| `fingerOrientation` | identical formula to `angle` | Retracted — duplicate, r = 1.000000 |
| `movementVariability` | `L1(v − p₀) − L2(v − p₀)` | Retracted |
| `SN Swipe Time of Day Impact` | `timeOfDayImpact / itself` | Retracted — constant 1.0 |

**Still valid in the swipe export**, renamed for accuracy in v1.1:

| v1.0 name | v1.1 name | Unit |
|---|---|---|
| `endX` | `flingVelocityX` | px/s |
| `endY` | `flingVelocityY` | px/s |
| `straightness` | `l2_l1_ratio` | dimensionless, bounded [0.7071, 1] |
| `initialX`, `initialY`, `duration`, `initialPressure` | unchanged | px, px, s, — |

`straightness` is bounded below by 1/√2 by construction, so it cannot express
real curvature; it is kept under an honest name rather than retracted.

**Not recoverable.** True path length, curvature and area need the intermediate
touch points, and `updateCollecting()` was an empty stub in v1.0, so they were
never stored. v1.1 records the full point sequence.

### 3.2 Tap — 2 columns

| Column | v1.0 definition | Status |
|---|---|---|
| `TapSpeed` | `1 ~/ duration` | Retracted — Dart integer division; 99.29 % of values are exactly 0 |
| `Latency` | `calculateTapLatency(release, release)` | Retracted — reduces to `TapDuration`, r = 0.999997 |

**Both are recomputable** from columns that are intact:

```
tapRate_hz        = 1000.0 / TapDuration            # median 14.9 Hz
withinTapDrift_px = hypot(TapFinalGlobalLocationX - TapInitialGlobalLocationX,
                          TapFinalGlobalLocationY - TapInitialGlobalLocationY)
```

`tapDrift` as exported is also wrong — the formula repeated the x term where
the y term was intended, giving a median 421 px with a 102 px floor. The
recomputation above gives a sub-pixel median, which is what within-tap
slippage actually looks like.

### 3.3 Accelerometer gait — 4 columns

| Column | Status |
|---|---|
| `orientation_pitch` | Retracted — **not recomputable** |
| `orientation_roll` | Retracted — **not recomputable** |
| `orientation_yaw` | Retracted — **not recomputable** |
| `jerk` | Retracted — **not recomputable** |

`getOrientation()` indexed `_accelerationData[0..2]` as if those were the x, y,
z components of gravity. `_accelerationData` is a time series of low-pass
filtered **magnitudes**, so those three elements are the first three magnitude
*samples* of the session. The result is exactly one orientation value per
session across all 489 sessions, clustered at pitch ≈ −19.8°, roll ≈ 37.8°,
regardless of whether the participant was walking, jogging or climbing stairs.

The raw three-axis samples were never stored, so this cannot be repaired
retrospectively.

`jerk` was evaluated only at the downward zero-crossing terminating a step, so
100 % of released values are negative — a step-detection artefact, not a
behavioural feature.

Note also that `_maxDataEntries` capped a session at 20 steps; 43.4 % of
sessions saturate the cap, so step counts are censored. The cap is removed in
v1.1.

### 3.4 Gyroscope — 2 columns

| v1.0 column | v1.1 name | Status |
|---|---|---|
| `roll` | `omegaAzimuth` | Retracted **as an orientation**; valid as an axis direction |
| `pitch` | `omegaElevation` | Retracted **as an orientation**; valid as an axis direction |

v1.0 applied gravity-vector tilt formulas to angular *velocity*. The result is
the spherical direction of the instantaneous rotation axis, not the device's
orientation. The columns reproduce exactly as `atan2` of the raw angular
velocities, and 7.2 % of consecutive sample pairs differ by more than 90° at a
median spacing of 4.7 ms — impossible for a hand-held device's physical
orientation.

These are **usable under the corrected interpretation**: they describe how a
participant rotates the device. They are not orientation.

Also note that the exported gyroscope records passed through the v1.0
significance filter, which retained 98.5 % of samples — it was close to a
no-op. Treat the gyroscope stream as essentially unfiltered.

## 4. Export integrity: the tap timestamp defect

`Tap_Data.csv` in the v1.0 release wrote three epoch columns in
six-significant-digit scientific notation (`1.73573E+12`):

- `sessionId`
- `TapPressTime`
- `TapReleaseTime`

This collapsed **4,150 genuine game rounds into 537 apparent session
identifiers** and destroyed roughly seven orders of magnitude of timestamp
resolution (to about 2.8 hours).

**What survived:** every behavioural tap feature (duration, coordinates,
normalised position) and the ISO-8601 `startTime` / `endTime` brackets, which
are intact to microseconds.

**How to recover session identity:**

```python
tap["session_key"] = tap["id"].astype(str) + "|" + tap["startTime"].astype(str)
# -> 4,150 sessions, matching the ISO brackets
```

Only this one file is affected. The other ten exports round-trip exactly.
v1.1 writes all epoch columns as quoted strings and verifies distinct-value
counts after writing.

## 5. Keystroke session vector

v1.0 exported eleven whole-session scalars. Three of them are aliases of one
another:

| Pair | Pearson r |
|---|---|
| `AverageInterkeyTime` vs `AverageSeekTime` | 0.9975 |
| `AverageKeyReleaseDuration` vs `AverageSeekTime` | 0.9999 |
| `KeyPressRate` vs `KeyReleaseRate` | 0.9909 |

`AverageKeyReleaseDuration` is also misnamed: it measures the gap *between*
keys, not a release duration.

Other issues in the v1.0 vector: rates were computed with
`Duration.inSeconds`, which truncates (so sub-second sessions divided by zero);
coefficients of variation were unguarded and went negative when the mean did;
and there was no pause segmentation, so a 37-minute gap was recorded as a
single flight time. Raw `holdTime` ranges from −1040 ms because the wall clock
could step backwards.

v1.1 replaces this with a 28-feature vector on a monotonic clock, with pause
segmentation at 3,000 ms and guarded statistics. See
`lib/services/v11/feature_extractors_v11.dart`.

## 6. Amharic composition tagging

v1.1 adds `compositionRole` to each key event:

| Value | Meaning |
|---|---|
| `base` | A base fidel tap. Inserts the 1st order (ግዕዝ) and opens the order row. |
| `order` | An order-key tap that replaces the base with the composed fidel. |
| `standalone` | Latin, punctuation, digits, control keys. |

A 1st-order fidel costs **one** physical key event; any other order costs
**two**. Hold time is per physical key event and is never summed across the two
taps of a composed fidel. Flight time spans the base→order transition, which is
the order-selection decision and has no analogue in Latin typing.

For the v1.0 corpus the tag is recoverable by matching `keyText` against the
fidel table in `lib/widgets/keyboard/languages_alphabets.dart`.

## 7. Instrument metadata (v1.1 only)

Recorded per session so cross-device comparisons can control for hardware:

| Field | Unit |
|---|---|
| `realisedRateHz` | Hz, measured — not the requested rate |
| `rateJitterP95OverP05` | ratio |
| `samplesSeen`, `samplesKept`, `samplesDtRejected` | count |
| `sensorFullScaleRadS` | rad/s |
| `screenDiagonalPx`, `screenWidthPx`, `screenHeightPx` | logical px |
| `devicePixelRatio` | ratio |
| `deviceModel`, `deviceManufacturer`, `androidRelease` | string |

None of this exists in the v1.0 corpus. Device form factor there must be
recovered indirectly — see `analysis/` §6, which reconstructs screen diagonal
as `distance / "SN Swipe Length"` and validates it against the tap export's
`_targetSizeAre` (r = 0.78 across 224 shared participants).
