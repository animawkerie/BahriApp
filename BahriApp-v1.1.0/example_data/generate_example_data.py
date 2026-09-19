#!/usr/bin/env python3
"""Generate small SYNTHETIC datasets matching the BahriApp export schema.

Purpose: let a third party exercise the dashboard, the export path and the
analysis notebook without access to the pilot corpus, which contains real
participants' behavioural data and is distributed separately under its own
data-use conditions.

THIS DATA IS NOT REAL. It is drawn from plausible distributions and contains
no human subject's behaviour. Do not use it to evaluate recognition accuracy,
and do not cite any number computed from it.

The generator deliberately writes epoch columns as quoted strings and verifies
the round trip, demonstrating the v1.1 export contract that the v1.0 tap
export violated.

    python example_data/generate_example_data.py
"""
import csv
import os
import random
from datetime import datetime, timedelta

random.seed(20260919)  # reproducible

OUT = os.path.dirname(os.path.abspath(__file__))
N_PARTICIPANTS = 6
EPOCH_BASE = 1735689600000  # 2025-01-01T00:00:00Z in ms

EPOCH_COLUMNS = {"sessionId", "pressTime", "releaseTime",
                 "TapPressTime", "TapReleaseTime"}


def iso(ms):
    return datetime.utcfromtimestamp(ms / 1000.0).isoformat()


def participants():
    return [f"SYNTH{i:03d}" for i in range(1, N_PARTICIPANTS + 1)]


def write(name, rows, fieldnames):
    path = os.path.join(OUT, name)
    with open(path, "w", newline="", encoding="utf-8") as f:
        # QUOTE_ALL keeps 13-digit epochs out of a spreadsheet's numeric
        # inference path — the v1.1 export contract.
        w = csv.DictWriter(f, fieldnames=fieldnames, quoting=csv.QUOTE_ALL)
        w.writeheader()
        w.writerows(rows)

    # Verify the round trip, exactly as export_data.py does.
    with open(path, newline="", encoding="utf-8") as f:
        back = list(csv.DictReader(f))
    for col in EPOCH_COLUMNS & set(fieldnames):
        before = len({str(r[col]) for r in rows})
        after = len({str(r[col]) for r in back})
        if before != after:
            raise RuntimeError(
                f"{name}: epoch precision lost in column '{col}' "
                f"({before} -> {after} distinct values)")
    print(f"  {name}: {len(rows)} rows, epoch round-trip verified")


def keystroke(name, language, n_sessions=3):
    cols = ["id", "sessionId", "gender", "skillLevel", "language", "Sentence",
            "completeUserInput", "keyText", "keyType", "pressTime",
            "releaseTime", "holdTime", "flightTime", "compositionRole"]
    rows = []
    alphabet = ("ሀለሐመሠረሰሸቀበተቸነአከወዘየደገጠጰጸፈፐ" if language == "am"
                else "abcdefghijklmnopqrstuvwxyz")
    for p in participants():
        for s in range(n_sessions):
            sid = EPOCH_BASE + random.randint(0, 9_000_000_000)
            t = sid
            text = "".join(random.choice(alphabet) for _ in range(random.randint(8, 16)))
            prev_release = None
            for ch in text:
                hold = max(20, int(random.gauss(90, 25)))
                # Amharic: non-first-order fidels cost two physical key events
                is_composed = language == "am" and random.random() < 0.40
                flight = "" if prev_release is None else max(0, t - prev_release)
                rows.append({
                    "id": p, "sessionId": str(sid), "gender": random.choice(["M", "F"]),
                    "skillLevel": random.choice(["beginner", "intermediate", "expert"]),
                    "language": language, "Sentence": text,
                    "completeUserInput": text, "keyText": ch,
                    "keyType": "KeyTypes.textKey",
                    "pressTime": str(t), "releaseTime": str(t + hold),
                    "holdTime": hold, "flightTime": flight,
                    "compositionRole": "base" if is_composed else "standalone",
                })
                prev_release = t + hold
                t = prev_release + max(30, int(random.gauss(320, 140)))
                if is_composed:
                    hold2 = max(20, int(random.gauss(85, 22)))
                    rows.append({
                        "id": p, "sessionId": str(sid), "gender": "",
                        "skillLevel": "", "language": language, "Sentence": text,
                        "completeUserInput": text, "keyText": ch,
                        "keyType": "KeyTypes.textKey",
                        "pressTime": str(t), "releaseTime": str(t + hold2),
                        "holdTime": hold2, "flightTime": max(0, t - prev_release),
                        "compositionRole": "order",
                    })
                    prev_release = t + hold2
                    t = prev_release + max(30, int(random.gauss(300, 120)))
    write(name, rows, cols)


