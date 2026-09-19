"""Line-for-line Python mirror of the v1.1 Dart extractors, running the same
26 assertions as test/feature_extractors_v11_test.dart.

This validates the ARITHMETIC of the corrected algorithms. It does not check
Dart syntax or Flutter API usage — no Dart SDK is available in this container.
"""
import math
import unittest


# ===================================================================== GYRO
class GyroPipelineV11:
    def __init__(self, thr_speed=1.63, thr_accel=None, thr_jerk=None,
                 dt_min=1e-4, dt_max=0.25, alpha=0.98):
        self.thr_speed, self.thr_accel, self.thr_jerk = thr_speed, thr_accel, thr_jerk
        self.dt_min, self.dt_max, self.alpha = dt_min, dt_max, alpha
        self.reset()

    def reset(self):
        self._last_us = None
        self._last_speed = None
        self._last_accel = None
        self.roll = 0.0
        self.pitch = 0.0
        self.cum = [0.0, 0.0, 0.0]
        self.seen = self.kept = self.dt_rejected = 0
        self._dt_log = []

    @staticmethod
    def calibrate(speeds, target_retention=0.30):
        if not speeds:
            return 0.0
        s = sorted(speeds)
        idx = round((1.0 - target_retention) * (len(s) - 1))
        return s[max(0, min(idx, len(s) - 1))]

    @staticmethod
    def omega_direction(wx, wy, wz):
        return [math.degrees(math.atan2(wy, wz)),
                math.degrees(math.atan2(-wx, math.hypot(wy, wz)))]

    def _update_orientation(self, wx, wy, wz, dt, ax=None, ay=None, az=None):
        self.roll += math.degrees(wx * dt)
        self.pitch += math.degrees(wy * dt)
        if ax is not None and not (ax == 0 and ay == 0 and az == 0):
            acc_roll = math.degrees(math.atan2(ay, az))
            acc_pitch = math.degrees(math.atan2(-ax, math.hypot(ay, az)))
            self.roll = self.alpha * self.roll + (1 - self.alpha) * acc_roll
            self.pitch = self.alpha * self.pitch + (1 - self.alpha) * acc_pitch
        self.roll = (self.roll + 180.0) % 360.0 - 180.0
        self.pitch = max(-90.0, min(90.0, self.pitch))

    def step(self, wx, wy, wz, elapsed_us, ax=None, ay=None, az=None):
        self.seen += 1
        speed = math.sqrt(wx * wx + wy * wy + wz * wz)
        if self._last_us is None:
            self._last_us, self._last_speed = elapsed_us, speed
            return None
        dt = (elapsed_us - self._last_us) / 1e6
        if dt < self.dt_min or dt > self.dt_max:
            self.dt_rejected += 1
            self._last_us, self._last_speed = elapsed_us, speed
            return None
        self._dt_log.append(dt)
        accel = (speed - self._last_speed) / dt
        jerk = 0.0 if self._last_accel is None else (accel - self._last_accel) / dt
        for i, w in enumerate((wx, wy, wz)):
            self.cum[i] += w * dt
        self._update_orientation(wx, wy, wz, dt, ax, ay, az)
        az_dir, el_dir = self.omega_direction(wx, wy, wz)
        significant = (speed > self.thr_speed
                       or (self.thr_accel is not None and abs(accel) > self.thr_accel)
                       or (self.thr_jerk is not None and abs(jerk) > self.thr_jerk))
        self._last_us, self._last_speed, self._last_accel = elapsed_us, speed, accel
        if not significant:
            return None
        self.kept += 1
        return {"angularSpeed": speed, "angularAccel": accel, "angularJerk": jerk,
                "rollDeg": self.roll, "pitchDeg": self.pitch,
                "omegaAzimuthDeg": az_dir, "omegaElevationDeg": el_dir,
                "cumRotXRad": self.cum[0]}


