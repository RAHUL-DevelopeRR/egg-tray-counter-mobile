import { Buffer } from "node:buffer";

type Bindings = Env & { ROBOFLOW_API_KEY: string; SCAN_ARCHIVE?: R2Bucket; RECONSTRUCTION_ENABLED?: string; RIM_VERIFY?: string; VISION_SERVICE_URL?: string; VISION_SERVICE_TOKEN?: string };

type Prediction = { class?: string; confidence?: number; x?: number; y?: number; width?: number; height?: number };
type ImageSize = { width: number; height: number };
type ViewInference = { count: number; confidence: number; detections?: Prediction[]; image?: ImageSize | null };

const VIEWS = ["left", "right", "straight"] as const;
const MAX_IMAGE_BYTES = 20 * 1024 * 1024;
const RETRYABLE = new Set([429, 502, 503, 504]);

class HttpError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

const json = (body: unknown, status = 200) =>
  Response.json(body, { status, headers: { "Cache-Control": "no-store" } });

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

async function countScan(request: Request, env: Bindings) {
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
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(rawScanId)) {
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

  // Private, content-addressed originals survive failed inference and retries.
  // No public download route: operators retrieve using authenticated R2 access.
  if (env.SCAN_ARCHIVE) {
    for (const [index, view] of VIEWS.entries()) {
      const file = files[view] as File;
      await env.SCAN_ARCHIVE.put(`scans/${rawScanId}/${view}/${hashes[index]}`, file.stream(), {
        httpMetadata: { contentType: file.type },
        customMetadata: { scan_id: rawScanId, view, sha256: hashes[index], received_at: new Date().toISOString() },
      });
    }
    console.log(JSON.stringify({ event: "scan_archived", scan_id: rawScanId }));
  }
  const started = Date.now();
  const results = {} as Record<string, ViewInference>;
  for (const view of VIEWS) results[view] = await infer(files[view] as File, env, modelScan,
    {scan_id: rawScanId, view});
  console.log(JSON.stringify({event: "scan_stages_complete", scan_id: rawScanId,
    multipart_ms: multipartMs, inference_ms: Date.now() - started,
    total_ms: Date.now() - requestStarted}));
  if (modelScan) {
    console.log(JSON.stringify({event: "scan_complete", scan_id: rawScanId, accepted: false,
      counts: Object.fromEntries(VIEWS.map(v => [v, results[v].count])), latency_ms: Date.now() - started}));
    const columns = Object.fromEntries(VIEWS.map(view => [view, spanColumns(results[view].detections ?? [])]));
    const rimStatus = await rimVerify(files as Record<string, File>, columns, env);
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
  return json({
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
  });
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
  return json({
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
  });
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
  perspective_gradient: number | null; pitch_px: number; duplicate_boxes: number; x_min: number; x_max: number; y_first: number; y_last: number;
  rim_count?: number | null; rim_confidence?: number | null };
type FaceColumn = { layers: number; scale: number; recessed: boolean; count_agreement: boolean; reason: string | null; source: string };
type Cell = { x: number; y: number; status: string; layers: number | null; source: string };
const RECESS_SCALE = 0.85;
const MAX_PERSPECTIVE_GRADIENT = 1.5;
const MIN_RIM_CONFIDENCE = 0.5;  // rim-edge verification only vetoes when its own confidence is at least this  // top-third / bottom-third layer spacing; measured frontal photos stay <= 1.42
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
// duplicate boxes and filling single missed layers. Exact on 51/53 reference stacks (span: 40/53).
function walkLayers(ysIn: number[], height: number) {
  const ys = [...ysIn].sort((a, b) => a - b);
  if (!ys.length) return { count: 0, gaps: [] as number[], duplicates: 0, filled: 0, perspective_gradient: null as number | null };
  const rawGaps = ys.slice(1).map((y, i) => y - ys[i]);
  const real = rawGaps.filter(g => g > 0.5 * height);
  const globalPitch = real.length ? median(real) : height;
  let pitch = globalPitch;
  let count = 1, duplicates = 0, filled = 0, last = ys[0];
  const gaps: number[] = [];
  for (const y of ys.slice(1)) {
    const gap = y - last;
    if (gap < 0.65 * pitch) { duplicates++; continue; }          // duplicate or stray half-pitch box
    const steps = Math.max(1, roundHalfEven(gap / pitch));
    if (steps > 1) filled += steps - 1;
    count += steps;
    for (let k = 0; k < steps; k++) gaps.push(gap / steps);
    pitch = Math.min(Math.max(median(gaps.slice(-3)), 0.6 * globalPitch), 1.4 * globalPitch);
    last = y;
  }
  let gradient: number | null = null;
  if (gaps.length >= 6) {
    const third = Math.max(2, Math.floor(gaps.length / 3));
    gradient = roundHalfEven(1000 * median(gaps.slice(0, third)) / median(gaps.slice(-third))) / 1000;
  }
  return { count, gaps, duplicates, filled, perspective_gradient: gradient };
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
      walk_count: walk.count, walk_filled: walk.filled, perspective_gradient: walk.perspective_gradient,
      pitch_px: roundHalfEven(pitch * 100) / 100, duplicate_boxes: column.length - real.length - 1,
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
    let reason: string | null = null;
    const rim = c.rim_count ?? null, rimConf = c.rim_confidence ?? 0;
    if (Math.abs(c.span_count - layers) > 1) reason = `layer counts disagree (span ${c.span_count}, walk ${layers}); retake this face`;
    else if (rim !== null && rimConf >= MIN_RIM_CONFIDENCE && rim !== layers) reason = `rim edges count ${rim} layers but boxes count ${layers}; retake this face`;
    else if (c.perspective_gradient !== null && c.perspective_gradient > MAX_PERSPECTIVE_GRADIENT)
      reason = `camera looked down on the stack (spacing ratio ${c.perspective_gradient}); hold the phone level at mid-height`;
    return { layers, scale, recessed: scale < RECESS_SCALE, count_agreement: reason === null, reason, source: name };
  });
}

