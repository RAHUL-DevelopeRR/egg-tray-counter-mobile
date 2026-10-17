"""export_manual_counts: a scan listed twice keeps its state record, and the CSV says where each record lives."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import export_manual_counts as emc  # noqa: E402


def record(storage: str | None, created_at: str, filled: int) -> dict:
    rec = {"scan_id": "s1", "block_id": "B", "created_at": created_at, "recorded_at": created_at,
           "cells": [{"x": 0, "y": 0, "filled": filled, "empty": 0}], "totals": {"filled": filled, "empty": 0}}
    if storage:
        rec.update(storage=storage, tamper_proof=storage == "state")
    return rec


def test_state_record_wins_over_a_newer_legacy_copy():
    state = record("state", "2026-10-15T08:00:00Z", 99)
    legacy = record("legacy_scans", "2026-10-15T09:00:00Z", 12)   # later, e.g. rewritten through the open route
    for order in ([state, legacy], [legacy, state]):
        kept = emc.latest_per_scan(order, log=lambda *_: None)
        assert len(kept) == 1 and kept[0]["storage"] == "state" and kept[0]["totals"]["filled"] == 99


def test_newer_record_wins_within_one_kind_and_untagged_records_still_work():
    old, new = record(None, "2026-10-09T03:00:00Z", 98), record(None, "2026-10-09T04:00:00Z", 99)
    assert emc.latest_per_scan([new, old], log=lambda *_: None)[0]["totals"]["filled"] == 99


def test_block_rows_carry_storage_and_tamper_proof():
    _, blocks = emc.rows_for([record("state", "2026-10-15T08:00:00Z", 99), record(None, "2026-10-09T04:00:00Z", 5)])
    assert (blocks[0]["storage"], blocks[0]["tamper_proof"]) == ("state", True)
    assert (blocks[1]["storage"], blocks[1]["tamper_proof"]) == (None, None)
    assert {"storage", "tamper_proof"} <= set(emc.BLOCK_FIELDS)
