# Zenodo archival — both versions

Complete documentation of the BahriApp software record: what is archived, why
two versions exist, how they relate, and how to deposit them.

**This addresses reviewer comment R1-15**, which noted that the manuscript's
repository link pointed at a live GitHub repository rather than an archived
version corresponding to the article. A live repository can change after
publication; a Zenodo DOI cannot.

---

## 1. What is being archived

Two software versions, as separate records under one shared concept DOI.

| | v1.0.0 | v1.1.0 |
|---|---|---|
| Role | Collected the pilot corpus | Current; use for new collection |
| Source | **Unmodified** | Corrected |
| Collected data | 454 enrolled / 265 contributing, 341,606 records, Jan–May 2025 | none yet |
| Known defects | 15 classes, documented | none known |
| Retracted columns | 18 of 165 | — |
| Unit tests | 0 | 30 |
| Security | No encryption of any kind | TLS + pinning, AES-256 cache, bearer auth |

**Both must be archived.** Archiving only v1.1 would leave the pilot corpus
without the code that produced it, and would make the measurements reported in
the article uncheckable. Archiving only v1.0 would leave the corrections
undistributed.

## 2. Why v1.0 is archived unmodified

This is a deliberate decision, and it has a cost worth stating plainly.

`README.md` in v1.0 contains two claims now known to be false: that the
platform used end-to-end encryption, and that its architecture was
Firestore-centred. Archiving it unmodified means **those false claims become
part of a permanent, citable public record.**

We archive it unmodified anyway, because:

1. **The corpus needs its code.** Several defects determine what the exported
   columns actually mean. An analyst who reads corrected code will
   misunderstand data produced by uncorrected code.
2. **The article's measurements were taken on this code.** They cannot be
   reproduced against a modified version.
3. **Silently correcting an archived artefact is itself a research-integrity
   problem.** It would make the record disagree with what was deployed, with
   no way for a reader to tell.

The corrections are therefore delivered **alongside** the source rather than
inside it:

- `ARCHIVAL_NOTICE.md` at the archive root — states both false claims, lists
  every defect, and points to v1.1.
- The Zenodo record's own description repeats the withdrawal, so it is visible
  on the landing page before anyone downloads anything.
- `MANIFEST.sha256` lists SHA-256 checksums for all 469 original files, so a
  reader can verify nothing was altered.

Only four files are added to the v1.0 archive: `ARCHIVAL_NOTICE.md`,
`MANIFEST.sha256`, `.zenodo.json`, `CITATION.cff`. They are listed separately
at the end of the manifest.

> **If you would rather patch the v1.0 README before depositing**, that is a
> defensible alternative — but then say so in `ARCHIVAL_NOTICE.md` and drop
> the "unmodified" claim from the Zenodo description and the manifest header,
> because both would no longer be true.

## 3. DOI structure

Zenodo issues two kinds of DOI. Use them for different purposes.

```
Concept DOI  10.5281/zenodo.AAAAAAA   ← always resolves to the latest version
  │
  ├── Version DOI  10.5281/zenodo.BBBBBBB   v1.0.0
  └── Version DOI  10.5281/zenodo.CCCCCCC   v1.1.0
```

| Where | Which DOI | Why |
|---|---|---|
| Manuscript metadata table, field C2 | **v1.1.0 version DOI** | The article describes v1.1.0. A reader must get exactly that. |
| Manuscript "Data availability" | **v1.1.0 version DOI** + concept DOI | Exact version, plus a stable pointer to the project. |
| Dataset record, "collected with" | **v1.0.0 version DOI** | The corpus was collected with v1.0.0, not v1.1.0. |
| General citation of the project | Concept DOI | Resolves forward as new versions appear. |

**Do not put the concept DOI in field C2.** It resolves to whatever version is
newest, which will eventually not be the version the article describes — which
is the same class of problem R1-15 raised about the GitHub link.

## 4. Deposit procedure

Order matters: deposit **v1.0.0 first**, then v1.1.0 as a *new version* of that
record. That produces the shared concept DOI and the correct
`isNewVersionOf` / `isPreviousVersionOf` linkage automatically.

### 4.1 Reserve the DOIs first

Every metadata file in both archives contains `10.5281/zenodo.XXXXXXX`
placeholders. You cannot fill them in after publishing — the zip is frozen.
So:

1. Sign in to <https://zenodo.org> with your ORCID.
2. **New upload** → do not upload files yet.
3. Set *Upload type* = **Software**.
4. Under DOI, click **Reserve DOI**. Note the number.
5. Repeat in a second draft for v1.1.0, and note that number too.

You now have both version DOIs and can fill them in before zipping.

### 4.2 Fill in the placeholders

In **both** archives, replace every `10.5281/zenodo.XXXXXXX` with the correct
reserved DOI. Watch the direction of the cross-references:

