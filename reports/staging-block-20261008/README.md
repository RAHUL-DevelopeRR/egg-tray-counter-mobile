# Staging deployment of block_model_v1 — 8 October 2026

Deployed `egg-tray-counter-api-staging` version `a012c14e-8ad0-4a50-b2ab-9a697a0df857`
(`npx wrangler deploy --env staging`). Production Worker untouched: its /health
still lists only cell_identity_v1 and model_spatial_v1 and /ready is ready.
Staging needed its own ROBOFLOW_API_KEY secret (set by the user; never printed).

End-to-end probe with three archived labelled photos used as transport slots
(img 19 straight, img 30 left, img 02 right — three different blocks, so the
grid is a mechanics check, not a real inventory): HTTP 200 in 11.5 s,
block 5 x 4, observed 220, computed 180, total 400 (eggs 12 000), no conflicts,
all three views accepted by the capture gate (gradient 1.01–1.08, coverage
0.68–0.86, height 0.71–1.01). Per-view span counts: straight 20/20/20/20/20,
left 20/19/21/19, right 21/20/20/20. Legacy top-level total_trays stays null.
Response saved as scan-img19-30-02.json.
