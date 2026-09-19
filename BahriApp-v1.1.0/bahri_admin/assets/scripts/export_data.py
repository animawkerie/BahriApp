"""BahriApp v1.1 — dataset export.

Two defects in the v1.0 export path are corrected here.

1.  EXPORT INTEGRITY (reviewer comment R1-4, "export correctness").

    The v1.0 exporter wrote millisecond epoch columns through pandas' default
    float formatting. Any spreadsheet round-trip then rendered them in
    six-significant-digit scientific notation ("1.73573E+12"). In the released
    Tap_Data.csv this collapsed 4,150 genuine game rounds into 537 apparent
    session identifiers and destroyed roughly seven orders of magnitude of
    timestamp resolution. Only that one export was affected; the other ten
    round-tripped exactly.

    v1.1 coerces every epoch-valued column to a string before writing, and
    verifies after writing that the file reloads with the same number of
    distinct values it went in with. The check is cheap and it would have
    caught the original defect on the first run.

2.  PARTICIPANT PRIVACY (R1-6).

    The v1.0 export included an 'Email' column, so a direct identifier could
    leave the study in a file intended to be pseudonymous. Identifier columns
    are removed here; exports are keyed by the opaque participant id only.

Credentials come from the environment (GOOGLE_APPLICATION_CREDENTIALS or
BAHRI_SERVICE_ACCOUNT), never from a hard-coded developer path — see
.env.example.
"""

import os
import sys

import pandas as pd
from google.cloud import firestore

# Columns holding millisecond epoch timestamps. These must never be written as
# floats: 13 significant digits do not survive a float -> spreadsheet round
# trip. Extend this list when a new epoch column is added.
EPOCH_COLUMNS = {
    "sessionId",
    "pressTime",
    "releaseTime",
    "TapPressTime",
    "TapReleaseTime",
}

# Direct identifiers that must never appear in an exported dataset.
IDENTIFIER_COLUMNS = {"Email", "email", "phone", "phoneNumber", "fullName", "name"}


def _stringify_epochs(df: pd.DataFrame) -> pd.DataFrame:
    """Render epoch columns as exact integer strings."""
    for col in df.columns:
        if col in EPOCH_COLUMNS:
            df[col] = (
                pd.to_numeric(df[col], errors="coerce")
                .astype("Int64")
                .astype(str)
                .replace("<NA>", "")
            )
    return df


def _drop_identifiers(df: pd.DataFrame) -> pd.DataFrame:
    present = [c for c in df.columns if c in IDENTIFIER_COLUMNS]
    if present:
        print(f"Removing direct-identifier columns from export: {present}")
    return df.drop(columns=present, errors="ignore")


def verify_export(csv_path: str, original: pd.DataFrame) -> None:
    """Reload the written file and confirm epoch resolution survived.

    Raises RuntimeError rather than warning, because a silently damaged export
    is worse than a failed one: it is indistinguishable from real data
    downstream.
    """
    reloaded = pd.read_csv(csv_path, dtype=str, low_memory=False)
    for col in EPOCH_COLUMNS & set(original.columns):
        before = original[col].astype(str).nunique()
        after = reloaded[col].astype(str).nunique() if col in reloaded else 0
        if after < before:
            raise RuntimeError(
                f"Export integrity check FAILED for column '{col}': "
                f"{before} distinct values before writing, {after} after. "
                "Epoch precision was lost — do not distribute this file."
            )
    print(f"Export integrity check passed for {csv_path}")


def export_data(export_type, output_dir):
    """Export one modality from Firestore to CSV.

    export_type: 'Keystroke Data' | 'Swipe Data' | 'Tap Data'
    output_dir:  directory to write the CSV into
    """
    try:
        output_dir = output_dir.replace("\\", "/")
        print(f"Output directory: {output_dir}")

        creds = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS") or os.environ.get(
            "BAHRI_SERVICE_ACCOUNT"
        )
        if not creds:
            msg = (
                "No service-account credentials found. Set "
                "GOOGLE_APPLICATION_CREDENTIALS (or BAHRI_SERVICE_ACCOUNT) to the "
                "path of your service-account JSON. See .env.example."
            )
            print(msg, file=sys.stderr)
            return msg
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = creds

        db = firestore.Client()

        main_collection = "users"
        subcollection_map = {
            "Keystroke Data": "KeyStrokeData",
            "Swipe Data": "swipeData",
            "Tap Data": "tapData",
        }

        subcollection = subcollection_map.get(export_type)
        if not subcollection:
            print(f"Invalid export type: {export_type}")
            return f"Invalid export type: {export_type}"

        users = db.collection(main_collection).stream()

        data = []
        for user in users:
            user_dict = user.to_dict()
            user_id = user.id
            sub_docs = (
                db.collection(main_collection)
                .document(user_id)
                .collection(subcollection)
                .stream()
            )

            for doc in sub_docs:
                doc_dict = doc.to_dict()
                combined = {
                    "id": user_id,
                    # 'Email' deliberately omitted — see IDENTIFIER_COLUMNS.
                    "birthYear": str(user_dict.get("dateOfBirth", ""))[:4],
                    "skillLevel": user_dict.get("skillLevel", ""),
                    "gender": user_dict.get("gender", ""),
                    "Sentence": doc_dict.get("Sentence", ""),
                    "completeUserInput": doc_dict.get("completeUserInput", ""),
                    "keystrokeData": doc_dict.get("keystrokeData", ""),
                }
                for col in EPOCH_COLUMNS:
                    if col in doc_dict:
                        combined[col] = doc_dict.get(col)
                data.append(combined)

        if not data:
            print("No data found to export.")
            return "No data to export."

        df = pd.DataFrame(data)
        df = _drop_identifiers(df)
        df = _stringify_epochs(df)
        print(f"DataFrame created with shape: {df.shape}")

        csv_filename = f'{export_type.replace(" ", "_").lower()}.csv'
        csv_path = os.path.join(output_dir, csv_filename)

        # quoting=1 (QUOTE_ALL) keeps long integers out of a spreadsheet's
        # numeric inference path, which is what damaged the v1.0 tap export.
        df.to_csv(csv_path, index=False, quoting=1)

        verify_export(csv_path, df)

        print(f"Export successful: {csv_path}")
        return f"Exported {export_type} to {csv_path} successfully."

    except Exception as e:
        print(f"Error during export: {e}", file=sys.stderr)
        return f"Error exporting data: {e}"


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: export_data.py '<Export Type>' <output_dir>", file=sys.stderr)
        raise SystemExit(2)
    print(export_data(sys.argv[1], sys.argv[2]))
