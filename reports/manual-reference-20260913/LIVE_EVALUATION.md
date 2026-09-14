# Fresh deployed-model check

Run on 2026-09-13 through the existing Cloudflare `/v1/scans/count` endpoint.
The raw response is `live-worker-evaluation.json`, HTTP 200, model `projec-mutta/2`,
server inference latency 12,470 ms. This is fresh cloud inference, separate from
the saved-response replay in `comparison.json`.

The endpoint requires three files. LEFT was img04.jpg, RIGHT img01.jpg and
STRAIGHT img02.jpg. These are separate benchmark scenes, **not three angles of
one inventory**. Submitted evaluation IDs were EVAL04/EVAL01/EVAL02; the deployed
baseline ignored them. Do not evaluate its scene fusion using this request.

For img04.jpg, the retained non-blind visual reference is 32 visible trays.
The fresh LEFT model count is 29: signed error -3, absolute error 3,
relative absolute error 9.375%, count closeness 90.625%, exact match false.
Other returned model counts were 9 and 12; no truth comparison is asserted here.
Precision and recall remain unavailable without validated instance annotations.
Egg occupancy and hidden physical inventory were not verified.

The deployed processing mode is `cloudflare_roboflow_egg_tray_baseline`.
Its health response is only `{"status":"ok"}` and does not advertise the new
optional-marker contract. It is incompatible with the updated client's preflight.
No new Worker deployment occurred. Wrangler still reports unauthenticated.