# ==================================================================== SWIPE
def swipe_extract(points, screen_diag, fling_vx=0.0, fling_vy=0.0):
    if len(points) < 2:
        raise ValueError("a swipe needs at least two sampled points")
    duration = points[-1][2] - points[0][2]
    if duration <= 0:
        raise ValueError("non-positive swipe duration")
    path_len = peak_speed = peak_accel = 0.0
    sum_accel = sum_jerk = 0.0
    n_accel = n_jerk = 0
    prev_v = prev_a = None
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    for i in range(1, len(points)):
        a, b = points[i - 1], points[i]
        seg = math.hypot(b[0] - a[0], b[1] - a[1])
        dt = max(b[2] - a[2], 1e-9)
        path_len += seg
        v = seg / dt
        peak_speed = max(peak_speed, v)
        if prev_v is not None:
            acc = (v - prev_v) / dt
            sum_accel += acc
            n_accel += 1
            peak_accel = max(peak_accel, abs(acc))
            if prev_a is not None:
                sum_jerk += (acc - prev_a) / dt
                n_jerk += 1
            prev_a = acc
        prev_v = v
    dx, dy = points[-1][0] - points[0][0], points[-1][1] - points[0][1]
    chord = math.hypot(dx, dy)
    mean_speed = path_len / duration
    return {"pathLength_px": path_len, "straightLineDistance_px": chord,
            "straightnessIndex": chord / path_len if path_len > 0 else 1.0,
            "bboxArea_px2": (max(xs) - min(xs)) * (max(ys) - min(ys)),
            "direction_deg": math.degrees(math.atan2(dy, dx)),
            "duration_s": duration, "meanSpeed_px_s": mean_speed,
            "peakSpeed_px_s": peak_speed,
            "meanAccel_px_s2": sum_accel / n_accel if n_accel else 0.0,
            "peakAccel_px_s2": peak_accel,
            "meanJerk_px_s3": sum_jerk / n_jerk if n_jerk else 0.0,
            "flingSpeed_px_s": math.hypot(fling_vx, fling_vy),
            "flingDirection_deg": math.degrees(math.atan2(fling_vy, fling_vx)),
            "snPathLength": path_len / screen_diag,
            "snMeanSpeed": mean_speed / screen_diag,
            "snPeakAccel": peak_accel / screen_diag,
            "nSampledPoints": float(len(points))}


# ====================================================================== TAP
def tap_extract(press_us, release_us, press_pos, release_pos, target, screen):
    dur_ms = (release_us - press_us) / 1000.0
    if dur_ms <= 0:
        raise ValueError("non-positive tap duration")
    dx, dy = release_pos[0] - press_pos[0], release_pos[1] - press_pos[1]
    ex, ey = press_pos[0] - target[0], press_pos[1] - target[1]
    return {"duration_ms": dur_ms, "tapRate_hz": 1000.0 / dur_ms,
            "withinTapDrift_px": math.hypot(dx, dy),
            "targetingError_px": math.hypot(ex, ey),
            "normalizedX": press_pos[0] / screen[0],
            "normalizedY": press_pos[1] / screen[1]}


# ================================================================ KEYSTROKE
PAUSE_MS, MAX_HOLD_MS = 3000.0, 5000.0


def _median(v):
    s = sorted(v)
    n = len(s)
    if n == 0:
        return float("nan")
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2.0


def _pct(sorted_v, p):
    if not sorted_v:
        return float("nan")
    idx = max(0, min(round(p * (len(sorted_v) - 1)), len(sorted_v) - 1))
    return sorted_v[idx]


def _stats(v, prefix):
    keys = ("mean", "median", "sd", "cv", "p25", "p75", "iqr")
    if not v:
        return {f"{prefix}_{k}": float("nan") for k in keys}
    s = sorted(v)
    mean = sum(v) / len(v)
    sd = 0.0
    if len(v) > 1:
        sd = math.sqrt(sum((x - mean) ** 2 for x in v) / (len(v) - 1))
    p25, p75 = _pct(s, 0.25), _pct(s, 0.75)
    return {f"{prefix}_mean": mean, f"{prefix}_median": _median(v), f"{prefix}_sd": sd,
            f"{prefix}_cv": (sd / mean) if (len(v) > 1 and mean > 0) else float("nan"),
            f"{prefix}_p25": p25, f"{prefix}_p75": p75, f"{prefix}_iqr": p75 - p25}