const BLOCK_NOTE = "Interior stacks are computed from the observed faces (X x Y x height); missing or shorter interior stacks are not visible from the faces.";

function blockResult(width: number | null, depth: number | null, facesUsed: string[], typical: number | null, cells: Cell[], conflicts: Record<string, unknown>[]) {
  const observed = cells.filter(c => c.status === "observed").reduce((s, c) => s + (c.layers ?? 0), 0);
  const computed = cells.filter(c => c.status === "computed").reduce((s, c) => s + (c.layers ?? 0), 0);
  const rescan = cells.filter(c => c.status === "rescan" || c.status === "conflict").map(c => [c.x, c.y]);
  const consistent = !conflicts.length && !rescan.length && typical !== null;
  return { width, depth, faces_used: facesUsed, typical_layers: typical, cells, observed_trays: observed, computed_trays: computed,
    total_trays: consistent ? observed + computed : null, fully_observed: consistent && computed === 0, faces_consistent: consistent,
    conflicts, rescan_cells: rescan, note: BLOCK_NOTE };
}

function buildBlock(straightCols: SpanColumn[], leftCols: SpanColumn[], rightCols: SpanColumn[]) {
  const facesUsed = [...(straightCols.length ? ["straight"] : []), ...(leftCols.length ? ["left"] : []), ...(rightCols.length ? ["right"] : [])];
  if (!straightCols.length || (!leftCols.length && !rightCols.length)) {
    return blockResult(null, null, facesUsed, null, [], [{ reason: "STRAIGHT and at least one side face must show stacks" }]);
  }
  const xf = faceColumns(straightCols, "straight");
  const lf = leftCols.length ? faceColumns(leftCols, "left").reverse() : null;   // left photo: front corner is right-most
  const rf = rightCols.length ? faceColumns(rightCols, "right") : null;          // right photo: front corner is left-most
  const width = xf.length;
  const conflicts: Record<string, unknown>[] = [];
  const sides = ([["left", lf], ["right", rf]] as [string, FaceColumn[] | null][]).filter(([, f]) => f);
  const depths = Object.fromEntries(sides.map(([n, f]) => [n, f!.length]));
  if (new Set(Object.values(depths)).size > 1) conflicts.push({ reason: "depth differs between LEFT and RIGHT faces", ...depths });
  const depth = Math.max(...Object.values(depths));
  for (const [name, f, xi] of [["left", lf, 0], ["right", rf, width - 1]] as [string, FaceColumn[] | null, number][]) {
    if (!f) continue;
    const a = xf[xi], b = f[0];
    if (!b.count_agreement) conflicts.push({ cell: [xi, 0], reason: `${name.toUpperCase()}: ${b.reason}` });
    if (a.recessed !== b.recessed) conflicts.push({ cell: [xi, 0], reason: `corner stack is set back on one face only (STRAIGHT vs ${name.toUpperCase()})` });
    else if (Math.abs(a.layers - b.layers) > 1) conflicts.push({ cell: [xi, 0],
      reason: `corner height differs between STRAIGHT and ${name.toUpperCase()}`, straight_layers: a.layers, [`${name}_layers`]: b.layers });
  }
  const heights = [...xf, ...(lf ?? []), ...(rf ?? [])].filter(c => !c.recessed).map(c => c.layers);
  const typical = heights.length ? roundHalfEven(median(heights)) : null;
  const cells = new Map<string, Cell>();
  for (let y = 0; y < depth; y++) for (let x = 0; x < width; x++) cells.set(`${x},${y}`, { x, y, status: "computed", layers: typical, source: "faces" });
  const promotions = new Map<string, Partial<Cell>[]>();
  const place = (key: string, col: FaceColumn, source: string, behindKey: string) => {
    const cell = cells.get(key)!;
    if (col.recessed) {
      Object.assign(cell, { status: "missing", layers: 0, source });
      if (cells.has(behindKey)) promotions.set(behindKey, [...(promotions.get(behindKey) ?? []), { status: "observed", layers: col.layers, source: `${source}-recessed` }]);
      else conflicts.push({ cell: [cell.x, cell.y], reason: `${source.toUpperCase()} shows a stack behind a missing one, but the faces give no room for it; rescan` });
    } else Object.assign(cell, { status: "observed", layers: col.layers, source });
    if (!col.count_agreement) { cell.status = "rescan"; conflicts.push({ cell: [cell.x, cell.y], reason: `${source.toUpperCase()}: ${col.reason}` }); }
  };
  xf.forEach((col, x) => place(`${x},0`, col, "straight", `${x},1`));
  for (const [name, f, xi, dx] of [["left", lf, 0, 1], ["right", rf, width - 1, -1]] as [string, FaceColumn[] | null, number, number][]) {
    if (!f) continue;
    f.forEach((col, y) => { if (y === 0 || y >= depth) return; place(`${xi},${y}`, col, name, `${xi + dx},${y}`); });
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
  return blockResult(width, depth, facesUsed, typical, [...cells.values()], conflicts);
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
};
const NO_STACKS = "no stacks detected";
const CAPTURE_ADVICE = "Step closer and face the block squarely; the whole face must fill the frame";
type CaptureMetrics = { columns: number; model_boxes: number; pitch_px: number | null; pitch_frac: number | null;
  height_frac: number | null; coverage_x: number | null; pitch_gradient: number | null; recessed_columns: number;
  min_pitch_scale: number | null; image: ImageSize | null };
type CaptureQuality = { accepted: boolean; reasons: string[]; metrics: CaptureMetrics };
const round3 = (v: number | null) => v === null ? null : Math.round(v * 1000) / 1000;

function captureQuality(columns: SpanColumn[], imageWidth: number | null, imageHeight: number | null): CaptureQuality {
  const w = imageWidth !== null && Number.isFinite(imageWidth) && imageWidth > 0 ? imageWidth : null;
  const h = imageHeight !== null && Number.isFinite(imageHeight) && imageHeight > 0 ? imageHeight : null;
  const image = w && h ? { width: w, height: h } : null;
  if (!columns.length) {
    return { accepted: false, reasons: [NO_STACKS], metrics: { columns: 0, model_boxes: 0, pitch_px: null, pitch_frac: null,
      height_frac: null, coverage_x: null, pitch_gradient: null, recessed_columns: 0, min_pitch_scale: null, image } };
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
  if (gradient > GATE.max_pitch_gradient) reasons.push("layer pitch changes across the face (angled or corner view)");
  const minCoverage = ordered.length === 1 ? GATE.min_coverage_single : GATE.min_coverage_x;
  if (coverage !== null && coverage < minCoverage) reasons.push("stacks cover too little of the frame width");
  if (heightFrac !== null && heightFrac < GATE.min_height_frac) reasons.push("stacks are too small in the frame (too far away)");
  return { accepted: !reasons.length, reasons, metrics: {
    columns: ordered.length, model_boxes: ordered.reduce((s, c) => s + c.model_boxes, 0),
    pitch_px: Math.round(faceMedian * 100) / 100, pitch_frac: round3(pitchFrac), height_frac: round3(heightFrac),
    coverage_x: round3(coverage), pitch_gradient: round3(gradient), recessed_columns: recessed.length,
    min_pitch_scale: round3(Math.min(...scales)), image } };
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
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(scanId)) {
    throw new HttpError(422, "invalid_scan_id", "scan_id must be a UUID");
  }
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
  const recordedAt = new Date().toISOString();
  const totals = { filled: clean.reduce((s, c) => s + c.filled, 0), empty: clean.reduce((s, c) => s + c.empty, 0), unreachable: clean.filter(c => c.unreachable).length };
  const record = { kind: "manual_count_v1", scan_id: scanId, block_id: blockId, cells: clean, notes, tray, recorded_at: recordedAt,
    app_version: typeof body.app_version === "string" ? body.app_version.slice(0, 32) : null, totals };
  const key = `scans/${scanId}/manual-count/${recordedAt.replace(/[:.]/g, "-")}.json`;
  const body_ = JSON.stringify(record);
  const meta = { httpMetadata: { contentType: "application/json" }, customMetadata: { scan_id: scanId, block_id: blockId, kind: "manual_count" } };
  // Timestamped history plus a fixed "latest" key so scoring can fetch one object per scan.
  await env.SCAN_ARCHIVE.put(key, body_, meta);
  await env.SCAN_ARCHIVE.put(`scans/${scanId}/manual-count/latest.json`, body_, meta);
  console.log(JSON.stringify({ event: "manual_count_stored", scan_id: scanId, block_id: blockId, cells: clean.length, key }));
  return json({ stored: true, key, latest_key: `scans/${scanId}/manual-count/latest.json`, totals });
}

// Keys archived for one scan (photos by view/sha, manual counts). Key names only; bytes need
// authenticated R2 access. Scan ids are unguessable UUIDs.
async function listArchive(env: Bindings, scanId: string) {
  if (!env.SCAN_ARCHIVE) throw new HttpError(503, "archive_unavailable", "Scan archive is not configured");
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(scanId)) {
    throw new HttpError(422, "invalid_scan_id", "scan_id must be a UUID");
  }
  const listed = await env.SCAN_ARCHIVE.list({ prefix: `scans/${scanId}/`, limit: 100 });
  return json({ scan_id: scanId, keys: listed.objects.map(o => ({ key: o.key, size: o.size, uploaded: o.uploaded })) });
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
    captureQuality(columns[view], results[view].image?.width ?? null, results[view].image?.height ?? null)]));
  const rejectedView = worstView(capture, VIEWS);
  const assembled = buildBlock(columns.straight, columns.left, columns.right);
  // A face that fails the capture gate gives no usable column counts, so the block total is withheld.
  const block = rejectedView ? { ...assembled, total_trays: null, faces_consistent: false, fully_observed: false } : assembled;
  // Model boxes are useful evidence, but not proof of cross-view identity or egg occupancy.
  // Do not substitute whole-photo voting for an unfinished spatial hybrid pipeline.
  const reason = "Model detections are available. Physical stack matching and egg occupancy remain unresolved; these per-photo counts are not a verified inventory total.";
  const rescan = rejectedView
    ? { recommended_view: rejectedView, reason: `${CAPTURE_ADVICE} (${rejectedView.toUpperCase()}: ${capture[rejectedView].reasons.join("; ")})` }
    : { recommended_view: "straight", reason };
  return json({
    scan_id: scanId, status: "rescan_required", accepted: false,
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
      total_eggs: block.total_trays === null ? null : block.total_trays * Number(env.EGGS_PER_TRAY), capture },
    rescan,
  });
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

export { base64, buildBlock, captureQuality, fuseCounts, fuseCells, readCellIds, readOptionalCellIds, spanColumns };

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);
    try {
      if (request.method === "GET" && url.pathname === "/health") return json({ status: "ok", scan_contract: "cell_identity_v1", scan_contracts: ["cell_identity_v1", "model_spatial_v1", ...(env.RECONSTRUCTION_ENABLED === "true" ? ["reconstruct_v1"] : [])], hybrid_ready: false });
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
      if (error instanceof HttpError) return json({ detail: { code: error.code, message: error.message } }, error.status);
      console.error(JSON.stringify({ event: "request_failed", error_type: "unexpected_error" }));
      return json({ detail: { code: "internal_error", message: "Scan could not be processed" } }, 500);
    }
  },
} satisfies ExportedHandler<Bindings>;