| File | Placeholder refers to |
|---|---|
| `v1.0.0/ARCHIVAL_NOTICE.md` | v1.1.0 (superseded-by), then v1.0.0 (its own, in the BibTeX) |
| `v1.0.0/.zenodo.json` | v1.1.0 (`isPreviousVersionOf`), article, dataset |
| `v1.0.0/CITATION.cff` | v1.0.0 (its own), article |
| `v1.1.0/.zenodo.json` | v1.0.0 (`isNewVersionOf`), article, dataset |
| `v1.1.0/CITATION.cff` | v1.1.0 (its own), article, v1.0.0 (in `references`) |
| `v1.1.0/README.md`, `CHANGELOG.md`, `DEPLOY.md` | v1.1.0 |

A helper script is included — run it from each archive root:

```bash
python3 tools/fill_dois.py --v10 10.5281/zenodo.1234567 \
                           --v11 10.5281/zenodo.1234568 \
                           --article 10.1016/j.softx.2026.102XXX \
                           --dataset 10.5281/zenodo.1234569
```

It reports every substitution and refuses to leave a placeholder behind.

### 4.3 Add ORCIDs

`CITATION.cff` and `.zenodo.json` have ORCID fields commented out. Fill them
in — Zenodo uses them to link the record to author profiles, which is most of
the point of depositing under your own identity.

### 4.4 Tag the repository

The archive must correspond to a git state a reader can find:

```bash
git tag -a v1.0.0 -m "Version used to collect the pilot corpus"
git tag -a v1.1.0 -m "Post-review corrections; see CHANGELOG.md"
git push origin v1.0.0 v1.1.0
```

Record the 40-character commit SHA for v1.1.0 — the manuscript metadata table
asks for it alongside the DOI.

### 4.5 Deposit v1.0.0

1. Open the reserved v1.0.0 draft.
2. Upload `BahriApp-v1.0.0.zip`.
3. Paste metadata from `.zenodo.json` (title, description, creators, keywords,
   license, version, related identifiers).
4. **Version** field: `1.0.0`.
5. Under *Related identifiers*, confirm:
   - `isSupplementTo` → the SoftwareX article DOI
   - `isPreviousVersionOf` → the v1.1.0 DOI
   - `isSourceOf` → the dataset DOI
6. Publish.

### 4.6 Deposit v1.1.0 as a new version

1. Open the published v1.0.0 record → **New version**.
2. Remove the v1.0.0 file; upload `BahriApp-v1.1.0.zip`.
3. Replace metadata with `v1.1.0/.zenodo.json`.
4. **Version** field: `1.1.0`.
5. Publish.

Zenodo now shows both under one concept DOI, with version navigation.

### 4.7 Update the manuscript

| Field | Value |
|---|---|
| C1 Current code version | `v1.1.0` |
| C2 Permanent link | v1.1.0 version DOI + git tag + commit SHA |
| C3 Reproducible capsule | `.../tree/v1.1.0/analysis` |
| Data availability | v1.1.0 DOI, concept DOI, dataset DOI |

Also add to the article, in the limitations or data-availability section: *the
pilot corpus was collected with v1.0.0, archived separately at [DOI]*. A reader
who takes v1.1.0 and assumes it produced the data will be wrong about eighteen
columns.

## 5. Post-deposit checklist

- [ ] Both DOIs resolve
- [ ] Concept DOI resolves to v1.1.0
- [ ] v1.0.0 landing page shows the encryption withdrawal in its description
- [ ] `sha256sum -c MANIFEST.sha256` passes on the downloaded v1.0.0 zip
- [ ] Version navigation links the two records
- [ ] Dataset record points at v1.0.0, not v1.1.0
- [ ] No `XXXXXXX` placeholder remains in either archive
- [ ] `pubspec.lock` committed (see `DEPLOY.md` §0)
- [ ] GitHub repository README updated — it still carried the withdrawn claims

## 6. If you use the GitHub–Zenodo integration instead

Enabling the integration and pushing a tag auto-creates a record. Two cautions:

1. It archives **the repository as tagged**, so the DOI placeholders must be
   filled in and committed *before* tagging.
2. It ignores `.zenodo.json` fields Zenodo cannot infer. Check the description
   and related identifiers on the draft before publishing — in particular, the
   withdrawal notice on the v1.0 record is the single most important thing on
   that page and is easy to lose.

Manual deposit gives more control and is what these instructions assume.

## 7. Long-term maintenance

- A future v1.2.0 goes in as another *new version* under the same concept DOI.
- Never edit a published record's files. Zenodo does not permit it, and that is
  the property that makes the DOI worth citing.
- If a further defect is found in v1.1.0, publish v1.1.1 and add an erratum to
  the v1.1.0 record's description. Do not silently supersede.
