# MASTER CODEX PROMPT — PRODUCTION EGG TRAY COUNTER

You are acting as a senior computer-vision engineer, Flutter mobile engineer, Python/FastAPI backend engineer, ML deployment engineer, and software architect.

Your task is to **DESIGN, IMPLEMENT, TEST, AND DOCUMENT a complete working Egg Tray Counting system**.

Do not stop after producing architecture diagrams or pseudocode.

Do not merely tell me what files I should create.

Actually create the project files, application code, backend code, computer-vision pipeline, configuration, tests, scripts, documentation, and runnable development environment.

Work incrementally, test each stage, and keep the repository runnable throughout development.

---

# 1. PRODUCT GOAL

Build a mobile application that allows a warehouse operator to photograph stacks of egg trays from exactly three guided viewpoints:

1. FRONT
2. LEFT — approximately 25–35° from front
3. RIGHT — approximately 25–35° from front

The system must use the three photographs together to determine the number of **physical egg trays** in the scene.

The application must return:

* number of physical stacks detected
* tray count for every physical stack
* total tray count
* eggs per tray = 30
* total egg count = total trays × 30
* verification status
* confidence/quality information
* processing time
* model version
* per-view diagnostic results

The user must see either:

`VERIFIED`

or

`RESCAN REQUIRED`

The system MUST NOT fabricate a number when evidence is insufficient.

Accuracy is more important than always returning a count.

---

# 2. EXISTING ASSETS

The local dataset is expected at:

```text
C:\Users\dharani\Downloads\egg pic\egg pic
```

There is also an existing Roboflow project/dataset/model.

DO NOT assume the exact Roboflow project ID, workspace, model version, annotation type, endpoint URL, or API key.

Read them from environment/configuration.

Create:

```text
.env.example
```

with variables such as:

```env
ROBOFLOW_API_KEY=
ROBOFLOW_WORKSPACE=
ROBOFLOW_PROJECT=
ROBOFLOW_MODEL_ID=
ROBOFLOW_MODEL_VERSION=
ROBOFLOW_INFERENCE_URL=

SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=

APP_ENV=development
LOG_LEVEL=INFO
EGGS_PER_TRAY=30
```

Never commit real API keys.

Never expose `ROBOFLOW_API_KEY` or `SUPABASE_SERVICE_ROLE_KEY` inside the Flutter application.

The Flutter application should communicate with our backend.

The backend communicates securely with Roboflow.

---

# 3. CRITICAL COMPUTER-VISION PRINCIPLE

DO NOT make the final architecture:

```text
photo
→ YOLO detects individual trays
→ count bounding boxes
```

The physical egg trays are tightly stacked and frequently touch each other.

Individual object detection therefore produces:

* merged detections
* missed trays
* duplicated boxes
* inaccurate box boundaries
* occlusion errors
* perspective errors

The desired production architecture is:

```text
FRONT IMAGE
LEFT IMAGE
RIGHT IMAGE
        │
        ▼
Image quality validation
        │
        ▼
Locate physical stack/counting faces
        │
        ▼
Segmentation / ROI extraction
        │
        ▼
Map ROI back onto original-resolution image
        │
        ▼
Perspective rectification
        │
        ▼
Detect repeating horizontal tray-layer structure
        │
        ▼
Estimate tray count independently for every view
        │
        ▼
Associate the same physical stack across views
        │
        ▼
Three-view fusion
        │
        ├── sufficient evidence → VERIFIED
        │
        └── insufficient evidence → RESCAN REQUIRED
        │
        ▼
Total trays
        │
        ▼
Total eggs = trays × 30
```

A Roboflow model should preferably identify a class such as:

```text
stack_face
```

or

```text
counting_face
```

rather than trying to make the neural network directly identify every tightly touching tray.

If the currently trained Roboflow model only detects individual trays, support it through an adapter as an experimental baseline, but DO NOT make simple box counting the final production algorithm.

Keep the model interface generic enough that we can later switch to:

* Roboflow hosted inference
* Roboflow Workflow
* ONNX Runtime
* Ultralytics segmentation export
* Core ML
* LiteRT

without changing business logic.

---

# 4. REQUIRED REPOSITORY

If the directory is currently empty, initialize this structure:

