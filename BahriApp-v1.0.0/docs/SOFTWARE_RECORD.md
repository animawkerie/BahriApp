# BahriApp — software record

Authoritative provenance document for the BahriApp software archive. Covers
both archived versions: what each is, what each produced, how they differ, and
which one any given claim or dataset belongs to.

Included in both version archives so that either one, downloaded alone, tells
the whole story.

| | |
|---|---|
| Software | BahriApp — multimodal behavioural-biometric acquisition platform |
| Archived versions | v1.0.0, v1.1.0 |
| Licence | MIT (both) |
| Concept DOI | `10.5281/zenodo.XXXXXXX` |
| Article | SoftwareX, `10.1016/j.softx.XXXX.XXXXXX` |
| Dataset | `10.5281/zenodo.XXXXXXX` |
| Contact | animaw.kerie@kue.edu.et |

---

## 1. Which version do I want?

| If you are… | Use | DOI |
|---|---|---|
| Collecting new data | **v1.1.0** | version DOI |
| Analysing the pilot corpus | **v1.0.0** — the code that produced it | version DOI |
| Reproducing the article's measurements | **v1.0.0** for corpus figures, **v1.1.0** for the correction figures | both |
| Citing the project generally | concept DOI | resolves to latest |
| Reviewing the audit | **v1.1.0** → `analysis/`, `CHANGELOG.md` | version DOI |

**The most common mistake to avoid:** taking v1.1.0 and assuming it produced
the pilot corpus. It did not. Eighteen exported columns mean something
different — or nothing — in data collected with v1.0.0.

## 2. Timeline

```
2025-01-01 ─┐
            │  Pilot data collection, v1.0.0
            │  454 enrolled · 265 contributing · 341,606 records
2025-05-07 ─┘

2026        ── SoftwareX submission SOFTX-D-26-00834
            ── Peer review: two algorithmic defects identified
            ── Audit of v1.0.0 against the corpus it produced
            ── 13 further defects found, disclosed
2026-09-19  ── v1.1.0 released; both versions archived
```

## 3. What is common to both versions

Unchanged between v1.0.0 and v1.1.0:

- **Eleven modalities** in one application: fixed-text, free-text and password
  keystroke dynamics in English and Amharic; swipe; tap; handwriting
  trajectories in two scripts; accelerometer gait; gyroscopic tilt.
- **Native Amharic keystroke capture.** The system keyboard is suppressed and
  the application renders its own two-tier fidel keyboard, so every logged
  event is a physical touch on a key the app drew. No transliteration IME, no
  candidate list, no OS composition. A first-order fidel costs one key event;
  any other order costs two.
- **Gamified elicitation** across six game categories, with individual and
  team leaderboards.
- **Offline-first synchronisation** via an on-device Hive queue.
- **Bahri Panel** desktop dashboard with CSV export.
- **Flutter/Dart** client targeting Android 8.0 (API 26) and above.
- **MIT licence.**

## 4. Version 1.0.0

### 4.1 Role

The version that collected the pilot corpus. Archived **unmodified**; see
`ARCHIVAL_NOTICE.md` in that archive for why, and for the integrity manifest
covering all 469 original files.

### 4.2 What it produced

| | |
|---|---|
| Acquisition window | 1 January – 7 May 2025 (125 days) |
| Enrolled participants | 454 |
| Contributing participants | 265 (58.4 %) |
| Records | 341,606 |
| Sessions | 23,106 |
| Keystroke session vectors | 4,721 |
| Exported feature columns | 165 |
| Sites | Three Ethiopian higher-education institutions, BYOD |

Per-modality yield is in the article's Table 3 and in `analysis/` §3.

### 4.3 Known defects

Fifteen classes, found by auditing this code against its own output. Two were
identified by reviewers; the rest by the audit their comments prompted.

