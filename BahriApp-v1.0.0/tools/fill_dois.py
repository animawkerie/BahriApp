#!/usr/bin/env python3
"""Replace DOI placeholders across an archive before Zenodo deposit.

The archives ship with `10.5281/zenodo.XXXXXXX` and
`10.1016/j.softx.XXXX.XXXXXX` placeholders, because the DOIs are not known
until they are reserved. Once a zip is published the placeholders cannot be
fixed, so this script fills them in and then REFUSES to finish if any
placeholder survives.

Cross-references point in different directions in different files, so the
script resolves each by file and context rather than doing one blind
search-and-replace.

    python3 tools/fill_dois.py \
        --v10 10.5281/zenodo.1234567 \
        --v11 10.5281/zenodo.1234568 \
        --article 10.1016/j.softx.2026.102345 \
        --dataset 10.5281/zenodo.1234569 \
        [--concept 10.5281/zenodo.1234566] [--dry-run]

Run it from the root of each archive (v1.0.0 and v1.1.0 separately).
"""
import argparse
import pathlib
import re
import sys

ZENODO_PLACEHOLDER = "10.5281/zenodo.XXXXXXX"
ARTICLE_PLACEHOLDER = "10.1016/j.softx.XXXX.XXXXXX"

# Which Zenodo DOI each placeholder means, per file. Rules are tried in order
# and the first match wins. 'context' is a regex searched in a window spanning
# LINES_BEFORE lines back and LINES_AFTER lines forward, because the
# disambiguating token sits before the placeholder in Markdown ("Superseded
# by ...") but *after* it in JSON, where "identifier" precedes "relation":
#
#     { "identifier": "10.5281/zenodo.XXXXXXX",
#       "relation":   "isPreviousVersionOf",  <- the token that disambiguates
#
# Looking only backwards silently resolved every JSON relation to the wrong
# version, which is exactly the kind of error that is invisible until someone
# clicks a DOI on a published record.
LINES_BEFORE, LINES_AFTER = 3, 3

RULES = [
    # ---- v1.0.0 archive ----
    # Its own BibTeX block: 'doi' and 'url' both refer to v1.0 itself, even
    # though the 'note' field two lines up mentions v1.1. Checked first so the
    # more general "Superseded by" rule cannot capture it.
    ("ARCHIVAL_NOTICE.md", r"@software|doi\s*=|url\s*=\s*\{https://doi", "v10"),
    ("ARCHIVAL_NOTICE.md", r"Superseded by|superseded-by", "v11"),
    ("ARCHIVAL_NOTICE.md", None, "v10"),
    # In v1.0's record, isPreviousVersionOf points AT v1.1.
    # In v1.1's record, isNewVersionOf points AT v1.0.
    (".zenodo.json", r"isPreviousVersionOf", "v11"),
    (".zenodo.json", r"isNewVersionOf", "v10"),
    (".zenodo.json", r'"resource_type"\s*:\s*"dataset"|isSourceOf|"relation"\s*:\s*"references"', "dataset"),
    # ---- v1.1.0 archive ----
    ("CITATION.cff", r"v1\.0\.0|pilot corpus", "v10"),
    ("README.md", None, "v11"),
    ("CHANGELOG.md", None, "v11"),
    ("DEPLOY.md", None, "v11"),
    ("MIGRATION.md", None, "v11"),
    ("SECURITY.md", None, "v11"),
]

SKIP_FILES = {"tools/fill_dois.py", "docs/ZENODO_ARCHIVE.md"}


def resolve(rel_path, idx, lines, dois, default):
    """Pick which DOI the placeholder on lines[idx] refers to."""
    lo = max(0, idx - LINES_BEFORE)
    hi = min(len(lines), idx + LINES_AFTER + 1)
    haystack = "\n".join(lines[lo:hi])
    for pattern_file, context, which in RULES:
        if not rel_path.endswith(pattern_file):
            continue
        if which is None:
            return None
        if context is None or re.search(context, haystack, re.I):
            return dois.get(which)
    return dois.get(default)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--v10", help="v1.0.0 version DOI")
    ap.add_argument("--v11", help="v1.1.0 version DOI")
    ap.add_argument("--article", help="SoftwareX article DOI")
    ap.add_argument("--dataset", help="dataset DOI")
    ap.add_argument("--concept", help="concept DOI (optional)")
    ap.add_argument("--root", default=".", help="archive root (default: cwd)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    root = pathlib.Path(args.root).resolve()
    dois = {k: v for k, v in
            (("v10", args.v10), ("v11", args.v11),
             ("dataset", args.dataset), ("concept", args.concept)) if v}

    # Which version's archive is this? Used as the fallback for bare refs.
    default = "v11" if (root / "CHANGELOG.md").exists() else "v10"
    print(f"Archive root : {root}")
    print(f"Detected     : {'v1.1.0' if default == 'v11' else 'v1.0.0'}\n")

    changed, substitutions = [], 0
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix not in {".md", ".json", ".cff", ".yaml", ".yml"}:
            continue
        rel = str(path.relative_to(root))
        if rel in SKIP_FILES:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, PermissionError):
            continue
        if ZENODO_PLACEHOLDER not in text and ARTICLE_PLACEHOLDER not in text:
            continue

        lines = text.split("\n")
        out, n = [], 0
        for idx, line in enumerate(lines):
            new = line
            if ARTICLE_PLACEHOLDER in new and args.article:
                new = new.replace(ARTICLE_PLACEHOLDER, args.article)
                n += 1
            while ZENODO_PLACEHOLDER in new:
                target = resolve(rel, idx, lines, dois, default)
                if not target:
                    break
                new = new.replace(ZENODO_PLACEHOLDER, target, 1)
                n += 1
            out.append(new)

        if n:
            if not args.dry_run:
                path.write_text("\n".join(out), encoding="utf-8")
            changed.append((rel, n))
            substitutions += n

    for rel, n in changed:
        print(f"  {rel}: {n} substitution{'s' if n != 1 else ''}")
    print(f"\n{substitutions} substitutions across {len(changed)} files"
          f"{' (dry run — nothing written)' if args.dry_run else ''}")

    # Refuse to finish quietly if anything is still unresolved.
    leftovers = []
    for path in root.rglob("*"):
        if not path.is_file() or path.suffix not in {".md", ".json", ".cff", ".yaml", ".yml"}:
            continue
        rel = str(path.relative_to(root))
        if rel in SKIP_FILES:
            continue
        try:
            t = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, PermissionError):
            continue
        if ZENODO_PLACEHOLDER in t or ARTICLE_PLACEHOLDER in t:
            leftovers.append(rel)

    if leftovers and not args.dry_run:
        print("\nPLACEHOLDERS REMAIN — do not deposit this archive:")
        for r in leftovers:
            print(f"  {r}")
        print("\nSupply the missing DOI(s) and re-run.")
        return 1

    if not args.dry_run:
        print("\nNo placeholders remain. Archive is ready to zip and deposit.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
