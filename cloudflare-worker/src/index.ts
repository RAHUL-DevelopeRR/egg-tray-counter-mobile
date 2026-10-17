import { Buffer } from "node:buffer";

// AUTH_MODE: unset or "open" keeps the open 0.4.11 behaviour; "enforce" turns on devices, admin and scan jobs;
// "observe" (the rollout step between them) enforces every request that carries a credential and answers an upload
// without one as 0.4.11 did. Any other value enforces.
// STATE_PREFIX: per-environment R2 prefix for device, job and manual-count records (both Workers bind one bucket).
// Required when AUTH_MODE is not open: without it every route that needs state answers 503 state_prefix_missing,
// so a deployment that lost it never shares another environment's records.
// ADMIN_TOKEN: Worker secret; absent means every admin call is refused.
type Bindings = Env & { ROBOFLOW_API_KEY: string; SCAN_ARCHIVE?: R2Bucket; RECONSTRUCTION_ENABLED?: string; RIM_VERIFY?: string; VISION_SERVICE_URL?: string; VISION_SERVICE_TOKEN?: string;
  AUTH_MODE?: string; STATE_PREFIX?: string; ADMIN_TOKEN?: string };

type Prediction = { class?: string; confidence?: number; x?: number; y?: number; width?: number; height?: number };
type ImageSize = { width: number; height: number };
type ViewInference = { count: number; confidence: number; detections?: Prediction[]; image?: ImageSize | null };

const VIEWS = ["left", "right", "straight"] as const;
const MAX_IMAGE_BYTES = 20 * 1024 * 1024;
const RETRYABLE = new Set([429, 502, 503, 504]);
const SCAN_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

class HttpError extends Error {
  // extra: additional top-level response fields (for example the scan job block).
  constructor(public status: number, public code: string, message: string, public extra: Record<string, unknown> = {}) {
    super(message);
  }
}

const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  Response.json(body, { status, headers: { "Cache-Control": "no-store", ...headers } });

function fuseCounts(results: Record<string, ViewInference>, maxViewCountRatio = 1.25) {
  // Detector confidence is not calibrated count confidence: this is only a rejection guard.
  if (!Number.isFinite(maxViewCountRatio) || maxViewCountRatio < 1 ||
      Object.values(results).some(({ count, confidence }) =>
        !Number.isSafeInteger(count) || count <= 0 ||
        !Number.isFinite(confidence) || confidence < 0.8 || confidence > 1)) return null;
  const positiveCounts = Object.values(results).map(({ count }) => count).filter((count) => count > 0);
  if (positiveCounts.length >= 2) {
    const lowest = Math.min(...positiveCounts);
    const highest = Math.max(...positiveCounts);
    if (highest / lowest > maxViewCountRatio) return null;
  }
  const frequencies = new Map<number, number>();
  for (const { count } of Object.values(results)) {
    if (count > 0) frequencies.set(count, (frequencies.get(count) ?? 0) + 1);
  }
  const agreed = [...frequencies].filter(([, frequency]) => frequency >= 2).map(([count]) => count);
  return agreed.length === 1 ? agreed[0] : null;
}

function readCellIds(form: FormData): Record<string, string> {
  return Object.fromEntries(VIEWS.map((view) => {
    const raw = form.get(`${view}_cell_id`);
    const id = typeof raw === "string" ? raw.trim().toUpperCase() : "";
    if (!/^[A-Z0-9][A-Z0-9_-]{0,31}$/.test(id)) {
      throw new HttpError(422, "cell_identity_required", `Enter the painted cell ID for ${view.toUpperCase()} (1-32 letters, digits, - or _)`);
    }
    return [view, id];
  }));
}

function fuseCells(results: Record<string, ViewInference>, cellIds: Record<string, string>, maxRatio = 1.25) {
  const groups = new Map<string, Record<string, ViewInference>>();
  for (const view of VIEWS) {
    const id = cellIds[view];
    if (!id || !results[view]) throw new Error("Missing cell identity or inference");
    const group = groups.get(id) ?? {};
    group[view] = results[view];
    groups.set(id, group);
  }
  return [...groups].map(([id, observations]) => {
    const finalCount = fuseCounts(observations, maxRatio);
    const accepted = finalCount !== null;
    return {
      physical_stack_id: id, // Legacy response field; identity now denotes a painted cell.
      counts: Object.fromEntries(Object.entries(observations).map(([view, result]) => [view, result.count])),
      final_count: finalCount,
      confidence: accepted ? Math.min(...Object.values(observations).map((r) => r.confidence)) : 0,
      accepted,
      reason: accepted ? "Same-cell views agree; operator-confirmed cell ID" :
        Object.keys(observations).length < 2 ? "Manual recount: capture at least two distinct angles of this same cell" :
        "Manual recount: same-cell views disagree, are empty, or have low detection confidence",
      association_confidence: null, // Manually entered identity is not measured visual association.
    };
  });
}

function base64(bytes: Uint8Array) {
  return Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength).toString("base64");
}

async function infer(file: File, env: Bindings, requireSpatial = false,
                     trace: { scan_id: string; view: string } | undefined = undefined): Promise<ViewInference> {
  const url = new URL(`https://serverless.roboflow.com/${env.MODEL_ID}`);
  url.searchParams.set("api_key", env.ROBOFLOW_API_KEY);
  url.searchParams.set("confidence", env.CONFIDENCE);
  url.searchParams.set("overlap", env.OVERLAP);
  url.searchParams.set("classes", "egg_tray");
  url.searchParams.set("format", "json");
  const encodingStarted = Date.now();
  const body = base64(new Uint8Array(await file.arrayBuffer()));
  console.log(JSON.stringify({event: "view_encoded", ...trace, image_bytes: file.size,
    encoded_bytes: body.length, encoding_ms: Date.now() - encodingStarted}));
  const upstreamStarted = Date.now();
  let attempts = 0;
  let response: Response | undefined;
  for (let attempt = 0; attempt < 3; attempt++) {
    attempts++;
    try {
      response = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body,
        signal: AbortSignal.timeout(20000),
      });
      if (!RETRYABLE.has(response.status)) break;
    } catch {
      response = undefined;
    }
    if (attempt < 2) await new Promise((resolve) => setTimeout(resolve, 250 * 2 ** attempt));
  }
  if (!response?.ok) {
    console.error(JSON.stringify({ event: "roboflow_error", ...trace,
      status: response?.status ?? 0, attempts, upstream_ms: Date.now() - upstreamStarted }));
    if (response?.status === 402) {
      throw new HttpError(503, "inference_quota_exhausted", "Roboflow inference credits are unavailable");
    }
    throw new HttpError(502, "inference_failed", "Roboflow inference is unavailable");
  }
  const payload = (await response.json()) as { predictions?: Prediction[]; image?: { width?: unknown; height?: unknown } };
  if (!Array.isArray(payload.predictions)) {
    throw new HttpError(502, "invalid_inference_response", "Roboflow returned an invalid response");
  }
  const predictions = payload.predictions.filter(
    (item) => item && item.class === "egg_tray" && typeof item.confidence === "number",
  );
  if (predictions.some((p) => !Number.isFinite(p.confidence) || p.confidence! < 0 || p.confidence! > 1 ||
      (requireSpatial && (![p.x, p.y, p.width, p.height].every(Number.isFinite) || p.width! <= 0 || p.height! <= 0)))) {
    throw new HttpError(502, "invalid_inference_response", "Model returned invalid spatial evidence");
  }
  console.log(JSON.stringify({event: "view_inferred", ...trace, attempts,
    upstream_ms: Date.now() - upstreamStarted, detection_count: predictions.length}));
  // serverless.roboflow.com reports the inferred image size; keep it for the capture gate, tolerate its absence.
  const { width: imageWidth, height: imageHeight } = payload.image ?? {};
  const image = typeof imageWidth === "number" && typeof imageHeight === "number" &&
    Number.isFinite(imageWidth) && Number.isFinite(imageHeight) && imageWidth > 0 && imageHeight > 0
    ? { width: imageWidth, height: imageHeight } : null;
  return {
    count: predictions.length,
    detections: predictions.map(({class: label, confidence, x, y, width, height}) =>
      ({class: label, confidence, x, y, width, height})),
    confidence: predictions.length
      ? predictions.reduce((sum, item) => sum + item.confidence!, 0) / predictions.length
      : 0,
    image,
  };
}