| # | Component | Defect | Data consequence |
|---|---|---|---|
| 1 | Gyroscope filter | Scalar `20` compared against two angular velocities (rad/s) and one angular acceleration (rad/s²) | Retained 98.53 % of samples, 98.41 % by the acceleration term alone. Stream is effectively unfiltered. |
| 2 | Gyroscope orientation | Gravity-vector tilt formulas applied to angular velocity | `roll`/`pitch` are not orientation. Valid only as rotation-axis direction. |
| 3 | Δt computation | `Duration.inMilliseconds` truncates; `> 0` guard then drops faster samples | Sub-millisecond events silently discarded, uncounted. |
| 4 | Clock | Wall-clock `DateTime.now()` | Hold times to −1040 ms; negative flight times. |
| 5 | Swipe collector | `updateCollecting()` an empty stub | No trajectory retained; path features uncomputable. |
| 6 | Swipe features | Fling velocity (px/s) assigned to `endX`/`endY`, used as coordinates (px) | 9 columns mix units. Median "distance" = 2.8 screen diagonals. |
| 7 | Swipe features | `fingerOrientation` duplicates `angle`; `deceleration` duplicates `acceleration`; time-of-day impact constant | r = 1.000000; one column has a single value. |
| 8 | Tap rate | `1 ~/ duration` — integer division | Exactly 0 in 99.29 % of records. |
| 9 | Tap drift | x term repeated where y intended | Median 421 px, floor 102 px. |
| 10 | Tap latency | Release time passed as screen-response time | Duplicates duration, r = 0.999997. |
| 11 | Keystroke rates | Division by `Duration.inSeconds` | Sub-second sessions divide by zero. |
| 12 | Keystroke aggregation | No pause segmentation; unguarded CV; three aliased metrics | 37-min gap as one flight time; negative CVs; pairwise r ≥ 0.9975. |
| 13 | Gait orientation | Magnitude series indexed as three axis components | One constant orientation per session, all 489 sessions. |
| 14 | Gait jerk / cap | Jerk sampled only at downward zero-crossings; 20-step cap | 100 % negative; 43.4 % of sessions censored. |
| 15 | Tap export | Epoch columns written in scientific notation | 4,150 rounds → 537 apparent sessions. |

### 4.4 Retracted columns

Eighteen of 165. Four recomputable, fourteen not.

| Modality | Count | Recomputable? |
|---|---|---|
| Swipe | 10 | No — trajectory never stored |
| Tap | 2 | **Yes** — from stored coordinates and duration |
| Gait | 4 | No — raw axes never stored |
| Gyroscope | 2 | Reinterpretable, not orientation |

Full list with reasons and corrected definitions: `docs/data_dictionary.md`
in v1.1.0.

### 4.5 Security posture

**No encryption of any kind was implemented.** The v1.0 README's claim of
end-to-end encryption is withdrawn in full.

| Aspect | v1.0.0 |
|---|---|
| Transport | Plain HTTP to a hard-coded IPv4 address, 24 endpoints |
| On-device cache | Eight Hive boxes, no `encryptionCipher` |
| Authentication | Token stored at login, never attached to uploads |
| Key custody | None |
| Export | Included an `Email` column |
| Credentials | Absolute developer path |

**Implication for the corpus:** data travelled unencrypted and sat unencrypted
on devices until upload. Because uploads were unauthenticated, records cannot
be cryptographically attributed. No evidence of interception has been found;
that is not evidence of absence.

Participants consented to behavioural collection, minimal demographics, and
publication of a de-identified corpus, and consent materials stated that
behavioural biometrics can act as persistent identifiers.

## 5. Version 1.1.0

### 5.1 Role

Current. Use for new data collection. Corrects all fifteen defect classes.

### 5.2 Corrections

| Area | v1.0.0 | v1.1.0 |
|---|---|---|
| Gyroscope gate | One scalar, three quantities, two dimensions | Per-dimension thresholds; `calibrate()` derives the speed gate from observed data (pilot p70 = 1.63 rad/s = 93 °/s) |
| Orientation | atan2 of angular velocity | Complementary filter fusing gyroscope + accelerometer; honest `omegaDirection()` retained separately |
| Clock | Wall clock, ms | Monotonic, µs |
| Δt | Truncated, unguarded | Explicit window [0.1 ms, 250 ms]; rejects **and counts** |
| Swipe | Two points | Full trajectory; dimensionally consistent kinematics |
| Tap | Integer division, axis typo | Float rate; `.dy` fixed; drift and targeting error separated |
| Keystroke | 11 scalars, unguarded | 28 statistics, pause segmentation at 3 s, guarded CV |
| Gait | Magnitudes as axes; signed jerk; 20-step cap | Three-axis orientation; signed jerk over the full cycle; cap removed |
| Export | Floats | Quoted strings + post-write verification |
| Instrument metadata | None | Device model, screen geometry, realised rate, jitter, rejection counts |

### 5.3 Security

| Control | Implementation |
|---|---|
| Transport | HTTPS enforced at startup; optional SHA-256 certificate pinning |
| Cache | `HiveAesCipher`, 256-bit key in the Android Keystore, purged on ack |
| Authentication | Bearer token on every request; refresh rotation |
| Replay | `Idempotency-Key` + server-side unique constraint |
| Export | Identifier columns removed; role-gated; append-only audit log |
| Withdrawal | `withdraw_participant()` cascades across behavioural tables |

An eight-threat model is in `SECURITY.md`. **De-identification is partial, not
absolute** — behavioural biometrics are themselves persistent identifiers.

### 5.4 Verification shipped with the release

