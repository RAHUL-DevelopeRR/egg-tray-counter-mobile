# Live capture constraints — implementation, evidence, and the exact-count question

Date: 2026-09-18
Scope: local, deterministic capture constraints in the Flutter app, plus the
build/install verification. No model was retrained, no Worker was deployed.

## 1. Authentication status (verified, not assumed)

| Service | State | Evidence |
|---|---|---|
| GitHub CLI | authenticated | `gh auth status` → account `RAHUL-DevelopeRR` (keyring), scopes `repo`, `workflow`, `gist`, `read:org` |
| Cloudflare (local deploy) | **not authenticated** | `wrangler whoami` → "You are not authenticated. Please run `wrangler login`." No `CLOUDFLARE_API_TOKEN` in the environment |
| Deployed Worker | live | `GET /health` → 200 `{"status":"ok","scan_contract":"cell_identity_v1","hybrid_ready":false}`; `GET /ready` → 200 `{"status":"ready","provider":"roboflow_serverless","model_reference":"projec-mutta/2"}` |
| Roboflow | reachable server-side only | the Worker's `/ready` reports the key is configured; no Roboflow key exists in this shell, and the app never calls Roboflow directly by design |
| MCP servers | **cannot be authorized from a shell** | MCP OAuth consent runs in the client UI; there are no stored tokens to reuse. Nothing in this session depended on them |

Consequence: everything below was implemented, tested, built and installed
without MCP authentication. The one operation that remains blocked is deploying
changed Worker code — that needs `wrangler login` or a Cloudflare API token.

## 2. What was added to the app

| File | Role |
|---|---|
| `mobile/lib/services/frame_evidence.dart` | measurement only: luma plane, guide geometry, 13 frame metrics, preview→still guide mapping |
| `mobile/lib/services/frame_preflight.dart` | judgement only: pass / advisory / blocking checks, result and threshold policy, audit serialisation |
| `mobile/lib/services/live_frame_preflight.dart` | live loop: camera YUV plane + accelerometer → report; JPEG still decoding; pose conversion |
| `mobile/lib/features/capture/guided_capture_pane.dart` | live banner with the exact reason and the fix, level-reference control, capture lock, post-capture verification |
| `mobile/lib/features/capture/camera_guide_overlay.dart` | guide outline colour follows the live verdict |
| `mobile/lib/services/settings_store.dart`, `mobile/lib/models/scan_session.dart`, `mobile/lib/services/api_client.dart` | level reference persistence; per-view constraint evidence carried with the upload |

Checks and the values they compare (pilot heuristics, not validated gates):

| Check | Blocks when | Advisory when |
|---|---|---|
| lighting | mean luma < 45 or > 215, crushed pixels > 40%, blown pixels > 20%, top/bottom brightness ratio > 2.6 | banding above 1.8 |
| sharpness | guide Laplacian variance < 18 | < 30 |
| tilt (sensor) | roll > 4° from the stored reference, or pitch outside −5…28° down | roll > 2.4°, pitch outside 0…22°, reference not set, sensor and image horizon disagree by > 6° |
| framing | guide top/bottom edge energy > 45% of the guide's mean, or > 34% of image detail in the outer 3% ring | > 30% at the guide edges |
| coverage | guide structure coverage < 18% or > 97% | < 32% |
| direction | never blocks | left/right vertical-edge span ratio > 1.45 |

Every blocking check carries the measured value, the limit and the sentence the
operator must act on. The report is attached to each captured view as
`${view}_constraint_evidence` (additive JSON; the current deployment ignores the
extra fields, so uploads stay compatible).

## 3. Verification

- `flutter analyze`: no issues.
- `flutter test`: 54 tests pass (16 before). New: synthetic-frame measurement,
  every blocking path, the audit record, pose conversion from raw accelerometer
  axes, JPEG→luma decoding, the guide mapping, and a real-photo harness.
- Real-photo harness (`mobile/test/preflight_on_evaluation_frames_test.dart`)
  over the ten labelled frames in `accuracy-evaluation/test-images`:

| image | trays | model | sharpness | luma | coverage | app guide | full frame |
|---|---:|---:|---:|---:|---:|---|---|
| img01 | 60 | 9 | 1974 | 147 | 0.88 | REFUSE base cut off | REFUSE base cut off |
| img02 | 60 | 12 | 1521 | 137 | 0.98 | REFUSE top cut off | REFUSE base cut off |
| img03 | 60 | 93 | 2276 | 140 | 0.88 | REFUSE base cut off | accept |
| img04 | 32 | 29 | 1840 | 120 | 1.00 | REFUSE top cut off | REFUSE top cut off |
| img05 | 120 | 124 | 2685 | 141 | 0.93 | REFUSE base cut off | accept |
| img06 | 21 | 9 | 1186 | 137 | 0.99 | REFUSE top cut off | REFUSE base cut off |
| img07 | 21 | 21 | 824 | 137 | 1.00 | REFUSE top cut off | REFUSE top cut off |
| img08 | 46 | 73 | 1370 | 128 | 0.92 | REFUSE top cut off | REFUSE top cut off |
| img09 | 76 | 25 | 2039 | 66 | 0.75 | REFUSE top cut off | REFUSE top cut off |
| img10 | 1 | 1 | 346 | 139 | 0.88 | REFUSE top cut off | REFUSE top cut off |

  0/10 accepted under the app guide, 2/10 under a full-frame guide (mean
  absolute model error on the refused set: 22.9 trays, identical to the whole
  set because nothing is accepted).