```text
egg-tray-counter/
│
├── README.md
├── .gitignore
├── .env.example
├── docker-compose.yml
│
├── docs/
│   ├── architecture.md
│   ├── api.md
│   ├── vision-pipeline.md
│   ├── dataset-audit.md
│   ├── testing.md
│   └── deployment.md
│
├── mobile/
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app/
│   │   ├── core/
│   │   ├── models/
│   │   ├── services/
│   │   ├── repositories/
│   │   ├── features/
│   │   │   ├── home/
│   │   │   ├── capture/
│   │   │   ├── processing/
│   │   │   ├── result/
│   │   │   ├── history/
│   │   │   └── settings/
│   │   └── widgets/
│   ├── android/
│   ├── ios/
│   └── test/
│
├── backend/
│   ├── app/
│   │   ├── main.py
│   │   ├── config.py
│   │   ├── api/
│   │   ├── schemas/
│   │   ├── services/
│   │   ├── providers/
│   │   │   ├── base.py
│   │   │   ├── roboflow.py
│   │   │   └── mock.py
│   │   ├── vision/
│   │   │   ├── quality.py
│   │   │   ├── preprocessing.py
│   │   │   ├── segmentation.py
│   │   │   ├── rectification.py
│   │   │   ├── layer_signal.py
│   │   │   ├── periodicity.py
│   │   │   ├── stack_matching.py
│   │   │   ├── fusion.py
│   │   │   ├── confidence.py
│   │   │   └── overlay.py
│   │   ├── database/
│   │   └── utils/
│   ├── tests/
│   ├── requirements.txt
│   ├── Dockerfile
│   └── pytest.ini
│
├── ml/
│   ├── audit_dataset.py
│   ├── prepare_dataset.py
│   ├── evaluate.py
│   ├── export_model.py
│   ├── experiments/
│   └── configs/
│
├── dashboard/
│   └── optional Next.js dashboard
│
└── scripts/
    ├── run_backend.ps1
    ├── run_mobile.ps1
    ├── test_all.ps1
    └── setup_windows.ps1
```

Use a clean architecture but avoid unnecessary enterprise abstractions.

---

# 5. PHASE ZERO — INSPECT BEFORE IMPLEMENTING

Before changing the dataset or training anything, inspect:

```text
C:\Users\dharani\Downloads\egg pic\egg pic
```

Determine automatically:

* number of images
* directory structure
* image formats
* image dimensions
* label formats
* whether annotations exist
* whether annotations are YOLO boxes
* YOLO segmentation polygons
* COCO
* Pascal VOC
* Roboflow export format
* class names
* number of classes
* class distribution
* images missing labels
* labels missing images
* corrupt images
* duplicate filenames
* obvious duplicate images
* dataset split
* train/validation/test counts

Create:

```text
ml/audit_dataset.py
```

Running:

```powershell
python ml/audit_dataset.py
```

must produce a human-readable dataset report.

Do not destructively modify the original dataset.

---

# 6. MOBILE APPLICATION

Use:

```text
Flutter
```

The application must have a polished but simple warehouse-oriented UI.

Required screens:

### A. Home

Show:

```text
Egg Tray Counter

[ START NEW SCAN ]

Recent scans
Settings
```

### B. Guided capture

The mobile app must NOT let the user randomly upload three unspecified pictures.

Implement a controlled state machine:

```text
FRONT
↓
LEFT
↓
RIGHT
↓
PROCESS
```

For FRONT:

```text
FRONT PHOTO

Keep all stacks inside the guide.
Keep the top and bottom of every stack visible.
Stand approximately straight in front.

[camera preview]

[ CAPTURE FRONT ]
```

After successful capture:

```text
Front ✓
```

Then:

```text
LEFT PHOTO

Move approximately 25–35° to the LEFT.

[ CAPTURE LEFT ]
```

Then:

```text
RIGHT PHOTO

Move approximately 25–35° to the RIGHT.

[ CAPTURE RIGHT ]
```

### Camera overlay

Add guide overlays to encourage:

* whole stack visibility
* bottom visibility
* top visibility
* adequate distance
* correct orientation

Do not crop photos before uploading.

Preserve the original-resolution still image.

A smaller image may be generated for quick validation/model inference.

---

# 7. LOCAL IMAGE QUALITY GATE

Implement inexpensive quality checks before uploading.

Check:

### Blur

Use variance of Laplacian or equivalent metric.

### Exposure

Reject severe:

* underexposure
* overexposure

### Resolution

Reject images below configured minimum resolution.

### Orientation

Handle EXIF orientation correctly.

### Coverage

Where feasible, use the model or a fast precheck to determine whether useful stack regions are visible.

The app should say things such as:

```text
Image is blurry.
Please retake the FRONT photo.
```

