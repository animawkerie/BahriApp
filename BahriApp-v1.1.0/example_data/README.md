# Example data

**These files are synthetic. They contain no human subject's behaviour.**

They exist so a third party can exercise the dashboard, the export path and
the analysis notebook without access to the pilot corpus, which holds real
participants' behavioural data and is distributed separately under its own
data-use conditions.

Do not use these files to evaluate recognition accuracy, and do not cite any
number computed from them.

## Regenerating

```bash
python example_data/generate_example_data.py
```

Seeded (`random.seed(20260919)`), so output is reproducible.

## What they demonstrate

Beyond being runnable input, the generator demonstrates the **v1.1 export
contract**: epoch columns are written as quoted strings and the round trip is
verified before the file is accepted.

```
  Tap_Data.csv: 498 rows, epoch round-trip verified
```

That check is the one that would have caught the v1.0 tap defect, where epoch
columns were written in six-significant-digit scientific notation
(`1.73573E+12`) and 4,150 genuine game rounds collapsed into 537 apparent
sessions. Compare:

| | v1.0 tap export | These files |
|---|---|---|
| `sessionId` format | `1.73573E+12` | `1740910895580` |
| Significant digits | 6 | 13 |
| Distinct `TapPressTime` values | 1 per session | 497 of 498 rows |

## Schema

The columns match the v1.1 export schema, including fields that do not exist
in the v1.0 corpus:

- `compositionRole` on keystroke events (`base` / `order` / `standalone`)
- `flingVelocityX` / `flingVelocityY` on swipes, correctly named — v1.0 stored
  these as `endX` / `endY` and then used them as coordinates
- `pathLength_px`, `straightnessIndex` from a real trajectory
- `omegaAzimuth` / `omegaElevation` on gyroscope records, replacing v1.0's
  `roll` / `pitch`, which were retracted as orientation estimates

The Amharic keystroke file includes composed fidels at roughly the rate
observed in the pilot corpus (~40 % of text-key events are order forms), so
the two-tap composition model is visible in the data.

See [`docs/data_dictionary.md`](../docs/data_dictionary.md) for full field
definitions.
