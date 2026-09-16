# MUTAA unchanged V2 and 3D/band candidate audit

2026-09-16. Starting branch `codex/hybrid-cell-counting`, commit
`bd8abb4b6ecc8c0fcfaff5e9661b5688e212d558`.

**35 images, 35 byte-unique originals archived; fresh V2 results obtained for
all 35. No confirmed physical ground truth for these arrangements. No verified
exact hybrid count or accuracy improvement.**

## Evidence

- [Manifest](manifest.json): original filenames, byte SHA-256, dimensions,
  available top-level EXIF, duplicate status; originals preserved byte-for-byte.
- [Contact sheet](contact-sheet.jpg), [scene groups](scene-groups.json),
  [per-image results](per-image-results.json), [table](RESULTS.md).
- `raw/`: complete gateway JSON responses and request metadata. Model
  `projec-mutta/2`; checked-in unchanged settings confidence 35, overlap 50,
  class `egg_tray`. No threshold tuning, cropping or image recompression before
  baseline requests. Gateway transport groups are NOT physical scene triplets.
- `analysis/`: original-coordinate detection files, automatic stack polygons,
  beam hypotheses/traces and per-image overlays. EXIF orientation applied before
  geometric analysis. Cyan = RF boxes, red = proposed faces, yellow = band centers.
- [Cross-view prototype](cross-view-prototype.json): tentative 07/10/11 grouping,
  zero correspondence proposals surviving feature filters, no accepted anchors,
  no reconstructed X/Y footprint. Depth and eligible totals remain null.
- `design/`: the user's exact prompt and two sketches, retained as design input.
  Its production rollback description is historical; see current context.

Gateway JSON preserves boxes/classes/confidence, but is not the entire upstream
Roboflow response: model image dimensions, upstream timing and other fields are
not forwarded. This task did not retrieve a private API key or change production
to expose upstream JSON. No hidden claim of raw upstream capture is made.

## Fresh failures and transport recovery

Initial batches 01–04 succeeded. Batches 05–12 returned HTTP 503 with Cloudflare
error pages saying `Worker exceeded resource limits`. These responses are
retained with client-IP text redacted. Batch 05 included three 12+ MB images.
Later retries recovered batches 06–12. Images 13/14/15 then succeeded separately,
each accompanied by two small original images to satisfy the existing triplet
API. Companion detections are repeats, not additional independent evaluations.

This isolates a reproducible resource failure on the attempted workload and a
working smaller-batch path. It does not identify CPU versus memory conclusively,
nor prove the earlier phone send timeout had the same cause. The Worker buffers
multipart images and base64-encodes them; instrument/test that path separately.
No backend deployment, account-plan change, or APK change was made.

## Visual error audit

Reviewed the contact sheet and detailed overlays for images 07, 10, 17 and 24.
Other overlays are generated for review; no exhaustive instance annotation has
been invented.

- **07:** RF=56; five automatic faces with band candidates 16/20/22/19/19.
  These faces do not cover all visible stock; a face can join projected front
  and rear observations. The 96-band sum is not inventory and has no relation
  to the old 100-tray truth. No known count was supplied to this algorithm.
- **10:** RF=12; only one partial automatic face, with 17 exploratory bands.
  Several stacks are clearly visible. Missed and oversized/merged detections
  leave inadequate localization. This is direct evidence that the current
  whole-stack proposal stage cannot yet cover the scene reliably.
- **17:** the model labels a broken egg/shell on the floor as `egg_tray`.
  Detailed visual review shows no tray in that image. This is a clear negative
  example and a false positive for physical-tray detection, not a physical
  recount of any warehouse stock.
- **24:** the model detects an apparently empty tray as `egg_tray`. This is not
  necessarily a physical-tray detection error, but counting it as egg-containing
  would be wrong. Generic class membership is not occupancy classification.

The camera can supply useful detail; the current detector/localization and
occupancy interpretation fail in observable ways. A higher image resolution
alone does not establish the resolution used inside the hosted model.

## What works and what is unfinished

Working locally: unchanged-model collection, hashes/orientation, automatic
candidate stack faces, per-stack RF/band evidence, retained pitch alternatives,
an abstaining candidate endpoint, and synthetic physical-grid accounting.
The test rectangle gives 200, an explicitly absent rear stack gives 180, and
repeated observations of the same supported physical cell do not add stock.

Unfinished: reliable complete stack localization, physical-rim/endpoint
validation, calibrated cross-view identity and depth, per-layer egg occupancy,
metric pose/height integration, and real-image verified totals. The candidate
API consumes saved hash-bound predictions, not a new end-to-end inference call.
All real MUTAA totals stay unresolved; no hidden stock is filled in by an SOP.

## Reproduce

With existing backend requirements and `PYTHONPATH=backend`:

```text
python scripts/intake_mutaa.py SOURCE NEW_REPORT_FOLDER
python scripts/audit_mutaa_baseline.py REPORT_FOLDER
python scripts/audit_mutaa_baseline.py REPORT_FOLDER --single image-13
python scripts/report_mutaa.py REPORT_FOLDER
python -m pytest backend/tests -q
```

The intake requires a new folder. Successful inference responses are reused on
rerun; failures can be retried. Reports are diagnostic derivatives. Re-running
the report overwrites derivatives, not originals/raw successful responses.
Local endpoint details and the SOP are in
[3D architecture](../../docs/3D_BEAM_COUNTING_ARCHITECTURE.md).

## Exact next step

Confirm physical per-stack totals, empty layers, hidden gaps and which photos
share an unchanged arrangement. Annotate whole faces/rims and shared corners
on these images. Evaluate localized high-resolution crops as a separate ablation
before deciding on retraining. Audit the existing 300+ training-image labels:
the broken-shell false positive and empty-tray class demonstrate why model class
semantics and negative examples matter. Do not start training merely to force
the known 100-tray answer. Keep this research set out of future held-out scoring.