or:

```text
Bottom of stack may not be visible.
Move slightly backward.
```

Thresholds must live in configuration and not be scattered as magic numbers.

---

# 8. MOBILE NETWORK ARCHITECTURE

Do NOT send each photograph independently and immediately finalize its count.

Once all three images exist, submit one logical scan:

```text
POST /v1/scans/count
```

using:

```text
multipart/form-data
```

containing:

```text
front
left
right
```

plus optional metadata:

```text
scan_id
device_model
app_version
warehouse_id
lane_id
captured_at
```

Add:

* request timeout
* retries where safe
* cancellation
* upload progress
* meaningful error handling
* network connectivity handling

The UI should show:

```text
Uploading images...
Analyzing FRONT...
Analyzing LEFT...
Analyzing RIGHT...
Matching stacks...
Verifying count...
```

Do not pretend these stages are completed if the backend has not completed them.

---

# 9. BACKEND

Use:

```text
Python 3.11+
FastAPI
Pydantic
OpenCV
NumPy
SciPy
httpx
```

Add other dependencies only when justified.

The backend is the orchestration layer.

Implement:

```text
GET /health
GET /ready
GET /version
POST /v1/scans/count
```

Optional later endpoints:

```text
GET /v1/scans/{scan_id}
GET /v1/scans
POST /v1/scans/{scan_id}/feedback
```

---

# 10. INFERENCE PROVIDER ABSTRACTION

Create:

```python
class InferenceProvider(ABC):
    async def infer(self, image, metadata):
        ...
```

Implement:

```text
RoboflowInferenceProvider
MockInferenceProvider
```

The vision pipeline must not depend directly on Roboflow-specific response JSON.

Normalize model output into internal objects such as:

```python
StackFacePrediction(
    polygon=...,
    bbox=...,
    confidence=...,
    class_name="stack_face"
)
```

This is essential because later we will add:

```text
OnnxInferenceProvider
```

without rewriting the rest of the application.

---

# 11. ROBOFLOW INTEGRATION

Implement Roboflow inference behind the FastAPI backend.

Requirements:

* API key stored only on backend
* configurable endpoint
* configurable workspace/project/version
* request timeout
* retry with bounded exponential backoff where appropriate
* structured error handling
* response schema validation
* model-version logging
* no secret values written to logs
* dependency injectable provider for tests

Do not invent a Roboflow API format if the installed SDK/current endpoint exposes a different schema.

Inspect the actual configured Roboflow model and normalize its response.

Support either:

1. instance segmentation response, preferably `stack_face`
2. object detection response as temporary baseline

If segmentation masks/polygons are available, use them.

---

# 12. ORIGINAL-RESOLUTION PROCESSING

This is extremely important.

Do not resize the entire computer-vision process to 640×640.

Use approximately:

```text
640px model working resolution
```

for neural inference if required.

Then map the resulting mask/polygon coordinates back to the ORIGINAL image.

Perform thin tray-layer analysis on the high-resolution ROI.

Pipeline:

```text
original photo
     │
resize/letterbox
     ↓
Roboflow model
     ↓
stack-face polygon
     ↓
convert coordinates back
     ↓
original-resolution ROI
     ↓
perspective correction
     ↓
layer counting
```

Implement and unit-test coordinate transformations.

---

# 13. STACK FACE RECTIFICATION

For each predicted stack/counting face:

1. derive or estimate four useful corners
2. create a quadrilateral
3. use:

```python
cv2.getPerspectiveTransform()
```

and:

```python
cv2.warpPerspective()
```

4. produce a canonical rectified counting face

Example internal target size:

```text
512 × 768
```

but make it configurable.

Do not assume every stack is axis-aligned.

---

# 14. TRAY LAYER SIGNAL

This is the central counting algorithm.

For each rectified stack face:

### Step 1 — grayscale

```python
gray = cv2.cvtColor(...)
```

### Step 2 — mild smoothing

Gaussian blur.

### Step 3 — horizontal-rail response

Tray boundaries/rails are predominantly horizontal.

Use vertical intensity derivative:

```python
cv2.Sobel(
    gray,
    cv2.CV_32F,
    dx=0,
    dy=1,
    ksize=3
)
```

Then:

```text
abs(Sobel-Y)
```

### Step 4 — horizontal projection

Collapse the two-dimensional edge image along X.

Obtain:

```text
signal[y]
```

representing horizontal-structure strength at every vertical position.

Avoid left/right polygon edges contaminating the signal by ignoring configurable side margins.