- The harness found a real defect: with a guide reaching the image bottom the
  content-cell counter read one row past the plane (`RangeError`). Fixed and
  covered; without the harness this would have crashed the post-capture
  verification on any full-frame guide.
- APK: `flutter build apk --release`, version `0.3.0+6`, 60,074,272 bytes,
  SHA-256 `c8f2787146cc28568609b2a1d2a05a8d9a7a693627ca7f58e99090484b8e74e4`,
  signed with the existing debug key (pilot build, unchanged practice).
  `adb install -r` on the connected Redmi Note 9 Pro (serial `f76d5e20`) →
  `Success`; the app launches (pid alive, Impeller active, no crash in logcat).
- **Not verified on device: the live banner itself.** The phone is locked with a
  pattern (`uiautomator` reports "Draw pattern"), so no UI state can be read or
  driven over ADB. Sensor signs, the stream on the real camera and the live
  verdicts are therefore still unproven on hardware.

## 4. Would constraints make the count exact?

No — not by themselves, and anyone promising that should be doubted.

Constraints remove one specific class of error: counts produced from evidence in
which the object was not actually observable (cut-off stacks, blown highlights,
motion blur, extreme angles). The benchmark in `accuracy-evaluation/report.md`
(2/10 exact, MAE 22.9 trays) was measured on frames that this gate now refuses
on framing alone. That is the strongest statement the data supports: the old
accuracy number describes captures the app no longer accepts, so it is not a
baseline for a constrained pipeline.

Exactness then needs three more things, none of which are in this change:

1. **Layer visibility logic.** The model counts tray rims it can see. A side view
   shows only the rims on the near face; if a stack is blocked mid-height, the
   hidden layers are invisible and no lens or threshold recovers them. Counting
   exact trays requires either an unobstructed view per stack or explicit
   inference from geometry.
2. **Per-view poses, not just per-view quality.** Fusion needs the camera pose
   (roll, pitch and especially yaw) plus the lens intrinsics, so rim lines can be
   placed in 3D and the hidden layers extrapolated. Roll and pitch now exist per
   capture; yaw does not.
3. **Truth captured under the same constraints.** The pilot's GRID + HEIGHT
   recount flow already records operator ground truth; it now has to be run on
   scenes captured through the gate, otherwise the comparison mixes admissible
   and inadmissible evidence again.

## 5. What live detection covers today

Detected continuously, roughly every 300 ms, on the preview stream:
lighting level, clipping and cross-frame banding; focus; framing (stack running
past the guide top or bottom, and detail clipped by the photo border); guide
coverage; device roll and pitch against the stored level reference, cross-checked
against the image horizon. Each is surfaced as a coloured guide outline, a
per-check chip, one headline with the measured value, and one instruction; any
blocking finding disables the capture button. After the shutter, the same checks
run on the still that was actually written, and a blocking still is discarded
with its reason instead of being uploaded.

Not detected, and deliberately not claimed: hidden trays, egg occupancy per
tray, dirty or damaged rims, and whether the model's count is correct.

## 6. Next step for the 3D scan

1. Field-validate the gate first. The 0/10 result above is the top risk: if a
   willing operator cannot satisfy the guide, the guide is wrong. Measure how
   often it blocks a real capture, then tune the margins.
2. Add yaw. Tilt-compensated magnetometer yaw is coarse indoors (±5–10°); pair it
   with visual yaw from the convergence of the stack's vertical edges
   (vanishing-point estimate) and keep their disagreement as an advisory, as the
   roll check already does.
3. Pull lens intrinsics once per device
   (`LENS_INFO_AVAILABLE_FOCAL_LENGTHS`, `SENSOR_INFO_PHYSICAL_SIZE`) so image
   lines become 3D lines. With the tray pitch known from the height pilot,
   visible rim spacing along the stack axis gives a metric layer count.
4. Treat the constrained STRAIGHT view as the primary count and the two angled
   views as error detectors: a view only contributes when its pose is inside the
   accepted band and its rim spacing is consistent with the primary, instead of
   averaging three numbers that were never comparable.
5. Only then attempt hidden-layer inference: fit the visible rim sequence, and
   accept an extrapolated layer count solely when the residual is small and the
   height pilot agrees. Otherwise return `rescan_required`, as the Worker already
   does for inconsistent views.

## 7. Limitations stated plainly

- Every threshold in section 2 is a pilot heuristic chosen from a handful of
  frames. None is validated accuracy control, and the still-path region checks
  are advisory-only because preview and still are different crops.
- The guide is a bounding rectangle; the LEFT and RIGHT guides are trapezoids,
  so angled views are judged against a rectangle and rely on the ANGLE hint.
- The accelerometer sign convention is derived, not measured on hardware; the
  inconsistency advisory exists to expose it, and the on-device check is pending.
- No count was produced, accepted or changed by this work.
