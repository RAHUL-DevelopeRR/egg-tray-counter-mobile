# Failure analysis

| Pattern | Evidence | Required data/action |
|---|---|---|
| Side/oblique undercount | same 60-tray scene: 9 and 12 | many more left/right scenes; consistent partial-layer boxes |
| Straight-view overcount | same scene: 93 for truth 60 | review duplicate/large boxes and hard-negative top surfaces |
| Dense straight success | 120 → 124 | preserve this geometry but fix four duplicate false positives |
| Elevated-angle overcount | 46 → 73 | elevated-view examples and top-surface hard negatives |
| Distant/dark undercount | 76 → 25 | high-resolution distant images and controlled exposure augmentation |
| Exact medium/small cases | 21 → 21 and 1 → 1 | retain as controls; do not optimize only easy images |

The failure direction changes with viewpoint, so a global multiplicative calibration cannot solve it. The raw and backend counts match, excluding Cloudflare and Flutter as the primary source.
