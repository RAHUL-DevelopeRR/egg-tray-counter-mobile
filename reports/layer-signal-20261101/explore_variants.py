"""Pitch-rule variants on the LayerSignal strip profiles (exploratory, same photos as the parity test).

Input: the JSON the parity test writes when LAYER_SIGNAL_PROFILES is set (raw per-strip row profiles,
mean |Sobel-y| and mean signed Sobel-y, at the size the detector saw):

    cd mobile
    LAYER_SIGNAL_PROFILES=<file> flutter test test/layer_signal_on_registry_faces_test.dart
    python ../reports/layer-signal-20261101/explore_variants.py <file>

Every variant is scored on the photos it was chosen on, so the best row is optimistic. It answers one question:
is there an obvious classical pitch rule that the Dart port missed? Smoothing, standardisation, pitch range and the
first-strong rule follow backend/app/vision/layer_signal.py.
"""
from __future__ import annotations

import json
import sys

import numpy as np
from scipy.ndimage import gaussian_filter1d
from scipy.signal import find_peaks


def standardise(raw):
    p = np.asarray(raw, dtype=float)
    p[:2], p[-2:] = p[2], p[-3]
    s = gaussian_filter1d(p, 1.2)
    median = np.median(s)
    return (s - median) / max(1.4826 * np.median(np.abs(s - median)), 1e-6)


def autocorrelation(signal, max_lag):
    c = signal - signal.mean()
    n = len(c)
    max_lag = min(max_lag, n - 2)
    r = np.array([np.dot(c[: n - lag], c[lag:]) for lag in range(max_lag + 1)])
    return None if r[0] <= 1e-9 else r / r[0]


def first_strong(r, lo, hi):
    """estimate_pitch: the shortest local maximum at least 0.72 of the strongest."""
    section = r[lo : hi + 1]
    peaks, _ = find_peaks(section)
    if peaks.size:
        strengths = section[peaks]
        strong = peaks[strengths >= max(0.08, strengths.max() * 0.72)]
        i = strong[0] if strong.size else peaks[np.argmax(strengths)]
    else:
        i = int(np.argmax(section))
    return lo + i if section[i] >= 0.08 else None


def strongest(r, lo, hi):
    section = r[lo : hi + 1]
    peaks, _ = find_peaks(section)
    i = peaks[np.argmax(section[peaks])] if peaks.size else int(np.argmax(section))
    return lo + i if section[i] >= 0.08 else None


def comb(r, lo, hi):
    """Harmonic comb: mean R at k*L minus mean R at (k - 1/2)*L, k = 1..5."""
    best, score = None, -np.inf
    for lag in range(lo, hi + 1):
        ks = [k for k in range(1, 6) if k * lag < len(r) - 1]
        if not ks:
            continue
        s = np.mean([r[k * lag] for k in ks]) - np.mean([r[int(round((k - 0.5) * lag))] for k in ks])
        if s > score:
            best, score = lag, s
    return best


def classify(estimate, reference):
    if estimate is None:
        return "none"
    q = estimate / reference
    if abs(q - 1) <= 0.10:
        return "within"
    if abs(q - 0.5) <= 0.10:
        return "half"
    if abs(q - 2) <= 0.20:
        return "double"
    return "other"


POLARITIES = {
    "abs (port)": lambda a, g: a,
    "signed": lambda a, g: g,
    "dark below": lambda a, g: (a + g) / 2,
    "bright below": lambda a, g: (a - g) / 2,
}
RULES = {"first strong (port)": first_strong, "strongest": strongest, "harmonic comb": comb}


def main(path):
    faces = json.load(open(path))
    print(f"{len(faces)} faces")
    print("| profile | rule | accepted columns within 10% (strips inside the column) | half | double "
          "| faces half or double (all strips) |")
    print("|---|---|---:|---:|---:|---:|")
    for pname, polarity in POLARITIES.items():
        for rname, rule in RULES.items():
            columns, face_kinds = {}, {}
            for f in faces:
                height = f["height"]
                lo = max(8, round(0.01 * height))
                hi = max(lo + 2, round(0.15 * height))
                max_lag = hi * 6 + 2 if rule is comb else hi + 1
                acs = [autocorrelation(standardise(polarity(np.array(s["abs"]), np.array(s["sgn"]))), max_lag)
                       for s in f["strips"]]
                if f["columns"]:
                    pitches = [c["pitch_px"] for c in f["columns"]]
                    reference = np.median([p for p in pitches if p >= np.median(pitches)])
                    good = [a for a in acs if a is not None]
                    estimate = None
                    if good:
                        n = min(len(a) for a in good)
                        estimate = rule(np.mean([a[:n] for a in good], axis=0), lo, min(hi, n - 2))
                    kind = classify(estimate, reference)
                    face_kinds[kind] = face_kinds.get(kind, 0) + 1
                for c in f["columns"]:
                    if not c["accepted"]:
                        continue
                    inside = [a for s, a in zip(f["strips"], acs)
                              if a is not None and c["x_min"] <= (s["x0"] + s["x1"]) / 2 <= c["x_max"]]
                    if not inside:
                        kind = "none"
                    else:
                        n = min(len(a) for a in inside)
                        kind = classify(rule(np.mean([a[:n] for a in inside], axis=0), lo, min(hi, n - 2)),
                                        c["pitch_px"])
                    columns[kind] = columns.get(kind, 0) + 1
            total = sum(columns.values())
            nf = sum(face_kinds.values())
            harmonic = face_kinds.get("half", 0) + face_kinds.get("double", 0)
            print(f"| {pname} | {rname} | {columns.get('within', 0)}/{total} "
                  f"({100 * columns.get('within', 0) / total:.0f}%) | {columns.get('half', 0)} "
                  f"| {columns.get('double', 0)} | {harmonic}/{nf} ({100 * harmonic / nf:.0f}%) |")


if __name__ == "__main__":
    main(sys.argv[1])