def tap(name, n_sessions=3):
    cols = ["id", "sessionId", "startTime", "endTime", "TapPressTime",
            "TapReleaseTime", "TapDuration", "TapInitialGlobalLocationX",
            "TapInitialGlobalLocationY", "TapFinalGlobalLocationX",
            "TapFinalGlobalLocationY", "normalizedX", "normalizedY",
            "_targetSizeAre"]
    rows = []
    for p in participants():
        for s in range(n_sessions):
            sid = EPOCH_BASE + random.randint(0, 9_000_000_000)
            start = sid
            end = start + 10_000
            target_area = random.choice([1422, 1533, 1660, 1727])
            for _ in range(random.randint(15, 40)):
                press = start + random.randint(0, 9_500)
                dur = max(30, int(random.gauss(75, 20)))
                x = random.uniform(20, 380)
                y = random.uniform(40, 760)
                rows.append({
                    "id": p, "sessionId": str(sid),
                    "startTime": iso(start), "endTime": iso(end),
                    "TapPressTime": str(press), "TapReleaseTime": str(press + dur),
                    "TapDuration": dur,
                    "TapInitialGlobalLocationX": round(x, 2),
                    "TapInitialGlobalLocationY": round(y, 2),
                    "TapFinalGlobalLocationX": round(x + random.gauss(0, 0.8), 2),
                    "TapFinalGlobalLocationY": round(y + random.gauss(0, 0.8), 2),
                    "normalizedX": round(x / 400, 4), "normalizedY": round(y / 800, 4),
                    "_targetSizeAre": target_area,
                })
    write(name, rows, cols)


def swipe(name, n_sessions=3):
    cols = ["id", "sessionId", "initialX", "initialY", "flingVelocityX",
            "flingVelocityY", "duration", "pathLength_px",
            "straightLineDistance_px", "straightnessIndex", "meanSpeed_px_s",
            "snPathLength", "screenDiagonalPx"]
    rows = []
    for p in participants():
        diag = random.choice([846.0, 892.0, 934.0, 1024.0])
        for s in range(n_sessions):
            sid = EPOCH_BASE + random.randint(0, 9_000_000_000)
            for _ in range(random.randint(8, 20)):
                dur = round(random.uniform(0.08, 0.5), 4)
                chord = random.uniform(80, 400)
                path = chord * random.uniform(1.0, 1.35)
                rows.append({
                    "id": p, "sessionId": str(sid),
                    "initialX": round(random.uniform(20, 380), 2),
                    "initialY": round(random.uniform(40, 760), 2),
                    "flingVelocityX": round(random.gauss(0, 900), 1),
                    "flingVelocityY": round(random.gauss(0, 900), 1),
                    "duration": dur,
                    "pathLength_px": round(path, 2),
                    "straightLineDistance_px": round(chord, 2),
                    "straightnessIndex": round(chord / path, 4),
                    "meanSpeed_px_s": round(path / dur, 1),
                    "snPathLength": round(path / diag, 4),
                    "screenDiagonalPx": diag,
                })
    write(name, rows, cols)


def gyro(name, n_sessions=2):
    cols = ["id", "sessionId", "timestamp", "gyroX", "gyroY", "gyroZ",
            "angularSpeed_rad_s", "angularAccel_rad_s2", "omegaAzimuth",
            "omegaElevation", "roll_deg", "pitch_deg", "dtS"]
    rows = []
    import math
    for p in participants():
        for s in range(n_sessions):
            sid = EPOCH_BASE + random.randint(0, 9_000_000_000)
            t = sid
            last_speed = None
            for _ in range(120):
                dt = random.uniform(0.003, 0.008)
                t += dt * 1000
                wx, wy, wz = (random.gauss(0, 0.9) for _ in range(3))
                speed = math.sqrt(wx * wx + wy * wy + wz * wz)
                accel = 0.0 if last_speed is None else (speed - last_speed) / dt
                last_speed = speed
                if speed <= 1.63:      # v1.1 data-driven gate
                    continue
                rows.append({
                    "id": p, "sessionId": str(sid), "timestamp": iso(t),
                    "gyroX": round(wx, 5), "gyroY": round(wy, 5), "gyroZ": round(wz, 5),
                    "angularSpeed_rad_s": round(speed, 5),
                    "angularAccel_rad_s2": round(accel, 4),
                    "omegaAzimuth": round(math.degrees(math.atan2(wy, wz)), 3),
                    "omegaElevation": round(
                        math.degrees(math.atan2(-wx, math.hypot(wy, wz))), 3),
                    "roll_deg": round(random.uniform(-25, 25), 3),
                    "pitch_deg": round(random.uniform(-25, 25), 3),
                    "dtS": round(dt, 6),
                })
    write(name, rows, cols)


if __name__ == "__main__":
    print("Generating SYNTHETIC example data (not real participant data):")
    keystroke("Keystroke_Data_English.csv", "en")
    keystroke("Keystroke_Data_Amharic.csv", "am")
    tap("Tap_Data.csv")
    swipe("Swipe_Data.csv")
    gyro("Gyroscope_Data.csv")
    print("\nDone. These files are synthetic and must not be cited.")