def keystroke_build(events):
    ev = sorted(events, key=lambda e: e["press_us"])
    hold, flight, inter = [], [], []
    rejected = n_text = 0
    for i, e in enumerate(ev):
        h = (e["release_us"] - e["press_us"]) / 1000.0
        if h <= 0 or h > MAX_HOLD_MS:
            rejected += 1
            continue
        hold.append(h)
        if e.get("key_type") == "textKey":
            n_text += 1
        if i > 0:
            f = (e["press_us"] - ev[i - 1]["release_us"]) / 1000.0
            if 0 <= f <= PAUSE_MS:
                flight.append(f)
                inter.append((e["press_us"] - ev[i - 1]["press_us"]) / 1000.0)
    out = {}
    out.update(_stats(hold, "hold_ms"))
    out.update(_stats(flight, "flight_ms"))
    out.update(_stats(inter, "interkey_ms"))
    active_s = (sum(hold) + sum(flight)) / 1000.0
    mf = _median(flight) if flight else 0.0
    out.update({"n_events": float(len(ev)), "n_rejected": float(rejected),
                "n_text_keys": float(n_text), "activeTypingTime_s": active_s,
                "keyRate_hz": len(hold) / active_s if active_s > 0 else float("nan"),
                "typingSpeed_cpm": n_text / (active_s / 60.0) if active_s > 0 else float("nan"),
                "holdFlightRatio": _median(hold) / mf if (flight and mf > 0) else float("nan")})
    return out


# ===================================================================== GAIT
G = 9.80665


def gait_orientation(ax, ay, az, mx=None, my=None, mz=None):
    n = math.sqrt(ax * ax + ay * ay + az * az)
    if n == 0:
        return {"pitch": 0.0, "roll": 0.0, "yaw": 0.0}
    nx, ny, nz = ax / n, ay / n, az / n
    pitch = math.degrees(math.asin(max(-1.0, min(1.0, -nx))))
    roll = math.degrees(math.atan2(ny, nz))
    yaw = 0.0
    if mx is not None:
        mn = math.sqrt(mx * mx + my * my + mz * mz)
        if mn:
            ux, uy, uz = mx / mn, my / mn, mz / mn
            yaw = math.degrees(math.atan2(uy * nx - ux * ny, ux * nz - uz * nx))
    return {"pitch": pitch, "roll": roll, "yaw": yaw}


def gait_step_features(mags, times):
    if not mags:
        return {}
    mean = sum(mags) / len(mags)
    sd = 0.0
    if len(mags) > 1:
        sd = math.sqrt(sum((m - mean) ** 2 for m in mags) / (len(mags) - 1))
    sum_j = peak_abs = 0.0
    n_pos = n_j = 0
    for i in range(1, min(len(mags), len(times))):
        dt = max(times[i] - times[i - 1], 1e-9)
        j = (mags[i] - mags[i - 1]) / dt
        sum_j += j
        peak_abs = max(peak_abs, abs(j))
        if j > 0:
            n_pos += 1
        n_j += 1
    return {"meanAccel_ms2": mean, "meanLinearAccel_ms2": mean - G,
            "peakAccel_ms2": max(mags), "minAccel_ms2": min(mags), "sdAccel_ms2": sd,
            "meanJerk_ms3": sum_j / n_j if n_j else 0.0, "peakAbsJerk_ms3": peak_abs,
            "jerkSignBalance": n_pos / n_j if n_j else float("nan")}


