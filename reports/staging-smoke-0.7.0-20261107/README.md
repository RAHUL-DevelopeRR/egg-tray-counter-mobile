# Staging smoke test of Worker 0.7.0 from the Redmi (7 Nov 2026)

**Setup (measured).** Redmi Note 9 Pro (`f76d5e20`), app 0.7.0+31; staging `egg-tray-counter-api-staging`,
Cloudflare version `bafa21d1` (worker-0.7.0, source `748c5ea`), deployed the same morning. Gallery path (testing
only), the two photo sets already on the phone (`/sdcard/Pictures/EggTrayTest/`), declaration skipped, "same
stacks" ticked. 2 scans, **6 paid detector calls**. Gallery scans switched off again afterwards.

The 4 × 3 field block was not scanned: its original photos are not in the repo (only the replay answer), and the
phone's own camera gallery is not opened.

## Results

| Set | Phone result | Replay prediction (`reports/stacking-rule-0.7.0-20261105`) | Match |
|---|---|---|---|
| 99-tray row (img-01 / warehouse image-4 / img-32) | BLOCK ESTIMATE 99, 5 × 1, stacks 20/20/20/20/19, "Counted 99 + Assumed 0", corner note STRAIGHT 20 vs LEFT 19. Processing 5,404 ms. | `estimated` 99, one deep, rule not used | yes |
| L-100 (img-19 / img-21 / img-24) | RETAKE NEEDED, no total. Reasons: LEFT and RIGHT repeat the front; new in 0.7.0: "no full height for the hidden stacks: the stacking rule needs two stacks read cleanly at one height on two different faces, one of them a back corner" (`no_rule_height`). Per-photo detections 103 / 100 / 101. Processing 1,217 ms. | withheld in all modes | yes |

**Proof the phone reached Worker 0.7.0:** both results carry the 0.7.0 block note ("Hidden stacks are set to the
block's full height by the farm's stacking rule…"), which no earlier Worker emits, and L-100 carries the
`no_rule_height` reason that exists only in 0.7.0.

**What this does not show.** No deep block with hidden stacks was scanned, so no "=H by the stacking rule" total was
produced live yet; that needs a camera scan of a real deep block (farm day A). Nothing here is a physical count.

Screens: `01-row99-estimate.png`, `02-row99-rule-note.png`, `03-L100-withheld.png`, `04-L100-per-photo.png`,
`05-history.png`.