async function sha256(file: File) {
  const digest = await crypto.subtle.digest("SHA-256", await file.arrayBuffer());
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

// A validated, hashed upload: the input of both the open route and a scan job. scanContract: the form field as sent
// (null when absent).
type ParsedScan = { scanId: string; files: Record<string, File>; hashes: string[]; cellIds: Record<string, string>;
  scanContract: string | null; modelScan: boolean; baselineScan: boolean; requestStarted: number; multipartMs: number };

async function countScan(request: Request, env: Bindings) {
  const scan = await readScan(request);
  await archiveScan(env, scan);
  return json(await scanPipeline(env, scan));
}

async function readScan(request: Request): Promise<ParsedScan> {
  const requestStarted = Date.now();
  if (!request.headers.get("content-type")?.startsWith("multipart/form-data")) {
    throw new HttpError(415, "invalid_content_type", "Expected multipart form data");
  }
  const declaredLength = Number(request.headers.get("content-length"));
  console.log(JSON.stringify({event: "scan_received", declared_request_bytes:
    Number.isSafeInteger(declaredLength) && declaredLength > 0 ? declaredLength : null}));
  const form = await request.formData();
  const multipartMs = Date.now() - requestStarted;
  const requestedContract = form.get("scan_contract");
  if (requestedContract !== null && !["cell_identity_v1", "model_spatial_v1"].includes(String(requestedContract))) {
    throw new HttpError(422, "unsupported_scan_contract", "Unknown scan contract");
  }
  const modelScan = requestedContract === "model_spatial_v1";
  const baselineScan = requestedContract === null && !VIEWS.some(view => form.has(`${view}_cell_id`));
  const cellIds = modelScan || baselineScan ? readOptionalCellIds(form) : readCellIds(form);
  const rawScanId = String(form.get("scan_id") ?? crypto.randomUUID()).toLowerCase();
  if (!SCAN_ID.test(rawScanId)) {
    throw new HttpError(422, "invalid_scan_id", "scan_id must be a UUID");
  }
  const files = Object.fromEntries(VIEWS.map((view) => [view, form.get(view)])) as Record<string, string | File | null>;
  for (const view of VIEWS) {
    const file = files[view];
    if (!(file instanceof File)) throw new HttpError(422, "missing_view", `${view.toUpperCase()} image is required`);
    if (!["image/jpeg", "image/png"].includes(file.type)) {
      throw new HttpError(415, "invalid_mime_type", `${view.toUpperCase()} must be a JPEG or PNG image`);
    }
    if (!file.size || file.size > MAX_IMAGE_BYTES) {
      throw new HttpError(413, "image_too_large", `${view.toUpperCase()} is empty or exceeds 20 MB`);
    }
    const signature = new Uint8Array(await file.slice(0, 8).arrayBuffer());
    const jpeg = signature[0] === 0xff && signature[1] === 0xd8 && signature[2] === 0xff;
    const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every((byte, i) => signature[i] === byte);
    if (!jpeg && !png) throw new HttpError(415, "invalid_image_signature", `${view.toUpperCase()} is not a valid JPEG or PNG`);
  }
  console.log(JSON.stringify({event: "scan_validated", scan_id: rawScanId, multipart_ms: multipartMs,
    view_bytes: Object.fromEntries(VIEWS.map(v => [v, (files[v] as File).size]))}));
  const hashStarted = Date.now();
  const hashes: string[] = [];
  for (const view of VIEWS) hashes.push(await sha256(files[view] as File));
  console.log(JSON.stringify({event: "views_hashed", scan_id: rawScanId, hashing_ms: Date.now() - hashStarted}));
  if (new Set(hashes).size !== 3) {
    throw new HttpError(422, "duplicate_view", "LEFT, RIGHT, and STRAIGHT must be distinct photographs");
  }
  return { scanId: rawScanId, files: files as Record<string, File>, hashes, cellIds,
    scanContract: requestedContract === null ? null : String(requestedContract), modelScan, baselineScan, requestStarted, multipartMs };
}

// Private, content-addressed originals survive failed inference and retries.
// No public download route: operators retrieve using authenticated R2 access.
async function archiveScan(env: Bindings, { scanId: rawScanId, files, hashes }: ParsedScan) {
  if (env.SCAN_ARCHIVE) {
    for (const [index, view] of VIEWS.entries()) {
      const file = files[view];
      await env.SCAN_ARCHIVE.put(`scans/${rawScanId}/${view}/${hashes[index]}`, file.stream(), {
        httpMetadata: { contentType: file.type },
        customMetadata: { scan_id: rawScanId, view, sha256: hashes[index], received_at: new Date().toISOString() },
      });
    }
    console.log(JSON.stringify({ event: "scan_archived", scan_id: rawScanId }));
  }
}

// Inference, fusion and the block model; returns the count response body.
async function scanPipeline(env: Bindings, scan: ParsedScan): Promise<Record<string, unknown>> {
  const { scanId: rawScanId, files, cellIds, modelScan, baselineScan, requestStarted, multipartMs } = scan;
  const started = Date.now();
  const results = {} as Record<string, ViewInference>;
  for (const view of VIEWS) results[view] = await infer(files[view], env, modelScan,
    {scan_id: rawScanId, view});
  console.log(JSON.stringify({event: "scan_stages_complete", scan_id: rawScanId,
    multipart_ms: multipartMs, inference_ms: Date.now() - started,
    total_ms: Date.now() - requestStarted}));
  if (modelScan) {
    console.log(JSON.stringify({event: "scan_complete", scan_id: rawScanId, accepted: false,
      counts: Object.fromEntries(VIEWS.map(v => [v, results[v].count])), latency_ms: Date.now() - started}));
    const columns = Object.fromEntries(VIEWS.map(view => [view, spanColumns(results[view].detections ?? [])]));
    const rimStatus = await rimVerify(files, columns, env);
    console.log(JSON.stringify({event: "rim_verify", scan_id: rawScanId, status: rimStatus}));
    return modelDiagnostics(rawScanId, results, cellIds, env, Date.now() - started, columns, rimStatus);
  }
  if (baselineScan) return baselineResponse(rawScanId, results, env, Date.now() - started);
  const stacks = fuseCells(results, cellIds, Number(env.MAX_VIEW_COUNT_RATIO));
  const accepted = stacks.every((stack) => stack.accepted);
  const finalCount = accepted ? stacks.reduce((sum, stack) => sum + stack.final_count!, 0) : null;
  const latency = Date.now() - started;
  const views = Object.fromEntries(VIEWS.map((view) => [view, {
    quality: results[view].confidence,
    accepted: stacks.find((stack) => stack.physical_stack_id === cellIds[view])!.accepted,
    blur_score: 0,
    exposure_mean: 0,
    reason: stacks.find((stack) => stack.physical_stack_id === cellIds[view])!.reason,
  }]));
  const counts = Object.fromEntries(VIEWS.map((view) => [view, results[view].count]));
  console.log(JSON.stringify({ event: "scan_complete", scan_id: rawScanId, accepted, counts, latency_ms: latency }));
  return {
    scan_id: rawScanId,
    status: accepted ? "verified" : "manual_recount_required",
    accepted,
    physical_stack_count: null,
    physical_cell_count: accepted ? stacks.length : null,
    total_trays: finalCount,
    eggs_per_tray: Number(env.EGGS_PER_TRAY),
    total_eggs: accepted ? finalCount! * Number(env.EGGS_PER_TRAY) : null,
    model: { provider: "roboflow_serverless", workspace: "", project: "projec-mutta", version: "2", model_id: env.MODEL_ID },
    processing: { mode: "cell_identity_v1", latency_ms: latency, model_version: env.MODEL_ID, timings_ms: { total: latency } },
    cell_ids: cellIds,
    views,
    stacks,
    rescan: accepted ? null : {
      recommended_view: VIEWS.find((view) => !stacks.find((stack) => stack.physical_stack_id === cellIds[view])!.accepted),
      reason: "MANUAL RECOUNT REQUIRED: inspect each listed cell separately. Do not compare different cell totals.",
    },
  };
}

// Compatibility with the requested August baseline; not the spatial/hybrid path.
function fuseBaselineCounts(results: Record<string, ViewInference>, maxViewCountRatio = 1.25) {
  const positiveCounts = Object.values(results).map(({ count }) => count).filter((count) => count > 0);
  if (positiveCounts.length >= 2) {
    const lowest = Math.min(...positiveCounts);
    const highest = Math.max(...positiveCounts);
    if (highest / lowest > maxViewCountRatio) return null;
  }
  const frequencies = new Map<number, number>();
  for (const { count } of Object.values(results)) {
    if (count > 0) frequencies.set(count, (frequencies.get(count) ?? 0) + 1);
  }
  const agreed = [...frequencies].filter(([, frequency]) => frequency >= 2).map(([count]) => count);
  return agreed.length === 1 ? agreed[0] : null;
}

function baselineResponse(scanId: string, results: Record<string, ViewInference>, env: Bindings, latency: number) {
  const finalCount = fuseBaselineCounts(results, Number(env.MAX_VIEW_COUNT_RATIO));
  const accepted = finalCount !== null;
  const views = Object.fromEntries(VIEWS.map((view) => [view, {
    quality: results[view].confidence,
    accepted: results[view].count > 0,
    blur_score: 0,
    exposure_mean: 0,
    reason: results[view].count > 0 ? null : "No egg trays detected",
  }]));
  const counts = Object.fromEntries(VIEWS.map((view) => [view, results[view].count]));
  const confidence = accepted
    ? Math.min(...VIEWS.filter((view) => results[view].count === finalCount).map((view) => results[view].confidence))
    : 0;
  console.log(JSON.stringify({ event: "scan_complete", scan_id: scanId, accepted, counts, latency_ms: latency }));
  return {
    scan_id: scanId,
    status: accepted ? "verified" : "rescan_required",
    accepted,
    physical_stack_count: accepted ? 1 : null,
    total_trays: finalCount,
    eggs_per_tray: Number(env.EGGS_PER_TRAY),
    total_eggs: accepted ? finalCount! * Number(env.EGGS_PER_TRAY) : null,
    model: { provider: "roboflow_serverless", workspace: "", project: "projec-mutta", version: "2", model_id: env.MODEL_ID },
    processing: { mode: "cloudflare_roboflow_egg_tray_baseline", latency_ms: latency, model_version: env.MODEL_ID, timings_ms: { total: latency } },
    views,
    stacks: [{
      physical_stack_id: "single_stack_baseline",
      counts,
      final_count: finalCount,
      confidence,
      accepted,
      reason: accepted ? "At least two views agree" : "Views disagree or contain a large count mismatch",
      association_confidence: accepted ? 1 : 0,
    }],
    rescan: accepted ? null : {
      recommended_view: VIEWS.reduce((a, b) => results[a].count <= results[b].count ? a : b),
      reason: "RESCAN REQUIRED: views must agree without a large count mismatch",
    },
  };
}

function readOptionalCellIds(form: FormData): Record<string, string> {
  const entries: [string, string][] = [];
  for (const view of VIEWS) {
    const raw = form.get(`${view}_cell_id`);
    if (raw === null || raw === "") continue;
    if (typeof raw !== "string" || !/^[A-Z0-9][A-Z0-9_-]{0,31}$/.test(raw.trim().toUpperCase())) {
      throw new HttpError(422, "invalid_cell_id", "Optional cell IDs must use 1-32 letters, digits, - or _");
    }
    entries.push([view, raw.trim().toUpperCase()]);
  }
  return Object.fromEntries(entries);
}

// ---- Per-stack span counting and block model (ported from backend/app/vision/layer_span.py and block_model.py).
// Measured 2026-10-08 on 53 labelled stacks: span count exact 75%, within ±1 100%; raw box count exact 58%.
type SpanColumn = { column: number; model_boxes: number; span_count: number; walk_count: number; walk_filled: number;
  walk_unresolved_gaps?: number; perspective_gradient: number | null; pitch_px: number; box_height_px?: number;
  duplicate_boxes: number; x_min: number; x_max: number; y_first: number; y_last: number;
  rim_count?: number | null; rim_confidence?: number | null };
type FaceColumn = { layers: number; filled: number; scale: number; recessed: boolean; count_agreement: boolean; reason: string | null; source: string };
type Cell = { x: number; y: number; status: string; layers: number | null; source: string; filled_layers?: number };
const RECESS_SCALE = 0.85;
const MAX_PERSPECTIVE_GRADIENT = 1.5;  // top-third / bottom-third layer spacing; measured frontal photos stay <= 1.42
const MIN_RIM_CONFIDENCE = 0.5;  // rim-edge verification only vetoes when its own confidence is at least this
// Tray boxes are about as tall as the layer spacing (0.79-1.16 on the 53 reference stacks). Far away, cross-stacked
// trays get boxes on alternate layers only, the spacing doubles and the count halves (2026-10-13 corner block: 0.64-0.67).
const MIN_BOX_PITCH_RATIO = 0.75;
// Largest run of missed layers filled inside one gap; no reference stack needed more than one.
const MAX_FILLED_PER_GAP = 2;
const median = (values: number[]) => {
  const s = [...values].sort((a, b) => a - b);
  return s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2;
};
// Python/numpy round() is half-to-even; keep the port identical on exact halves.
const roundHalfEven = (v: number) => {
  const f = Math.floor(v), diff = v - f;
  if (diff > 0.5) return f + 1;
  if (diff < 0.5) return f;
  return f % 2 === 0 ? f : f + 1;
};

// Port of layer_span.walk_layers: count layers with a slowly varying local pitch, merging
// duplicate boxes and filling short runs of missed layers. Exact on 51/53 reference stacks (span: 40/53).
// A gap hiding more than MAX_FILLED_PER_GAP layers is not bridged; it is reported as unresolved.
function walkLayers(ysIn: number[], height: number) {
  const ys = [...ysIn].sort((a, b) => a - b);
  if (!ys.length) return { count: 0, gaps: [] as number[], duplicates: 0, filled: 0, unresolved_gaps: 0, perspective_gradient: null as number | null };
  const rawGaps = ys.slice(1).map((y, i) => y - ys[i]);
  const real = rawGaps.filter(g => g > 0.5 * height);
  const globalPitch = real.length ? median(real) : height;
  let pitch = globalPitch;
  let count = 1, duplicates = 0, filled = 0, unresolved = 0, last = ys[0];
  const gaps: number[] = [];
  for (const y of ys.slice(1)) {
    const gap = y - last;
    if (gap < 0.65 * pitch) { duplicates++; continue; }          // duplicate or stray half-pitch box
    const steps = Math.max(1, roundHalfEven(gap / pitch));
    last = y;
    if (steps - 1 > MAX_FILLED_PER_GAP) { unresolved++; count++; continue; }
    if (steps > 1) filled += steps - 1;
    count += steps;
    for (let k = 0; k < steps; k++) gaps.push(gap / steps);
    pitch = Math.min(Math.max(median(gaps.slice(-3)), 0.6 * globalPitch), 1.4 * globalPitch);
  }
  let gradient: number | null = null;
  if (gaps.length >= 6) {
    const third = Math.max(2, Math.floor(gaps.length / 3));
    gradient = roundHalfEven(1000 * median(gaps.slice(0, third)) / median(gaps.slice(-third))) / 1000;
  }
  return { count, gaps, duplicates, filled, unresolved_gaps: unresolved, perspective_gradient: gradient };
}

function spanColumns(detections: Prediction[]): SpanColumn[] {
  const boxes = detections.filter(d => [d.x, d.y, d.width, d.height].every(v => Number.isFinite(v)) && d.width! > 0 && d.height! > 0)
    .map(d => ({ x: d.x!, y: d.y!, width: d.width!, height: d.height! }));
  if (!boxes.length) return [];
  const gap = 0.6 * median(boxes.map(b => b.width));
  const columns: typeof boxes[] = [];
  for (const box of [...boxes].sort((a, b) => a.x - b.x)) {
    const last = columns[columns.length - 1];
    if (last && box.x - last.reduce((s, b) => s + b.x, 0) / last.length < gap) last.push(box);
    else columns.push([box]);
  }
  return columns.filter(c => c.length >= 3).map((column, index) => {
    const ys = column.map(b => b.y).sort((a, b) => a - b);
    const height = median(column.map(b => b.height));
    const real = ys.slice(1).map((y, i) => y - ys[i]).filter(g => g > 0.5 * height);
    const pitch = real.length ? median(real) : height;
    const walk = walkLayers(ys, height);
    return { column: index + 1, model_boxes: column.length, span_count: roundHalfEven((ys[ys.length - 1] - ys[0]) / pitch) + 1,
      walk_count: walk.count, walk_filled: walk.filled, walk_unresolved_gaps: walk.unresolved_gaps, perspective_gradient: walk.perspective_gradient,
      pitch_px: roundHalfEven(pitch * 100) / 100, box_height_px: roundHalfEven(height * 100) / 100, duplicate_boxes: column.length - real.length - 1,
      x_min: roundHalfEven(Math.min(...column.map(b => b.x - b.width / 2)) * 10) / 10,
      x_max: roundHalfEven(Math.max(...column.map(b => b.x + b.width / 2)) * 10) / 10,
      y_first: roundHalfEven(ys[0] * 10) / 10, y_last: roundHalfEven(ys[ys.length - 1] * 10) / 10 };
  });
}

function faceColumns(columns: SpanColumn[], name: string): FaceColumn[] {
  const ordered = [...columns].sort((a, b) => a.x_min - b.x_min);
  // Reference pitch = median of the front group (pitches at or above the face median).
  const pitches = ordered.map(c => c.pitch_px);
  const faceMedian = median(pitches);
  const reference = median(pitches.filter(p => p >= faceMedian));
  return ordered.map(c => {
    const scale = reference ? c.pitch_px / reference : 1;
    const layers = c.walk_count ?? c.span_count;
    const boxRatio = c.box_height_px && c.pitch_px ? c.box_height_px / c.pitch_px : null;
    let reason: string | null = null;
    const rim = c.rim_count ?? null, rimConf = c.rim_confidence ?? 0;
    if (boxRatio !== null && boxRatio < MIN_BOX_PITCH_RATIO) reason = "boxes found on only some layers (trays too small in the photo); step closer and retake this face";
    else if (c.walk_unresolved_gaps) reason = "boxes are missing over several layers of this stack; retake this face";
    else if (Math.abs(c.span_count - layers) > 1) reason = `layer counts disagree (span ${c.span_count}, walk ${layers}); retake this face`;
    else if (rim !== null && rimConf >= MIN_RIM_CONFIDENCE && rim !== layers) reason = `rim edges count ${rim} layers but boxes count ${layers}; retake this face`;
    else if (c.perspective_gradient !== null && c.perspective_gradient > MAX_PERSPECTIVE_GRADIENT)
      reason = `camera looked down on the stack (spacing ratio ${c.perspective_gradient}); hold the phone level at mid-height`;
    return { layers, filled: c.walk_filled ?? 0, scale, recessed: scale < RECESS_SCALE, count_agreement: reason === null, reason, source: name };
  });
}

const BLOCK_NOTE = "Interior stacks are computed from the observed faces (X x Y x height); missing or shorter interior stacks are not visible from the faces.";

// status: exact (every stack seen, faces agree), estimated (a total, but hidden stacks computed or a reading
// ambiguous), conflict (no total; retake the named face), needs_view (a face is missing or refused).
function blockResult(width: number | null, depth: number | null, facesUsed: string[], typical: number | null, cells: Cell[],
  conflicts: Record<string, unknown>[], ambiguities: Record<string, unknown>[] = [], needsView = false) {
  const observed = cells.filter(c => c.status === "observed").reduce((s, c) => s + (c.layers ?? 0), 0);
  const computed = cells.filter(c => c.status === "computed").reduce((s, c) => s + (c.layers ?? 0), 0);
  const filled = cells.filter(c => c.status === "observed").reduce((s, c) => s + (c.filled_layers ?? 0), 0);
  const rescan = cells.filter(c => c.status === "rescan" || c.status === "conflict").map(c => [c.x, c.y]);
  const consistent = !conflicts.length && !rescan.length && typical !== null;
  const total = consistent ? observed + computed : null;
  const status = needsView ? "needs_view" : total === null ? "conflict" : computed || ambiguities.length ? "estimated" : "exact";
  return { status, width, depth, faces_used: facesUsed, typical_layers: typical, cells, observed_trays: observed, computed_trays: computed,
    filled_trays: filled, total_trays: total, fully_observed: consistent && computed === 0, faces_consistent: consistent,
    conflicts, ambiguities, rescan_cells: rescan, note: BLOCK_NOTE };
}

function buildBlock(straightCols: SpanColumn[], leftCols: SpanColumn[], rightCols: SpanColumn[]) {
  const facesUsed = [...(straightCols.length ? ["straight"] : []), ...(leftCols.length ? ["left"] : []), ...(rightCols.length ? ["right"] : [])];
  if (!straightCols.length || (!leftCols.length && !rightCols.length)) {
    return blockResult(null, null, facesUsed, null, [], [{ reason: "STRAIGHT and at least one side face must show stacks" }], [], true);
  }
  const xf = faceColumns(straightCols, "straight");
  const lf = leftCols.length ? faceColumns(leftCols, "left").reverse() : null;   // left photo: front corner is right-most
  const rf = rightCols.length ? faceColumns(rightCols, "right") : null;          // right photo: front corner is left-most
  const width = xf.length;
  const conflicts: Record<string, unknown>[] = [];
  const ambiguities: Record<string, unknown>[] = [];
  const sides = ([["left", lf], ["right", rf]] as [string, FaceColumn[] | null][]).filter(([, f]) => f);
  const depths = Object.fromEntries(sides.map(([n, f]) => [n, f!.length]));
  if (new Set(Object.values(depths)).size > 1) conflicts.push({ reason: "depth differs between LEFT and RIGHT faces", ...depths });
  const depth = Math.max(...Object.values(depths));
  const heights = [...xf, ...(lf ?? []), ...(rf ?? [])].filter(c => !c.recessed).map(c => c.layers);
  const typical = heights.length ? roundHalfEven(median(heights)) : null;
  const cells = new Map<string, Cell>();
  for (let y = 0; y < depth; y++) for (let x = 0; x < width; x++) cells.set(`${x},${y}`, { x, y, status: "computed", layers: typical, source: "faces" });
  // Every face reading of a cell, merged below, never overwritten: STRAIGHT sees the front row, each side face its
  // column (corner included). A one-wide block puts LEFT and RIGHT on the same cells.
  type Reading = { col: FaceColumn; name: string; behind: string };
  const seen = new Map<string, Reading[]>();
  const add = (key: string, r: Reading) => seen.set(key, [...(seen.get(key) ?? []), r]);
  xf.forEach((col, x) => add(`${x},0`, { col, name: "straight", behind: `${x},1` }));
  for (const [name, f, xi, dx] of [["left", lf, 0, 1], ["right", rf, width - 1, -1]] as [string, FaceColumn[] | null, number, number][]) {
    (f ?? []).forEach((col, y) => add(`${xi},${y}`, { col, name, behind: `${xi + dx},${y}` }));
  }
  const FACE_ORDER = ["straight", "left", "right"];
  const promotions = new Map<string, Partial<Cell>[]>();
  for (const [key, readings] of seen) {
    const cell = cells.get(key)!;
    const names = readings.map(r => r.name);
    const source = names.join("+");
    const corner = cell.y === 0 && readings.length > 1;
    const unsure = readings.filter(r => !r.col.count_agreement);
    for (const r of unsure) conflicts.push({ cell: [cell.x, cell.y], reason: `${r.name.toUpperCase()}: ${r.col.reason}` });
    if (unsure.length) {
      Object.assign(cell, { status: "rescan", layers: readings[0].col.recessed ? 0 : readings[0].col.layers, source });
      continue;
    }
    if (new Set(readings.map(r => r.col.recessed)).size > 1) {
      const other = readings.find(r => r.col.recessed !== readings[0].col.recessed)!.name;
      conflicts.push({ cell: [cell.x, cell.y],
        reason: `${corner ? "corner stack" : "stack"} is set back on one face only (${names[0].toUpperCase()} vs ${other.toUpperCase()})` });
      Object.assign(cell, { status: "conflict", layers: null, source });
      continue;
    }
    if (readings[0].col.recessed) {
      Object.assign(cell, { status: "missing", layers: 0, source });
      for (const r of readings) {
        if (cell.y === 0 && r.name !== "straight") continue;   // a side face looks along the front row past a missing corner
        if (cells.has(r.behind)) promotions.set(r.behind, [...(promotions.get(r.behind) ?? []),
          { status: "observed", layers: r.col.layers, filled_layers: r.col.filled, source: `${r.name}-recessed` }]);
        else conflicts.push({ cell: [cell.x, cell.y], reason: `${r.name.toUpperCase()} shows a stack behind a missing one, but the faces give no room for it; rescan` });
      }
      continue;
    }
    const values = Object.fromEntries(readings.map(r => [r.name, r.col.layers])) as Record<string, number>;
    const low = readings.reduce((a, b) => b.col.layers < a.col.layers ? b : a).name;
    const high = readings.reduce((a, b) => b.col.layers > a.col.layers ? b : a).name;
    const layerFields = Object.fromEntries(Object.entries(values).map(([n, v]) => [`${n}_layers`, v]));
    if (values[high] - values[low] > 1) {
      const pair = [...new Set([low, high])].sort((a, b) => FACE_ORDER.indexOf(a) - FACE_ORDER.indexOf(b));
      conflicts.push({ cell: [cell.x, cell.y], reason: `${corner && "straight" in values ? "corner height" : "height"} differs between ${pair[0].toUpperCase()} and ${pair[1].toUpperCase()}`, ...layerFields });
      Object.assign(cell, { status: "conflict", layers: null, source });
      continue;
    }
    // Agreeing faces, or one layer apart: keep the reading with fewest gap-filled layers (STRAIGHT on a tie)
    // and record the ambiguity so the total is only an estimate.
    const best = [...readings].sort((a, b) => a.col.filled - b.col.filled || Number(a.name !== "straight") - Number(b.name !== "straight"))[0].col;
    Object.assign(cell, { status: "observed", layers: best.layers, filled_layers: best.filled, source });
    if (values[high] !== values[low]) ambiguities.push({ cell: [cell.x, cell.y], reason: "faces differ by one layer", ...layerFields, chosen: best.layers });
  }
  for (const [key, candidates] of promotions) {
    const cell = cells.get(key)!;
    const layers = new Set(candidates.map(c => c.layers));
    if (cell.status === "computed" && layers.size === 1) Object.assign(cell, candidates[0]);
    else if (cell.status === "observed" && layers.size === 1 && layers.has(cell.layers)) cell.source += "+" + candidates.map(c => c.source).join("+");
    else {
      Object.assign(cell, { status: "conflict", layers: null, source: candidates.map(c => c.source).join("+") });
      conflicts.push({ cell: [cell.x, cell.y], reason: "faces disagree about the stack behind a missing one" });
    }
  }
  return blockResult(width, depth, facesUsed, typical, [...cells.values()], conflicts, ambiguities);
}

// ---- Capture-quality gate for the model_spatial_v1 path.
// Tuned 2026-10-08 on the 39 tagged labelled photos (reports/field-labelled-20261007/capture_tags.csv): the tags were
// assigned after seeing the V2 errors, so this is a hindsight-biased development tuning set, not a validation set.
// Measured there: frontal fill-frame 17/18 accepted (img 4 rejected: block fills 40% of the frame height),
// angled/corner/multi-block + distant/wide 18/21 rejected (imgs 25, 26, 41 pass every signal: one is a single
// column, two show a second block at a different depth with the same pitch, which these signals cannot see).
// Signals use only the span columns and the inferred image size; coverage and height are skipped when the size is unknown.
const GATE = {
  max_pitch_gradient: 1.2,   // median pitch of the first third of columns (by x) vs the last third, max/min
  min_coverage_x: 0.45,      // union of column x-extents as a fraction of the image width
  min_coverage_single: 0.25, // a lone stack (side face of a one-row block) cannot fill a portrait frame's width
  min_height_frac: 0.4,      // tallest column span (first to last box centre + one pitch) as a fraction of the image height
  recess_floor: 0.6,         // one column at 0.6-0.85 of the front-group pitch is a stack set back one position, not an angle
  // A face filling most of the frame height is close enough even when it is narrow: a 1-3 stack face in a
  // landscape photo cannot fill the width. Neutral on the 39 tagged photos (2026-10-09).
  full_height_waiver: 0.8,
  // Tray boxes are wide (median width/height 3.1-6.4 on every usable photo); a sideways photo makes the
  // detector return a few square boxes (1.1-2.6). Below this the face is refused, not counted.
  min_box_aspect: 2.75,
};
const NO_STACKS = "no stacks detected";
const SIDEWAYS = "the trays look sideways or unclear in this photo; hold the phone level and retake";
const CAPTURE_ADVICE = "Step closer and face the block squarely; the whole face must fill the frame";
type CaptureMetrics = { columns: number; model_boxes: number; pitch_px: number | null; pitch_frac: number | null;
  height_frac: number | null; coverage_x: number | null; pitch_gradient: number | null; recessed_columns: number;
  min_pitch_scale: number | null; box_aspect: number | null; image: ImageSize | null };
type CaptureQuality = { accepted: boolean; reasons: string[]; metrics: CaptureMetrics };
const round3 = (v: number | null) => v === null ? null : Math.round(v * 1000) / 1000;

/** Median width/height of the detections; null when no box has a size. */
function medianBoxAspect(detections: Prediction[]): number | null {
  const aspects = detections.filter(d => (d.width ?? 0) > 0 && (d.height ?? 0) > 0).map(d => d.width! / d.height!);
  return aspects.length ? median(aspects) : null;
}

function captureQuality(columns: SpanColumn[], imageWidth: number | null, imageHeight: number | null,
  boxAspect: number | null = null): CaptureQuality {
  const w = imageWidth !== null && Number.isFinite(imageWidth) && imageWidth > 0 ? imageWidth : null;
  const h = imageHeight !== null && Number.isFinite(imageHeight) && imageHeight > 0 ? imageHeight : null;
  const image = w && h ? { width: w, height: h } : null;
  const aspect = boxAspect !== null && Number.isFinite(boxAspect) ? boxAspect : null;
  const sideways = aspect !== null && aspect < GATE.min_box_aspect;
  if (!columns.length) {
    return { accepted: false, reasons: sideways ? [SIDEWAYS, NO_STACKS] : [NO_STACKS], metrics: { columns: 0, model_boxes: 0,
      pitch_px: null, pitch_frac: null, height_frac: null, coverage_x: null, pitch_gradient: null, recessed_columns: 0,
      min_pitch_scale: null, box_aspect: round3(aspect), image } };
  }
  const ordered = [...columns].sort((a, b) => a.x_min - b.x_min);
  const pitches = ordered.map(c => c.pitch_px);
  const faceMedian = median(pitches);
  const reference = median(pitches.filter(p => p >= faceMedian));
  const scales = pitches.map(p => reference ? p / reference : 1);
  const recessed = scales.map((s, i) => s < RECESS_SCALE ? i : -1).filter(i => i >= 0);
  // Allow one recessed column (the block model's missing-front-stack case) and leave it out of the gradient;
  // a lone column below the floor is more than one tray depth back, which only an angled view produces.
  const gradientColumns = recessed.length === 1 && scales[recessed[0]] >= GATE.recess_floor
    ? ordered.filter((_, i) => i !== recessed[0]) : ordered;
  const k = Math.max(1, Math.ceil(gradientColumns.length / 3));
  const head = median(gradientColumns.slice(0, k).map(c => c.pitch_px));
  const tail = median(gradientColumns.slice(-k).map(c => c.pitch_px));
  const gradient = gradientColumns.length >= 2 && head > 0 && tail > 0 ? Math.max(head / tail, tail / head) : 1;
  let covered = 0;
  let span: [number, number] | null = null;
  for (const c of ordered) {
    if (span && c.x_min <= span[1]) span[1] = Math.max(span[1], c.x_max);
    else { if (span) covered += span[1] - span[0]; span = [c.x_min, c.x_max]; }
  }
  if (span) covered += span[1] - span[0];
  const coverage = w ? covered / w : null;
  const heightFrac = h ? Math.max(...ordered.map(c => c.y_last - c.y_first + c.pitch_px)) / h : null;
  const pitchFrac = h ? faceMedian / h : null;
  const reasons: string[] = [];
  // Sideways first: every other reason is measured on boxes that are not trays.
  if (sideways) reasons.push(SIDEWAYS);
  if (gradient > GATE.max_pitch_gradient) reasons.push("layer pitch changes across the face (angled or corner view)");
  const minCoverage = ordered.length === 1 ? GATE.min_coverage_single : GATE.min_coverage_x;
  const fillsHeight = heightFrac !== null && heightFrac >= GATE.full_height_waiver;
  if (coverage !== null && coverage < minCoverage && !fillsHeight) reasons.push("stacks cover too little of the frame width");
  if (heightFrac !== null && heightFrac < GATE.min_height_frac) reasons.push("stacks are too small in the frame (too far away)");
  return { accepted: !reasons.length, reasons, metrics: {
    columns: ordered.length, model_boxes: ordered.reduce((s, c) => s + c.model_boxes, 0),
    pitch_px: Math.round(faceMedian * 100) / 100, pitch_frac: round3(pitchFrac), height_frac: round3(heightFrac),
    coverage_x: round3(coverage), pitch_gradient: round3(gradient), recessed_columns: recessed.length,
    min_pitch_scale: round3(Math.min(...scales)), box_aspect: round3(aspect), image } };
}

// Worst view first: no stacks, then most reasons, then the smallest face in the frame, then LEFT/RIGHT/STRAIGHT order.
function worstView(capture: Record<string, CaptureQuality>, views: readonly string[]) {
  const rank = (q: CaptureQuality) => (q.reasons.includes(NO_STACKS) ? 100 : 0) + q.reasons.length * 10 + (1 - (q.metrics.height_frac ?? 1));
  return [...views].filter(v => !capture[v].accepted).sort((a, b) => rank(capture[b]) - rank(capture[a]) || views.indexOf(a) - views.indexOf(b))[0];
}

// ---- Manual count (field validation): the operator's on-site per-stack count, stored next to the
// scan's archived photos. It is ground truth for scoring; the Worker never uses it for counting.
async function manualCount(request: Request, env: Bindings, scanId: string) {
  if (!env.SCAN_ARCHIVE) throw new HttpError(503, "archive_unavailable", "Manual counts need the scan archive");
  if (!SCAN_ID.test(scanId)) {
    throw new HttpError(422, "invalid_scan_id", "scan_id must be a UUID");
  }
  const { blockId, clean, notes, tray, appVersion, totals } = await readManualCountBody(request);
  const recordedAt = new Date().toISOString();
  const record = { kind: "manual_count_v1", scan_id: scanId, block_id: blockId, cells: clean, notes, tray, recorded_at: recordedAt,
    app_version: appVersion, totals };
  const key = `scans/${scanId}/manual-count/${recordedAt.replace(/[:.]/g, "-")}.json`;
  const body_ = JSON.stringify(record);
  const meta = { httpMetadata: { contentType: "application/json" }, customMetadata: { scan_id: scanId, block_id: blockId, kind: "manual_count" } };
  // Timestamped history plus a fixed "latest" key so scoring can fetch one object per scan.
  await env.SCAN_ARCHIVE.put(key, body_, meta);
  await env.SCAN_ARCHIVE.put(`scans/${scanId}/manual-count/latest.json`, body_, meta);
  console.log(JSON.stringify({ event: "manual_count_stored", scan_id: scanId, block_id: blockId, cells: clean.length, key }));
  return json({ stored: true, key, latest_key: `scans/${scanId}/manual-count/latest.json`, totals });
}

// The operator's count as validated today; shared by the open route and the enforced (count_id) route.
async function readManualCountBody(request: Request) {
  let body: Record<string, unknown>;
  try { body = await request.json() as Record<string, unknown>; } catch { throw new HttpError(422, "invalid_json", "Body must be JSON"); }
  const blockId = String(body?.block_id ?? "").trim();
  if (!blockId || blockId.length > 64) throw new HttpError(422, "invalid_block_id", "block_id is required (max 64 characters)");
  const cells = body?.cells;
  if (!Array.isArray(cells) || !cells.length || cells.length > 400) throw new HttpError(422, "invalid_cells", "cells must be a non-empty list (max 400)");
  const int = (v: unknown, max: number) => Number.isInteger(v) && (v as number) >= 0 && (v as number) <= max;
  const clean = cells.map((c: Record<string, unknown>) => {
    if (!int(c?.x, 100) || !int(c?.y, 100) || !int(c?.filled, 1000) || !int(c?.empty, 1000)) {
      throw new HttpError(422, "invalid_cell", "each cell needs integer x, y, filled, empty");
    }
    return { x: c.x as number, y: c.y as number, filled: c.filled as number, empty: c.empty as number, unreachable: c.unreachable === true,
      app_layers: Number.isInteger(c.app_layers) ? c.app_layers as number : null,
      app_status: typeof c.app_status === "string" ? c.app_status.slice(0, 32) : null };
  });
  if (new Set(clean.map(c => `${c.x},${c.y}`)).size !== clean.length) throw new HttpError(422, "duplicate_cell", "cells must be unique by x,y");
  const notes = typeof body.notes === "string" ? body.notes.slice(0, 2000) : "";
  const trayRaw = body.tray && typeof body.tray === "object" ? Object.entries(body.tray as Record<string, unknown>) : [];
  const tray = Object.fromEntries(trayRaw.filter(([k, v]) => k.length <= 40 && typeof v === "number" && Number.isFinite(v)).slice(0, 10));
  const totals = { filled: clean.reduce((s, c) => s + c.filled, 0), empty: clean.reduce((s, c) => s + c.empty, 0), unreachable: clean.filter(c => c.unreachable).length };
  const appVersion = typeof body.app_version === "string" ? body.app_version.slice(0, 32) : null;
  return { body, blockId, clean, notes, tray, appVersion, totals };
}

// Keys archived for one scan (photos by view/sha, manual counts). Key names only; bytes need
// authenticated R2 access. Scan ids are unguessable UUIDs.
// withJob (admin route when enforced): also the scan job's photo hashes, null when the scan has no job. The open
// production Worker can add photos under the same prefix, so the job names the three photos this scan counted.
// It lists each view and the manual counts separately (up to 100 keys each), because the open manual-count route adds
// an object under manual-count/ on every call, which sorts between left/ and right/ and would push those photos out of
// one shared listing; `truncated_prefixes` names every prefix that had more (`truncated`: any did).
async function listArchive(env: Bindings, scanId: string, withJob = false) {
  if (!env.SCAN_ARCHIVE) throw new HttpError(503, "archive_unavailable", "Scan archive is not configured");
  if (!SCAN_ID.test(scanId)) {
    throw new HttpError(422, "invalid_scan_id", "scan_id must be a UUID");
  }
  const entry = (o: R2Object) => ({ key: o.key, size: o.size, uploaded: o.uploaded });
  if (!withJob) {
    const listed = await env.SCAN_ARCHIVE.list({ prefix: `scans/${scanId}/`, limit: 100 });
    return json({ scan_id: scanId, keys: listed.objects.map(entry) });
  }
  const bucket = env.SCAN_ARCHIVE;
  const key = jobKey(env, scanId);
  const prefixes = [...VIEWS, "manual-count"].map((name) => `scans/${scanId}/${name}/`).sort();   // R2 key order
  const listed = await Promise.all(prefixes.map((prefix) => bucket.list({ prefix, limit: 100 })));
  const keys = listed.flatMap((page) => page.objects.map(entry));
  const truncatedPrefixes = prefixes.filter((_, i) => listed[i].truncated);
  const stored = await readState<JobRecord>(bucket, key);
  const job = stored ? { image_hashes: stored.value.image_hashes, status: stored.value.status, attempt: stored.value.attempt,
    owner: stored.value.owner, pipeline_version: stored.value.pipeline_version, created_at: stored.value.created_at } : null;
  return json({ scan_id: scanId, keys, truncated: truncatedPrefixes.length > 0, truncated_prefixes: truncatedPrefixes, job });
}

// Independent second count: the Python service counts horizontal rim edges inside each stack
// column. Attaches rim_count/rim_confidence to the columns; never blocks the scan when the
// service is off or unreachable (status "unavailable").
async function rimVerify(files: Record<string, File>, columns: Record<string, SpanColumn[]>, env: Bindings) {
  const status: Record<string, string> = {};
  if (env.RIM_VERIFY !== "true") { for (const v of VIEWS) status[v] = "disabled"; return status; }
  if (!env.VISION_SERVICE_URL || !env.VISION_SERVICE_TOKEN) { for (const v of VIEWS) status[v] = "not_configured"; return status; }
  await Promise.all(VIEWS.map(async view => {
    if (!columns[view].length) { status[view] = "no_columns"; return; }
    try {
      const form = new FormData();
      form.set("image", files[view], `${view}.jpg`);
      form.set("columns", JSON.stringify(columns[view]));
      const response = await fetch(new URL("/candidate/rim-count", env.VISION_SERVICE_URL), {
        method: "POST", headers: { Authorization: `Bearer ${env.VISION_SERVICE_TOKEN}` }, body: form, signal: AbortSignal.timeout(60_000),
      });
      if (!response.ok) { status[view] = `unavailable_${response.status}`; return; }
      const body = await response.json() as { columns?: { column: number; rim_count: number | null; confidence: number }[] };
      for (const r of body.columns ?? []) {
        const target = columns[view][r.column - 1];
        if (target) { target.rim_count = Number.isInteger(r.rim_count) ? r.rim_count : null; target.rim_confidence = Number.isFinite(r.confidence) ? r.confidence : 0; }
      }
      status[view] = "ok";
    } catch { status[view] = "unavailable"; }
  }));
  return status;
}

// Every scan's latest manual count (operator ground truth), for scoring and the master CSV.
async function listManualCounts(env: Bindings) {
  if (!env.SCAN_ARCHIVE) throw new HttpError(503, "archive_unavailable", "Scan archive is not configured");
  const records: unknown[] = [];
  let cursor: string | undefined;
  do {
    const page = await env.SCAN_ARCHIVE.list({ prefix: "scans/", cursor, limit: 1000 });
    for (const object of page.objects) {
      if (!object.key.endsWith("/manual-count/latest.json")) continue;
      const body = await env.SCAN_ARCHIVE.get(object.key);
      if (body) records.push(await body.json());
      if (records.length >= 500) break;
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor && records.length < 500);
  return json({ count: records.length, records });
}

function modelDiagnostics(scanId: string, results: Record<string, ViewInference>, cellIds: Record<string, string>, env: Bindings, latency: number,
  precomputed?: Record<string, SpanColumn[]>, rimStatus?: Record<string, string>) {
  const columns = precomputed ?? Object.fromEntries(VIEWS.map(view => [view, spanColumns(results[view].detections ?? [])]));
  const capture = Object.fromEntries(VIEWS.map(view => [view,
    captureQuality(columns[view], results[view].image?.width ?? null, results[view].image?.height ?? null,
      medianBoxAspect(results[view].detections ?? []))]));
  const rejectedView = worstView(capture, VIEWS);
  const assembled = buildBlock(columns.straight, columns.left, columns.right);
  // When the block model names a face in its first conflict, that is the photo to retake.
  const namedFace = (() => {
    for (const c of assembled.conflicts) {
      const reason = String(c.reason ?? "");
      const m = /^(LEFT|RIGHT|STRAIGHT):/.exec(reason) ?? /STRAIGHT and (LEFT|RIGHT)/.exec(reason);
      if (m) return { view: m[1].toLowerCase(), reason };
    }
    return null;
  })();
  // A face that fails the capture gate gives no usable column counts, so the block total is withheld.
  const block = rejectedView
    ? { ...assembled, status: "needs_view", total_trays: null, faces_consistent: false, fully_observed: false } : assembled;
  // Model boxes are useful evidence, but not proof of cross-view identity or egg occupancy.
  // Do not substitute whole-photo voting for an unfinished spatial hybrid pipeline.
  const reason = "Model detections are available. Physical stack matching and egg occupancy remain unresolved; these per-photo counts are not a verified inventory total.";
  const rescan = rejectedView
    ? { recommended_view: rejectedView, reason: `${CAPTURE_ADVICE} (${rejectedView.toUpperCase()}: ${capture[rejectedView].reasons.join("; ")})` }
    : namedFace
      ? { recommended_view: namedFace.view, reason: namedFace.reason }
      : { recommended_view: "straight", reason };
  return {
    // Legacy top-level fields stay "not verified" for installed APKs; result_status is the block's one result state.
    scan_id: scanId, status: "rescan_required", accepted: false, result_status: block.status,
    physical_stack_count: null, total_trays: null, total_eggs: null,
    eggs_per_tray: Number(env.EGGS_PER_TRAY), cell_ids: cellIds,
    model: { provider: "roboflow_serverless", model_id: env.MODEL_ID },
    processing: { mode: "model_spatial_v1", latency_ms: latency, model_version: env.MODEL_ID, timings_ms: { total: latency } },
    views: Object.fromEntries(VIEWS.map(view => [view, {
      quality: 0, accepted: false, reason, detections: results[view].detections,
      detector_mean_confidence: results[view].confidence, stack_columns: columns[view], image: results[view].image ?? null,
    }])),
    stacks: [{ physical_stack_id: "Per-photo model detections (unmatched)",
      counts: Object.fromEntries(VIEWS.map(view => [view, results[view].count])),
      final_count: null, confidence: 0, accepted: false, reason }],
    // Block model: STRAIGHT = X face, LEFT/RIGHT = Y faces. total_trays here is X x Y x height computed
    // from observed faces; it is not a field-validated inventory until the held-out scene test passes.
    block: { ...block, contract: "block_model_v1", eggs_per_tray: Number(env.EGGS_PER_TRAY),
      verification: { method: "rim_edges", views: rimStatus ?? Object.fromEntries(VIEWS.map(v => [v, "disabled"])) },
      // Egg occupancy is not measured: this is tray capacity if every counted tray is full.
      total_eggs: block.total_trays === null ? null : block.total_trays * Number(env.EGGS_PER_TRAY),
      eggs_basis: "capacity_if_every_tray_full", capture },
    rescan,
  };
}

async function reconstructPair(request: Request, env: Bindings) {
  if (!env.VISION_SERVICE_TOKEN || !env.VISION_SERVICE_URL || !env.SCAN_ARCHIVE)
    throw new HttpError(503, "reconstruction_not_configured", "3D service is not configured on this server");
  if (!request.headers.get("content-type")?.startsWith("multipart/form-data"))
    throw new HttpError(415, "invalid_content_type", "Expected two image files");
  const reader = request.body?.getReader();
  if (!reader) throw new HttpError(422, "missing_images", "Two images are required");
  const chunks: Uint8Array[] = [];
  let bytes = 0;
  while (true) {
    const chunk = await reader.read();
    if (chunk.done) break;
    bytes += chunk.value.length;
    if (bytes > 4_100_000) {
      await reader.cancel();
      throw new HttpError(413, "request_too_large", "Each photo must be at most 2 MB");
    }
    chunks.push(chunk.value);
  }
  const body = new Uint8Array(bytes);
  let offset = 0;
  for (const chunk of chunks) { body.set(chunk, offset); offset += chunk.length; }
  let form: FormData;
  try { form = await new Response(body, {headers: request.headers}).formData(); }
  catch { throw new HttpError(422, "invalid_multipart", "Photo upload could not be read"); }
  const scanId = crypto.randomUUID();
  const files: File[] = [], hashes: string[] = [];
  for (const view of ["first", "second"]) {
    const file = form.get(view);
    if (!(file instanceof File)) throw new HttpError(422, "missing_image", `${view} photo is required`);
    if (!["image/jpeg", "image/png"].includes(file.type)) throw new HttpError(415, "invalid_image_type", "Use JPEG or PNG photos");
    if (!file.size || file.size > 2_000_000) throw new HttpError(413, "image_too_large", "Each photo must be at most 2 MB");
    const sig = new Uint8Array(await file.slice(0, 8).arrayBuffer());
    if (!(sig[0] === 255 && sig[1] === 216 && sig[2] === 255) &&
        ![137,80,78,71,13,10,26,10].every((v,i) => sig[i] === v))
      throw new HttpError(415, "invalid_image_signature", "Invalid photo data");
    files.push(file); hashes.push(await sha256(file));
  }
  if (hashes[0] === hashes[1]) throw new HttpError(422, "duplicate_images", "Choose two different overlapping photos");
  let processing: unknown = null;
  const supplied = form.get("client_processing");
  if (supplied !== null) {
    if (typeof supplied !== "string" || supplied.length > 4000) throw new HttpError(422, "invalid_processing", "Invalid image processing metadata");
    try { processing = JSON.parse(supplied); }
    catch { throw new HttpError(422, "invalid_processing", "Invalid image processing metadata"); }
  }
  const upstreamForm = new FormData();
  for (const [i, view] of ["first", "second"].entries()) {
    await env.SCAN_ARCHIVE.put(`reconstruct/${scanId}/${view}/${hashes[i]}`, files[i].stream(), {
      httpMetadata: {contentType: files[i].type},
      customMetadata: {scan_id:scanId, view, sha256:hashes[i], client_processing:JSON.stringify(processing)},
    });
    upstreamForm.set(view, files[i], `${view}.${files[i].type === "image/png" ? "png" : "jpg"}`);
  }
  const started = Date.now();
  let response: Response;
  try {
    response = await fetch(new URL("/candidate/reconstruct", env.VISION_SERVICE_URL), {
      method:"POST", headers:{Authorization:`Bearer ${env.VISION_SERVICE_TOKEN}`},
      body:upstreamForm, signal:AbortSignal.timeout(130_000),
    });
  } catch { throw new HttpError(504, "vision_timeout", "3D service did not respond. Retry shortly"); }
  if (response.status === 401) throw new HttpError(502, "vision_auth_failed", "3D service authentication needs administrator attention");
  if (response.status === 429) throw new HttpError(429, "vision_busy", "3D service is busy. Retry shortly");
  if (response.status >= 500) throw new HttpError(502, "vision_unavailable", "3D service is temporarily unavailable");
  if (!response.ok) throw new HttpError(response.status, "vision_images_rejected", "Images were rejected. Use distinct photos with matching dimensions");
  let result: Record<string, unknown>;
  try { result = await response.json() as Record<string, unknown>; }
  catch { throw new HttpError(502, "vision_invalid_response", "3D service returned an unreadable result"); }
  if (!result || result.physical_trays !== null || result.verified !== false ||
      !["reconstructed", "insufficient_matches", "pose_failed"].includes(String(result.status)) ||
      result.scale !== "arbitrary_unit_baseline")
    throw new HttpError(502, "vision_invalid_response", "3D service returned an incompatible diagnostic result");
  return json({...result, scan_id:scanId, input_hashes:{first:hashes[0],second:hashes[1]},
    timing:{upstream_ms:Date.now()-started}, client_processing:processing});
}

// ---- Devices, admin and scan jobs (AUTH_MODE=enforce or observe; contract: docs/SCAN_JOBS_AND_DEVICES.md).
// Records live in SCAN_ARCHIVE under STATE_PREFIX, outside scans/, so the archive listings never return them.
// Claims are create-only puts (If-None-Match: *); status changes are compare-and-swap puts (etagMatches).
// A null put means another request won. A claim is never decided from a GET.
// Open mode (AUTH_MODE unset or "open") never reaches this code: jobs and idempotency are enforce-only, so the
// installed 0.4.11 app keeps exactly today's answers until production is promoted. Observe mode reaches it for
// every request that carries a credential.
const PIPELINE_VERSION = "worker-0.4.12";
// How long a claimed job is left to its attempt before a retry may take it over. Cloudflare keeps waitUntil work alive
// for at most 30 s after the client disconnects, so an attempt whose phone gave up (the app's 90 s receive timeout, or
// a dropped link the edge noticed) is cancelled by about 120 s after the claim and writes nothing; one whose
// disconnect is never seen runs to its end and stores its result. 150 s is past that 120 s, and well inside
// the app's 3-minute wait for the result, so the app gets 409 processing_interrupted and uploads again instead of
// reporting the result lost. The longest count is computed, not measured: about 182 s of sequential inference with
// retries (3 views x up to 3 tries of 20 s, plus back-off) and up to 60 s of rim verification when RIM_VERIFY is on.
// Only a client that stays connected that long (the replay script) can outlive the lease; a retry then counts again
// and finishJob gives both the same stored answer (one extra inference, never two answers).
const LEASE_MS = 150_000;
// The job fingerprint covers the photos and what the upload asked for; jobs written before it have version 1
// (the photo hashes alone) and are matched on the photos only, as they were.
const FINGERPRINT_VERSION = 2;
const CAS_RETRIES = 5;
// latest.json: each lost round means another save moved it, so one round per save racing on the scan is enough
// (8 saves in ascending count time need up to 8; CAS_RETRIES = 5 answered 503 to the newest ones in the tests).
// The bound only stops a runaway (2 R2 calls per round).
const LATEST_RETRIES = 16;
const MAX_DIAGNOSTIC_BYTES = 25 * 1024 * 1024;
// Registration is the one enforced route that reads a body before any credential; the app sends about 150 bytes.
const MAX_REGISTRATION_BYTES = 4 * 1024;
// Control characters, bidi overrides and invisible marks in a registrant's label could forge or hide rows in the
// admin's device table (scripts/devices.py); each run becomes one space.
const UNSAFE_TEXT = /[\u0000-\u001f\u007f-\u009f\u061c\u200b-\u200f\u2028-\u202e\u2060-\u2069\ufeff]+/g;
// A manual count's created_at may run at most this far ahead of the server clock.
const MAX_CLOCK_SKEW_MS = 60 * 60 * 1000;
const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const DEVICE_SECRET = /^[A-Za-z0-9_-]{43,128}={0,2}$/;   // at least 32 random bytes, base64url
const ISO_TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,9})?)?(Z|[+-]\d{2}:\d{2})$/;

