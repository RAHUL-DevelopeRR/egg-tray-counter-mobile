# Independent rim count vs span count - 9 October 2026

Second, detector-independent layer count per stack column from horizontal rim edges in the
image (`backend/app/vision/rim_count.py`), compared with the production span count
(`layer_span.count_layers_by_span`) on the 13 straight-on labelled field photos
(1, 2, 4, 8, 9, 19, 20, 21, 23, 24, 30, 34, 50). Produced by `scripts/evaluate_rim_count.py`.

**Read this first.** The thresholds below were chosen by sweeping them on these same 13
photos and picking the best catch/false-alarm trade-off. This is tuning, not validation;
the numbers are optimistic for new photos. All 13 are WhatsApp copies (0.2-1.9 MP, no EXIF,
chroma-subsampled); originals captured in the field carry more detail per layer, which should
help the edge signal but has not been measured.

## Inputs

- Detector boxes: archived production responses `reports/field-labelled-20261007/raw/batch-*.json`
  (Roboflow projec-mutta/2), regrouped into columns with `count_layers_by_span` (same code as
  the Worker port). The rim count uses only each column's x-extent, y-extent and detector pitch
  as a prior; it never counts boxes.
- Reference: `per_stack_counts.csv` column `assistant_count` (per-stack values inferred from the
  user's scene totals plus visual inspection on 2026-10-08, not physical recounts). Columns of
  images 4, 9 and 50 have no reference (multi-depth scenes, close-up perspective) and are
  listed in results.csv but excluded from the scores.

## Method (as implemented)

- Strip = column widened by 10 %; signal = Sobel-Y of the gray channel, polarity `dark_below`
  (bright-to-dark going down = rim underside / egg-to-tray edge), reduced across the central
  60% of the strip by `mean`, Gaussian-smoothed with sigma =
  0.16 x pitch, robustly normalised (median/MAD).
- Search window: y_first - 1.0 x pitch to y_last + 1.0 x pitch.
- Candidate peaks need prominence >= 0.6 x a reference prominence: the
  median of the six strongest peaks within +/-3 pitches of the candidate (local_prominence =
  True), floored at a quarter of the strip-wide strong-peak median. A
  strip-wide threshold loses the perspective-compressed layers at the far end of a column.
- Peaks are accepted top to bottom with a minimum distance of 0.6 x the
  local pitch; the local pitch starts at the detector pitch and follows the running median of
  the last three accepted gaps, each gap first divided by its rounded multiple of the current
  local pitch so one missed rim cannot drag the tracker onto double pitch (clamped to
  0.5-1.6 x detector pitch).
- A gap of about two local pitches counts as one inferred (missed) rim: infer_missing = True.
- End rule: stacked trays alternate orientation, so consecutive gaps alternate long/short while
  each pair of gaps still spans two pitches; when the pair of gaps at a stack end is shorter
  than 0.75 x the next pair, the weaker of the two end peaks is dropped (an
  extra half-pitch edge from the floor, a pallet or the row of eggs behind).
- confidence = 0.6 x regularity of gap-pair sums + 0.4 x relative prominence - 0.15 per
  inferred rim. It is a diagnostic score, not a probability.
- perspective_gradient = median of the top-third gaps / median of the bottom-third gaps.

Parameters (`RimParams` defaults):

```json
{
  "widen_fraction": 0.1,
  "core_fraction": 0.6,
  "window_fraction": 1.0,
  "smooth_fraction": 0.16,
  "min_distance_fraction": 0.6,
  "prominence_fraction": 0.6,
  "channel": "gray",
  "polarity": "dark_below",
  "aggregate": "mean",
  "infer_missing": true,
  "pitch_clamp": [
    0.5,
    1.6
  ],
  "local_prominence": true,
  "end_pair_ratio": 0.75
}
```

## Results (measured on this set; same set as the tuning)

Columns: 66 in 13 photos; 53 with a reference; 13 without; rim_count None on 0.

| Per column vs reference | exact | within +/-1 |
|---|---:|---:|
| rim_count | 38/53 (72%) | 47/53 (89%) |
| span_count | 40/53 (75%) | 53/53 (100%) |

Key numbers (disagreement = rim_count != span_count):

- span WRONG vs reference: 13 columns; rim disagrees with span (caught) on **11/13 (85%)**, and gives the reference value on 7 of them.
- span RIGHT vs reference: 40 columns; rim wrongly disagrees (false alarm) on **9/40 (22%)**.
- Restricted to confidence >= 0.6 (7 columns): rim exact 6/7 (86%), caught 1/1, false alarms 1/6.

Per column (reference blank = unresolved stack):

| image | col | reference | span | rim | agrees | confidence | gradient | inferred | note |
|---:|---:|---:|---:|---:|:---:|---:|---:|---:|---|
| 1 | 1 | 20 | 21 | 18 | no | 0.0 | 0.648 | 5 | edge-peak count; diagnostic only, not a verified layer count; 5 rim(s) inferred from double-pitch gaps |
| 1 | 2 | 20 | 20 | 18 | no | 0.0 | 0.653 | 5 | edge-peak count; diagnostic only, not a verified layer count; 5 rim(s) inferred from double-pitch gaps |
| 1 | 3 | 20 | 20 | 21 | no | 0.0 | 0.681 | 6 | edge-peak count; diagnostic only, not a verified layer count; 6 rim(s) inferred from double-pitch gaps |
| 1 | 4 | 20 | 20 | 20 | yes | 0.0 | 0.712 | 6 | edge-peak count; diagnostic only, not a verified layer count; 6 rim(s) inferred from double-pitch gaps |
| 1 | 5 | 19 | 19 | 19 | yes | 0.073 | 0.857 | 5 | edge-peak count; diagnostic only, not a verified layer count; 5 rim(s) inferred from double-pitch gaps |
| 2 | 1 | 20 | 21 | 20 | no | 0.314 | 0.658 | 3 | edge-peak count; diagnostic only, not a verified layer count; 3 rim(s) inferred from double-pitch gaps |
| 2 | 2 | 20 | 20 | 20 | yes | 0.267 | 0.593 | 4 | edge-peak count; diagnostic only, not a verified layer count; 4 rim(s) inferred from double-pitch gaps |
| 2 | 3 | 20 | 20 | 20 | yes | 0.266 | 0.58 | 4 | edge-peak count; diagnostic only, not a verified layer count; 4 rim(s) inferred from double-pitch gaps |
| 2 | 4 | 20 | 20 | 20 | yes | 0.638 | 1.244 | 1 | edge-peak count; diagnostic only, not a verified layer count; 1 rim(s) inferred from double-pitch gaps |
| 4 | 1 |  | 17 | 20 | no | 0.431 | 1.087 | 3 | edge-peak count; diagnostic only, not a verified layer count; 3 rim(s) inferred from double-pitch gaps |
| 4 | 2 |  | 18 | 20 | no | 0.834 | 1.047 | 0 | edge-peak count; diagnostic only, not a verified layer count |
| 4 | 3 |  | 21 | 22 | no | 0.355 | 0.917 | 3 | edge-peak count; diagnostic only, not a verified layer count; 3 rim(s) inferred from double-pitch gaps |
| 4 | 4 |  | 18 | 20 | no | 0.607 | 0.963 | 2 | edge-peak count; diagnostic only, not a verified layer count; 2 rim(s) inferred from double-pitch gaps |
| 4 | 5 |  | 18 | 20 | no | 0.0 | 0.562 | 8 | edge-peak count; diagnostic only, not a verified layer count; 8 rim(s) inferred from double-pitch gaps |
| 4 | 6 |  | 19 | 20 | no | 0.0 | 0.587 | 8 | edge-peak count; diagnostic only, not a verified layer count; 8 rim(s) inferred from double-pitch gaps |
| 8 | 1 | 20 | 20 | 20 | yes | 0.242 | 0.659 | 4 | edge-peak count; diagnostic only, not a verified layer count; 4 rim(s) inferred from double-pitch gaps |
| 8 | 2 | 20 | 20 | 20 | yes | 0.136 | 0.511 | 4 | edge-peak count; diagnostic only, not a verified layer count; 4 rim(s) inferred from double-pitch gaps |
| 8 | 3 | 20 | 20 | 20 | yes | 0.235 | 0.839 | 4 | edge-peak count; diagnostic only, not a verified layer count; 4 rim(s) inferred from double-pitch gaps |
| 8 | 4 | 20 | 20 | 20 | yes | 0.147 | 1.286 | 5 | edge-peak count; diagnostic only, not a verified layer count; 5 rim(s) inferred from double-pitch gaps |
| 8 | 5 | 20 | 20 | 20 | yes | 0.037 | 0.607 | 6 | edge-peak count; diagnostic only, not a verified layer count; 6 rim(s) inferred from double-pitch gaps |
| 8 | 6 | 20 | 19 | 20 | no | 0.0 | 0.622 | 6 | edge-peak count; diagnostic only, not a verified layer count; 6 rim(s) inferred from double-pitch gaps |
| 8 | 7 | 20 | 20 | 20 | yes | 0.41 | 1.0 | 3 | edge-peak count; diagnostic only, not a verified layer count; 3 rim(s) inferred from double-pitch gaps |
| 8 | 8 | 20 | 19 | 19 | yes | 0.0 | 0.598 | 6 | edge-peak count; diagnostic only, not a verified layer count; 6 rim(s) inferred from double-pitch gaps |
| 9 | 1 |  | 18 | 11 | no | 0.84 | 1.38 | 0 | edge-peak count; diagnostic only, not a verified layer count |
| 9 | 2 |  | 7 | 7 | yes | 0.695 | 0.512 | 1 | edge-peak count; diagnostic only, not a verified layer count; 1 rim(s) inferred from double-pitch gaps |
| 9 | 3 |  | 17 | 19 | no | 0.0 | 0.795 | 8 | edge-peak count; diagnostic only, not a verified layer count; 8 rim(s) inferred from double-pitch gaps |
| 9 | 4 |  | 17 | 14 | no | 0.762 | 0.77 | 0 | edge-peak count; diagnostic only, not a verified layer count |
| 9 | 5 |  | 15 | 18 | no | 0.0 | 0.787 | 7 | edge-peak count; diagnostic only, not a verified layer count; 7 rim(s) inferred from double-pitch gaps |
| 19 | 1 | 20 | 20 | 20 | yes | 0.108 | 0.669 | 5 | edge-peak count; diagnostic only, not a verified layer count; 5 rim(s) inferred from double-pitch gaps |
| 19 | 2 | 20 | 20 | 19 | no | 0.18 | 1.062 | 4 | edge-peak count; diagnostic only, not a verified layer count; 4 rim(s) inferred from double-pitch gaps |
| 19 | 3 | 20 | 20 | 21 | no | 0.617 | 1.127 | 2 | edge-peak count; diagnostic only, not a verified layer count; 2 rim(s) inferred from double-pitch gaps |
| 19 | 4 | 20 | 20 | 21 | no | 0.594 | 1.103 | 2 | edge-peak count; diagnostic only, not a verified layer count; 2 rim(s) inferred from double-pitch gaps |
| 19 | 5 | 20 | 20 | 20 | yes | 0.237 | 0.635 | 4 | edge-peak count; diagnostic only, not a verified layer count; 4 rim(s) inferred from double-pitch gaps |
| 20 | 1 | 20 | 20 | 20 | yes | 0.118 | 0.624 | 5 | edge-peak count; diagnostic only, not a verified layer count; 5 rim(s) inferred from double-pitch gaps |
| 20 | 2 | 20 | 20 | 20 | yes | 0.512 | 1.0 | 2 | edge-peak count; diagnostic only, not a verified layer count; 2 rim(s) inferred from double-pitch gaps |
| 20 | 3 | 20 | 21 | 20 | no | 0.512 | 1.042 | 2 | edge-peak count; diagnostic only, not a verified layer count; 2 rim(s) inferred from double-pitch gaps |
| 21 | 1 | 20 | 20 | 20 | yes | 0.0 | 0.612 | 6 | edge-peak count; diagnostic only, not a verified layer count; 6 rim(s) inferred from double-pitch gaps |
| 21 | 2 | 20 | 20 | 20 | yes | 0.0 | 0.606 | 6 | edge-peak count; diagnostic only, not a verified layer count; 6 rim(s) inferred from double-pitch gaps |
| 21 | 3 | 20 | 20 | 19 | no | 0.005 | 1.189 | 4 | edge-peak count; diagnostic only, not a verified layer count; 4 rim(s) inferred from double-pitch gaps |
| 21 | 4 | 20 | 20 | 27 | no | 0.0 | 0.676 | 11 | edge-peak count; diagnostic only, not a verified layer count; 11 rim(s) inferred from double-pitch gaps |
| 21 | 5 | 20 | 20 | 20 | yes | 0.402 | 1.286 | 2 | edge-peak count; diagnostic only, not a verified layer count; 2 rim(s) inferred from double-pitch gaps |
| 23 | 1 | 20 | 20 | 20 | yes | 0.242 | 0.659 | 4 | edge-peak count; diagnostic only, not a verified layer count; 4 rim(s) inferred from double-pitch gaps |
| 23 | 2 | 20 | 20 | 20 | yes | 0.359 | 0.857 | 3 | edge-peak count; diagnostic only, not a verified layer count; 3 rim(s) inferred from double-pitch gaps |
| 23 | 3 | 20 | 20 | 20 | yes | 0.109 | 0.635 | 5 | edge-peak count; diagnostic only, not a verified layer count; 5 rim(s) inferred from double-pitch gaps |
| 23 | 4 | 20 | 19 | 20 | no | 0.015 | 0.624 | 6 | edge-peak count; diagnostic only, not a verified layer count; 6 rim(s) inferred from double-pitch gaps |
| 23 | 5 | 20 | 20 | 20 | yes | 0.037 | 0.607 | 6 | edge-peak count; diagnostic only, not a verified layer count; 6 rim(s) inferred from double-pitch gaps |
| 23 | 6 | 20 | 19 | 20 | no | 0.0 | 0.629 | 6 | edge-peak count; diagnostic only, not a verified layer count; 6 rim(s) inferred from double-pitch gaps |
| 23 | 7 | 20 | 20 | 20 | yes | 0.41 | 1.0 | 3 | edge-peak count; diagnostic only, not a verified layer count; 3 rim(s) inferred from double-pitch gaps |
| 23 | 8 | 20 | 20 | 19 | no | 0.231 | 0.598 | 4 | edge-peak count; diagnostic only, not a verified layer count; 4 rim(s) inferred from double-pitch gaps |
| 24 | 1 | 20 | 20 | 20 | yes | 0.0 | 0.615 | 6 | edge-peak count; diagnostic only, not a verified layer count; 6 rim(s) inferred from double-pitch gaps |
| 24 | 2 | 20 | 20 | 20 | yes | 0.0 | 0.606 | 6 | edge-peak count; diagnostic only, not a verified layer count; 6 rim(s) inferred from double-pitch gaps |
| 24 | 3 | 20 | 19 | 20 | no | 0.042 | 0.95 | 4 | edge-peak count; diagnostic only, not a verified layer count; 4 rim(s) inferred from double-pitch gaps |
| 24 | 4 | 20 | 20 | 27 | no | 0.0 | 0.686 | 11 | edge-peak count; diagnostic only, not a verified layer count; 11 rim(s) inferred from double-pitch gaps |
| 24 | 5 | 20 | 21 | 22 | no | 0.132 | 0.897 | 4 | edge-peak count; diagnostic only, not a verified layer count; 4 rim(s) inferred from double-pitch gaps |
| 30 | 1 | 20 | 20 | 20 | yes | 0.0 | 0.644 | 7 | edge-peak count; diagnostic only, not a verified layer count; 7 rim(s) inferred from double-pitch gaps; search window touches the image border |
| 30 | 2 | 20 | 19 | 19 | yes | 0.11 | 0.662 | 5 | edge-peak count; diagnostic only, not a verified layer count; 5 rim(s) inferred from double-pitch gaps |
| 30 | 3 | 20 | 21 | 19 | no | 0.131 | 0.724 | 5 | edge-peak count; diagnostic only, not a verified layer count; 5 rim(s) inferred from double-pitch gaps; search window touches the image border |
| 30 | 4 | 20 | 19 | 17 | no | 0.277 | 0.651 | 4 | edge-peak count; diagnostic only, not a verified layer count; 4 rim(s) inferred from double-pitch gaps; search window touches the image border |
| 34 | 1 | 20 | 20 | 20 | yes | 0.513 | 1.067 | 2 | edge-peak count; diagnostic only, not a verified layer count; 2 rim(s) inferred from double-pitch gaps |
| 34 | 2 | 20 | 20 | 20 | yes | 0.846 | 1.243 | 0 | edge-peak count; diagnostic only, not a verified layer count |
| 34 | 3 | 20 | 21 | 20 | no | 0.713 | 1.012 | 1 | edge-peak count; diagnostic only, not a verified layer count; 1 rim(s) inferred from double-pitch gaps |
| 34 | 4 | 20 | 20 | 20 | yes | 0.842 | 1.216 | 0 | edge-peak count; diagnostic only, not a verified layer count |
| 34 | 5 | 20 | 20 | 20 | yes | 0.661 | 1.047 | 1 | edge-peak count; diagnostic only, not a verified layer count; 1 rim(s) inferred from double-pitch gaps |
| 34 | 6 | 20 | 20 | 20 | yes | 0.783 | 1.282 | 0 | edge-peak count; diagnostic only, not a verified layer count |
| 50 | 1 |  | 17 | 16 | no | 0.188 | 1.084 | 4 | edge-peak count; diagnostic only, not a verified layer count; 4 rim(s) inferred from double-pitch gaps |
| 50 | 2 |  | 18 | 21 | no | 0.0 | 1.0 | 8 | edge-peak count; diagnostic only, not a verified layer count; 8 rim(s) inferred from double-pitch gaps |

## Reading the result

- A disagreement is a flag to rescan or count by hand, not a corrected count. Neither number
  is verified; `verified` stays false everywhere.
- Where span is wrong because the layer is physically outside the photo (crop cuts the base or
  the top), the rim count cannot see it either; those columns stay agreeing and wrong.
- Columns whose strip overlaps a neighbouring stack at a different depth carry mixed rims; the
  overlays (`overlays/img-NN.png`: orange = strip and search window, red = accepted rims,
  label green = agrees, red = disagrees) show where this happens.
- Images 21 and 24 are 582 px tall with a 19 px pitch; the bottom layers lose their edge in the
  WhatsApp copy and are filled by inferred rims with low confidence.

## What was tried and rejected (same set)

- Green channel instead of gray: consistently worse (WhatsApp chroma subsampling halves the
  vertical chroma resolution). Bright-to-dark-below polarity beats the opposite polarity and the
  absolute edge signal (two edges per layer, the half-pitch trap).
- Per-row median or edge-support fraction across the strip instead of the mean: no gain.
- A strip-wide prominence threshold: loses the compressed far end of perspective columns.
- Peak height above the baseline, or height over the deeper adjacent trough, instead of
  prominence: both much worse (baseline drift along the strip; distant bases inflate weak
  peaks). Prominence keeps a known bias against the last rim when the floor below is flat.
- Running median of raw gaps for the local pitch: one missed rim drags the tracker to double
  pitch and every second rim is then skipped; dividing each gap by its rounded multiple fixed it.
- Before the local threshold and the end rule the best setting reached 30/53 exact with 16/40
  false alarms; after them 38/53 with 9/40 (measured, same set).

## Expectations (not measured)

- Field originals (full resolution, no chroma subsampling, no re-encode) should give sharper rim
  edges and fewer inferred rims; the min-distance and prominence thresholds are relative to the
  pitch and the strip's own signal, so they should transfer, but this has to be measured on the
  first field set before any threshold is trusted.
- Held-out validation is required before using the disagreement flag to withhold totals.

Files: `results.csv` (one row per column), `overlays/` (one PNG per photo).
