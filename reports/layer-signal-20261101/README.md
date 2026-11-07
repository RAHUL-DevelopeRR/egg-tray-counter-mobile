# LayerSignal on the phone: offline parity (Plan 2, Phase K2) - 1 November 2026

**Verdict (measured): the pass bar fails and the plan's kill rule is met.**
- **Pitch.** A classical periodicity estimator on luminance finds the detector's layer pitch within 10% on only 58 of
  124 accepted columns (46.8%, against a bar of 90%).
- **Harmonics.** It reads half or double the pitch on 18 of 64 faces (28.1%), against the kill limit of 10%.
- **Frame edge.** It does not reliably show img-30's frame-cut bottom tray.

Per the plan (`C:\Users\rahul\.claude\plans\spicy-growing-flame.md`, K2: "kill it if half- or double-pitch answers
exceed 10% of faces"), the on-phone C4 / C5 / C7 gates should not be built on this estimator. Nothing was wired into
the app.

Plan: `C:\Users\rahul\.claude\plans\spicy-growing-flame.md`, section 1 "Phone-side engine (K2)" and section 3 "K2 / K3".
Development data only (see Caveats).

## What was built

| File | What it is |
|---|---|
| `mobile/lib/services/layer_signal.dart` | Pure-Dart estimator; see "Method" below. Not imported by any app code. |
| `mobile/test/layer_signal_test.dart` | 10 synthetic tests: sub-pixel pitch, run ends, top / bottom / side edge touches, a second block's pitch, harmonic rule, band, timing helper, JSON. |
| `mobile/test/layer_signal_on_registry_faces_test.dart` | Parity harness over the 72 registry faces. Asserts that every present photo is measured at the size the detector saw; prints and (with `LAYER_SIGNAL_OUT`) writes the pass-bar verdict. It does not assert the bar, which failed. |
| `mobile/test/fixtures/layer_signal_columns.json` | Detector columns for every face (below). |
| `make_columns.mjs` | Writes that fixture with the Worker's own column code. |
| `explore_variants.py` | Exploratory comparison of other classical pitch rules (table below). |
| `results.json`, `harness.txt` | The measured run: per face, per strip, per column, and the printed table. |

**Method of `layer_signal.dart`.**
- **Input.** A `LumaPlane` (width, height, bytes) and a band, by default the whole frame.
- **Strip profiles.** 16 vertical strips. Each gets a row profile of |Sobel-y|: the 3-tap blur convolved with the
  3-tap derivative, every 2nd pixel column. The profile is Gaussian-smoothed (sigma 1.2) and standardised with the
  median and MAD, as in the backend's `horizontal_structure_signal`.
- **Face pitch.** The mean of the strips' normalised autocorrelations goes through `estimate_pitch`: the shortest
  local maximum at least 0.72 of the strongest, with strength at least 0.08. The search range is 1%-15% of the band
  height, at least 8 px. A parabolic sub-pixel peak follows.
- **Strip pitch.** Each strip's own pitch is searched within 1/1.5 to 1.5 times the face pitch.
- **Periodic run.** In each strip, a run is the longest chain of rim peaks spaced one or two pitches apart, within
  0.28 of a pitch. A rim must have a prominence of at least 0.75, and at least 0.6 of the strip's six strongest rims
  (as `rim_count.py`). The run gives `top_y` and `base_y`.
- **Edge touches.** A strip touches the top or bottom edge when its outer rim is within one pitch of that edge, so
  the next rim would fall outside the frame. The first or last strip touches the side when it carries a run.
- **Outputs.** `pitch_frac` and `pitch_consistency` (the largest strip / face pitch ratio, at least 1).
- **Timing.** `timedLayerSignal` wraps the estimator in a Stopwatch.

## Inputs (as instructed)

- **Faces.** All 72 faces of `benchmarks/registry-20261101/manifest.json`; none was skipped, since the MUTAA
  originals in `C:\Users\rahul\MUTAA` were present.
- **Preparation.**
  - Faces with a `_sent` record (the 20 MUTAA views) went through `prepareCapturedStillSync`: EXIF-upright, resized
    to the sent size, JPEG quality 92, then decoded again. The harness asserts the prepared size equals the size
    the detector saw, and it matched for all 20.
  - The 7 Oct batch photos were used as raw pixels. Their originals carry no EXIF orientation, and their sizes equal
    the manifest's.
- **Luma.** Full resolution, 0.299 R + 0.587 G + 0.114 B, the same formula as `lumaFromImage`.
- **Detector columns** (`make_columns.mjs`, run on a dist build of `cloudflare-worker/src/index.ts` at dbcb19b,
  Worker 0.4.15):
  - **MUTAA.** The saved `stack_columns` from staging 0.4.12. All 81 match the rebuilt columns within 0.5 px of
    pitch.
  - **7 Oct batches.** These saved boxes only (`views.*.stack_columns` is absent), so their columns were rebuilt
    with the Worker's `spanColumns` from the saved boxes.
- **Accepted column.** The face passes `captureQuality` and `faceColumns` gives the column no retake reason, the same
  split the replay benchmark uses.
- **Counts.** 252 columns on 64 faces (8 faces have none); 124 accepted columns on 33 faces.
- **Mapping strips to columns.** A column's LayerSignal pitch is the median over the strips whose centre lies inside
  its x-range (else the most overlapping strip). Its top and base are the medians of those strips' run ends.

## Pass bar (measured)

| Bar (plan K2 / this task) | Measured | Met? |
|---|---|---|
| Pitch within ±10% of detector `pitch_px` on ≥ 90% of accepted columns | 58/124 (46.8%) | **No** |
| Half or double pitch on ≤ 10% of faces (kill rule) | 18/64 faces (28.1%): 17 half, 1 double; 30 "other" | **No: kill rule met** |
| Report: periodic top / base within half a pitch of `y_first` / `y_last` | top 20/117, base 8/117 accepted columns with a run (median offsets +1.58 and −6.11 pitches) | (report only) |
| img-30 and L-80 show the run touching the frame bottom | Neither (both touch the top, not the bottom) | **No** |

**Details.**
- **Accepted columns by class:** 58 within, 45 half, 4 double, 17 other.
- **All 252 columns:** 79 within, 74 half, 7 double, 89 other, 3 none.
- **Capture-accepted faces:** 12 within, 15 half, 10 other.
- **Face pitch on the img-30 photo:** 24.9 px against 41.5 px (img-30) and 44.5 px (L-80 straight). The pitch is
  wrong, so its runs are traced at the wrong spacing.

## Why it fails (measured on the strip autocorrelations)

The layer pitch is not the dominant vertical period of a tray face, so no "shortest strong lag" rule can find it.
- **Half pitch from edges.** On far faces (pitch about 20-27 px), |Sobel-y| gives two edges per layer, and the
  autocorrelation peaks at about p/2 above p. Example: img-01, a correct face read 99 = 99 by the detector, has
  R(10-11 px) = 0.60 against at most 0.45 at R(20-22 px) on its first column.
- **Double pitch from alternating trays.** In the signed gradient, the strongest peak is at about 2p on 80 of 124
  accepted columns. Stacked trays alternate orientation, so the clean period is a pair of trays: rim gaps alternate
  long and short. `reports/rim-count-20261009` (the end-pair rule) found the same.
- **Some close faces are clean, not all.** img-02, img-16, img-19 / L-100, img-22 and img-34 (pitch 32-43 px) read
  within 10% on almost every column. img-30 / L-80 straight (41-47 px), img-31 / L-80 left, img-47 and L-80 right
  (70-101 px) do not.
- **The cases the gates need are the failing ones.** C5 is about far faces, and img-30 itself is misread.

### Other classical rules (exploratory: `explore_variants.py`, chosen on these same photos, so optimistic)

The column figures use the detector's own x-range to choose the strips, which the phone does not have. The face
figures use all 16 strips, which is what the phone would see.

| profile | rule | accepted columns within 10% | half | double | faces half or double |
|---|---|---:|---:|---:|---:|
| abs (port) | first strong (port) | 49/124 (40%) | 46 | 6 | 17/64 (27%) |
| abs (port) | strongest | 45/124 (36%) | 40 | 19 | 18/64 (28%) |
| abs (port) | harmonic comb | 54/124 (44%) | 38 | 4 | 16/64 (25%) |
| signed | first strong (port) | 54/124 (44%) | 0 | 49 | 13/64 (20%) |
| signed | strongest | 24/124 (19%) | 0 | 80 | 18/64 (28%) |
| signed | harmonic comb | 85/124 (69%) | 20 | 5 | 10/64 (16%) |
| dark below | first strong (port) | 57/124 (46%) | 17 | 19 | 18/64 (28%) |
| dark below | strongest | 38/124 (31%) | 10 | 51 | 19/64 (30%) |
| dark below | harmonic comb | 67/124 (54%) | 16 | 13 | 13/64 (20%) |
| bright below | first strong (port) | 74/124 (60%) | 9 | 27 | 14/64 (22%) |
| bright below | strongest | 40/124 (32%) | 4 | 68 | 24/64 (38%) |
| bright below | harmonic comb | 86/124 (69%) | 2 | 13 | 9/64 (14%) |

**Reading the table.**
- The best rows reach 69% even with the detector's help, and 14% half or double faces. None meets the bar.
- Choosing one of these 12 rows on these photos would be tuning, so none was adopted.
- Two further checks, run once in scratch and not committed, also stayed below the bar:
  - restricting rows to the detector's own stack span: |Sobel-y| 43-55 of 124, signed comb 81 of 124;
  - averaging the profile across the whole column width before the autocorrelation.

## Gate by gate (what the measurements say about C4, C5, C7)

- **C4, frame margin.** The run's ends do not follow the stack ends.
  - Base within half a pitch of `y_last` on 8/117 columns; median −6.1 pitches.
  - Top within half a pitch of `y_first` on 20/117; median +1.6 pitches.
  - **Rim rule used here** (prominence ≥ 0.75 and ≥ 0.6 of the strip's strong rims): img-30 / L-80 do not touch the
    bottom, and 3 of 12 correct accepted faces "touch" the top (img-02, img-19, img-47).
  - **Earlier, looser rule** (prominence ≥ 0.75 only, measured the same day on the same photos): img-30 and L-80
    touched the bottom, but 5 of 12 correct faces touched an edge too, and synthetic noise above a stack extended
    runs to the frame top.
  - Neither rule separates cut from uncut faces. Background texture spaced about a pitch apart (other stacks, racks)
    extends runs, and the phone has no box to say which stack is the target.
- **C5, distance.** LayerSignal `pitch_frac` on the 12 correct accepted faces spans 0.013-0.040. W05 straight reads
  0.039 and W05 left 0.015. The ranges overlap completely, because of the harmonic errors.
- **C7, consistency.** The strip/face pitch ratio is 1.18-1.63 on the 12 correct faces, and above 1.2 on 64 of 72
  faces. A 1.2x gate would refuse nearly every photo.

## Timing (not the phone)

- **Measured.** `timedLayerSignal` in the `flutter test` VM on this laptop, at the sent size (at most 1600 px on the
  long side, column step 2): median 16.3 ms, max 38.4 ms per photo.
- **Unmeasured.** The phone's live plane is 1920 x 1080 (`ResolutionPreset.veryHigh`); the 720G cost is still
  unmeasured.

## Caveats

- **Development data.**
  - 10 of the 20 MUTAA views are re-encodes of labelled photos, so the same picture is counted twice.
  - img-08 / img-23, img-16 / img-22 and img-19 / L-100 are near-duplicates.
- **Image sources.** The 7 Oct photos are WhatsApp copies (0.2-1.9 MP), not phone captures. The MUTAA originals come
  from another phone at up to 8192 px.
- **The truth here is the detector's pitch, not physical truth.** The accepted columns are where span and walk
  counts agree, which is the most reliable detector pitch available.
- **The re-encode was made in Dart.** The MUTAA re-encodes were made with the app's own `prepareCapturedStillSync`.
  The staging upload was made the same way in size and quality, but not necessarily with the same resampler.

## Recommendation (for the user / main session; not done here)

1. **Stop the classical estimator.** Do not wire LayerSignal into `live_frame_preflight.dart` or
   `guided_capture_pane.dart`, and do not add C4, C5 or C7 phone checks on it.
2. **Use the detector-based doubts instead.** The phone side of C4, C5 and C7 is better served by the server's own
   doubts:
   - K1's `end_at_frame_edge`, which fires on img-30 and L-80 only;
   - `pitch_frac` from boxes;
   - `pitch_differs`.

   These reach the phone through Phase L's per-photo check (`POST /v1/views/check`): the same detector, so not
   independent, but correct on these faces.
3. **E is not affected.** The server pixel counter gets the column's x-range and the detector pitch as a prior, which
   is what lifts `rim_count.py` to 72% exact (`reports/rim-count-20261009`). Its harmonic checks (p/2, 2p) are the
   part these measurements bear on.

## Reproduce

```
# Fixture (any dist build of cloudflare-worker/src/index.ts; `npm run build` writes cloudflare-worker/dist)
node reports/layer-signal-20261101/make_columns.mjs --dist cloudflare-worker/dist/index.js
# Harness (Codex Flutter SDK), from mobile/
LAYER_SIGNAL_OUT=<results.json> LAYER_SIGNAL_PROFILES=<profiles.json> flutter test test/layer_signal_on_registry_faces_test.dart
# Variant table
python reports/layer-signal-20261101/explore_variants.py <profiles.json>
```