type DeviceStatus = "pending" | "active" | "revoked";
type DeviceRecord = { v: 1; device_id: string; secret_sha256: string; status: DeviceStatus; label: string | null;
  app_version: string | null; created_at: string; approved_at: string | null; revoked_at: string | null };
type JobError = { status: number; code: string; message: string };
// fingerprint_version, scan_contract and cell_ids are absent on jobs written before fingerprint version 2.
type JobRecord = { v: 1; scan_id: string; owner: string; image_hashes: Record<string, string>; fingerprint: string;
  fingerprint_version?: number; scan_contract?: string | null; cell_ids?: Record<string, string>;
  pipeline_version: string; status: "running" | "done" | "failed"; attempt: number; lease_until: string;
  created_at: string; updated_at: string; result?: Record<string, unknown>; error?: JobError };
type DeviceCaller = { kind: "device"; device_id: string; record: DeviceRecord };
type Caller = { kind: "admin" } | DeviceCaller;
type Stored<T> = { value: T; etag: string };
type ManualRecord = { scan_id: string; block_id: string; cells: unknown; notes: unknown; tray: unknown; app_version: unknown;
  app_total?: unknown; created_at?: string; recorded_at?: string; count_id?: string; totals?: unknown; recorded_by?: string };

type AuthMode = "open" | "observe" | "enforce";

