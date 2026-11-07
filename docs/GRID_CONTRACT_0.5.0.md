# Block grid, declaration and extra views: wire contract (Worker 0.5.0, app 0.5.0)

Plan: `C:\Users\rahul\.claude\plans\spicy-growing-flame.md` (Plan 3), steps 4-9.

**What it is.** A phone-only counter that reconstructs one physical block as an X/Y/Z grid.
- It is **a grid model, not a point cloud or a metric mesh**.
- Inventory from photos, declared, computed and unknown is always kept separate.

## Counting unit (frozen)
- **One eligible tray** is one physical tray holding eggs. A partly filled tray also counts as one.
- **Empty cover trays** are physical layers, never eligible.
- **Unknown occupancy stays unknown.** No validated reader measures occupancy in this milestone (Phase P is
  disabled). A layer's occupancy is therefore known only when the operator declares it, and then it is labelled
  `declared`.
- **Missing stock is never inferred from an expected height.** A declared reference height can only demote.

---

## Upload (multipart, `scan_contract=model_spatial_v1`)

**Required, as today:** `left`, `right` and `straight` photos; `<view>_capture`; `<view>_constraint_evidence`.

**New optional fields:**

| Field | Type | Meaning |
|---|---|---|
| `block_declaration` | JSON string, at most 4,000 characters | Entered **before** any result is shown (see below) |
| `corner` | JPEG/PNG | Optional CORNER photo showing two adjoining faces |
| `corner_capture` | JSON, as `<view>_capture` | Its provenance |
| `corner_side` | `front_left` or `front_right` | Which corner the operator stood at |
| `elevated` | JPEG/PNG | Optional ELEVATED photo of the block top |
| `elevated_capture` | JSON | Its provenance |
| `elevated_taps` | JSON string, at most 8,000 characters | The operator's reading of the elevated photo (below) |

**`block_declaration`:**
```json
{"x": 5, "y": 3, "interior": "full|partial|unknown",
 "missing_cells": [[2, 1]], "partial_stacks": [{"x": 4, "y": 0, "layers": 12}],
 "cover_trays": "yes|no|unknown", "occupancy": "egg_filled|unknown",
 "reference_height": 20, "reference_height_measured": true,
 "operator": "name or code", "declared_at": "2026-11-01T10:00:00Z"}
```
- `x` and `y` must be integers from 1 to 40.
- Cells use `x` from 0 (left to right on the front face) and `y` from 0 (front to back).
- `occupancy: "egg_filled"` means the operator states that every counted tray holds eggs. It feeds
  `eligible_egg_trays` with the basis `declared`.
- `reference_height` is ignored unless `reference_height_measured` is true.

**`elevated_taps`:**
```json
{"x": 5, "y": 3, "cells": [{"x": 2, "y": 1, "state": "present|missing|step_down|unsure"}]}
```

---

## Response additions (`block`)

### `block.grid`: an array of rows (`y` from 0), each an array of cells (`x` from 0)
```json
{"physical_stack_id": "S2-1", "x": 2, "y": 1, "stack_present": true,
 "z_layers": 20, "filled_layers": null, "partial_layers": null, "empty_cover_layers": null, "unknown_layers": 20,
 "observed_views": ["straight", "left"],
 "measurement_sources": ["observed", "declared", "computed", "top_view"],
 "status": "verified|observed|computed|declared|top_view|missing|conflict|rescan|unknown",
 "uncertainties": ["occupancy not measured", "height computed from the typical stack", "..."],
 "readings": [{"capture_id": "a1b2…", "reader": "rf-walk", "physical_stack_id": "S2-1", "view": "straight",
               "count": 20, "evidence": {"gap_filled": 0, "doubts": []}, "quality": "accepted|refused",
               "trusted": true, "pipeline_version": "worker-0.5.0"}],
 "pair_type": "cross_photo|same_photo_reader|null"}
```
- **Shared corners are one physical stack.** A second face is an observation, never more inventory.
- `stack_present` is null when unknown.

### `block.inventory`
```json
{"physical_layers_observed": 220, "physical_layers_computed": 180, "physical_layers_declared": 0,
 "eligible_egg_trays": {"value": 400, "basis": "declared|measured|unknown", "note": "..."},
 "empty_cover_layers": {"value": null, "basis": "unknown"},
 "unknown_occupancy_layers": 400, "unknown_cells": 0}
```

### Other block fields
- `block.declaration`: the parsed declaration as stored (or null), plus `agrees_with_faces` (true, false or null).
- `block.corner`: `{side, x, y, agrees}` or null.
- `block.top_view`: `{cells_present, cells_missing, steps, agrees}` or null.
- `block.suggested_views`: for example `["elevated"]` when the interior is unresolved.

## Statuses (`block.status`)

| Status | Means |
|---|---|
| `exact` | Every stack is visible, and every one is verified by two independent captures. Never from a declaration |
| `confirmed` | Every visible stack is verified; the declaration agrees with every measured face; and the interior is declared full or supported by the top view. **The basis is always shown** (`confirmed_basis: ["declaration", "top_view"]`) |
| `estimated` | Some positions or counts are inferred |
| `conflict` | Independent evidence disagrees (photos vs declaration, corner vs faces, top view vs faces) |
| `needs_view` | A named capture is required (`rescan.recommended_view`) |

The words "exact" and "physically verified" are never used for a value that rests on a declaration.