# ==================================================================== TESTS
class TestGyro(unittest.TestCase):
    def test_z_rotation_no_tilt(self):
        p = GyroPipelineV11(thr_speed=0.0)
        for k in range(101):
            p.step(0.0, 0.0, 1.0, k * 5000)
        s = p.step(0.0, 0.0, 1.0, 101 * 5000)
        self.assertLess(abs(s["rollDeg"]), 1e-6)
        self.assertLess(abs(s["pitchDeg"]), 1e-6)

    def test_constant_rate_integrates(self):
        p = GyroPipelineV11(thr_speed=0.0)
        last = None
        for k in range(201):
            s = p.step(1.0, 0.0, 0.0, k * 5000)
            if s:
                last = s
        self.assertAlmostEqual(last["cumRotXRad"], 1.0, places=6)

    def test_dt_window_rejects(self):
        p = GyroPipelineV11(thr_speed=0.0, dt_min=1e-3, dt_max=0.1)
        p.step(1, 0, 0, 0)
        p.step(1, 0, 0, 1)
        p.step(1, 0, 0, 5000001)
        self.assertEqual(p.dt_rejected, 2)

    def test_below_threshold_emits_nothing(self):
        p = GyroPipelineV11(thr_speed=10.0)
        for k in range(51):
            self.assertIsNone(p.step(0.01, 0.01, 0.01, k * 5000))

    def test_per_dimension_thresholds(self):
        p = GyroPipelineV11(thr_speed=100.0, thr_accel=1.0)
        p.step(0.0, 0.0, 0.0, 0)
        s = p.step(0.5, 0.0, 0.0, 10000)
        self.assertIsNotNone(s)
        self.assertLess(s["angularSpeed"], 100.0)
        self.assertGreater(abs(s["angularAccel"]), 1.0)

    def test_omega_direction(self):
        d = GyroPipelineV11.omega_direction(0.0, 1.0, 0.0)
        self.assertAlmostEqual(d[0], 90.0, places=6)

    def test_calibrate_percentile(self):
        thr = GyroPipelineV11.calibrate([i / 1000.0 for i in range(1000)], 0.30)
        self.assertAlmostEqual(thr, 0.70, delta=0.01)

    def test_speed_uses_three_axes(self):
        p = GyroPipelineV11(thr_speed=0.0)
        p.step(0, 0, 0, 0)
        s = p.step(3.0, 4.0, 12.0, 5000)
        self.assertAlmostEqual(s["angularSpeed"], 13.0, places=9)


class TestSwipe(unittest.TestCase):
    @staticmethod
    def line(n=11, length=100.0, dur=0.1):
        return [(length * i / (n - 1), 0.0, dur * i / (n - 1)) for i in range(n)]

    def test_straight_line_unit_straightness(self):
        f = swipe_extract(self.line(), 1000.0)
        self.assertAlmostEqual(f["straightnessIndex"], 1.0, places=9)

    def test_curve_path_exceeds_chord(self):
        f = swipe_extract([(0, 0, 0.0), (50, 40, .05), (100, 0, .1)], 1000.0)
        self.assertGreater(f["pathLength_px"], f["straightLineDistance_px"])
        self.assertLess(f["straightnessIndex"], 1.0)

    def test_below_v10_floor(self):
        f = swipe_extract([(0, 0, 0.0), (30, 60, .03), (60, -60, .06), (90, 0, .09)], 1000.0)
        self.assertLess(f["straightnessIndex"], 1 / math.sqrt(2))

    def test_speed_units(self):
        f = swipe_extract(self.line(length=100.0, dur=0.1), 1000.0)
        self.assertAlmostEqual(f["meanSpeed_px_s"], 1000.0, places=6)

    def test_screen_normalisation(self):
        small = swipe_extract(self.line(length=100.0), 800.0)
        large = swipe_extract([(2 * x, 2 * y, t) for x, y, t in self.line(length=100.0)], 1600.0)
        self.assertAlmostEqual(small["snPathLength"], large["snPathLength"], places=9)

    def test_zero_duration_rejected(self):
        with self.assertRaises(ValueError):
            swipe_extract([(0, 0, 0.0), (10, 0, 0.0)], 1000.0)

    def test_fling_separate_from_path(self):
        f = swipe_extract(self.line(), 1000.0, fling_vx=300.0, fling_vy=400.0)
        self.assertAlmostEqual(f["flingSpeed_px_s"], 500.0, places=9)
        self.assertAlmostEqual(f["pathLength_px"], 100.0, places=9)


