# Clean dataset gate

`scene-metadata.csv` is generated from the canonical manifest. Blank scene/count fields are intentional: no model prediction or filename heuristic is accepted as ground truth.

Before creating V3:

1. Assign a stable `scene_id` to every image.
2. Mark LEFT, RIGHT, STRAIGHT, or OTHER by human inspection.
3. Record independently counted scene and per-stack totals.
4. Move all views of one scene into the same split.
5. Review every cross-split candidate in `../01-dataset-audit/duplicate-report.csv`.
6. Lock the final acceptance scenes outside Roboflow training/version generation.
