# Stack face localization audit

Saved September 24 V2 detections replayed through the existing automatic
localizer. This known training scene has five assistant-reviewed approximate
face quadrilaterals. These are visual geometry references; the evaluation is
neither an independent test nor physical inventory certification.

| Measurement | Result |
|---|---|
| Reviewed faces | 5 |
| Proposed automatic faces | 8 |
| One-to-one matches at polygon IoU >= 0.50 | 3 |
| Mean IoU of matched faces | 0.6105 |
| Reviewed faces fragmented | 3: faces 1, 4, 5 |
| Proposed faces merging reviewed faces | 0 |
| Reviewed faces with no spatial association | 0 |
| Reviewed faces without accepted IoU match | 2: faces 1, 5 |

Fragment association means intersection divided by the smaller polygon area
is at least 0.50. It is deliberately separate from a successful whole-face
IoU match: a contained fragment can associate with a face yet fail its IoU
gate. Thresholds are declared geometry audit settings, not selected for count
accuracy. Spatial matching maximizes valid match cardinality before IoU.

`result.json` retains every polygon, the complete IoU and association matrices,
one-to-one mapping, fragments/merges, source hash and original-to-rectified
homographies for the reviewed faces. `spatial-mapping.jpg` overlays reviewed
faces in green (R) and automatic proposals in red (P). Manual rectification
remains a separate assisted stage; no localization model is trained from
unreviewed or nonexistent polygons. Counts were not inputs to localization.

Reproduce from repository root with installed OpenCV/NumPy/SciPy available:
`python scripts/evaluate_stack_localization.py --self-check`.

The solver module `app.vision.heatmap_sequence` enumerates pitch lattices from
heatmap spacing and retained band hypotheses. All y coordinates must use the
same rectified pixel space. It emits candidate/unresolved evidence, unknown
occupancy and verified=false. RF centres only annotate alignment. Missing
layers require independently reviewed layer-centre bands plus independently
observed endpoints or agreement with versioned calibrated height; raw bright
bands from analyze_rims do not assert those semantics. Unknown quality or
top/base prevents selected_count. No expected count enters inference.

Verification: eleven targeted synthetic solver cases pass. Spatial self-check
covers identity, fragmentation, merging and empty predictions. Saved replay
preserves the historical eight proposals. This does not prove real-scene
counting accuracy or endpoint reconstruction accuracy.