### Step 5 — smooth and normalize signal

Use:

* Gaussian smoothing
* median/MAD robust normalization

### Step 6 — estimate dominant tray pitch

Do NOT simply count every detected edge peak.

Estimate repeating vertical spacing through:

* autocorrelation
  and/or
* 1-D periodogram

Determine:

```text
pitch_px
```

representing expected tray-layer spacing.

### Step 7 — peak detection

Use:

```python
scipy.signal.find_peaks
```

with dynamically derived:

* minimum distance
* prominence

based on estimated pitch.

### Step 8 — regular lattice fitting

Given positions such as:

```text
100
117
134
168
185
```

and estimated pitch:

```text
17
```

recognize:

```text
168 - 134 = 34 ≈ 2 × 17
```

as evidence that one internal rail may have been obscured.

However:

DO NOT blindly invent missing layers.

Record:

```text
detected_layers
inferred_internal_layers
pitch_px
periodicity_error
peak_prominence_statistics
quality
```

Unknown trays beyond the observed top/bottom range must never be invented.

---

# 15. COLOR AND STRUCTURAL CUES

If the trays have a consistent green/plastic appearance in the dataset, optionally calculate:

* HSV color mask
* green-region support
* rail response restricted to tray regions

Do not rely exclusively on color because:

* illumination varies
* tray designs may vary
* trays may be dirty
* white balance changes between phones

Treat color as supporting evidence.

---

# 16. DO NOT SUM THREE VIEW COUNTS

This is a hard requirement.

Example:

```text
FRONT sees Stack A = 18 trays
LEFT sees Stack A = 18 trays
RIGHT sees Stack A = 17 trays
```

The result is NOT:

```text
18 + 18 + 17 = 53
```

These are observations of ONE physical stack.

The three views must be fused into:

```text
Stack A = 18
```

provided the verification policy accepts it.

---

# 17. PHYSICAL STACK ASSOCIATION

Create:

```text
stack_matching.py
```

Its job is to determine which stack in FRONT corresponds to which stack in LEFT and RIGHT.

Preferred architecture, in order of reliability:

### Option 1 — ArUco/lane markers

Support ArUco markers if physical markers can be placed near each warehouse row/stack.

Use:

```text
physical_stack_id
aruco_id
```

This gives deterministic cross-view identification.

### Option 2 — Lane/row identifiers

If the operator selects a warehouse lane before scanning, combine that with spatial order.

### Option 3 — visual/geometric matching

When no marker exists, use a combination of:

* left-to-right order
* relative horizontal position
* approximate stack height
* segmentation shape
* appearance descriptors
* scene geometry
* number of neighboring stacks

DO NOT associate stacks only by raw bounding-box coordinates because perspective changes across the three images.

Every association must produce:

```text
association_confidence
```

Low-confidence associations cause:

```text
RESCAN REQUIRED
```

rather than guessing.

---

# 18. THREE-VIEW FUSION

Implement:

```text
fusion.py
```

Each per-view estimate should include something similar to:

```python
ViewEstimate(
    view="front",
    physical_stack_id="stack_03",
    tray_count=18,
    image_quality=0.91,
    segmentation_quality=0.94,
    periodicity_quality=0.92,
    inferred_layers=0,
    top_visible=True,
    bottom_visible=True
)
```

Initial conservative fusion rule:

A stack is VERIFIED only if:

1. at least 2 of the 3 views are high quality
2. at least 2 usable views agree EXACTLY on integer tray count
3. stack association is reliable
4. top/bottom visibility is adequate
5. periodicity is stable
6. inferred rails are below a configured threshold
7. any inferred missing rail is supported by another view
8. no unexplained extra/missing physical stack exists

Example:

```text
FRONT 18 quality .93
LEFT  18 quality .89
RIGHT 17 quality .61

→ VERIFIED = 18
```

Example:

```text
FRONT 18
LEFT  17
RIGHT 19

→ RESCAN REQUIRED
```

Do NOT average:

```text
(18+17+19)/3
```

Do NOT use median as an automatic substitute for verification.

---

# 19. WHOLE SCENE VERIFICATION

This is another hard requirement.

A complete warehouse scene is:

```text
VERIFIED
```

ONLY when every detected physical stack is verified.

Example:

```text
Stack 1 ✓ 18
Stack 2 ✓ 21
Stack 3 ✓ 16
Stack 4 ? disagreement
```

Then:

```text
COUNT NOT VERIFIED
```

Do NOT return:

