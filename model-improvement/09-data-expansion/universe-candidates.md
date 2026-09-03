# Roboflow Universe candidates

Discovery date: 2026-09-03. This is Phase 2 discovery only: **no project was forked, downloaded, uploaded, or added to training**. Real LEFT/STRAIGHT/RIGHT warehouse capture remains the primary recommendation; external images are supplementary.

Searches covered `egg tray`, `stacked egg tray`, and `repeated object counting trays`. License text and image counts were verified on each linked Universe project page. A missing license is treated as all rights reserved.

## Full candidate list

| Project / workspace | License shown verbatim | Images | Task and classes | Visual similarity | Decision |
|---|---|---:|---|---|---|
| [Egg Tray Count / Innova8s](https://universe.roboflow.com/innova8s/egg-tray-count) | No license listed | 134 | Object detection: `egg_tray` | **Yes** — previews include warehouse stacks, side rails, and full trays | Exclude: closest visual match, but training rights are not granted |
| [Egg-Tray-Counter / dharaneesh-k-dhqik](https://universe.roboflow.com/dharaneesh-k-dhqik/egg-tray-counter) | CC BY 4.0 | 70 | Object detection: `Egg-Tray-Counter` | **Yes** — green warehouse tray stacks closely match production | Phase 3 candidate; high duplicate/leakage risk against `projec-mutta` and the golden benchmark |
| [Egg tray classification V2 / Despaletizador Cajas](https://universe.roboflow.com/dat-boi-43ejk/egg-tray-classification-v2) | CC BY 4.0 | 100 | Classification: `orientation_nok`, `orientation_ok` | **Unsure** — useful close side-rail views, but little warehouse context and no detection annotations | Phase 3 candidate; requires complete manual detection annotation |
| [EggTray / Public Workspace](https://universe.roboflow.com/public-workspace-pw2uu/eggtray) | Public Domain | 68 | Object detection: `Egg-Tray` | **Unsure** — blurred industrial side views and horizontal boxes; tray identity/granularity need review | Phase 3 candidate; reject any non-tray or aggregate-box images |
| [Project MF EPS / BEERKK](https://universe.roboflow.com/beerkk/project-mf-eps) | Public Domain | 200 | Object detection: `Egg tray`, `Foam`, `MF-EPS` | **Unsure** — mixed foam/manufacturing imagery; only some images may contain relevant tray faces | Phase 3 candidate for a small manually selected subset only |
| [Egg Tray Segmentation / LJ](https://universe.roboflow.com/lj-s4yqm/egg-tray-segmentation) | CC BY 4.0 | 371 | Semantic segmentation: `tray` | **No** — previews are top-down single empty trays on a chair | Exclude: lacks stacked side-rail geometry |
| [Egg Tray Segmentation2 / LJ](https://universe.roboflow.com/lj-s4yqm/egg-tray-segmentation2) | CC BY 4.0 | 311 | Semantic segmentation: `tray` | **No** — same single-tray/top-down capture family | Exclude: wrong geometry and annotation unit |
| [Egg Tray Pose / LJ](https://universe.roboflow.com/lj-s4yqm/egg-tray-pose) | CC BY 4.0 | 110 | Keypoint detection: `tray` | **No** — pose-oriented single trays rather than stacks | Exclude: wrong task and geometry |
| [Egg Tray Detection / Thesis](https://universe.roboflow.com/thesis-57aqe/egg-tray-detection) | CC BY 4.0 | 345 | Object detection: `Fertile`, `Infertile` | **No** — labels individual egg condition, not physical tray faces | Exclude: taxonomy would reintroduce the wrong counting unit |
| [Trays / Mahe](https://universe.roboflow.com/mahe/trays-4pjtd) | CC BY 4.0 | 104 | Object detection: `tray` | **No** — previews show fish/food trays | Exclude: unrelated object domain |

## License-safe Phase 3 shortlist

These projects have an allowed license and at least some potentially relevant images. License safety does **not** mean annotation safety; every selected image still needs human acceptance and normalization to the single active class.

| Priority | Project | Maximum source images | Required gate before use |
|---:|---|---:|---|
| 1 | [Egg-Tray-Counter](https://universe.roboflow.com/dharaneesh-k-dhqik/egg-tray-counter) | 70 | Perceptual-hash and filename deduplication against all V2/V3 and 10 benchmark images; then one-box-per-visible-face review |
| 2 | [Egg tray classification V2](https://universe.roboflow.com/dat-boi-43ejk/egg-tray-classification-v2) | 100 | Select only clear stack-side images; create all detection boxes manually because source labels are classifications |
| 3 | [EggTray](https://universe.roboflow.com/public-workspace-pw2uu/eggtray) | 68 | Verify each image is an egg tray, reject blur/clipping, and replace aggregate or rail-fragment boxes |
| 4 | [Project MF EPS](https://universe.roboflow.com/beerkk/project-mf-eps) | 200 | Select only clear egg-tray stack faces; discard foam/material-only images and normalize the class |

Do not use the full 438 images automatically. Phase 3 should first build a small review queue from visually plausible images, with `ready_for_training=false` by default and explicit checks for clipping, guessed occluded extents, duplicate/leakage, and annotation granularity.

## Exclusions summary

- Innova8s is excluded despite the best visual match because no license is displayed.
- LJ's three projects, Thesis, and Mahe are license-safe but excluded because their imagery or label unit conflicts with stack-face counting.
- Generic repeated-object-counting datasets returned by the search were not candidates: they contained unrelated fish trays, parts, fruit, maritime objects, or pallets and cannot teach egg-tray rail geometry.
