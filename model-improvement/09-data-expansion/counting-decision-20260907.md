# Counting decision and fresh source search — 2026-09-07

## Requirement clarified

The final count unit is ONE INDIVIDUAL PHYSICAL 5x6 / 30-cell TRAY inside a stack. A stack is the arrangement, not the count unit. Six stacks of twenty trays equal 120 trays, not six trays. Multiplication by 30 gives egg capacity; it gives actual egg quantity only when every tray is full.

The earlier explanation conflated the final count with an intermediate stack-face detection. Both approaches are possible, but their labels and evaluation must remain distinct:

- Direct detector: one annotation per visible individual tray layer, including trays within a stack. A standalone top-down tray is not representative training coverage for dense stacked layers.
- Two-stage system: one stack-face region, followed by a separately validated individual-layer counter. The region count is NEVER the tray count.

Do not rename legacy tray-layer labels into stack-face labels or combine the three new stack-face annotations with legacy layer labels under one target. Today's clarification does not make those three face boxes individual-layer ground truth. Keep them isolated. No annotations, frozen versions, model settings or deployments were changed during this research turn.

## Search performed

Queried Roboflow Universe through its API using `stacked plastic 30 egg trays warehouse`, `egg tray`, and `eggtray`. The long query returned many unrelated results; the shorter queries found relevant projects. Also searched the public web and image index for stacked orange 30-cell trays. Agent Reach's prescribed Exa CLI was unavailable on PATH, so the available web search and dedicated Roboflow API were used. This was keyword/visual-description search, not an upload of the user's warehouse photos to Google Lens.

| Source | Fresh result | Intake decision |
|---|---|---|
| [DuraPlas egg transport system](https://duraplasinc.com/en/agriculture/poultry-egg/egg-transport-system) | Image search returned industrial orange and blue loaded tray stacks | Relevant image-source lead; training-use permission and exact annotations are not established |
| [EggCartons orange plastic trays](https://www.eggcartons.com/products/plastic-egg-tray-orange) | Matching 30-cell / 5x6 product family and stacked/side-view pictures | Product reference, not a verified warehouse count dataset; usage rights unverified |
| [Innova8s / egg-tray-count](https://universe.roboflow.com/innova8s/egg-tray-count) | 134 images; egg_tray detection; API license null | Do not import pending permission/license verification; earlier project audit found visually relevant stacks |
| [dharaneesh-k-dhqik / egg-tray-counter](https://universe.roboflow.com/dharaneesh-k-dhqik/egg-tray-counter) | 70 images; CC BY 4.0 | Known shared-source risk: exclude benchmark matches and existing-training duplicates before any intake; no fork performed |
| [public-workspace-pw2uu / eggtray](https://universe.roboflow.com/public-workspace-pw2uu/eggtray) | 68 images; Public Domain | Candidate only; no newly completed per-image review or accepted labels |
| [dat-boi-43ejk / egg-tray-classification-v2](https://universe.roboflow.com/dat-boi-43ejk/egg-tray-classification-v2) | 100 images; CC BY 4.0; orientation classification | Requires detection labels from scratch and domain QA; source classification labels cannot train exact tray counting |

Direct web opening of the source preview image URLs failed; do not claim fresh full-resolution visual/annotation review from metadata alone. The earlier `universe-candidates.md` contains the prior visual-screening findings. This turn discovered/referenced sources, not a newly scraped, labeled training set. No external images were accepted into training and no training credits were spent.

## Why additional training is not a guarantee

Two scenes can expose the same front surfaces while containing different hidden trays behind them. No photo-only method can distinguish such cases without more views or recorded quantities. Repeated angles also share errors: agreement is a consistency check, not proof of a correct count. Matching the 5x6 product geometry does not supply visible layer boundaries, physical totals, capture diversity, or leakage-safe test scenes.

Last completed historical ten-file benchmark: deployed V2 Medium 2/10 exact, MAE 22.9; V3 Medium 2/10 exact, MAE 20.7, DO NOT DEPLOY. The three new manual-ROI layer checks yielded rejection/12/11 for visually counted 7/20/20 foreground trays. That is 0/3 exact in development, not a held-out estimate. Training a better stack detector alone cannot repair those layer-counter failures.

## Practical alternatives without ML

1. **Recommended: counted batches plus barcode/QR inventory.** Physically count a stack when it is formed or received, record its quantity against a unique stack ID, and scan receipts, transfers and dispatches. Standard-size stacks simplify this; record partial stacks explicitly. Correct opening stock, complete movements, duplicate-event prevention and periodic physical reconciliation remain necessary. A QR label stores/retrieves a count; it does not measure the contents.
2. **Automatic counting at a controlled handling station.** Pass trays individually through a sensor-controlled lane before stacking and use the counter to establish batch quantities. Requires suitable spacing, direction/jam handling, commissioning and periodic checks; it is not a magic counter for an already occluded pile. [A published egg-stacking design](https://patents.google.com/patent/CN115180418A/en) describes photoelectric counting of passing trays; that design concerns tray manufacturing, not a validated installation for this warehouse.
3. **Photo-assisted manual counting.** An operator marks each visible tray boundary, with a second count/check for disputed stacks. Software can number marks and keep an audit photo without any trained model. Hidden layers still require another view or physical access. This mode is a proposal, not an implemented APK feature.
4. **Controlled classical vision.** A fixed stand, consistent lighting and one completely visible stack can support calibrated rail/edge counting without ML. Current OpenCV code does not yet pass its development cases, so no accuracy promise or deployment is justified. Loaded and nested-empty stacks must not share an assumed pitch. Counting by weight is likewise not exact for mixed egg sizes/fill levels.

Existing software to assess: [Odoo Barcode](https://www.odoo.com/documentation/18.0/applications/inventory_and_mrp/barcode.html) tracks product/package movements; [Odoo Packages](https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/inventory/product_management/configure/package.html) records package contents; [Ovotrack](https://ovotrack.com/egg-processing-modules/) provides egg-industry traceability, barcode receiving and stock-location management. These maintain recorded quantities rather than count concealed trays from photographs. No software was purchased or integrated.

## Decision

Do not run open-ended training to chase a guaranteed 100%. For an operational rollout, prefer audited count-at-entry inventory, with vision as an optional cross-check. A vision-only pilot should first fix the tray-layer target, annotate the real warehouse images, reserve separate physical arrangements for evaluation, and measure exact count, MAE, false acceptances and rejection/coverage together. RF-DETR Medium remains the requested architecture if a valid training dataset passes review; no Large run is authorized. Existing deployment remains untouched.