```text
55 + guessed Stack 4 count
```

Instead return:

```text
RESCAN REQUIRED

Reason:
Stack 4 differs across views.

Please retake LEFT photo.
```

---

# 20. CONFIDENCE

Do not do:

```text
Roboflow confidence = 0.96
therefore
count confidence = 96%
```

These are different quantities.

Create a system confidence score from features such as:

```text
image sharpness
exposure quality
segmentation confidence
mask quality
top visibility
bottom visibility
pitch stability
periodicity residual
peak prominence
number of inferred rails
front/left/right agreement
stack association confidence
marker confidence
```

Initially implement a transparent heuristic score.

Structure it so a calibrated statistical model can replace the heuristic later.

---

# 21. RESPONSE CONTRACT

`POST /v1/scans/count` should return a JSON structure similar to:

```json
{
  "scan_id": "uuid",
  "status": "verified",
  "accepted": true,

  "physical_stack_count": 7,
  "total_trays": 126,
  "eggs_per_tray": 30,
  "total_eggs": 3780,

  "processing": {
    "mode": "roboflow_cloud",
    "latency_ms": 1842,
    "model_version": "..."
  },

  "views": {
    "front": {
      "quality": 0.94,
      "accepted": true
    },
    "left": {
      "quality": 0.91,
      "accepted": true
    },
    "right": {
      "quality": 0.88,
      "accepted": true
    }
  },

  "stacks": [
    {
      "physical_stack_id": "stack_01",

      "counts": {
        "front": 18,
        "left": 18,
        "right": 18
      },

      "final_count": 18,
      "confidence": 0.98,
      "accepted": true,
      "reason": "3/3 usable views agree"
    }
  ],

  "rescan": null
}
```

For rejection:

```json
{
  "status": "rescan_required",
  "accepted": false,
  "total_trays": null,
  "total_eggs": null,

  "rescan": {
    "recommended_view": "left",
    "reason": "Stack 4 count disagrees across views"
  }
}
```

Never provide an inventory count in a rejected response.

---

# 22. RESULT SCREEN

A verified result should look conceptually like:

```text
✓ VERIFIED

Physical stacks        7
Total trays          126
Eggs / tray            30

TOTAL EGGS          3,780

3/3 views processed
Model: <version>
Processing: Cloud / Roboflow

[ VIEW DETAILS ]
[ NEW SCAN ]
```

Rejected:

```text
⚠ COUNT NOT VERIFIED

Front ✓
Left  ⚠
Right ✓

Stack 4 disagreement

Front: 18
Left: 17
Right: 19

Please retake the LEFT photograph.

[ RETAKE LEFT ]
```

The application should return directly to the LEFT capture state while preserving FRONT and RIGHT if only LEFT needs retaking.

---

# 23. DEBUG OVERLAYS

Backend should optionally generate diagnostic images showing:

* detected stack-face polygon
* rectified ROI
* detected tray rails
* inferred rail positions
* stack IDs
* per-view tray counts

Expose them only in developer/debug mode initially.

These overlays are essential for debugging incorrect counts.

Store diagnostic data separately from production UI behavior.

---

# 24. DATABASE

Use Supabase as an optional operational backend.

Tables should include:

```text
scans
stack_results
model_versions
```

Suggested scan fields:

```text
id
user_id
created_at
status
total_trays
total_eggs
model_version
device_model
latency_ms
inference_mode
```

Stack results:

```text
scan_id
physical_stack_id
front_count
left_count
right_count
final_count
confidence
accepted
reason
```

Enable Row Level Security.

Never place Supabase service-role credentials in mobile code.

The application must remain usable during development without Supabase by using a local repository/mock implementation.

---

# 25. PRIVACY

Warehouse photos may contain workers.

Default behavior:

```text
successful scan
→ process image
→ keep only result/metadata
→ do not permanently store photograph
```

Failure images should only be stored when explicit configuration/consent permits it.

If images are stored:

* private storage only
* no public bucket
* configurable retention
* access-controlled review
* record purpose
* support eventual automatic deletion

Design storage behind an interface.

---

# 26. HISTORY

Flutter app should maintain local scan history using SQLite or another appropriate local persistent store.

Store:

```text
scan ID
date/time
status
tray count
egg count
model version
latency
```

Do not store full photographs indefinitely by default.

---

# 27. ROBOFLOW MODEL DEVELOPMENT SUPPORT

Create scripts/documentation describing how the existing Roboflow dataset should evolve toward:

```text
class: stack_face
```