class TestTap(unittest.TestCase):
    def test_rate_not_truncated(self):
        f = tap_extract(0, 80000, (10, 10), (10, 10), (10, 10), (400, 800))
        self.assertAlmostEqual(f["tapRate_hz"], 12.5, places=9)

    def test_drift_uses_y(self):
        f = tap_extract(0, 50000, (100, 100), (100, 106), (100, 100), (400, 800))
        self.assertAlmostEqual(f["withinTapDrift_px"], 6.0, places=9)

    def test_drift_vs_targeting(self):
        f = tap_extract(0, 50000, (120, 100), (123, 104), (100, 100), (400, 800))
        self.assertAlmostEqual(f["withinTapDrift_px"], 5.0, places=9)
        self.assertAlmostEqual(f["targetingError_px"], 20.0, places=9)

    def test_nonpositive_duration(self):
        with self.assertRaises(ValueError):
            tap_extract(1000, 1000, (0, 0), (0, 0), (0, 0), (400, 800))


class TestKeystroke(unittest.TestCase):
    @staticmethod
    def ev(press_ms, hold_ms, kt="textKey"):
        return {"press_us": round(press_ms * 1000),
                "release_us": round((press_ms + hold_ms) * 1000), "key_type": kt}

    def test_negative_hold_rejected(self):
        v = keystroke_build([self.ev(0, 100),
                             {"press_us": 500000, "release_us": 400000, "key_type": "textKey"},
                             self.ev(1000, 120)])
        self.assertEqual(v["n_rejected"], 1.0)
        self.assertAlmostEqual(v["hold_ms_median"], 110.0, places=6)

    def test_pause_segmentation(self):
        v = keystroke_build([self.ev(0, 100), self.ev(200, 100), self.ev(600000, 100)])
        self.assertLess(v["flight_ms_median"], PAUSE_MS)

    def test_rate_finite_subsecond(self):
        v = keystroke_build([self.ev(0, 50), self.ev(100, 50)])
        self.assertTrue(math.isfinite(v["keyRate_hz"]))
        self.assertGreater(v["keyRate_hz"], 0)

    def test_cv_guarded(self):
        v = keystroke_build([self.ev(0, 100)])
        self.assertTrue(math.isnan(v["hold_ms_cv"]) or v["hold_ms_cv"] >= 0)

    def test_empty_session(self):
        self.assertEqual(keystroke_build([])["n_events"], 0.0)

    def test_composed_fidel_two_events(self):
        v = keystroke_build([
            {"press_us": 0, "release_us": 90000, "key_type": "textKey"},
            {"press_us": 400000, "release_us": 480000, "key_type": "textKey"}])
        self.assertEqual(v["n_events"], 2.0)
        self.assertAlmostEqual(v["flight_ms_median"], 310.0, places=6)


class TestGait(unittest.TestCase):
    def test_flat_device_zero_tilt(self):
        o = gait_orientation(0.0, 0.0, 9.81)
        self.assertAlmostEqual(o["pitch"], 0.0, places=6)
        self.assertAlmostEqual(o["roll"], 0.0, places=6)

    def test_ninety_degree_tilt(self):
        o = gait_orientation(9.81, 0.0, 0.0)
        self.assertAlmostEqual(o["pitch"], -90.0, places=4)

    def test_not_v10_constant(self):
        o = gait_orientation(5.66, 5.66, 5.66)
        self.assertGreater(abs(o["pitch"] + 19.82), 1.0)

    def test_jerk_not_signed(self):
        t = [i * 0.01 for i in range(100)]
        m = [9.81 + math.sin(2 * math.pi * 2 * x) for x in t]
        f = gait_step_features(m, t)
        self.assertGreater(f["jerkSignBalance"], 0.3)
        self.assertLess(f["jerkSignBalance"], 0.7)

    def test_gravity_removed(self):
        t = [i * 0.01 for i in range(50)]
        f = gait_step_features([9.80665] * 50, t)
        self.assertAlmostEqual(f["meanLinearAccel_ms2"], 0.0, places=6)


if __name__ == "__main__":
    suite = unittest.TestSuite()
    for tc in (TestGyro, TestSwipe, TestTap, TestKeystroke, TestGait):
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(tc))
    res = unittest.TextTestRunner(verbosity=2).run(suite)
    print(f"\nRAN {res.testsRun} | failures {len(res.failures)} | errors {len(res.errors)}")
