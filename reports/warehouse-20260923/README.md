# Four-photo diagnostic audit

Originals supplied by the user, preserved under input/. Fresh Cloudflare/Roboflow
responses are upstream-1.json and upstream-2.json. API view slots were assigned
for diagnostic transport only: images 1/2/3, then 1/2/4. They are not calibrated
LEFT/STRAIGHT/RIGHT poses. Physical ground truth and unchanged arrangement have
not been confirmed. No accuracy percentage can be computed.

| Photo | Fresh model detections | Automatically proposed regions | Band candidates |
|---|---:|---:|---|
| 1 | 76 | 8 | 6, 4, 11, 11, 21, unresolved, 24, 5 |
| 2 | 87 | 7 | 10, 10, 10, 11, 4, 22, 5 |
| 3 | 19 | 1 | 16 |
| 4 | 19 | 1 | 18 |

The wide views visibly contain five stack fronts, but detection-box grouping
fragments them into 8/7 candidate regions. Consequently the bands are not five
independent stack counts and must not be summed. Photo 4 clips the top; the
side views occlude stacks behind the nearest face. No accepted correspondence
was produced by the local matcher. No calibrated 3D reconstruction or physical
total was obtained. The original-count discrepancy is unresolved, not repaired
by averaging or adding one.

Inspect image-N-overlay.jpg and image-N-analysis.json for the measured regions.
Next: correct stack-face localization (compare assisted face polygons against
automatic grouping), validate rim/egg-band semantics, obtain complete endpoint
views and confirmed per-stack filled/empty counts. Keep ground truth out of
inference inputs. Hosting alone does not fix this measurement failure.

Archive verification: downloaded photo 1 from the new private R2 archive and
verified SHA-256 bd2ba34e77d6cda94ed982d678590d9a5a0bde5a9b684dbaec0591ffa6ca0970
matches the original. The old historical phone scans were not recovered.