Each training image ideally contains segmentation polygons around useful visible counting faces.

Ground truth must also preserve:

```text
scene_id
view
physical_stack_id
tray_count_gt
```

The complete dataset concept should be triplets:

```text
scene_000001/
    front.jpg
    left.jpg
    right.jpg
```

Never randomly place the FRONT photo of the same scene into training and its LEFT photo into validation.

Split by entire scene/capture session.

Otherwise validation leakage will occur.

If the current dataset cannot support this structure, do not destroy it.

Generate a migration/report explaining what additional annotation is required.

---

# 28. TRAINING/EVALUATION

Do not report only YOLO/Roboflow mAP as product accuracy.

Calculate:

### Exact stack accuracy

Percentage of stacks whose integer tray count is exactly correct.

### MAE

```text
mean(abs(predicted_count - true_count))
```

### Exact scene accuracy

A scene counts as correct only if the total number of trays is exactly correct.

### Coverage

```text
verified scans / all scans
```

### Accepted accuracy

```text
correct verified scans / verified scans
```

### False accept rate

```text
incorrect verified scans / verified scans
```

These metrics must be reported separately.

---

# 29. GOLDEN TEST DATA

Create infrastructure for:

```text
tests/golden/
```

Every golden scene should contain:

```text
front
left
right
ground_truth.json
```

Example ground truth:

```json
{
  "scene_id": "golden_001",
  "total_trays": 126,
  "stacks": [
    {
      "physical_stack_id": "stack_01",
      "tray_count": 18
    }
  ]
}
```

Regression tests must detect when an algorithm or model update changes a previously correct exact count.

---

# 30. UNIT TESTS

Add meaningful tests for:

* coordinate mapping
* image quality metrics
* perspective rectification
* signal generation
* pitch estimation
* peak detection
* inferred gaps
* fusion
* disagreement rejection
* stack association
* API schema
* invalid MIME type
* oversized image
* missing view
* duplicate view
* Roboflow timeout
* Roboflow malformed response
* frontend repository/service logic

Particularly test:

```text
[18,18,17] → 18 if quality conditions pass
[18,17,19] → reject
[18,None,18] → 18 if two valid views exist
[18,18,None] → 18
only one valid view → reject
```

---

# 31. INPUT SECURITY

Validate uploaded files.

Allow only expected image formats such as:

```text
image/jpeg
image/png
```

Set configurable maximum upload size.

Do not rely only on filename extension.

Generate server-side scan IDs.

Sanitize logs.

Implement CORS correctly for development/production.

Do not create a wildcard production security configuration simply to make the demo work.

---

# 32. PERFORMANCE

Measure separately:

```text
image decoding
Roboflow network request
model inference
ROI processing
OpenCV layer count
cross-view matching
fusion
total request
```

Return total latency to the mobile application.

Design the system so independent Roboflow per-view inference can execute concurrently when safe.

For example:

```python
await asyncio.gather(
    infer(front),
    infer(left),
    infer(right),
)
```

Do not perform unnecessary sequential HTTP requests.

However, post-inference physical stack matching and fusion must occur after all required results exist.

---

# 33. CACHING / DUPLICATE REQUESTS

A retry from a poor network must not accidentally create multiple scans.

Support:

```text
scan_id
```

as an idempotency identifier.

If the same completed scan request is retried, return the prior result when appropriate.

---

# 34. FUTURE EDGE INFERENCE

Although the first implementation may use Roboflow cloud inference, preserve this architecture:

```text
InferenceProvider
    ├── RoboflowInferenceProvider
    ├── MockInferenceProvider
    └── OnnxInferenceProvider   ← future
```

The eventual production architecture should support:

```text
Flutter
→ native model runtime
→ ONNX/CoreML/LiteRT
→ OpenCV
→ fusion
```

without changing higher-level business logic.

Therefore, do not embed Roboflow-specific types throughout the application.

---

# 35. OPTIONAL ON-DEVICE PHASE

Once the Roboflow MVP is stable:

1. export compatible model to ONNX
2. verify prediction parity
3. add ONNX Runtime
4. benchmark CPU/XNNPACK/NNAPI on Android
5. benchmark Core ML path on iOS
6. move stack-face inference on-device
7. eventually move the OpenCV layer counter on-device
8. retain cloud inference only as fallback

Do not implement this phase prematurely if it prevents the cloud MVP from running.

---

# 36. DASHBOARD

After the mobile + backend counting loop works, optionally create a small Next.js dashboard.

Show:

```text
Scans today
Verified %
Rescan %
Manual review %
Average tray count
False accepts after review
p50 latency
p95 latency
Model version
Errors by device
Errors by lighting
Errors by stack height
```

Add a review page for permitted failure cases showing:

```text
FRONT
LEFT
RIGHT

stack masks
detected rails
proposed counts
final status

verified human correction
```

Do not allow dashboard development to delay the working mobile counter.

---

# 37. MODEL VERSIONING

Every response should include a model version.

Do not use an untraceable:

```text
latest
```

as the only model identifier.

Model/config metadata should support:

```text
model_id
architecture
version
input_size
checksum
created_at
```

Eventually support controlled model rollout.

---

# 38. WINDOWS DEVELOPMENT EXPERIENCE

The primary development machine is Windows.

Provide PowerShell scripts.

Example:

```powershell
.\scripts\setup_windows.ps1
.\scripts\run_backend.ps1
.\scripts\run_mobile.ps1
.\scripts\test_all.ps1
```

Avoid instructions that only work on bash/Linux.

Where Docker is useful, supply Docker support as an option, not the only way to run the project.

---

# 39. README REQUIREMENTS

The root README must explain, from zero:

## Prerequisites

* Git
* Python
* Flutter
* Android Studio/SDK
* optional Docker

## Backend setup

Exact commands.

## `.env`

Exact variables.

## Starting FastAPI

Exact commands.

## Testing API

Provide curl and PowerShell examples.

## Flutter setup

Exact commands.

## Android emulator

How to connect to backend from emulator.

Remember:

```text
Android emulator localhost != host localhost
```

Use the appropriate development host such as:

```text
10.0.2.2
```

where applicable.

## Physical Android phone

Explain LAN backend address configuration.

## Roboflow configuration

Explain where credentials belong without committing them.

---

# 40. ERROR HANDLING

Create explicit typed/domain errors such as:

```text
ImageQualityError
InferenceProviderError
NoStackDetectedError
StackAssociationError
ViewDisagreementError
InsufficientEvidenceError
```

Map them into appropriate API responses.

The user must see actionable language.

Bad:

```text
Inference failed.
```

Better:

```text
The LEFT photograph is too blurry to verify Stack 3.
Please retake the LEFT photograph.
```

---

# 41. LOGGING

Use structured backend logging.

Include:

```text
scan_id
view
processing_stage
duration
provider
model_version
error_type
```

Never log:

```text
API keys
authorization tokens
Supabase service credentials
```

Avoid logging raw images.

---

# 42. CONFIGURATION

Important thresholds belong in configuration/dataclasses.

Examples:

```text
minimum blur score
minimum image width
minimum image height
minimum view quality
minimum segmentation confidence
minimum pitch
maximum pitch
peak prominence factor
maximum inferred rails
association threshold
fusion threshold
```

Do not bury them throughout functions.

Create one documented configuration layer.

---

# 43. IMPLEMENTATION PRIORITY

Follow this exact order.

## Milestone 1

Repository + FastAPI + Flutter skeleton.

Success:

```text
Flutter successfully calls GET /health.
```

## Milestone 2

Three-photo capture UI.

Success:

```text
Front + Left + Right retained in one ScanSession.
```

## Milestone 3

Multipart upload.

Success:

```text
FastAPI receives all three images in one request.
```

## Milestone 4

Roboflow adapter.

Success:

```text
Each view can be run through the configured Roboflow model.
```

## Milestone 5

Diagnostic visualization.

Success:

```text
Model predictions can be drawn correctly on original-resolution photographs.
```

## Milestone 6

Stack-face ROI extraction and rectification.

Success:

```text
At least one stack face becomes a normalized rectangular ROI.
```

## Milestone 7

OpenCV layer counter.

Success:

```text
Visual rail peaks and estimated pitch can be rendered/debugged.
```

## Milestone 8

Three-view physical stack matching.

Success:

```text
Same stacks are represented by a common physical_stack_id.
```

## Milestone 9

Fusion.

Success:

```text
Two agreeing high-quality views can VERIFY.
Disagreement causes RESCAN.
```

## Milestone 10

Finished mobile result/rescan experience.

## Milestone 11

Local scan history.

## Milestone 12

Supabase/dashboard only after the counter itself works.

---

# 44. IMPORTANT DEVELOPMENT BEHAVIOR FOR CODEX

Do not attempt to generate the entire application blindly in one enormous untested commit.

At every milestone:

