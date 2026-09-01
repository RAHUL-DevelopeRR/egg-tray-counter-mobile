# Count error analysis

## Largest errors

| Image / view | Truth | Medium | Large | Dominant failure |
|---|---:|---:|---:|---|
| img01 / left | 60 | 9 | 3 | perspective-compressed side layers missed |
| img02 / right | 60 | 12 | 4 | close oblique layers missed |
| img08 / elevated | 46 | 73 | 87 | top surfaces and overlapping patterns counted as trays |
| img09 / distant | 76 | 25 | 42 | small/dark distant layers missed |
| img03 / straight | 60 | 93 | 88 | repeated visual patterns and duplicate-like detections |

## Error histogram

| Absolute-error bin | Medium | Large |
|---|---:|---:|
| 0 | 2 | 1 |
| 1–5 | 2 | 3 |
| 6–20 | 1 | 1 |
| 21–50 | 3 | 3 |
| >50 | 2 | 2 |

## Dominant causes

1. **Mixed annotation unit.** V2 contains at least one dense multi-stack image with one `egg_tray` box and another dense image with 159 individual boxes. The detector is being trained to predict incompatible objects.
2. **Viewpoint shift.** The same nominal 60-tray scene remains catastrophic: Medium `9 / 93 / 12`, Large `3 / 88 / 4` for left/straight/right.
3. **Scale and perspective.** Distant layers are missed while elevated top surfaces cause false positives. A single global confidence or NMS value cannot correct errors with opposite directions.

## Next evidence-based action

Review and relabel frozen V2 to one tight box per visible/countable tray layer, add scene/view/count metadata, then split by scene. Retrain Medium first as the controlled data-quality experiment. Only test higher resolution after corrected labels show that small-object recall remains the dominant error.
