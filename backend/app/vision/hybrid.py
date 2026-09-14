"""Conservative, server-internal fusion for calibrated physical columns.

This module consumes evidence; it does not detect markers or eggs. Inputs must
come from trusted vision adapters, never unchecked mobile form fields. Synthetic
tests establish policy behavior, not warehouse accuracy.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Literal


@dataclass(frozen=True)
class HeightSample:
    count: int
    height_cm: float
    uncertainty_cm: float

    def __post_init__(self) -> None:
        if type(self.count) is not int or self.count < 0:
            raise ValueError("Count must be a nonnegative integer")
        if any(not math.isfinite(v) or v <= 0 for v in (self.height_cm, self.uncertainty_cm)):
            raise ValueError("Height and uncertainty must be finite and positive")


def _fits(samples: tuple[HeightSample, ...]) -> bool:
    """Eliminate intercept from all interval pairs in H(n) = H1 + (n-1)*pitch."""
    ordered = sorted(samples, key=lambda s: s.count)
    lower, upper = 0.0, math.inf
    for i, a in enumerate(ordered):
        for b in ordered[i + 1:]:
            delta = b.count - a.count
            error = a.uncertainty_cm + b.uncertainty_cm
            difference = b.height_cm - a.height_cm
            if delta == 0:
                if abs(difference) > error:
                    return False
            else:
                lower = max(lower, (difference - error) / delta)
                upper = min(upper, (difference + error) / delta)
    return upper > 0 and lower <= upper


@dataclass(frozen=True)
class HeightCalibration:
    profile_id: str
    samples: tuple[HeightSample, ...]

    def __post_init__(self) -> None:
        counts = {s.count for s in self.samples}
        if (
            not self.profile_id.strip()
            or len(counts) != len(self.samples)
            or not {1, 5, 10}.issubset(counts)
            or max(counts, default=0) <= 10
            or min(counts, default=0) < 1
            or max(counts, default=0) > 200
            or any(s.height_cm <= s.uncertainty_cm for s in self.samples)
            or not _fits(self.samples)
        ):
            raise ValueError("Use consistent measured references at 1, 5, 10 and a taller stack")

    def candidates(self, height_cm: float, uncertainty_cm: float) -> tuple[int, ...]:
        """Never round, extrapolate, or clip an uncertain height to a unique count.

        The height must already be perspective/depth corrected, measured from
        stack support to tray rim (not egg tips), in this tray profile's units.
        """
        limit = max(s.count for s in self.samples)
        candidates = tuple(
            n for n in range(limit + 2)
            if _fits((*self.samples, HeightSample(n, height_cm, uncertainty_cm)))
        )
        if 0 in candidates or limit + 1 in candidates:
            return ()
        return candidates


@dataclass(frozen=True)
class ColumnEvidence:
    # Identity includes the physical column inside a floor cell, not just the cell.
    column_id: str
    view: Literal["left", "right", "straight"]
    image_sha256: str
    camera_azimuth_deg: float
    calibration_id: str
    height_candidates: tuple[int, ...]
    detected_trays: int | None
    filled_trays: int | None
    # filled_trays requires evidence for every layer, including empty layers.
    occupancy_complete: bool = False
    geometry_valid: bool = False
    identity_resolved: bool = False
    full_column_visible: bool = False
    layer_count: int | None = None

    def __post_init__(self) -> None:
        if not self.column_id.strip() or not self.calibration_id.strip():
            raise ValueError("Physical column and calibration identity are required")
        if self.view not in {"left", "right", "straight"}:
            raise ValueError("Unknown capture view")
        if len(self.image_sha256) != 64 or any(c not in "0123456789abcdef" for c in self.image_sha256):
            raise ValueError("Evidence requires an image SHA-256")
        if not math.isfinite(self.camera_azimuth_deg):
            raise ValueError("Camera azimuth must be finite")
        flags = (self.occupancy_complete, self.geometry_valid,
                 self.identity_resolved, self.full_column_visible)
        if any(type(flag) is not bool for flag in flags):
            raise ValueError("Evidence validity flags must be booleans")
        counts = (*self.height_candidates, self.detected_trays, self.filled_trays, self.layer_count)
        if any(n is not None and (type(n) is not int or n < 0) for n in counts):
            raise ValueError("Evidence counts must be nonnegative integers")
        if any(n == 0 for n in self.height_candidates):
            raise ValueError("Height cannot prove a column is empty")


@dataclass(frozen=True)
class HybridResult:
    accepted: bool
    total_filled_trays: int | None
    # Deliberately omit egg total: partially filled trays do not imply 30 eggs.
    columns: tuple[tuple[str, int], ...]
    reason: str


def fuse_hybrid(
    expected_columns: frozenset[str],
    observations: tuple[ColumnEvidence, ...],
    *,
    calibration_id: str,
    minimum_view_separation_deg: float = 15.0,
) -> HybridResult:
    """Sum each surveyed column once, only when all expected columns resolve.

    Minimum angle is a configurable capture gate, not a validated accuracy
    threshold. Agreeing views are consistency checks, not independent proof.
    """
    def reject(reason: str) -> HybridResult:
        return HybridResult(False, None, (), reason)

    if not expected_columns or any(not key.strip() for key in expected_columns):
        return reject("A surveyed scan scope is required")
    if not math.isfinite(minimum_view_separation_deg) or not 0 < minimum_view_separation_deg <= 180:
        raise ValueError("View separation must be in (0, 180]")
    if {o.column_id for o in observations} != expected_columns:
        return reject("Missing or unexpected physical columns; rescan the complete scope")
    if not calibration_id.strip() or any(o.calibration_id != calibration_id for o in observations):
        return reject("Calibration identity mismatch")
    # One view label corresponds to one original image and recovered camera pose.
    views: dict[str, tuple[str, float]] = {}
    for o in observations:
        signature = (o.image_sha256, o.camera_azimuth_deg)
        if o.view in views and views[o.view] != signature:
            return reject("Inconsistent image or camera pose for a capture view")
        views[o.view] = signature
    if set(views) != {"left", "right", "straight"}:
        return reject("All three guided photographs are required")
    if len({signature[0] for signature in views.values()}) != 3:
        return reject("Repeated photographs cannot verify a scan")
    accepted: list[tuple[str, int]] = []
    for column_id in sorted(expected_columns):
        group = [o for o in observations if o.column_id == column_id]
        if len({o.view for o in group}) != len(group):
            return reject(f"{column_id}: duplicate column evidence in one view")
        usable = []
        for o in group:
            if not (o.geometry_valid and o.identity_resolved and o.full_column_visible):
                continue
            if len(o.height_candidates) != 1 or o.detected_trays != o.height_candidates[0]:
                return reject(f"{column_id}: height and tray evidence unresolved or disagree")
            count = o.height_candidates[0]
            if o.layer_count is not None and o.layer_count != count:
                return reject(f"{column_id}: layer evidence disagrees")
            if not o.occupancy_complete or o.filled_trays is None or o.filled_trays > count:
                return reject(f"{column_id}: egg occupancy is unresolved")
            usable.append(o)
        if len(usable) < 2:
            return reject(f"{column_id}: two complete views are required")
        separated = any(
            abs((a.camera_azimuth_deg - b.camera_azimuth_deg + 180) % 360 - 180)
            >= minimum_view_separation_deg
            for i, a in enumerate(usable) for b in usable[i + 1:]
        )
        if not separated:
            return reject(f"{column_id}: camera views are too similar")
        if len({(o.height_candidates[0], o.filled_trays) for o in usable}) != 1:
            return reject(f"{column_id}: views disagree on trays or egg occupancy")
        accepted.append((column_id, usable[0].filled_trays))
    return HybridResult(True, sum(count for _, count in accepted), tuple(accepted),
                        "Evidence agrees for every scoped column")