1. inspect existing files
2. explain briefly what you are implementing
3. modify/create code
4. run formatter
5. run lint/static checks
6. run relevant tests
7. run build where possible
8. fix failures
9. continue only after the current stage is stable

If an environmental dependency prevents a test from running, clearly distinguish:

```text
CODE FAILURE
```

from:

```text
ENVIRONMENT NOT INSTALLED
```

Never claim that something was tested successfully when the command was not actually executed.

---

# 45. DO NOT ASK ME TO WRITE MISSING CODE

You are responsible for implementation.

When reasonable assumptions are possible, choose the most maintainable default and document the assumption.

Only stop for user input when information is genuinely impossible to infer, such as:

* missing Roboflow API credential
* missing project/version identifier
* unavailable dataset directory
* a destructive action requiring approval

Even when a credential is missing, continue by building the provider with `.env` configuration and MockInferenceProvider so the rest of the project remains runnable.

---

# 46. DO NOT OVERPROMISE ACCURACY

Never claim:

```text
100% accuracy
```

because a camera cannot count a completely hidden tray.

The product promise is:

```text
VERIFIED COUNT
```

or:

```text
RESCAN REQUIRED
```

The system should maximize:

```text
exact accuracy among VERIFIED scans
```

while separately reporting:

```text
coverage
```

A wrong VERIFIED inventory count is significantly worse than asking the warehouse operator to retake a photograph.

---

# 47. TARGET ACCEPTANCE CRITERIA

Initial engineering targets, to be measured rather than assumed:

```text
Exact-stack accuracy:
establish baseline first

Exact-scene accuracy among accepted scans:
>= 99.5% pilot target

Long-term accepted exact-scene goal:
potentially >= 99.9% after sufficient validation

False accept rate:
<= 0.5% pilot target and reduce further

Coverage:
>= 85% pilot
90–95% desirable later

P95 processing:
target < 3 seconds where infrastructure/device permits
```

Never manipulate rejection thresholds purely to make accuracy appear impressive.

Report accuracy and coverage together.

---

# 48. CORE BUSINESS RULE

The final inventory number should be generated approximately as:

```python
for physical_stack in scene:

    estimates = collect_front_left_right_estimates(
        physical_stack
    )

    result = verify_and_fuse(estimates)

    if not result.accepted:
        return RESCAN_REQUIRED

    total_trays += result.tray_count

total_eggs = total_trays * 30

return VERIFIED(total_trays, total_eggs)
```

Not:

```python
total_trays = len(all_roboflow_boxes)
```

And not:

```python
total_trays =
    front_detection_count +
    left_detection_count +
    right_detection_count
```

---

# 49. FINAL USER EXPERIENCE EXAMPLE

The desired successful experience is:

```text
Operator opens app

        ↓

START NEW SCAN

        ↓

Capture FRONT
✓

        ↓

Capture LEFT
✓

        ↓

Capture RIGHT
✓

        ↓

Analyzing photographs...

        ↓

Finding stacks...

        ↓

Counting tray layers...

        ↓

Cross-checking all three views...

        ↓

✓ VERIFIED

Physical stacks: 7
Total trays: 126
Eggs per tray: 30

TOTAL EGGS: 3,780
```

Failure case:

```text
Analyzing...

Front ✓
Left ⚠
Right ✓

COUNT NOT VERIFIED

Stack 4 could not be verified.

Front estimate: 18
Left estimate: 17
Right estimate: 18
Left image quality: poor

Please retake LEFT.

[ RETAKE LEFT ]
```

This is a correct system outcome.

---

# 50. FIRST ACTION YOU SHOULD TAKE NOW

Begin now.

Do not start by redesigning everything theoretically.

Perform the following:

1. inspect the current repository
2. inspect the local dataset directory:
   `C:\Users\dharani\Downloads\egg pic\egg pic`
3. generate the dataset audit
4. report what annotation format/model assumptions are actually available
5. create the monorepo structure
6. implement the FastAPI health endpoint
7. implement the Flutter application skeleton
8. make Flutter successfully communicate with FastAPI
9. create the inference-provider abstraction
10. implement the Roboflow provider behind environment variables
11. create a MockInferenceProvider so development can proceed without credentials
12. implement the three-photo capture state machine
13. implement the multipart triplet upload
14. then begin the actual CV pipeline

Continue milestone-by-milestone until there is a runnable end-to-end prototype.

Do not stop after giving me a plan.

Create the code.
Run the tests.
Fix failures.
Document setup commands.
Keep the project runnable.