// Unset or "open" keeps 0.4.11; "observe" is the rollout step; any other value enforces, so a mistyped mode fails closed.
function authMode(env: Bindings): AuthMode {
  const mode = (env.AUTH_MODE ?? "").trim().toLowerCase();
  if (mode === "" || mode === "open") return "open";
  return mode === "observe" ? "observe" : "enforce";
}

// A credential is carried by an X-Device-Id header or any Authorization header (Device, Bearer or another scheme,
// which the enforced path refuses): such a request is never answered as an open one.
const carriesCredential = (request: Request) =>
  request.headers.has("x-device-id") || (request.headers.get("authorization") ?? "").trim() !== "";

// No default: a non-production deployment that lost its STATE_PREFIX (a copied env, a `--var STATE_PREFIX:` override)
// would otherwise read and write production's devices, jobs and manual counts. Production sets it when promoted.
function statePrefix(env: Bindings) {
  const prefix = (env.STATE_PREFIX ?? "").trim();
  if (!prefix) throw new HttpError(503, "state_prefix_missing", "STATE_PREFIX is not configured for this Worker");
  return prefix.endsWith("/") ? prefix : `${prefix}/`;
}

function stateBucket(env: Bindings) {
  if (!env.SCAN_ARCHIVE) throw new HttpError(503, "state_unavailable", "Device and scan records need the scan archive");
  return env.SCAN_ARCHIVE;
}

