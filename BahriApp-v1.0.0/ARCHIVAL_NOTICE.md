# ARCHIVAL NOTICE — read before using this software or its data

**This is BahriApp v1.0.0, archived unmodified.**

It is the version that collected the pilot corpus described in the
accompanying SoftwareX article (454 enrolled participants, 265 contributing,
341,606 records, 1 January – 7 May 2025).

**It contains known defects.** They were found by auditing this code against
the data it produced, after peer review. Nothing in this archive has been
corrected, because correcting it would destroy the record of what actually
collected the data. **Use v1.1.0 for new data collection.**

| | |
|---|---|
| Superseded by | **v1.1.0** — <https://doi.org/10.5281/zenodo.XXXXXXX> |
| Full defect analysis | `CHANGELOG.md` and `docs/data_dictionary.md` in v1.1.0 |
| Security disclosure | `SECURITY.md` in v1.1.0 |
| Reproducible audit | `analysis/` in v1.1.0 |

---

## Why this version is archived at all

Three reasons, all of which require the code to be exactly as it ran:

1. **The pilot corpus was collected with it.** Anyone analysing that data
   needs to see the code that produced it, defects included. The defects are
   not incidental to the data — several of them determine what the exported
   columns actually mean.
2. **Reproducibility.** The SoftwareX article reports measurements taken *on
   this code*. Those numbers cannot be checked against a corrected version.
3. **The audit itself is a contribution.** The v1.1 corrections are only
   interpretable against the original.

## Two corrections to this repository's own documentation

The files in this archive are unmodified, which means **`README.md` still
contains two claims that are now known to be false.** They are corrected here
rather than in the file, so the archive stays faithful.

### 1. "End-to-end encryption" — withdrawn in full

`README.md` claims data is "encrypted at rest, in transit, and at the edge."
A source-level audit established this was **not implemented in any sense**:

| Aspect | What this code actually does |
|---|---|
| Transport | All 24 endpoints use plain HTTP to a hard-coded IPv4 address (`http://15.184.243.127:8080/...`). No TLS. |
| On-device cache | All eight offline Hive boxes opened with no `encryptionCipher`. Cached sessions stored as plaintext. |
| Authentication | `authToken` written to secure storage at login, then never attached to any upload. Collection endpoints accepted anonymous writes. |
| Key custody | No key generation, storage or rotation of any kind. |

**Implication for the pilot corpus:** data travelled unencrypted over the
network and sat unencrypted on participant devices until upload. Because
uploads were unauthenticated, records cannot be cryptographically attributed —
a participant id is asserted by the client, not verified by the server. No
evidence of interception or tampering has been found; that is not the same as
evidence of absence, and we do not claim it is.

### 2. The documented architecture is not the deployed architecture

`README.md` describes a Firestore-centred design. In this code the Firebase
dependencies are **commented out** in `pubspec.yaml`, and the client posts to
a Dart Frog service on AWS EC2. Only the admin dashboard uses Firestore.

## Defects affecting how the exported data must be read

Eighteen of the 165 exported feature columns are invalid as defined. Four can
be recomputed from surviving raw fields; **fourteen cannot**, because the
necessary inputs were never stored.

| Area | Defect | Consequence for the data |
|---|---|---|
| **Swipe** (10 columns) | Fling velocity (px/s) assigned to fields named `endX`/`endY`, then used as coordinates (px) | Median "distance" is 2,524 px on screens with a recovered 892 px diagonal — 2.8 screen diagonals per swipe. `updateCollecting()` is an empty stub, so no trajectory was ever retained. |
| **Tap** (2) | `TapSpeed` uses Dart integer division (`1 ~/ duration`) | Exactly 0 in 99.29 % of records. `Latency` reduces to a duplicate of `TapDuration` (r = 0.999997). Both are recomputable. |
| **Tap** | Drift formula repeats the x term where y was intended | Median 421 px with a 102 px floor — impossible for a stationary press. Recomputable from stored coordinates. |
| **Gait** (4) | `getOrientation()` indexes a magnitude time series as three axis components | Exactly one orientation value per session across all 489 sessions (pitch ≈ −19.8°, roll ≈ 37.8°) regardless of activity. **Not recomputable** — raw axes never stored. `jerk` is 100 % negative, a step-detection artefact. |
| **Gait** | `_maxDataEntries` caps a session at 20 steps | 43.4 % of sessions saturate the cap. Step counts are censored, not measured. |
| **Gyroscope** (2) | Gravity-vector tilt formulas applied to angular velocity | `roll`/`pitch` are not orientation. They are the direction of the instantaneous rotation axis — valid under that reading, invalid as orientation. |
| **Gyroscope** | Significance filter compares the scalar `20` against two angular velocities (rad/s) and one angular acceleration (rad/s²) | Retained 98.53 % of samples, 98.41 % by the acceleration term alone. Treat the stream as essentially unfiltered. |
| **Keystroke** | Wall-clock `DateTime.now()`; no pause segmentation; `Duration.inSeconds` division | Hold times down to −1040 ms; a 37-minute gap recorded as one flight time; sub-second sessions divided by zero. Three session metrics are aliases (pairwise r ≥ 0.9975). |
| **Export** | Tap CSV wrote epoch columns in six-significant-digit scientific notation | 4,150 genuine game rounds collapsed into 537 apparent session identifiers. Recover with `(id, startTime)`. Only this one file is affected. |

**Before analysing the pilot corpus, read `docs/data_dictionary.md` in
v1.1.0.** It lists every retracted column with its reason and, where one
exists, a corrected definition.

## Integrity of this archive

`MANIFEST.sha256` lists SHA-256 checksums for all 469 original source files.
The three files added for archival purposes — this notice, `MANIFEST.sha256`,
`.zenodo.json` and `CITATION.cff` — are listed separately at the end of the
manifest and are the only additions. **No original file was modified.**

Verify with:

```bash
sha256sum -c MANIFEST.sha256
```

## Citing this version

Cite **the version you actually used**. If you analysed the pilot corpus, that
is v1.0.0, and this DOI:

```bibtex
@software{aseres_bahriapp_v1_0_0,
  author  = {Aseres, Animaw Kerie and Beyene, Asrat Mulatu
             and Tegegne, Lemlem Kassa},
  title   = {BahriApp: An Android Platform for Gamified Multimodal
             Behavioural-Biometric Data Acquisition, v1.0.0},
  version = {1.0.0},
  year    = {2025},
  note    = {Version used to collect the pilot corpus. Superseded by v1.1.0;
             see ARCHIVAL_NOTICE.md for known defects.},
  doi     = {10.5281/zenodo.XXXXXXX},
  url     = {https://doi.org/10.5281/zenodo.XXXXXXX}
}
```

## Licence

MIT, unchanged. See `LICENSE`.

## Contact

animaw.kerie@kue.edu.et
