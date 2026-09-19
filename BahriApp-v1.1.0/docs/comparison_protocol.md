# Platform comparison: search protocol

Supports Table 2 of the SoftwareX manuscript. Recorded here so the search can
be repeated and the comparison checked, per reviewer comment R1-1.

## Databases and date

Searched **September 2026** across:

- Scopus
- IEEE Xplore
- ACM Digital Library
- Google Scholar

Plus a repository search of GitHub, GitLab and Zenodo using the same terms.

## Query

```
("behavio*ral biometric*" OR "keystroke dynamics" OR "touch dynamics"
 OR "continuous authentication")
AND
("dataset" OR "data collection" OR "acquisition" OR "collection tool" OR "corpus")
```

Publication window: **2015 onwards**.

| Source | Records |
|---|---|
| Scopus | 168 |
| IEEE Xplore | 121 |
| ACM Digital Library | 63 |
| Google Scholar (first 100 screened) | 60 |
| **Total retrieved** | **412** |
| After de-duplication | term-level dedup applied at screening |

## Inclusion criteria

A record was retained only if **all three** held:

1. It contributes a **data-acquisition instrument**, not only a classifier or a
   benchmark result on someone else's corpus.
2. It targets **mobile devices** (smartphone or tablet).
3. It describes its collected modalities in enough detail to populate every
   axis of the comparison table.

## Screening outcome

| Stage | Remaining |
|---|---|
| Retrieved | 412 |
| After title/abstract screening | 34 |
| After full-text screening against criteria 1–3 | 7 |

The most common reason for exclusion at full text was criterion 1: the work
reported a model trained on an existing public corpus and contributed no
acquisition tool.

## Included platforms

| Platform | Reference |
|---|---|
| BrainRun | Papamichail et al., *Data* 4(2):60, 2019 |
| BioGames | Stylios et al., *Inf. Comput. Secur.* 30(2), 2022 |
| BehavePassDB | Stragapede et al., *Pattern Recognit.* 134:109089, 2023 |
| M2auth | Mahfouz et al., *Neural Comput. Appl.* 36(34), 2024 |
| MotionID | Alawami et al., *Pervasive Mob. Comput.* 101:101922, 2024 |
| Shuwandy et al. | *J. Cybersecur. Priv.* 5(2):20, 2025 |
| Cheng et al. | *Mathematics* 14(2):311, 2026 |

## Repository search

GitHub, GitLab and Zenodo, same query terms, filtered to repositories with a
commit in the preceding 24 months. **No additional maintained mobile
behavioural-biometric acquisition tool** was found that met criteria 1–3. Note
this is a weaker search than the database one: repository search is
keyword-only and a tool published without a descriptive README would be missed.

## How table entries were filled

Each cell was taken from the cited publication. Where a capability is simply
not discussed, the cell reads **"n/s"** (not stated) rather than "No" — absence
of a statement is not evidence of absence.

Participant counts are as reported by each set of authors; we did not attempt
to normalise for what counts as a participant (enrolled vs. contributing), so
these are not strictly comparable. BahriApp reports both (454 enrolled / 265
contributing) for exactly that reason.

## Scope of the resulting claim

Within this search, BahriApp is the only platform providing native
non-Latin-script keystroke capture, and the only one combining
handwriting-trajectory acquisition, team-based gamification, offline-first
synchronisation and an administrative dashboard.

**We do not claim:**

- priority over unpublished, non-indexed or non-English work;
- the largest cohort — BrainRun reports 2,218 participants against our 265
  contributors;
- that the comparison axes are exhaustive. They were chosen to reflect what a
  researcher selecting an acquisition tool would need to know, which is a
  judgement call and open to disagreement.