const deviceKey = (env: Bindings, id: string) => `${statePrefix(env)}devices/${id}.json`;
const jobKey = (env: Bindings, id: string) => `${statePrefix(env)}jobs/${id}.json`;
const manualPrefix = (env: Bindings, scanId: string) => `${statePrefix(env)}manual-counts/${scanId}/`;
const legacyManualPrefix = (scanId: string) => `scans/${scanId}/manual-count/`;
const createOnly = () => new Headers({ "If-None-Match": "*" });
const isoAt = (ms: number) => new Date(ms).toISOString();
const displayCode = (id: string) => `${id.slice(0, 4)}-${id.slice(4, 8)}`.toUpperCase();

async function digestText(text: string) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
}
const toHex = (bytes: Uint8Array) => [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
const fromHex = (text: string) => /^[0-9a-f]{64}$/.test(text)
  ? Uint8Array.from(text.match(/../g)!.map((pair) => parseInt(pair, 16))) : new Uint8Array(32);

// Both sides are SHA-256 digests (fixed, public length): every byte is compared, no early exit.
function sameDigest(a: Uint8Array, b: Uint8Array) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

async function readState<T>(bucket: R2Bucket, key: string): Promise<Stored<T> | null> {
  const object = await bucket.get(key);
  return object ? { value: await object.json<T>(), etag: object.etag } : null;
}

function writeState(bucket: R2Bucket, key: string, value: unknown, customMetadata: Record<string, string>, onlyIf: R2Conditional | Headers) {
  return bucket.put(key, JSON.stringify(value), { httpMetadata: { contentType: "application/json" }, customMetadata, onlyIf });
}

const writeJob = (bucket: R2Bucket, key: string, job: JobRecord, onlyIf: R2Conditional | Headers) =>
  writeState(bucket, key, job, { status: job.status, owner: job.owner }, onlyIf);

// ---- Authentication. Device: X-Device-Id plus "Authorization: Device <secret>". Admin: "Authorization: Bearer <ADMIN_TOKEN>".
// Secrets and tokens are never logged; the device id is.
function presentedCredential(request: Request) {
  const match = /^(\S+)\s+(\S+)$/.exec((request.headers.get("authorization") ?? "").trim());
  return { scheme: match?.[1].toLowerCase() ?? "", credential: match?.[2] ?? "" };
}

// audience "admin": the admin token only. "device_or_admin": a Bearer header is checked as the admin token,
// anything else as an active device.
async function authenticate(request: Request, env: Bindings, audience: "admin" | "device_or_admin"): Promise<Caller> {
  const { scheme, credential } = presentedCredential(request);
  if (audience === "admin" || scheme === "bearer") {
    if (scheme === "bearer" && await adminTokenMatches(credential, env)) return { kind: "admin" };
    console.log(JSON.stringify({ event: "admin_auth_failed" }));
    throw new HttpError(401, "admin_auth_failed", "Administrator token missing or wrong");
  }
  return authenticateDevice(request, env, false);
}

async function authenticateDevice(request: Request, env: Bindings, anyStatus: boolean): Promise<DeviceCaller> {
  const { scheme, credential } = presentedCredential(request);
  const deviceId = (request.headers.get("x-device-id") ?? "").trim().toLowerCase();
  if (scheme !== "device" || !credential || !deviceId) {
    throw new HttpError(401, "device_credentials_required", "This server needs the device id and device secret");
  }
  const known = UUID_V4.test(deviceId);
  const stored = known ? await readState<DeviceRecord>(stateBucket(env), deviceKey(env, deviceId)) : null;
  // Unknown id and wrong secret take the same path and give the same answer (no oracle).
  const matches = sameDigest(await digestText(credential), fromHex(stored?.value.secret_sha256 ?? ""));
  if (!stored || !matches) {
    console.log(JSON.stringify({ event: "device_auth_failed", device_id: known ? deviceId : null }));
    throw new HttpError(401, "device_auth_failed", "Device id or secret not recognised");
  }
  const record = stored.value;
  if (!anyStatus && record.status !== "active") {
    console.log(JSON.stringify({ event: "device_refused", device_id: deviceId, status: record.status }));
    if (record.status === "pending") {
      throw new HttpError(403, "device_pending", `Device ${displayCode(deviceId)} is waiting for administrator approval`);
    }
    throw new HttpError(403, "device_revoked", `Device ${displayCode(deviceId)} has been revoked`);
  }
  return { kind: "device", device_id: deviceId, record };
}

async function adminTokenMatches(token: string, env: Bindings) {
  const expected = env.ADMIN_TOKEN ?? "";
  const matches = sameDigest(await digestText(token), await digestText(expected));
  return expected.length > 0 && matches;
}

const ownerOf = (caller: Caller) => caller.kind === "admin" ? "admin" : caller.device_id;
const canAccess = (caller: Caller, job: JobRecord) => caller.kind === "admin" || job.owner === caller.device_id;
const deviceView = (record: DeviceRecord) => ({ device_id: record.device_id, status: record.status, display_code: displayCode(record.device_id) });
const adminDeviceView = ({ secret_sha256: _hash, ...record }: DeviceRecord) => ({ ...record, display_code: displayCode(record.device_id) });

// Reads a JSON body of at most `limit` bytes. A declared or actual larger body is refused without buffering it.
async function readSmallJson(request: Request, limit: number) {
  const tooLarge = () => new HttpError(413, "request_too_large", `This request body is limited to ${limit} bytes`);
  if (Number(request.headers.get("content-length")) > limit) throw tooLarge();
  const chunks: Uint8Array[] = [];
  let bytes = 0;
  const reader = request.body?.getReader();
  while (reader) {
    const chunk = await reader.read();
    if (chunk.done) break;
    bytes += chunk.value.byteLength;
    if (bytes > limit) {
      await reader.cancel();
      throw tooLarge();
    }
    chunks.push(chunk.value);
  }
  const body = new Uint8Array(bytes);
  let offset = 0;
  for (const chunk of chunks) { body.set(chunk, offset); offset += chunk.byteLength; }
  try { return JSON.parse(new TextDecoder().decode(body)) as unknown; } catch { throw new HttpError(422, "invalid_json", "Body must be JSON"); }
}

// ---- Device registry: create-only registration, admin approve/revoke by compare-and-swap.
async function registerDevice(request: Request, env: Bindings) {
  const bucket = stateBucket(env);
  const body = (await readSmallJson(request, MAX_REGISTRATION_BYTES) ?? {}) as Record<string, unknown>;
  const deviceId = typeof body.device_id === "string" ? body.device_id.trim().toLowerCase() : "";
  if (!UUID_V4.test(deviceId)) throw new HttpError(422, "invalid_device_id", "device_id must be a UUID v4");
  const secret = typeof body.secret === "string" ? body.secret : "";
  if (!DEVICE_SECRET.test(secret)) throw new HttpError(422, "invalid_device_secret", "secret must be at least 32 random bytes in base64url");
  const text = (value: unknown, max: number) => {
    const clean = typeof value === "string" ? value.replace(UNSAFE_TEXT, " ").replace(/\s+/g, " ").trim().slice(0, max).trim() : "";
    return clean || null;
  };
  const presented = await digestText(secret);
  const record: DeviceRecord = { v: 1, device_id: deviceId, secret_sha256: toHex(presented), status: "pending",
    label: text(body.label, 64), app_version: text(body.app_version, 32), created_at: isoAt(Date.now()), approved_at: null, revoked_at: null };
  const key = deviceKey(env, deviceId);
  for (let round = 0; round < CAS_RETRIES; round++) {
    if (await writeState(bucket, key, record, { status: record.status }, createOnly())) {
      console.log(JSON.stringify({ event: "device_registered", device_id: deviceId }));
      return json(deviceView(record));
    }
    const existing = await readState<DeviceRecord>(bucket, key);
    if (!existing) continue;   // removed between the claim and the read: claim again
    // Same id and same secret: a retried registration. The record is never rewritten.
    if (!sameDigest(presented, fromHex(existing.value.secret_sha256))) {
      console.log(JSON.stringify({ event: "device_register_conflict", device_id: deviceId }));
      throw new HttpError(409, "device_exists", "This device id is already registered with another secret");
    }
    return json(deviceView(existing.value));
  }
  throw new HttpError(503, "device_registry_busy", "Device registration is busy; try again");
}

async function listDevices(env: Bindings, url: URL) {
  const bucket = stateBucket(env);
  const status = url.searchParams.get("status");
  const listed = await bucket.list({ prefix: `${statePrefix(env)}devices/`, cursor: url.searchParams.get("cursor") || undefined,
    limit: 100, include: ["customMetadata"] });
  const devices = [];
  for (const object of listed.objects) {
    if (status && object.customMetadata?.status !== status) continue;
    const stored = await readState<DeviceRecord>(bucket, object.key);
    if (stored && (!status || stored.value.status === status)) devices.push(adminDeviceView(stored.value));
  }
  return json({ devices, cursor: listed.truncated ? listed.cursor : null });
}

// Approve (pending -> active) or revoke (-> revoked). Repeating the same change is a no-op. Revocation is final: a
// revoked device keeps its old secret, so one mistaken approve would bring a lost phone back; a reinstalled phone
// registers a new device id instead. The CAS also stops an approve that read "pending" from landing over a revoke.
async function setDeviceStatus(env: Bindings, rawId: string, target: "active" | "revoked") {
  const bucket = stateBucket(env);
  const deviceId = rawId.toLowerCase();
  if (!UUID_V4.test(deviceId)) throw new HttpError(422, "invalid_device_id", "device_id must be a UUID v4");
  const key = deviceKey(env, deviceId);
  for (let round = 0; round < CAS_RETRIES; round++) {
    const stored = await readState<DeviceRecord>(bucket, key);
    if (!stored) throw new HttpError(404, "device_not_found", "No device with this id");
    if (stored.value.status === target) return json(adminDeviceView(stored.value));
    if (stored.value.status === "revoked") {
      throw new HttpError(409, "device_revoked", `Device ${displayCode(deviceId)} was revoked and cannot be approved again; ` +
        "a reinstalled phone registers a new device id");
    }
    const now = isoAt(Date.now());
    const next: DeviceRecord = { ...stored.value, status: target, ...(target === "active" ? { approved_at: now } : { revoked_at: now }) };
    if (await writeState(bucket, key, next, { status: target }, { etagMatches: stored.etag })) {
      console.log(JSON.stringify({ event: "device_status_changed", device_id: deviceId, from: stored.value.status, status: target }));
      return json(adminDeviceView(next));
    }
  }
  throw new HttpError(409, "device_changed", "The device record kept changing; try again");
}

// ---- Scan jobs: one scan id = one ordered photo triplet; retries replay the stored response.
const jobView = (job: JobRecord, replayed = false) =>
  ({ scan_id: job.scan_id, status: job.status, attempt: job.attempt, replayed, pipeline_version: job.pipeline_version });
const leaseValid = (job: JobRecord) => Date.parse(job.lease_until) > Date.now();

// A done job answers with the stored response (the version that computed it); only the replay flag changes.
function replay(job: JobRecord) {
  const result = job.result ?? {};
  const stored = (result.job ?? jobView(job)) as Record<string, unknown>;
  return json({ ...result, job: { ...stored, replayed: true } });
}

function stillProcessing(job: JobRecord) {
  const remaining = Date.parse(job.lease_until) - Date.now();
  const retryAfter = Number.isFinite(remaining) ? Math.max(1, Math.min(5, Math.ceil(remaining / 1000))) : 5;
  return json({ detail: { code: "processing", message: "This scan is still being counted; ask again shortly" },
    job: { ...jobView({ ...job, status: "running" }), retry_after_s: retryAfter } }, 202, { "Retry-After": String(retryAfter) });
}

// What one upload asks for: the photos in view order, the scan_contract as sent and the cell ids (by view name).
// The same photos with another contract or other cell ids are another request (409 scan_id_conflict), not a retry.
async function requestIdentity(scan: ParsedScan) {
  const cellIds = Object.fromEntries(Object.entries(scan.cellIds).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
  const fingerprint = toHex(await digestText(JSON.stringify([FINGERPRINT_VERSION, ...scan.hashes, scan.scanContract, Object.entries(cellIds)])));
  return { fingerprint, fingerprint_version: FINGERPRINT_VERSION, scan_contract: scan.scanContract, cell_ids: cellIds };
}

// A job written before fingerprint version 2 holds the photo hashes alone ("left|right|straight"): its missing
// contract and cell ids match any request, as they did then, so the same photos still replay.
async function sameRequest(job: JobRecord, scan: ParsedScan, fingerprint: string) {
  if ((job.fingerprint_version ?? 1) === 1) return job.fingerprint === toHex(await digestText(scan.hashes.join("|")));
  return job.fingerprint === fingerprint;
}

async function countScanJob(request: Request, env: Bindings, caller: Caller, ctx?: ExecutionContext) {
  const bucket = stateBucket(env);
  const scan = await readScan(request);
  const imageHashes = Object.fromEntries(VIEWS.map((view, i) => [view, scan.hashes[i]]));
  const identity = await requestIdentity(scan);
  const key = jobKey(env, scan.scanId);
  const now = Date.now();
  const claim: JobRecord = { v: 1, scan_id: scan.scanId, owner: ownerOf(caller), image_hashes: imageHashes, ...identity,
    pipeline_version: PIPELINE_VERSION, status: "running", attempt: 1, lease_until: isoAt(now + LEASE_MS),
    created_at: isoAt(now), updated_at: isoAt(now) };
  for (let round = 0; round < CAS_RETRIES; round++) {
    const won = await writeJob(bucket, key, claim, createOnly());
    if (won) {
      console.log(JSON.stringify({ event: "job_claimed", scan_id: claim.scan_id, owner: claim.owner, attempt: 1 }));
      return runJob(env, bucket, key, claim, won.etag, scan, ctx);
    }
    const stored = await readState<JobRecord>(bucket, key);
    if (!stored) continue;   // removed between the claim and the read: claim again
    const job = stored.value;
    if (!canAccess(caller, job)) throw new HttpError(403, "scan_forbidden", "This scan belongs to another device");
    if (!await sameRequest(job, scan, identity.fingerprint)) {
      throw new HttpError(409, "scan_id_conflict",
        "This scan id was already used with other photos or other scan settings; a retake needs a new scan id");
    }
    if (job.status === "done") {
      console.log(JSON.stringify({ event: "job_replayed", scan_id: job.scan_id, owner: job.owner, attempt: job.attempt }));
      return replay(job);
    }
    if (job.status === "running" && leaseValid(job)) return stillProcessing(job);
    // The lease ran out (the Worker counting it died) or the job failed: take it over with a new lease. The takeover
    // counts this request, so the job takes its identity (a version 1 job is upgraded; a version 2 one is unchanged).
    const at = Date.now();
    const { error: _previous, ...rest } = job;
    const takeover: JobRecord = { ...rest, ...identity, status: "running", attempt: job.attempt + 1, lease_until: isoAt(at + LEASE_MS),
      updated_at: isoAt(at), pipeline_version: PIPELINE_VERSION };
    const taken = await writeJob(bucket, key, takeover, { etagMatches: stored.etag });
    if (!taken) return stillProcessing(takeover);
    console.log(JSON.stringify({ event: "job_taken_over", scan_id: job.scan_id, owner: job.owner, attempt: takeover.attempt, previous: job.status }));
    return runJob(env, bucket, key, takeover, taken.etag, scan, ctx);
  }
  throw new HttpError(503, "scan_job_busy", "The scan record is busy; try again");
}

// Only the claim holder archives and counts. Any error after the claim marks the job failed and is answered
// as that error, never as a count; if even that write fails, the lease running out lets a retry take over.
// waitUntil lets a count that started finish and be stored when the phone's link drops mid-request, for at most 30 s
// after the disconnect; a longer count is cancelled and the lease (LEASE_MS) lets a retry take the job over.
function runJob(env: Bindings, bucket: R2Bucket, key: string, job: JobRecord, etag: string, scan: ParsedScan, ctx?: ExecutionContext) {
  const work = (async () => {
    let body: Record<string, unknown>;
    try {
      await archiveScan(env, scan);
      body = await scanPipeline(env, scan);
    } catch (error) {
      const failure: JobError = error instanceof HttpError ? { status: error.status, code: error.code, message: error.message }
        : { status: 500, code: "internal_error", message: "Scan could not be processed" };
      const outcome = await failJob(bucket, key, job, etag, failure, error instanceof HttpError ? null : "unexpected_error");
      if (outcome instanceof Response) return outcome;
      throw new HttpError(failure.status, failure.code, failure.message, { job: jobView(outcome) });
    }
    return finishJob(bucket, key, job, etag, body);
  })();
  ctx?.waitUntil(work.catch(() => undefined));
  return work;
}

// Stores the failure (CAS on this attempt's etag). When the lease was lost, the attempt that holds the job decides
// the answer, as in finishJob: its stored result is replayed and a valid lease is answered 202. Otherwise the
// error is returned with the job as it is stored ("failed" only when this failure was recorded).
async function failJob(bucket: R2Bucket, key: string, job: JobRecord, etag: string, failure: JobError,
  errorType: string | null): Promise<Response | JobRecord> {
  const failed: JobRecord = { ...job, status: "failed", updated_at: isoAt(Date.now()), error: failure };
  let stored = false;
  try {
    stored = !!await writeJob(bucket, key, failed, { etagMatches: etag });
  } catch { /* not recorded: the lease runs out and a retry takes the job over */ }
  console.log(JSON.stringify({ event: "job_failed", scan_id: job.scan_id, owner: job.owner, attempt: job.attempt,
    code: failure.code, error_type: errorType, stored }));
  if (stored) return failed;
  let latest: Stored<JobRecord> | null = null;
  try { latest = await readState<JobRecord>(bucket, key); } catch { /* unknown: answer with this attempt's state */ }
  if (!latest || latest.etag === etag || latest.value.fingerprint !== job.fingerprint) return job;
  if (latest.value.attempt === job.attempt) return latest.value;   // this attempt's own write landed although the call threw
  console.log(JSON.stringify({ event: "job_lease_lost", scan_id: job.scan_id, attempt: job.attempt, holder_attempt: latest.value.attempt,
    holder_status: latest.value.status }));
  if (latest.value.status === "done") return replay(latest.value);
  if (latest.value.status === "running" && leaseValid(latest.value)) return stillProcessing(latest.value);
  return latest.value;
}

async function finishJob(bucket: R2Bucket, key: string, job: JobRecord, etag: string, body: Record<string, unknown>) {
  const response = { ...body, job: jobView({ ...job, status: "done" }) };
  let current: Stored<JobRecord> = { value: job, etag };
  try {
    for (let round = 0; round < CAS_RETRIES; round++) {
      const { error: _stale, ...rest } = current.value;
      const done: JobRecord = { ...rest, status: "done", attempt: job.attempt, pipeline_version: job.pipeline_version,
        updated_at: isoAt(Date.now()), result: response };
      if (await writeJob(bucket, key, done, { etagMatches: current.etag })) {
        console.log(JSON.stringify({ event: "job_done", scan_id: job.scan_id, owner: job.owner, attempt: job.attempt }));
        return json(response);
      }
      // The lease ran out and another request took the job over. A stored result wins; otherwise this result
      // (same photos) is stored over the other attempt so every later answer is the same.
      const latest = await readState<JobRecord>(bucket, key);
      if (!latest || latest.value.fingerprint !== job.fingerprint) break;
      if (latest.value.status === "done") return replay(latest.value);
      console.log(JSON.stringify({ event: "job_lease_lost", scan_id: job.scan_id, attempt: job.attempt, holder_attempt: latest.value.attempt }));
      current = latest;
    }
  } catch { /* the count itself succeeded; the lease covers the unstored job */ }
  console.log(JSON.stringify({ event: "job_result_not_stored", scan_id: job.scan_id, attempt: job.attempt }));
  return json(response);
}

async function scanResult(env: Bindings, caller: Caller, scanId: string) {
  if (!SCAN_ID.test(scanId)) throw new HttpError(422, "invalid_scan_id", "scan_id must be a UUID");
  const stored = await readState<JobRecord>(stateBucket(env), jobKey(env, scanId));
  if (!stored) throw new HttpError(404, "scan_not_found", "The server never received this scan; upload it again");
  const job = stored.value;
  if (!canAccess(caller, job)) throw new HttpError(403, "scan_forbidden", "This scan belongs to another device");
  if (job.status === "done") return replay(job);
  if (job.status === "running" && leaseValid(job)) return stillProcessing(job);
  if (job.status === "running") {
    throw new HttpError(409, "processing_interrupted", "Counting stopped before it finished; upload the same photos again", { job: jobView(job) });
  }
  throw new HttpError(409, "scan_failed", "Counting failed; upload the same photos again", { job: { ...jobView(job), error: job.error ?? null } });
}

// ---- Manual counts with idempotency: one object per count_id (create-only) and a latest.json that only
// moves forward in count time (countTime).
// Stored only under STATE_PREFIX (manual-counts/<scan_id>/<count_id>.json and .../latest.json), never under scans/:
// staging and production bind one bucket and production runs open, and its open manual-count route writes
// scans/<id>/manual-count/latest.json for any scan id. Records under scans/ (0.4.11, the open route, and the
// pre-state-prefix 0.4.12 builds) are read as "legacy_scans" and marked as not tamper-proof.
const manualMeta = (record: ManualRecord) => ({ httpMetadata: { contentType: "application/json" }, customMetadata: {
  scan_id: record.scan_id, block_id: record.block_id, kind: "manual_count", count_id: String(record.count_id), created_at: String(record.created_at) } });
// What the operator saved; the server's recorded_at and recorded_by are left out of the comparison.
const manualContent = (record: ManualRecord) =>
  JSON.stringify([record.block_id, record.cells, record.notes, record.tray, record.app_version, record.app_total ?? null, record.created_at]);

async function hasArchivedPhotos(bucket: R2Bucket, scanId: string) {
  const listed = await bucket.list({ prefix: `scans/${scanId}/`, limit: 100 });
  return listed.objects.some((object) => VIEWS.some((view) => object.key.startsWith(`scans/${scanId}/${view}/`)));
}

async function manualCountJob(request: Request, env: Bindings, caller: Caller, scanId: string) {
  const bucket = stateBucket(env);
  if (!SCAN_ID.test(scanId)) throw new HttpError(422, "invalid_scan_id", "scan_id must be a UUID");
  const job = await readState<JobRecord>(bucket, jobKey(env, scanId));
  if (job && !canAccess(caller, job.value)) throw new HttpError(403, "scan_forbidden", "This scan belongs to another device");
  // Scans counted before 0.4.12 have no job: only the administrator may attach a count, and only to archived photos.
  if (!job && !(caller.kind === "admin" && await hasArchivedPhotos(bucket, scanId))) {
    throw new HttpError(404, "scan_not_found", "Manual counts need a scan this server received");
  }
  const { body, blockId, clean, notes, tray, appVersion, totals } = await readManualCountBody(request);
  const countId = typeof body.count_id === "string" ? body.count_id.trim().toLowerCase() : "";
  if (!UUID_V4.test(countId)) throw new HttpError(422, "invalid_count_id", "count_id must be a UUID v4");
  const createdAt = typeof body.created_at === "string" ? body.created_at.trim() : "";
  const createdMs = ISO_TIME.test(createdAt) ? Date.parse(createdAt) : NaN;
  if (!Number.isFinite(createdMs) || createdMs < Date.UTC(2020, 0, 1)) {
    throw new HttpError(422, "invalid_created_at", "created_at must be an ISO 8601 time with a zone, e.g. 2026-10-15T07:19:00Z");
  }
  if (createdMs > Date.now() + MAX_CLOCK_SKEW_MS) {
    throw new HttpError(422, "invalid_created_at", "created_at is in the future; check the phone's clock");
  }
  const appTotal = body.app_total ?? null;
  if (appTotal !== null && !(Number.isInteger(appTotal) && (appTotal as number) >= 0 && (appTotal as number) <= 1_000_000)) {
    throw new HttpError(422, "invalid_app_total", "app_total must be a whole number of trays or null");
  }
  const record = { kind: "manual_count_v1", scan_id: scanId, block_id: blockId, cells: clean, notes, tray, recorded_at: isoAt(Date.now()),
    created_at: createdAt, count_id: countId, app_total: appTotal as number | null, app_version: appVersion, totals, recorded_by: ownerOf(caller) };
  const key = `${manualPrefix(env, scanId)}${countId}.json`;
  const latestKey = `${manualPrefix(env, scanId)}latest.json`;
  let saved: ManualRecord = record;
  let replayed = false;
  if (!await bucket.put(key, JSON.stringify(record), { ...manualMeta(record), onlyIf: createOnly() })) {
    const existing = await readState<ManualRecord>(bucket, key);
    if (!existing) throw new HttpError(503, "manual_count_busy", "The manual count could not be saved; send it again");
    if (manualContent(existing.value) !== manualContent(record)) {
      throw new HttpError(409, "manual_count_conflict", "This count_id was already saved with other values; a correction needs a new count_id");
    }
    saved = existing.value;
    replayed = true;
  }
  // Run on a replay too: a lost response may have come before latest.json was moved.
  const isLatest = await promoteLatest(bucket, latestKey, saved);
  console.log(JSON.stringify({ event: "manual_count_stored", scan_id: scanId, block_id: blockId, cells: clean.length, key,
    count_id: countId, replayed, is_latest: isLatest, recorded_by: saved.recorded_by ?? null }));
  return json({ stored: true, replayed, key, latest_key: latestKey, is_latest: isLatest, count_id: countId, totals: saved.totals, record: saved });
}

// When the operator made a count: the phone's created_at, but never later than the server's recorded_at. A phone
// clock running fast (up to MAX_CLOCK_SKEW_MS is accepted) would otherwise pin latest.json until real time caught
// up, and every later correction would be stored as not latest. A late retry still keeps its early created_at.
// 0.4.11 records have no created_at; their server recorded_at stands in.
function countTime(record: ManualRecord) {
  const created = Date.parse(String(record.created_at ?? ""));
  const recorded = Date.parse(String(record.recorded_at ?? ""));
  if (Number.isFinite(created) && Number.isFinite(recorded)) return Math.min(created, recorded);
  return Number.isFinite(created) ? created : recorded;
}

// latest.json is replaced only by a newer count time (compare-and-swap loop), so a late retry of an older count
// cannot overwrite a newer correction.
async function promoteLatest(bucket: R2Bucket, key: string, record: ManualRecord) {
  const created = countTime(record);
  for (let round = 0; round < LATEST_RETRIES; round++) {
    const current = await readState<ManualRecord>(bucket, key);
    if (current && current.value.count_id === record.count_id) return true;
    const currentTime = current ? countTime(current.value) : NaN;
    if (current && Number.isFinite(currentTime) && currentTime >= created) return false;
    if (await bucket.put(key, JSON.stringify(record), { ...manualMeta(record), onlyIf: current ? { etagMatches: current.etag } : createOnly() })) {
      return true;
    }
  }
  throw new HttpError(503, "manual_count_busy", "The manual count is saved but the scan's latest count is busy; send it again");
}

// Where a manual-count record was read from. "state": written by this Worker's enforced route under STATE_PREFIX.
// "legacy_scans": under scans/<id>/manual-count/, which the open production Worker can overwrite for any scan id.
type ManualSource = "state" | "legacy_scans";
const LEGACY_MANUAL_NOTE = "stored under scans/, which the open production Worker can overwrite; not tamper-proof";

function tagManual(value: unknown, storage: ManualSource): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return storage === "state" ? { ...value, storage, tamper_proof: true }
    : { ...value, storage, tamper_proof: false, storage_note: LEGACY_MANUAL_NOTE };
}

async function readManual(bucket: R2Bucket, key: string, storage: ManualSource) {
  const object = await bucket.get(key);
  if (!object) return null;
  try { return tagManual(await object.json(), storage); } catch { return null; }
}

const listingPrefix = (env: Bindings, source: ManualSource) => source === "state" ? `${statePrefix(env)}manual-counts/` : "scans/";

// The listing cursor names the source and the position inside it: base64url of {v: 1, source, r2, after?}. `after` is
// the last key read (the next listing starts after it); `r2` is an R2 cursor, used only after a page that returned no
// keys, and in cursors issued before `after` existed.
function encodeListingCursor(source: ManualSource, r2: string | null, after: string | null) {
  return Buffer.from(JSON.stringify({ v: 1, source, r2, ...(after ? { after } : {}) }), "utf8").toString("base64url");
}

function decodeListingCursor(text: string, env: Bindings): { source: ManualSource; r2: string | undefined; after: string | undefined } {
  const invalid = () => new HttpError(422, "invalid_cursor", "cursor is not valid; start again without it");
  let value: unknown;
  try { value = JSON.parse(Buffer.from(text, "base64url").toString("utf8")); } catch { throw invalid(); }
  const { v, source, r2, after } = (value ?? {}) as Record<string, unknown>;
  if (v !== 1 || (source !== "state" && source !== "legacy_scans") || (r2 !== null && (typeof r2 !== "string" || !r2))) throw invalid();
  if (after !== undefined && (typeof after !== "string" || !after.startsWith(listingPrefix(env, source)))) throw invalid();
  return { source, r2: r2 ?? undefined, after };
}

// R2 calls (lists, GETs and HEADs) one listing request may make, well below the 1000 subrequests a Worker request may
// make to Cloudflare services; a record costs at most LISTING_CALLS_PER_RECORD of them.
const LISTING_R2_CALLS = 400;
const LISTING_CALLS_PER_RECORD = 3;

// Why a legacy record is not listed as its scan's count: the scan has a state record (listed instead), or a scan job (a
// 0.4.12 client saves its count only under the state prefix, so a scans/ record for such a scan came through an open
// route). Null: the scan has neither, and its legacy record is its count.
async function legacyShadow(env: Bindings, bucket: R2Bucket, scanId: string): Promise<"state" | "scan_job" | null> {
  if (!SCAN_ID.test(scanId)) return null;
  const [state, job] = await Promise.all([bucket.head(`${manualPrefix(env, scanId)}latest.json`), bucket.head(jobKey(env, scanId))]);
  return state ? "state" : job ? "scan_job" : null;
}

// Admin listing of every scan's latest manual count: first the records under STATE_PREFIX, then the legacy records
// under scans/*/manual-count/latest.json, each tagged with its storage. A scan appears at most once: a legacy record
// whose scan has a state record or a scan job is left out and named in `legacy_shadowed` ({scan_id, by}).
// An answer stops at `limit` records (default 100, max 500) or LISTING_R2_CALLS R2 calls, whichever comes first, even
// inside an R2 page; `cursor` continues after the last key read, null at the end. An answer may hold fewer records
// than `limit` (or none) and still have a cursor.
async function listManualCountsPage(env: Bindings, url: URL) {
  if (!env.SCAN_ARCHIVE) throw new HttpError(503, "archive_unavailable", "Scan archive is not configured");
  const bucket = env.SCAN_ARCHIVE;
  const requested = Number(url.searchParams.get("limit") ?? 100);
  const limit = Number.isInteger(requested) && requested >= 1 ? Math.min(requested, 500) : 100;
  const start = url.searchParams.get("cursor");
  let { source, r2: cursor, after } = start ? decodeListingCursor(start, env)
    : { source: "state" as ManualSource, r2: undefined as string | undefined, after: undefined as string | undefined };
  let done = false;
  let calls = 0;
  const records: unknown[] = [];
  const shadowed: { scan_id: string; by: "state" | "scan_job" }[] = [];
  const full = () => records.length >= limit || calls + LISTING_CALLS_PER_RECORD > LISTING_R2_CALLS;
  pages: for (let page = 0; page < 10 && !full(); page++) {
    const state = source === "state";
    let listed: R2Objects;
    calls++;
    const position = cursor ? { cursor } : after ? { startAfter: after } : {};
    try { listed = await bucket.list({ prefix: listingPrefix(env, source), ...position, limit: 1000 }); }
    catch (error) {
      if (page === 0 && cursor) throw new HttpError(422, "invalid_cursor", "cursor is not valid; start again without it");
      throw error;
    }
    cursor = undefined;
    for (const object of listed.objects) {
      if (full()) break pages;
      if (object.key.endsWith(state ? "/latest.json" : "/manual-count/latest.json")) {
        const legacyScan = state ? null : object.key.split("/")[1];   // scans/<id>/manual-count/latest.json
        let by: "state" | "scan_job" | null = null;
        if (legacyScan !== null) {
          calls += 2;
          by = await legacyShadow(env, bucket, legacyScan);
        }
        if (by && legacyScan !== null) shadowed.push({ scan_id: legacyScan, by });
        else {
          calls++;
          const record = await readManual(bucket, object.key, source);
          if (record) records.push(record);
        }
      }
      after = object.key;
    }
    if (listed.truncated) {
      if (!listed.objects.length) cursor = listed.cursor;   // nothing read: continue from R2's own position
    } else if (state) {
      source = "legacy_scans";
      after = undefined;
    } else {
      done = true;
      break;
    }
  }
  return json({ count: records.length, records, legacy_shadowed: shadowed,
    cursor: done ? null : encodeListingCursor(source, cursor ?? null, after ?? null) });
}

// Every key under `prefix` (one scan's manual counts: a few objects), bounded against a runaway listing.
async function listKeys(bucket: R2Bucket, prefix: string) {
  const keys: string[] = [];
  let cursor: string | undefined;
  for (let page = 0; page < 10; page++) {
    const listed = await bucket.list({ prefix, cursor, limit: 1000 });
    keys.push(...listed.objects.map((object) => object.key));
    if (!listed.truncated) break;
    cursor = listed.cursor;
  }
  return keys;
}

const countIdsIn = (keys: string[], prefix: string) => keys.map((key) => key.slice(prefix.length))
  .filter((name) => name.endsWith(".json") && UUID_V4.test(name.slice(0, -5))).map((name) => name.slice(0, -5)).sort();

// One scan's manual counts for its owner or the admin: `latest` is the state latest.json; for a scan without a job
// (counted before 0.4.12, the admin's only) the legacy one (tagged) stands in when there is none. A scan with a job
// was counted by a 0.4.12 client, which always saves its count with its credential, under the state prefix, so a
// scans/ record for it came through an open route (production, or an observe request without a credential) and is
// never its count. `legacy_latest` is the scans/ record whenever it is not the one returned as `latest`.
async function manualCountRead(env: Bindings, caller: Caller, scanId: string) {
  const bucket = stateBucket(env);
  if (!SCAN_ID.test(scanId)) throw new HttpError(422, "invalid_scan_id", "scan_id must be a UUID");
  const job = await readState<JobRecord>(bucket, jobKey(env, scanId));
  if (job && !canAccess(caller, job.value)) throw new HttpError(403, "scan_forbidden", "This scan belongs to another device");
  if (!job && caller.kind !== "admin") throw new HttpError(404, "scan_not_found", "Manual counts need a scan this server received");
  const prefix = manualPrefix(env, scanId);
  const legacyPrefix = legacyManualPrefix(scanId);
  const state = await readManual(bucket, `${prefix}latest.json`, "state");
  const legacy = await readManual(bucket, `${legacyPrefix}latest.json`, "legacy_scans");
  const latest = state ?? (job ? null : legacy);
  return json({ scan_id: scanId, latest, storage: latest?.storage ?? null, count_ids: countIdsIn(await listKeys(bucket, prefix), prefix),
    legacy_count_ids: countIdsIn(await listKeys(bucket, legacyPrefix), legacyPrefix), legacy_latest: latest === legacy ? null : legacy });
}

// Upload probe: reads and discards the body so the phone can measure its link without spending inference.
async function diagnosticsUpload(request: Request, caller: Caller) {
  const tooLarge = () => new HttpError(413, "upload_too_large", "Diagnostic uploads are limited to 25 MB");
  if (Number(request.headers.get("content-length")) > MAX_DIAGNOSTIC_BYTES) throw tooLarge();
  const started = Date.now();
  let bytes = 0;
  const reader = request.body?.getReader();
  while (reader) {
    const chunk = await reader.read();
    if (chunk.done) break;
    bytes += chunk.value.byteLength;
    if (bytes > MAX_DIAGNOSTIC_BYTES) {
      await reader.cancel();
      throw tooLarge();
    }
  }
  const ms = Date.now() - started;
  console.log(JSON.stringify({ event: "diagnostics_upload", device_id: ownerOf(caller), bytes, ms }));
  return json({ bytes, ms });
}

// Open: 0.4.11's answer. Enforce and observe advertise the same device auth and scan jobs (a 0.4.12 app then always
// sends its credential), plus which of the two is on.
function health(env: Bindings) {
  const contracts = ["cell_identity_v1", "model_spatial_v1", ...(env.RECONSTRUCTION_ENABLED === "true" ? ["reconstruct_v1"] : [])];
  const mode = authMode(env);
  if (mode === "open") return json({ status: "ok", scan_contract: "cell_identity_v1", scan_contracts: contracts, hybrid_ready: false });
  return json({ status: "ok", scan_contract: "cell_identity_v1", scan_contracts: [...contracts, "scan_jobs_v1"], hybrid_ready: false,
    auth: "device_v1", auth_mode: mode });
}

// Every route except /health and /ready when AUTH_MODE is enforce or observe. Credentials are checked before the body
// is read. Observe answers an upload that carries no credential at all (the installed 0.4.11 app) exactly as the open
// Worker does: count, manual count and, where enabled, reconstruct. Everything else is as in enforce.
async function routeEnforced(request: Request, env: Bindings, url: URL, mode: AuthMode, ctx?: ExecutionContext): Promise<Response> {
  const { method } = request;
  const path = url.pathname;
  const openUpload = mode === "observe" && !carriesCredential(request);
  const observed = (route: string) => console.log(JSON.stringify({ event: "observe_open_request", route }));
  if (method === "POST" && path === "/v1/devices") return await registerDevice(request, env);
  if (method === "GET" && path === "/v1/devices/me") return json(deviceView((await authenticateDevice(request, env, true)).record));
  if (method === "POST" && path === "/v1/scans/count") {
    if (openUpload) { observed("scans/count"); return await countScan(request, env); }
    return await countScanJob(request, env, await authenticate(request, env, "device_or_admin"), ctx);
  }
  const result = path.match(/^\/v1\/scans\/([^/]+)\/result$/);
  if (method === "GET" && result) return await scanResult(env, await authenticate(request, env, "device_or_admin"), result[1].toLowerCase());
  const manual = path.match(/^\/v1\/scans\/([^/]+)\/manual-count$/);
  if (method === "POST" && manual) {
    if (openUpload) { observed("scans/manual-count"); return await manualCount(request, env, manual[1].toLowerCase()); }
    return await manualCountJob(request, env, await authenticate(request, env, "device_or_admin"), manual[1].toLowerCase());
  }
  if (method === "GET" && manual) return await manualCountRead(env, await authenticate(request, env, "device_or_admin"), manual[1].toLowerCase());
  const archive = path.match(/^\/v1\/scans\/([^/]+)\/archive$/);
  if (method === "GET" && archive) {
    await authenticate(request, env, "admin");
    return await listArchive(env, archive[1].toLowerCase(), true);
  }
  if (method === "GET" && path === "/v1/manual-counts") {
    await authenticate(request, env, "admin");
    return await listManualCountsPage(env, url);
  }
  if (method === "POST" && path === "/v1/reconstruct" && env.RECONSTRUCTION_ENABLED === "true") {
    if (openUpload) { observed("reconstruct"); return await reconstructPair(request, env); }
    await authenticate(request, env, "device_or_admin");
    return await reconstructPair(request, env);
  }
  if (method === "POST" && path === "/v1/diagnostics/upload") {
    return await diagnosticsUpload(request, await authenticate(request, env, "device_or_admin"));
  }
  if (method === "GET" && path === "/v1/admin/devices") {
    await authenticate(request, env, "admin");
    return await listDevices(env, url);
  }
  const admin = path.match(/^\/v1\/admin\/devices\/([^/]+)\/(approve|revoke)$/);
  if (method === "POST" && admin) {
    await authenticate(request, env, "admin");
    return await setDeviceStatus(env, admin[1], admin[2] === "approve" ? "active" : "revoked");
  }
  return json({ detail: { code: "not_found", message: "Route not found" } }, 404);
}

export { base64, buildBlock, captureQuality, fuseCounts, fuseCells, readCellIds, readOptionalCellIds, spanColumns, walkLayers };

export default {
  async fetch(request, env, ctx): Promise<Response> {
    const url = new URL(request.url);
    try {
      if (request.method === "GET" && url.pathname === "/health") return health(env);
      const ready = request.method === "GET" && url.pathname === "/ready";
      const mode = authMode(env);
      if (mode !== "open" && !ready) return await routeEnforced(request, env, url, mode, ctx);
      if (request.method === "POST" && url.pathname === "/v1/reconstruct" && env.RECONSTRUCTION_ENABLED === "true") return await reconstructPair(request, env);
      if (request.method === "GET" && url.pathname === "/ready") {
        return json({ status: env.ROBOFLOW_API_KEY ? "ready" : "not_ready", provider: "roboflow_serverless", model_reference: env.MODEL_ID }, env.ROBOFLOW_API_KEY ? 200 : 503);
      }
      if (request.method === "POST" && url.pathname === "/v1/scans/count") return await countScan(request, env);
      const manual = url.pathname.match(/^\/v1\/scans\/([^/]+)\/manual-count$/);
      if (request.method === "POST" && manual) return await manualCount(request, env, manual[1].toLowerCase());
      if (request.method === "GET" && url.pathname === "/v1/manual-counts") return await listManualCounts(env);
      const archive = url.pathname.match(/^\/v1\/scans\/([^/]+)\/archive$/);
      if (request.method === "GET" && archive) return await listArchive(env, archive[1].toLowerCase());
      return json({ detail: { code: "not_found", message: "Route not found" } }, 404);
    } catch (error) {
      if (error instanceof HttpError) return json({ detail: { code: error.code, message: error.message }, ...error.extra }, error.status);
      console.error(JSON.stringify({ event: "request_failed", error_type: "unexpected_error" }));
      return json({ detail: { code: "internal_error", message: "Scan could not be processed" } }, 500);
    }
  },
} satisfies ExportedHandler<Bindings>;