| Artefact | What it checks |
|---|---|
| `test/feature_extractors_v11_test.dart` | 30 unit tests, 5 groups. Each encodes a property v1.0 violated, so the suite fails against v1.0 by construction. |
| `analysis/verify_extractor_logic.py` | Same 30 assertions in Python — runs without a Flutter toolchain. |
| `tools/audit_v10_defects.sh` | 15 defect-class sweep; all report CLEAR. |
| `analysis/…​.ipynb` | Regenerates 31 result tables and 8 figures from the released corpus. |

### 5.5 Known limitations

- Android only.
- The v1.0 corpus cannot be retrospectively repaired for the fourteen
  non-recomputable columns.
- The pilot had no non-gamified control arm, so its retention figures cannot
  establish that gamification reduced attrition.
- v1.1.0's Dart sources were not compiled at package-build time (no toolchain
  available); the arithmetic was verified in Python instead. Run
  `flutter analyze` and `flutter test` before deployment.
- `pubspec.lock` is not in the archive — the v1.0 `.gitignore` had a blanket
  `*.lock` rule. Generate with `flutter pub get` and commit.

## 6. Relationship to the publications

| Output | Describes | Cite |
|---|---|---|
| SoftwareX article | The **tool**, at v1.1.0, with pilot figures from v1.0.0 data | article DOI |
| Companion dataset publication | The **corpus**, collected with v1.0.0 | dataset DOI |
| This software record | Both versions | concept DOI |

The 578-feature registry referred to in the initial submission is a downstream
feature-engineering product belonging to the dataset publication, not to the
acquisition tool. The tool exports 165 columns. The article's §2.2 reconciles
the counts.

## 7. Reproducing the article's numbers

1. Obtain the pilot corpus (dataset DOI).
2. Place the eleven CSVs in `analysis/data/`.
3. Run the notebook from **v1.1.0** — it audits v1.0.0 output and needs the
   corrected reference implementations to compute the "after" figures.
4. Expect: `RAN 30 | failures 0 | errors 0` from the logic verifier, and
   `headline_numbers.json` matching the article.

Key figures for a quick check:

| Quantity | Value |
|---|---|
| Contributing / enrolled | 265 / 454 = 58.4 % |
| Acquisition span | 125 days |
| Records | 341,606 |
| Gyro records retained by the v1.0 filter | 98.53 % |
| …by the acceleration term alone | 98.41 % |
| Records exceeding the 20 rad/s gate | 0.117 % |
| Cross-modal session overlap | 0.61 % |
| Amharic / English key events per rendered char | 1.44 / 0.94 |
| Recovered device profiles | 71, spanning 611–1468 logical px |

## 8. Archive contents

### v1.0.0

```
BahriApp-v1.0.0/
├── ARCHIVAL_NOTICE.md     ← read first
├── MANIFEST.sha256        ← 469 original files + 4 additions
├── CITATION.cff
├── .zenodo.json
├── docs/SOFTWARE_RECORD.md
├── tools/fill_dois.py
└── [469 original source files, unmodified]
```

### v1.1.0

```
BahriApp-v1.1.0/
├── README.md · CHANGELOG.md · MIGRATION.md · SECURITY.md · DEPLOY.md
├── CITATION.cff · .zenodo.json · .env.example
├── lib/
│   ├── config/app_config.dart
│   └── services/v11/        ← corrected extractors + security layer
├── test/feature_extractors_v11_test.dart   ← 30 tests
├── docs/    data_dictionary · comparison_protocol · ZENODO_ARCHIVE · SOFTWARE_RECORD
├── analysis/    notebook · figures · logic verifier
├── deploy/      docker-compose · schema.sql · nginx.conf
├── example_data/   synthetic CSVs + generator
└── tools/       audit_v10_defects.sh · fill_dois.py
```

## 9. Citing

Cite the **version you used**.

```bibtex
@software{aseres_bahriapp_v1_1_0,
  author  = {Aseres, Animaw Kerie and Beyene, Asrat Mulatu
             and Tegegne, Lemlem Kassa},
  title   = {BahriApp: An Android Platform for Gamified Multimodal
             Behavioural-Biometric Data Acquisition, v1.1.0},
  version = {1.1.0}, year = {2026},
  doi     = {10.5281/zenodo.XXXXXXX}
}

@software{aseres_bahriapp_v1_0_0,
  author  = {Aseres, Animaw Kerie and Beyene, Asrat Mulatu
             and Tegegne, Lemlem Kassa},
  title   = {BahriApp: An Android Platform for Gamified Multimodal
             Behavioural-Biometric Data Acquisition, v1.0.0},
  version = {1.0.0}, year = {2025},
  note    = {Version used to collect the pilot corpus},
  doi     = {10.5281/zenodo.XXXXXXX}
}
```

Machine-readable equivalents are in each archive's `CITATION.cff`.
