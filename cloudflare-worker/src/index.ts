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
  scanContract: string | null; modelScan: boolean; baselineScan: boolean; requestStarted: number; multipartMs: number;
  headings: Record<string, ViewHeading>; captures: Record<string, ViewCapture>; evidence: Record<string, string | null>;
  extras: ScanExtras };
// Optional evidence beyond the three faces (0.5.0): the blind declaration, a CORNER photo and an ELEVATED photo with
// the operator's taps.
type ScanExtras = { declaration: BlockDeclaration | null; corner: File | null; cornerHash: string | null; cornerCapture: ViewCapture;
  cornerSide: string | null; elevated: File | null; elevatedHash: string | null; elevatedCapture: ViewCapture; topView: TopViewTaps | null };
// Phone heading at capture, from the app's per-view constraint evidence: gyroscope yaw about gravity in degrees,
// comparable only within one yaw_session (one scan, kept across retakes). Positive yaw is a left (counter-clockwise)
// turn seen from above.
type ViewHeading = { yaw_deg: number; yaw_session: string } | null;
// How a photo was taken, as the app reports it: source "captured_still" (the guided camera) or "uploaded_photo"
// (the gallery), and whether the phone's live checks blocked it. Self-reported: it stops honest mistakes such as a
// gallery photo standing in for a face, not a modified app.
type ViewCapture = { source: string | null; blocked: boolean | null; heading: ViewHeading };
const MAX_EVIDENCE_CHARS = 8000;
const MAX_CAPTURE_CHARS = 1000;
const MAX_ARCHIVED_EVIDENCE_CHARS = 64_000;

function headingFrom(evidence: Record<string, unknown>): ViewHeading {
  const yaw = evidence.yaw_deg, session = evidence.yaw_session;
  if (typeof yaw !== "number" || !Number.isFinite(yaw) || Math.abs(yaw) > 1e6) return null;
  if (typeof session !== "string" || !/^[A-Za-z0-9_-]{1,64}$/.test(session)) return null;
  return { yaw_deg: yaw, yaw_session: session };
}

// Evidence is additive and never refuses a scan: anything missing or malformed is simply unknown. Apps from 0.4.15
// send a short <view>_capture field, so the heading no longer depends on the full constraint evidence staying under
// MAX_EVIDENCE_CHARS; older apps send only <view>_constraint_evidence.
function readCapture(form: FormData, view: string): ViewCapture {
  const parse = (name: string, limit: number) => {
    const raw = form.get(name);
    if (typeof raw !== "string" || !raw || raw.length > limit) return null;
    try {
      const value = JSON.parse(raw) as unknown;
      return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
    } catch {
      return null;
    }
  };
  const evidence = parse(`${view}_capture`, MAX_CAPTURE_CHARS) ?? parse(`${view}_constraint_evidence`, MAX_EVIDENCE_CHARS);
  if (!evidence) return { source: null, blocked: null, heading: null };
  const source = typeof evidence.source === "string" && evidence.source.length <= 40 ? evidence.source : null;
  return { source, blocked: typeof evidence.blocked === "boolean" ? evidence.blocked : null, heading: headingFrom(evidence) };
}

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
  const checkImage = async (file: File, name: string) => {
    if (!["image/jpeg", "image/png"].includes(file.type)) {
      throw new HttpError(415, "invalid_mime_type", `${name} must be a JPEG or PNG image`);
    }
    if (!file.size || file.size > MAX_IMAGE_BYTES) {
      throw new HttpError(413, "image_too_large", `${name} is empty or exceeds 20 MB`);
    }
    const signature = new Uint8Array(await file.slice(0, 8).arrayBuffer());
    const jpeg = signature[0] === 0xff && signature[1] === 0xd8 && signature[2] === 0xff;
    const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every((byte, i) => signature[i] === byte);
    if (!jpeg && !png) throw new HttpError(415, "invalid_image_signature", `${name} is not a valid JPEG or PNG`);
  };
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
  const captures = Object.fromEntries(VIEWS.map(view => [view, readCapture(form, view)]));
  const extraFile = async (name: string) => {
    const file = form.get(name);
    if (!(file instanceof File)) return { file: null, hash: null };
    await checkImage(file, name.toUpperCase());
    const hash = await sha256(file);
    if (hashes.includes(hash)) throw new HttpError(422, "duplicate_view", `${name.toUpperCase()} must be a photo of its own, not a copy of a face`);
    return { file, hash };
  };
  const corner = await extraFile("corner"), elevated = await extraFile("elevated");
  const cornerSide = ["front_left", "front_right"].includes(String(form.get("corner_side"))) ? String(form.get("corner_side")) : null;
  const extras: ScanExtras = { declaration: readDeclaration(form), corner: corner.file, cornerHash: corner.hash,
    cornerCapture: readCapture(form, "corner"), cornerSide, elevated: elevated.file, elevatedHash: elevated.hash,
    elevatedCapture: readCapture(form, "elevated"), topView: readTopViewTaps(form) };
  const evidence = Object.fromEntries(VIEWS.map(view => {
    const raw = form.get(`${view}_constraint_evidence`);
    return [view, typeof raw === "string" && raw && raw.length <= MAX_ARCHIVED_EVIDENCE_CHARS ? raw : null];
  }));
  return { scanId: rawScanId, files: files as Record<string, File>, hashes, cellIds,
    scanContract: requestedContract === null ? null : String(requestedContract), modelScan, baselineScan, requestStarted, multipartMs,
    headings: Object.fromEntries(VIEWS.map(view => [view, captures[view].heading])), captures, evidence, extras };
}

// Private, content-addressed originals survive failed inference and retries.
// No public download route: operators retrieve using authenticated R2 access.
async function archiveScan(env: Bindings, { scanId: rawScanId, files, hashes, captures, evidence, extras }: ParsedScan) {
  if (env.SCAN_ARCHIVE) {
    const meta = { scan_id: rawScanId, received_at: new Date().toISOString() };
    for (const [name, file, hash, capture] of [["corner", extras.corner, extras.cornerHash, extras.cornerCapture],
      ["elevated", extras.elevated, extras.elevatedHash, extras.elevatedCapture]] as [string, File | null, string | null, ViewCapture][]) {
      if (file && hash) await env.SCAN_ARCHIVE.put(`scans/${rawScanId}/${name}/${hash}`, file.stream(), {
        httpMetadata: { contentType: file.type }, customMetadata: { ...meta, view: name, sha256: hash,
          ...(capture.source !== null ? { capture_source: capture.source } : {}) } });
    }
    // The declaration and the elevated taps are their own evidence source, kept as sent (parsed).
    if (extras.declaration || extras.topView || extras.cornerSide) {
      await env.SCAN_ARCHIVE.put(`scans/${rawScanId}/declaration.json`, JSON.stringify({ declaration: extras.declaration,
        elevated_taps: extras.topView, corner_side: extras.cornerSide }), { httpMetadata: { contentType: "application/json" }, customMetadata: meta });
    }
    for (const [index, view] of VIEWS.entries()) {
      const file = files[view];
      // Provenance and heading travel with the photo, so a replay from the archive judges the faces as the live scan did.
      const { source, blocked, heading } = captures[view];
      await env.SCAN_ARCHIVE.put(`scans/${rawScanId}/${view}/${hashes[index]}`, file.stream(), {
        httpMetadata: { contentType: file.type },
        customMetadata: { scan_id: rawScanId, view, sha256: hashes[index], received_at: new Date().toISOString(),
          ...(source !== null ? { capture_source: source } : {}), ...(blocked !== null ? { capture_blocked: String(blocked) } : {}),
          ...(heading ? { yaw_deg: String(heading.yaw_deg), yaw_session: heading.yaw_session } : {}) },
      });
      // The full live-check evidence (pose, frame metrics, checks) is kept beside the photo for later threshold work.
      if (evidence[view]) await env.SCAN_ARCHIVE.put(`scans/${rawScanId}/${view}/evidence.json`, evidence[view]!, {
        httpMetadata: { contentType: "application/json" }, customMetadata: { scan_id: rawScanId, view, sha256: hashes[index] } });
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
    const columns = Object.fromEntries(VIEWS.map(view => [view, spanColumns(results[view].detections ?? [], results[view].image ?? null)]));
    const rimStatus = await rimVerify(files, columns, env);
    console.log(JSON.stringify({event: "rim_verify", scan_id: rawScanId, status: rimStatus}));
    const extras = scan.extras;
    const corner = extras.corner ? await infer(extras.corner, env, modelScan, {scan_id: rawScanId, view: "corner"}) : null;
    const captureIds = Object.fromEntries(VIEWS.map((view, i) => [view, scan.hashes[i].slice(0, 16)]));
    return modelDiagnostics(rawScanId, results, cellIds, env, Date.now() - started, columns, rimStatus, scan.headings, scan.captures,
      { declaration: extras.declaration, topView: extras.topView, corner, cornerSide: extras.cornerSide, cornerCapture: extras.cornerCapture,
        elevated: !!extras.elevated, captureIds });
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
  duplicate_boxes: number; x_min: number; x_max: number; y_first: number; y_last: number; doubts?: string[];
  rim_count?: number | null; rim_confidence?: number | null };
type FaceColumn = { layers: number; filled: number; doubts: string[]; scale: number; recessed: boolean; count_agreement: boolean; reason: string | null; source: string };
type CellReading = { face: string; layers: number; gap_filled: number; doubts: string[]; trusted: boolean };
type Cell = { x: number; y: number; status: string; layers: number | null; source: string; filled_layers?: number; verified?: boolean;
  readings?: CellReading[]; hidden?: boolean; assumed_layers?: number | null; assumed_range?: [number, number | null] | null;
  assumed_from?: string | null; neighbours?: { x: number; y: number; layers: number }[]; flags?: string[];
  past_gap_layers?: number | null; past_gap_scale?: number | null; past_gap_face?: string | null };
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

// Doubts: a stack reading that may have lost a tray with nothing else to show for it (2026-11-01 miss taxonomy,
// reports/miss-taxonomy-20261101). Every silent miss on a close face was at a stack end:
// - box_over_two_stacks: a box 1.5x the face's median width covered the top trays of two stacks, and the second
//   stack lost its top tray (img-30 stack 2);
// - box_over_two_trays: a box 1.5x its column's median height;
// - end_box_cut_short: the bottom tray, cut by the frame edge, got a half-height box whose centre sat 0.3 pitch from
//   the box above, so it was merged as a duplicate (img-30 and L-80 stack 4);
// - bottom_above_floor: the bottom tray had no box at all; the stack's last box sits over half a pitch above its
//   neighbours' (L-109 stack 4).
// With the image size (2026-11-01 plan Phase K1):
// - end_at_frame_edge: the column's top or bottom box lies within one box height of the frame edge, so a tray
//   beyond it can be cut off or missing (img-30 and L-80: 0.07 / 0.00 box heights; every correct accepted face had
//   at least 2.0);
// - cut_at_frame_side: the column touches the left or right frame edge, so it may be part of a stack;
// - pitch_differs: the column's layer pitch is over 1.2x the face's, a nearer stack or another block (M16-FAR).
// A doubt never refuses a count. It only keeps that reading from verifying a stack.
const ODD_BOX_SCALE = 1.5;
const SHORT_END_BOX = 0.6;
const FRAME_MARGIN_BOXES = 1;
const SIDE_TOUCH_FRACTION = 0.005;
const PITCH_DIFFERS_SCALE = 1.2;
type Box = { x: number; y: number; width: number; height: number };

// Boxes grouped into stack columns by x: a box joins the last column when it lies within 0.6 x the median box width
// of that column's mean x.
function groupColumns(detections: Prediction[]): { groups: Box[][]; medianWidth: number } {
  const boxes = detections.filter(d => [d.x, d.y, d.width, d.height].every(v => Number.isFinite(v)) && d.width! > 0 && d.height! > 0)
    .map(d => ({ x: d.x!, y: d.y!, width: d.width!, height: d.height! }));
  if (!boxes.length) return { groups: [], medianWidth: 0 };
  const medianWidth = median(boxes.map(b => b.width));
  const groups: Box[][] = [];
  for (const box of [...boxes].sort((a, b) => a.x - b.x)) {
    const last = groups[groups.length - 1];
    if (last && box.x - last.reduce((s, b) => s + b.x, 0) / last.length < 0.6 * medianWidth) last.push(box);
    else groups.push([box]);
  }
  return { groups, medianWidth };
}

function spanColumns(detections: Prediction[], frame: ImageSize | null = null): SpanColumn[] {
  const { groups, medianWidth } = groupColumns(detections);
  const columns = groups.filter(c => c.length >= 3);
  // A box wider than a stack also covers the neighbouring stack's tray at that level, so every column whose centre
  // it spans is marked, not only the one it was grouped into.
  const centres = columns.map(c => c.reduce((s, b) => s + b.x, 0) / c.length);
  const wide = columns.flat().filter(b => b.width > ODD_BOX_SCALE * medianWidth);
  const result = columns.map((column, index) => {
    const ordered = [...column].sort((a, b) => a.y - b.y);
    const ys = ordered.map(b => b.y);
    const height = median(column.map(b => b.height));
    const real = ys.slice(1).map((y, i) => y - ys[i]).filter(g => g > 0.5 * height);
    const pitch = real.length ? median(real) : height;
    const walk = walkLayers(ys, height);
    const doubts: string[] = [];
    if (wide.some(b => column.includes(b) || Math.abs(b.x - centres[index]) < b.width / 2)) doubts.push("box_over_two_stacks");
    if (column.some(b => b.height > ODD_BOX_SCALE * height)) doubts.push("box_over_two_trays");
    if ([ordered[0], ordered[ordered.length - 1]].some(b => b.height < SHORT_END_BOX * height)) doubts.push("end_box_cut_short");
    if (frame && frame.width > 0 && frame.height > 0) {
      const top = Math.min(...column.map(b => b.y - b.height / 2)), bottom = Math.max(...column.map(b => b.y + b.height / 2));
      if (top < FRAME_MARGIN_BOXES * height || frame.height - bottom < FRAME_MARGIN_BOXES * height) doubts.push("end_at_frame_edge");
      const left = Math.min(...column.map(b => b.x - b.width / 2)), right = Math.max(...column.map(b => b.x + b.width / 2));
      if (left <= SIDE_TOUCH_FRACTION * frame.width || right >= (1 - SIDE_TOUCH_FRACTION) * frame.width) doubts.push("cut_at_frame_side");
    }
    return { column: index + 1, model_boxes: column.length, span_count: roundHalfEven((ys[ys.length - 1] - ys[0]) / pitch) + 1,
      walk_count: walk.count, walk_filled: walk.filled, walk_unresolved_gaps: walk.unresolved_gaps, perspective_gradient: walk.perspective_gradient,
      pitch_px: roundHalfEven(pitch * 100) / 100, box_height_px: roundHalfEven(height * 100) / 100, duplicate_boxes: column.length - real.length - 1,
      x_min: roundHalfEven(Math.min(...column.map(b => b.x - b.width / 2)) * 10) / 10,
      x_max: roundHalfEven(Math.max(...column.map(b => b.x + b.width / 2)) * 10) / 10,
      y_first: roundHalfEven(ys[0] * 10) / 10, y_last: roundHalfEven(ys[ys.length - 1] * 10) / 10, doubts };
  });
  // Floor line: stacks stand on one floor, so a bottom box over half a pitch above both neighbours' marks a lost
  // bottom tray. Set-back stacks are left out (their bottoms sit higher), and so are the two end stacks: with one
  // neighbour, camera tilt alone moved a correct end stack's bottom that far on 4 of 21 accepted faces (2026-11-01).
  const pitches = result.map(c => c.pitch_px);
  const reference = median(pitches.filter(p => p >= median(pitches)));
  for (const c of result) if (c.pitch_px > PITCH_DIFFERS_SCALE * reference) c.doubts.push("pitch_differs");
  const front = result.filter(c => c.pitch_px >= RECESS_SCALE * reference);
  front.forEach((c, i) => {
    const neighbours = [front[i - 1], front[i + 1]].filter(Boolean);
    if (neighbours.length === 2 && neighbours.every(n => c.y_last < n.y_last - 0.5 * c.pitch_px)) c.doubts.push("bottom_above_floor");
  });
  return result;
}

/** Groups of one or two boxes: a short stack, a loose tray or a stray box. Never counted, but reported. */
function strayGroups(detections: Prediction[]) {
  return groupColumns(detections).groups.filter(g => g.length < 3).map(g => ({ boxes: g.length,
    x_min: roundHalfEven(Math.min(...g.map(b => b.x - b.width / 2)) * 10) / 10,
    x_max: roundHalfEven(Math.max(...g.map(b => b.x + b.width / 2)) * 10) / 10 }));
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
    return { layers, filled: c.walk_filled ?? 0, doubts: c.doubts ?? [], scale, recessed: scale < RECESS_SCALE,
      count_agreement: reason === null, reason, source: name };
  });
}

const BLOCK_NOTE = "Counted trays are read top to floor on photographed faces. Hidden stacks are set to the block's full height by the farm's " +
  "stacking rule (partial stacks stand only on the photographed faces, the back row is full, no inside place is empty); they are not seen " +
  "and not counted. A top view checks holes and step-ups, never counts. A depth over one stack rests on the declared block size.";

/** The most common value, ties to the lower; null for an empty list. */
function mode(values: number[]) {
  const counts = new Map<number, number>();
  for (const v of values) counts.set(v, (counts.get(v) ?? 0) + 1);
  let best: number | null = null;
  for (const [v, n] of counts) if (best === null || n > counts.get(best)! || (n === counts.get(best)! && v < best)) best = v;
  return best;
}

/** A face reading of a stack: top to floor, the only real count. Seen-empty gaps, conflicts and stacks seen only through
 * a gap are not. */
const measuredCell = (c: Cell | undefined): c is Cell => !!c && c.status === "observed" && !c.hidden && (c.layers ?? 0) > 0;

// Hidden stacks (0.7.0, docs/GRID_CONTRACT_0.7.0.md; Plan 5 Decision 1, answered "yes" on 5 Nov 2026): a stack no face
// photo counts is the block's full height H "by the stacking rule" (stackingRule below), never seen and never counted.
// This replaces 0.6.0's median of the line-of-sight neighbours, which took half-filled face stacks as neighbours and so
// under-read the hidden stacks behind them (contract case H2: 236 where the rule gives 237). The cell's range is [H, H]:
// the cover-tray range of the hidden stacks is reported once, on the block (rule.range_heights). Idempotent: it rewrites
// only hidden cells.
function assumeHidden(cells: Cell[], X: number, Y: number, height: number | null) {
  for (const g of cells.filter(c => c.status === "computed" && c.x < X && c.y < Y)) {
    const flags: string[] = (g.flags ?? []).filter(f => f === "line_of_sight_past_gap");
    Object.assign(g, { hidden: true, layers: height, assumed_layers: height, assumed_range: height === null ? null : [height, height],
      assumed_from: "stacking_rule", neighbours: [], flags });
  }
  return cells;
}

// ---- 0.7.0 stacking rule (docs/PLAN_5_MULTI_PHOTO.md §4). The farm's rules, stated by the user on 5 Nov 2026 and not yet
// audited on a farm day: partial stacks stand only on the photographed faces (STRAIGHT, LEFT, RIGHT), the back row is
// always full, and no inside place is ever empty. So every hidden stack is the block's full height H. H is read from the
// faces: the largest height that two different stacks read cleanly on two different faces, one of them a back corner
// (the back row is full, so a back corner is a full stack). Cover trays are used "sometimes" (Decision 4), so a full
// stack is F or F + 1 layers: H and the height one away are both full, and the hidden stacks get a range. Each check
// that fails withholds the total and names the face to retake. A rule value is never "counted", "measured", "exact" or
// "confirmed": every block that uses the rule is at most estimated.
type RuleBasis = "two_faces" | "strict_sides" | "doubted_allowed" | "any_photo";
type RuleOptions = { basis: RuleBasis; plurality: boolean; coverRange: boolean; taller: "withhold" | "note";
  backCorner: "withhold" | "warn"; oneSide: "withhold" | "wall_full"; heightRange: [number, number] | null };
// Decision 3 (open; default (a)): basis "two_faces" = (a), "strict_sides" = (a') a side that repeats the front never
// counts, "any_photo" = (b) two stacks in any photo, no back corner needed, "doubted_allowed" = (c) as (a) with doubted and
// gap-filled readings. Decision 4 (answered "sometimes"): coverRange on, plurality guard off. Decisions 5 (taller), 6
// (back corner), 7 (one side) and 10 (height range) at the plan's defaults.
const RULE_DEFAULTS: Readonly<RuleOptions> = Object.freeze({ basis: "two_faces", plurality: false, coverRange: true, taller: "withhold",
  backCorner: "withhold", oneSide: "withhold", heightRange: null } as RuleOptions);
const RULE_FACE_ORDER = ["straight", "left", "right"];
type RuleStack = { x: number; y: number; face: string; layers: number };
type RuleSummary = {
  applied: boolean; options: RuleOptions; height: number | null; partner: number | null; full_heights: number[];
  range_heights: [number, number] | null; hidden_stacks: number; basis: RuleStack[]; stacks_at_height: number;
  taller: (RuleStack & { released: boolean })[]; back_corners: (RuleStack & { check: string })[];
  plurality: { at_height: number; one_below: number; withheld: boolean } | null;
  hints_below: { x: number; y: number; face: string | null; layers: number }[]; doubted_low: RuleStack[];
  kept_readings: RuleStack[]; one_side: string | null; withheld_reason: string | null; notes: string[];
  exceptions?: { x: number; y: number; kind: string; layers: number | null }[]; affirmed_by_operator?: boolean;
  provisional?: Record<string, unknown> | null };

function emptyRule(options: RuleOptions, hidden: number): RuleSummary {
  return { applied: hidden > 0, options, height: null, partner: null, full_heights: [], range_heights: null, hidden_stacks: hidden,
    basis: [], stacks_at_height: 0, taller: [], back_corners: [], plurality: null, hints_below: [], doubted_low: [], kept_readings: [],
    one_side: null, withheld_reason: null, notes: [] };
}

/** The heights a full stack may have once H is known: [H-1, H+1] while the faces show only H (nobody knows whether H
 * includes a cover tray), the pair the faces show otherwise; [H, H] with the cover range off. */
function ruleRange(height: number, partner: number | null, coverRange: boolean): [number, number] {
  if (!coverRange) return [height, height];
  return partner === null ? [height - 1, height + 1] : [Math.min(height, partner), Math.max(height, partner)];
}

// cells: buildBlock's merged cells (hidden ones flagged); sidesSeen: the side faces that show stacks; eligible: per face,
// whether its readings may set H (a guided-camera still, not blocked, not a copy, a side confirmed as a side face; a side
// that repeats the front counts once a CORNER photo and the declaration settle it). A failed check pushes a conflict
// tagged `check` and, for a named stack, sets that cell to conflict (its reading is kept in kept_readings).
function stackingRule(cells: Cell[], X: number, Y: number, sidesSeen: string[], eligible: (face: string) => boolean,
  opts: RuleOptions, conflicts: Record<string, unknown>[]): RuleSummary {
  const hidden = cells.filter(c => c.hidden);
  const rule = emptyRule(opts, hidden.length);
  if (!hidden.length) return rule;
  const withhold = (check: string, conflict: Record<string, unknown>) => {
    conflicts.push({ ...conflict, check });
    rule.withheld_reason ??= check;
  };
  const readings = (c: Cell) => (c.readings ?? []) as CellReading[];
  const isFace = (c: Cell) => !c.hidden && c.status === "observed";
  const unDoubted = (r: CellReading) => !r.gap_filled && !r.doubts.length;
  const candidate = (r: CellReading) => (opts.basis === "doubted_allowed" || unDoubted(r)) && eligible(r.face);
  const isBackCorner = (c: Cell) => c.y === Y - 1 && (c.x === 0 || c.x === X - 1);
  const faceOrder = (faces: Set<string>) => RULE_FACE_ORDER.filter(f => faces.has(f));
  const where = (c: { x: number; y: number }) => `(${c.x}, ${c.y})`;
  // Clean readings by height: for each height, the stacks read at it and the faces that read them.
  const at = new Map<number, Map<Cell, Set<string>>>();
  for (const c of cells.filter(isFace)) for (const r of readings(c).filter(candidate)) {
    const stacks = at.get(r.layers) ?? new Map<Cell, Set<string>>();
    at.set(r.layers, stacks);
    stacks.set(c, new Set([...(stacks.get(c) ?? []), r.face]));
  }
  if (sidesSeen.length < 2) {
    const missing = ["left", "right"].find(s => !sidesSeen.includes(s))!;
    rule.one_side = missing;
    if (opts.oneSide === "withhold") withhold("one_side_only", { reason: `${missing.toUpperCase()}: only one side face was photographed; ` +
      `partial stacks may stand on the side not seen, so the stacking rule cannot set the hidden stacks; photograph the ${missing} side face` });
  }
  // Two distinct stacks at h on two different faces, one of them a back corner; a stack counts once, for one face.
  const basisAt = (h: number): RuleStack[] | null => {
    const stacks = [...(at.get(h) ?? new Map<Cell, Set<string>>()).entries()].sort(([a], [b]) => b.y - a.y || a.x - b.x);
    if (opts.basis === "any_photo") return stacks.length >= 2
      ? stacks.slice(0, 2).map(([c, f]) => ({ x: c.x, y: c.y, face: faceOrder(f)[0], layers: h })) : null;
    for (const [a, fa] of stacks) {
      if (!isBackCorner(a)) continue;
      for (const [b, fb] of stacks) {
        if (b === a) continue;
        for (const f1 of faceOrder(fa)) for (const f2 of faceOrder(fb)) if (f1 !== f2)
          return [{ x: a.x, y: a.y, face: f1, layers: h }, { x: b.x, y: b.y, face: f2, layers: h }];
      }
    }
    return null;
  };
  let H: number | null = null;
  for (const h of [...at.keys()].sort((a, b) => b - a)) {
    const basis = basisAt(h);
    if (basis) { H = h; rule.basis = basis; break; }
  }
  if (H === null) {
    // Until a close photo of a back corner can be asked for (Plan 5 Phase 5): retake the side with the most doubts.
    const doubted = (side: string) => cells.filter(isFace).flatMap(readings).filter(r => r.face === side && !unDoubted(r)).length;
    const side = [...sidesSeen].sort((a, b) => doubted(b) - doubted(a))[0] ?? "straight";
    withhold("no_rule_height", { reason: `${side.toUpperCase()}: no full height for the hidden stacks: the stacking rule needs two stacks ` +
      `read cleanly at one height on two different faces, one of them a back corner; retake this side closer, with the back corner stack whole in the frame` });
    return rule;
  }
  rule.height = H;
  rule.stacks_at_height = at.get(H)!.size;
  const partner = !opts.coverRange ? null : at.has(H - 1) ? H - 1 : at.has(H + 1) ? H + 1 : null;
  rule.partner = partner;
  rule.full_heights = partner === null ? [H] : [Math.min(H, partner), Math.max(H, partner)];
  const [lo, hi] = rule.range_heights = ruleRange(H, partner, opts.coverRange);
  const fullText = partner === null ? `${H}` : `${lo} or ${hi}, with or without a cover tray`;
  if (opts.heightRange && (H < opts.heightRange[0] || H > opts.heightRange[1]))
    withhold("rule_height_out_of_range", { reason: `${rule.basis[0].face.toUpperCase()}: the block's full height ${H} is outside the farm's ` +
      `normal range ${opts.heightRange[0]}-${opts.heightRange[1]}; retake this face` });
  const oneBelow = at.get(H - 1)?.size ?? 0;
  rule.plurality = { at_height: rule.stacks_at_height, one_below: oneBelow, withheld: opts.plurality && oneBelow > rule.stacks_at_height };
  if (rule.plurality.withheld) withhold("rule_height_ambiguous", { reason: `${rule.basis[0].face.toUpperCase()}: more face stacks read ` +
    `${H - 1} than ${H}, so the full height may rest on two over-read stacks or two cover trays; retake this face` });
  // A face stack above the full heights: H may be too low, or the stack was over-read. A second capture reading the same
  // height releases it (counted as read, H unchanged).
  for (const c of cells.filter(isFace)) {
    if ((c.layers ?? 0) <= hi) continue;
    const face = readings(c).find(r => r.layers === c.layers)?.face ?? "straight";
    const released = opts.taller === "note" || c.verified === true;
    rule.taller.push({ x: c.x, y: c.y, face, layers: c.layers!, released });
    if (released) { rule.notes.push(`one stack taller than the block's full height: ${where(c)} reads ${c.layers}`); continue; }
    rule.kept_readings.push({ x: c.x, y: c.y, face, layers: c.layers! });
    withhold("stack_taller_than_rule_height", { cell: [c.x, c.y], layers: c.layers, rule_height: H,
      reason: `${face.toUpperCase()}: the stack at ${where(c)} reads ${c.layers} trays, above the block's full height (${fullText}); retake this face so a second photo reads it` });
    Object.assign(c, { status: "conflict", layers: null });
  }
  // The back row is full by the rule, so a back corner read cleanly below the full heights breaks it (a doubted low
  // reading is kept at its reading and shows how far it could rise, Decision 9).
  for (const c of cells.filter(c => isBackCorner(c))) {
    const side = c.x === 0 ? "left" : "right";
    if (c.hidden) { rule.back_corners.push({ x: c.x, y: c.y, face: side, layers: 0, check: "not_seen" }); continue; }
    if (c.status !== "observed" && c.status !== "missing") continue;
    const layers = c.status === "missing" ? 0 : c.layers!;
    const face = readings(c).find(r => r.layers === c.layers)?.face ?? side;
    const clean = c.status === "missing" || readings(c).some(r => r.layers === c.layers && candidate(r));
    if (layers >= lo) { rule.back_corners.push({ x: c.x, y: c.y, face, layers, check: "full" }); continue; }
    if (!clean) { rule.back_corners.push({ x: c.x, y: c.y, face, layers, check: "doubted_low" }); continue; }
    const released = opts.backCorner === "warn" || c.verified === true;
    rule.back_corners.push({ x: c.x, y: c.y, face, layers, check: released ? "rule_broken" : "below" });
    if (released) { rule.notes.push(`rule broken at back corner ${where(c)}: it reads ${layers}`); continue; }
    rule.kept_readings.push({ x: c.x, y: c.y, face, layers });
    withhold("back_corner_below_rule_height", { cell: [c.x, c.y], layers, rule_height: H,
      reason: `${face.toUpperCase()}: the back corner stack at ${where(c)} reads ${layers}, below the block's full height (${fullText}); ` +
        `the stacking rule says the back row is full: retake this side` });
    Object.assign(c, { status: "conflict", layers: null });
  }
  // Trays glimpsed through a gap on a hidden cell, below the full heights: a short hidden stack, or another block behind.
  for (const c of hidden.filter(c => c.status === "computed" && c.past_gap_layers !== null && c.past_gap_layers !== undefined && c.past_gap_layers < lo)) {
    const face = c.past_gap_face ?? null;
    rule.hints_below.push({ x: c.x, y: c.y, face, layers: c.past_gap_layers! });
    withhold("inside_hint_below_rule", { cell: [c.x, c.y], past_gap_layers: c.past_gap_layers, rule_height: H,
      reason: `${(face ?? "straight").toUpperCase()}: trays seen through a gap in front of the hidden stack at ${where(c)} read ${c.past_gap_layers}, ` +
        `below the block's full height (${fullText}): it may be a short hidden stack or another block behind; retake this face` });
    Object.assign(c, { status: "conflict", layers: null });
  }
  // Decision 9: a doubted or gap-filled face reading below H stays at its reading; the result says how far it could rise.
  for (const c of cells.filter(isFace)) if ((c.layers ?? 0) > 0 && c.layers! < H && !readings(c).some(r => r.layers === c.layers && unDoubted(r)))
    rule.doubted_low.push({ x: c.x, y: c.y, face: readings(c)[0]?.face ?? "straight", layers: c.layers! });
  return rule;
}

// status: exact (every stack seen and verified by two photos, faces agree), estimated (a total, but hidden stacks
// computed, a stack read by one photo only, or a reading ambiguous), conflict (no total; retake the named face),
// needs_view (a face is missing or refused).
// One photo's reading of a stack can be wrong with nothing to show for it: a box over two trays loses one, and an
// end tray can have no box at all (2026-11-01 miss taxonomy: img-30 read 78 for 80 with every rule satisfied). So a
// stack counts as verified only when two different photos read it the same, with no gap-filled layer and no doubt
// (see spanColumns); agreement between counts from the same boxes (span and walk) is not a second reading.
function blockResult(width: number | null, depth: number | null, facesUsed: string[], typical: number | null, cells: Cell[],
  conflicts: Record<string, unknown>[], ambiguities: Record<string, unknown>[] = [], needsView = false, rule: RuleSummary | null = null) {
  const sum = (list: Cell[]) => list.reduce((s, c) => s + (c.layers ?? 0), 0);
  const observedCells = cells.filter(c => c.status === "observed");
  const observed = sum(observedCells);
  const computed = sum(cells.filter(c => c.status === "computed"));
  const filled = observedCells.reduce((s, c) => s + (c.filled_layers ?? 0), 0);
  const verified = sum(observedCells.filter(c => c.verified));
  const single = cells.filter(c => (c.status === "observed" || c.status === "missing") && !c.verified).map(c => [c.x, c.y]);
  const rescan = cells.filter(c => c.status === "rescan" || c.status === "conflict").map(c => [c.x, c.y]);
  const consistent = !conflicts.length && !rescan.length && typical !== null;
  const total = consistent ? observed + computed : null;
  const status = needsView ? "needs_view" : total === null ? "conflict"
    : computed || ambiguities.length || single.length ? "estimated" : "exact";
  return { status, width, depth, faces_used: facesUsed, typical_layers: typical, cells, observed_trays: observed, computed_trays: computed,
    filled_trays: filled, visible_verified_trays: verified, visible_single_reading_trays: observed - verified, single_reading_cells: single,
    total_trays: total, fully_observed: consistent && computed === 0, faces_consistent: consistent,
    conflicts, ambiguities, rescan_cells: rescan, note: BLOCK_NOTE, rule };
}

// trusted: per face, whether its readings may verify a stack (null: all, for callers without capture provenance);
// duplicates: a face whose photo repeats an earlier face's (see duplicateViews).
// meta.captureIds: per face, the capture it came from (a copy carries the original's id, so two readings of one
// capture never verify each other); meta.quality: per face, whether the capture gate accepted it.
function buildBlock(straightCols: SpanColumn[], leftCols: SpanColumn[], rightCols: SpanColumn[], strays: Record<string, number> = {},
  trusted: Record<string, boolean> | null = null, duplicates: Record<string, string> = {},
  meta: { captureIds?: Record<string, string>; quality?: Record<string, string>; eligible?: Record<string, boolean>; rule?: Partial<RuleOptions> } = {}) {
  const trust = (face: string) => trusted === null || trusted[face] === true;
  // Which faces may set the full height H (stackingRule); without provenance (trusted null) every face may.
  const eligible = (face: string) => meta.eligible ? meta.eligible[face] === true : trust(face);
  const ruleOptions: RuleOptions = { ...RULE_DEFAULTS, ...(meta.rule ?? {}) };
  const captureOf = (face: string): string => meta.captureIds?.[face] ?? (duplicates[face] ? captureOf(duplicates[face]) : face);
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
  const cells = new Map<string, Cell>();
  for (let y = 0; y < depth; y++) for (let x = 0; x < width; x++) cells.set(`${x},${y}`, { x, y, status: "computed", layers: null, source: "faces" });
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
  // Trays seen through a gap: never a reading (usually another stack or block well behind), only a hint on the cell.
  const pastGap = new Map<string, { layers: number; scale: number; source: string }[]>();
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
    // Every reading names its capture, reader and evidence (plan Phase Q). The only reader in this release is the
    // detector walk ("rf-walk"); the rim reader was rejected (reports/rim-independent-20261101).
    const asRead = readings.map(r => ({ face: r.name, layers: r.col.layers, gap_filled: r.col.filled, doubts: r.col.doubts, trusted: trust(r.name),
      capture_id: captureOf(r.name), reader: "rf-walk", physical_stack_id: `S${cell.x}-${cell.y}`, view: r.name, count: r.col.layers,
      evidence: { gap_filled: r.col.filled, doubts: r.col.doubts }, quality: meta.quality?.[r.name] ?? "unknown",
      pipeline_version: PIPELINE_VERSION }));
    if (readings[0].col.recessed) {
      // A gap in the front row is verified only when two photos both see it.
      Object.assign(cell, { status: "missing", layers: 0, source, readings: asRead,
        verified: new Set(names.filter(trust).map(captureOf)).size > 1 });
      for (const r of readings) {
        if (cell.y === 0 && r.name !== "straight") continue;   // a side face looks along the front row past a missing corner
        if (cells.has(r.behind)) pastGap.set(r.behind, [...(pastGap.get(r.behind) ?? []),
          { layers: r.col.layers, scale: roundHalfEven(r.col.scale * 100) / 100, source: `${r.name}-recessed` }]);
        else ambiguities.push({ cell: [cell.x, cell.y], reason: `${r.name.toUpperCase()} shows trays behind a missing stack, but the faces give no room for a stack there; they are not counted`,
          past_gap_layers: r.col.layers });
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
    // Verified by two different captures: readings of one photo or its copies never count twice.
    const clean = readings.filter(r => r.col.layers === best.layers && !r.col.filled && !r.col.doubts.length && trust(r.name))
      .map(r => captureOf(r.name));
    Object.assign(cell, { status: "observed", layers: best.layers, filled_layers: best.filled, source, readings: asRead,
      verified: new Set(clean).size > 1 });
    if (values[high] !== values[low]) ambiguities.push({ cell: [cell.x, cell.y], reason: "faces differ by one layer", ...layerFields, chosen: best.layers });
  }
  for (const key of cells.keys()) if (!seen.has(key)) cells.get(key)!.hidden = true;
  for (const [key, candidates] of pastGap) {
    const cell = cells.get(key)!;
    const layers = new Set(candidates.map(c => c.layers));
    // A cell no face counts stays hidden: the trays seen past the gap are a hint (they may be another block behind).
    if (cell.hidden && cell.status === "computed" && layers.size === 1) {
      Object.assign(cell, { past_gap_layers: candidates[0].layers, past_gap_scale: candidates[0].scale,
        past_gap_face: candidates[0].source.replace(/-recessed$/, ""), flags: ["line_of_sight_past_gap"] });
    } else if (cell.hidden) {
      Object.assign(cell, { status: "conflict", layers: null, source: candidates.map(c => c.source).join("+"), flags: ["line_of_sight_past_gap"] });
      conflicts.push({ cell: [cell.x, cell.y], reason: "faces disagree about the stack behind a missing one" });
    } else if (cell.status === "observed" && (layers.size > 1 || !layers.has(cell.layers!))) {
      ambiguities.push({ cell: [cell.x, cell.y], reason: "trays seen through a gap differ from this stack's face reading; the face reading is kept",
        past_gap_layers: [...layers], chosen: cell.layers });
    }
  }
  // Hidden stacks are the full height H by the stacking rule (0.7.0). A block with none keeps its typical face height:
  // the most common measured stack (each physical stack once), ties to the lower.
  const rule = stackingRule([...cells.values()], width, depth, sides.map(([n]) => n), eligible, ruleOptions, conflicts);
  const typical = rule.applied ? rule.height : mode([...cells.values()].filter(measuredCell).map(c => c.layers!));
  assumeHidden([...cells.values()], width, depth, typical);
  for (const face of FACE_ORDER.filter(f => duplicates[f])) ambiguities.push({ face,
    reason: `${face.toUpperCase()}: the same capture as ${duplicates[face].toUpperCase()} (a copy or re-encode, not a second photo); it adds no reading` });
  for (const face of FACE_ORDER.filter(f => strays[f])) ambiguities.push({ face,
    reason: `${face.toUpperCase()}: ${strays[face]} group(s) of one or two boxes beside the counted stacks (a short stack, a loose tray or a stray box) are not counted` });
  return blockResult(width, depth, facesUsed, typical, [...cells.values()], conflicts, ambiguities, false, rule);
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

// ---- Side-face check. The block model trusts that LEFT and RIGHT show the side faces; a front photo sent again
// as a side builds a false depth (MUTAA L-100, 2026-10-31: three front views of a 5 x 1 block gave 500
// "estimated" for 100 trays). Camera captures carry the phone heading (one session per scan, kept across retakes):
// a side must be turned from the front, and LEFT and RIGHT must face opposite ways. Stack counts alone cannot tell
// a side face from the front photographed again (a square block of even height looks the same, and a re-shot framed
// one stack tighter or with one stack misread slips past any count match), so a block more than one stack deep gets
// no total unless the heading confirms every side face it was built from. Gallery photos and older apps therefore
// get totals only for one-deep blocks; refusing is safer than a fivefold total.
// 0.5.1: the heading alone no longer settles a side that repeats the front. Replayed as camera captures with a
// quarter turn each way, the L-100 front photos still gave 500 "estimated" (and a neighbouring block's sides gave 240
// for 80): a heading says the phone turned, not that the photo shows another face (an oblique re-shot of the front,
// a neighbouring block, a sensor glitch). When a turned side shows the front's stacks again, its depth must come from
// a guided-camera CORNER photo that sees that side and the front at once, read as the same width and depth. Without
// one the total, depth and grid are withheld and a CORNER photo is asked for. Not witnesses on their own: a declaration
// (a habitual "5 x 5" would turn the same 500 into a released total; since 0.6.0 it is needed as well, see DEPTH_PROOF)
// and ELEVATED taps (the app sizes the tap grid from the declaration, and an empty grid reads nothing). A side let
// through by a CORNER photo still never verifies a stack: it may yet be the front again, with the depth right.
const SIDE_MIN_TURN_DEG = 45;      // a side face is about 90 degrees from the front
const SIDES_MIN_APART_DEG = 90;    // LEFT and RIGHT face opposite ways, about 180 degrees apart
const SIDE_MAX_TURN_DEG = 135;     // past this the camera faces the back face, not a side
// 0.6.0 (Plan 4 Decision 1, corrected): rows standing against a block look the same in every photo, a CORNER photo
// included (cornerReading counts the columns on each side of the nearest stack, so it sees the same rows the side photo
// saw: S25 with a CORNER photo read 5 x 3 and gave estimated 300 for 100). A turned side more than one stack deep
// therefore gets its depth from the operator's declared block size (X x Y); a side that repeats the front needs the
// CORNER photo as well. Otherwise the side is depth_unproven and the block is withheld, with provisional figures.
// "corner_or_declaration" would let an agreeing CORNER photo alone prove a depth again (not the default).
const DEPTH_PROOF = "declaration" as "declaration" | "corner_or_declaration";
type SideStatus = "turned" | "turned_repeats_front" | "faces_back" | "same_way_as_straight" | "same_way_as_other_side" | "repeats_front"
  | "unconfirmed" | "unverified" | "depth_unproven";
type SideVerdict = { status: SideStatus; turn_deg?: number; direction_ok?: boolean; reason?: string; repeats_front?: boolean;
  depth_witness?: "corner" | "declaration" | "corner_and_declaration"; corner_settles?: boolean; retake?: "corner" | "side" | "declaration" };
/** What the CORNER photo read: width and depth (null when unreadable), the side face it sees, and why it cannot be used. */
type CornerWitness = { x: number | null; y: number | null; side: "left" | "right" | null; problem: string | null };
// The side to retake first: wrong-way photos before the ones that only need a CORNER photo.
const SIDE_FAULT_ORDER: SideStatus[] = ["same_way_as_straight", "faces_back", "same_way_as_other_side", "repeats_front", "unconfirmed",
  "turned_repeats_front", "depth_unproven"];
const wrap180 = (deg: number) => ((deg + 180) % 360 + 360) % 360 - 180;

/** A turned side that could be the front again (or the front plus stacks behind it): the same heights (within one
 * layer) in the same or reversed order, allowing one stack more or fewer at an edge (a re-shot framed wider or
 * tighter) and, from four stacks up, one misread height. A square block of even height matches too: that is the
 * case a heading cannot settle. Behind a one-stack front any deeper side matches: the stack's own side and the
 * stacks standing behind it look alike. */
function mirrorsFront(side: number[], front: number[]) {
  if (front.length === 1) return side.length >= 2;
  const [short, long] = side.length <= front.length ? [side, front] : [front, side];
  if (short.length < 2 || long.length - short.length > 1) return false;
  const fits = (run: number[]) => {
    for (let off = 0; off <= long.length - run.length; off++) {
      const misses = run.filter((v, i) => Math.abs(v - long[off + i]) > 1).length;
      if (misses === 0 || (misses === 1 && run.length >= 4)) return true;
    }
    return false;
  };
  return fits(short) || fits([...short].reverse());
}

// declared: the operator's block size (x wide, y deep) when a declaration was sent; it proves the depth of a turned side
// only when it names this front's width and this side's depth.
function sideCheck(columns: Record<string, SpanColumn[]>, headings: Record<string, ViewHeading> = {}, corner: CornerWitness | null = null,
  declared: { x: number; y: number } | null = null) {
  const layers = (cols: SpanColumn[]) => [...cols].sort((a, b) => a.x_min - b.x_min).map(c => c.walk_count ?? c.span_count);
  const close = (a: number[], b: number[]) => a.length === b.length && a.every((v, i) => Math.abs(v - b[i]) <= 1);
  const front = layers(columns.straight ?? []);
  const depth = Math.max((columns.left ?? []).length, (columns.right ?? []).length);   // as buildBlock takes it
  const straight = headings.straight ?? null;
  const repeats: Record<string, boolean> = Object.fromEntries(["left", "right"].map(side => [side, mirrorsFront(layers(columns[side] ?? []), front)]));
  // A CORNER photo settles a repeating side when it reads this block's width and that side's depth, and it sees that
  // side, or sees the other side and that side repeats the front too with the same depth (an even block: the photo
  // that is not seen then adds no depth of its own).
  const settles = (side: string, n: number) => corner !== null && corner.problem === null && corner.side !== null
    && corner.x === front.length && corner.y === n
    && (corner.side === side || (repeats[corner.side] && (columns[corner.side] ?? []).length === n));
  const unsettled = (side: string, n: number): [string, "corner" | "side"] => {
    const name = side.toUpperCase(), ask = `add a CORNER photo from the front-${side} corner, with the corner stack and both faces in frame, to count the depth`;
    const what = front.length === 1 ? "STRAIGHT shows one stack, so this side cannot be told from stacks standing behind it"
      : "this photo shows the same stacks with the same heights as STRAIGHT, so it may be the front face again";
    if (corner === null) return [`${name}: ${what}; ${ask}`, "corner"];
    if (corner.problem !== null) return [`${name}: ${what}, and ${corner.problem}; retake the CORNER photo`, "corner"];
    if (corner.side !== null && corner.x === n && corner.y === front.length && corner.x !== corner.y)
      return [`${name}: ${what}, and the CORNER photo reads ${corner.x} wide and ${corner.y} deep, the other way round; was it taken from the other front corner?`, "corner"];
    if (corner.x !== front.length || corner.y !== n)
      return [`${name}: the CORNER photo shows ${corner.x} stacks wide and ${corner.y} deep, but this side shows ${n} stacks and STRAIGHT ${front.length}: it is not the ${side} side face; walk around the corner and retake it`, "side"];
    return [`${name}: ${what}, and the CORNER photo sees the ${corner.side} side, not this one; ${ask}`, "corner"];
  };
  const cornerReads = (n: number) => corner !== null && corner.problem === null && corner.side !== null && corner.x === front.length && corner.y === n;
  const unproven = (side: string, n: number, settled: boolean) =>
    `${side.toUpperCase()}: ${settled ? `the CORNER photo shows this is a side face ${n} deep` : `the block reads ${n} deep here`}, but rows standing against a block look the same in every photo; declare the block size (X x Y) before the scan to say where the block ends`
    + (declared ? `; the declaration says ${declared.x} x ${declared.y}` : "");
  // A turned side: its depth needs proof only when this side sets it (the other side has no stacks or the same depth). A
  // side of another depth is buildBlock's "depth differs" conflict; the photos cannot tell which side is wrong, so the
  // rescan names no side (STRAIGHT with the general reason, as in 0.5.1).
  const turnedSide = (side: string, n: number, base: { turn_deg: number; direction_ok: boolean }): SideVerdict => {
    const other = (columns[side === "left" ? "right" : "left"] ?? []).length;
    const settled = repeats[side] && settles(side, n);
    if (repeats[side] && !settled) {
      const [reason, retake] = unsettled(side, n);
      return { status: "turned_repeats_front", ...base, repeats_front: true, reason, retake };
    }
    const seen: Partial<SideVerdict> = repeats[side] ? { repeats_front: true, corner_settles: true } : {};
    const cornerOnly = DEPTH_PROOF === "corner_or_declaration" && (settled || cornerReads(n));
    if (n <= 1 || (other !== 0 && other !== n)) return { status: "turned", ...base, ...seen, ...(settled && cornerOnly ? { depth_witness: "corner" as const } : {}) };
    if (declared !== null && declared.x === front.length && declared.y === n)
      return { status: "turned", ...base, ...seen, depth_witness: settled ? "corner_and_declaration" : "declaration" };
    if (cornerOnly) return { status: "turned", ...base, ...seen, depth_witness: "corner" };
    return { status: "depth_unproven", ...base, ...seen, reason: unproven(side, n, settled), retake: "declaration" };
  };
  const verdicts: Record<string, SideVerdict> = {};
  for (const side of ["left", "right"]) {
    const name = side.toUpperCase();
    const heading = headings[side] ?? null;
    if (straight && heading && heading.yaw_session === straight.yaw_session) {
      const turn = Math.round(wrap180(heading.yaw_deg - straight.yaw_deg));
      // Facing the left side face is a right turn from the front (negative yaw), the right side face a left turn.
      // Recorded, not enforced, until a phone walk-around confirms the sign; a wrong sign would refuse every scan.
      const direction_ok = side === "left" ? turn < 0 : turn > 0;
      const n = (columns[side] ?? []).length;
      verdicts[side] = Math.abs(turn) < SIDE_MIN_TURN_DEG ? { status: "same_way_as_straight", turn_deg: turn, direction_ok,
          reason: `${name}: taken facing the same way as STRAIGHT (phone turned only ${Math.abs(turn)} degrees); walk around the corner and photograph the ${side} side face` }
        : Math.abs(turn) > SIDE_MAX_TURN_DEG ? { status: "faces_back", turn_deg: turn, direction_ok,
          reason: `${name}: taken facing the back of the block (phone turned ${Math.abs(turn)} degrees from STRAIGHT); photograph the ${side} side face, about a quarter turn from the front` }
        : turnedSide(side, n, { turn_deg: turn, direction_ok });
      continue;
    }
    const cols = layers(columns[side] ?? []);
    if (front.length >= 2 && (close(cols, front) || close([...cols].reverse(), front))) {
      verdicts[side] = { status: "repeats_front", reason: `${name}: shows the same ${front.length} stacks with the same heights as STRAIGHT, so it looks like the front face again; photograph the ${side} side face with the camera after walking around the corner` };
    } else if (cols.length && depth > 1) {
      verdicts[side] = { status: "unconfirmed", reason: `${name}: not confirmed as a side face (no phone heading from the camera session that took STRAIGHT), and this block is ${depth} stacks deep, so its hidden stacks cannot be computed; scan it with the camera, walking around the block` };
    } else {
      verdicts[side] = { status: "unverified" };
    }
  }
  // LEFT and RIGHT from one capture screen are compared even when the front came from another one (a retake). A side
  // held back only for repeating the front still faced the way its heading says, so it is compared too.
  const left = headings.left ?? null, right = headings.right ?? null;
  const headingOk = (v: SideVerdict) => !v.reason || v.status === "turned_repeats_front" || v.status === "depth_unproven";
  if (left && right && left.yaw_session === right.yaw_session && headingOk(verdicts.left) && headingOk(verdicts.right)) {
    const apart = Math.round(Math.abs(wrap180(left.yaw_deg - right.yaw_deg)));
    if (apart < SIDES_MIN_APART_DEG) verdicts.right = { status: "same_way_as_other_side", turn_deg: verdicts.right.turn_deg,
      reason: `RIGHT: taken facing the same way as LEFT (${apart} degrees apart), so both show one side; photograph the right side face` };
  }
  return verdicts;
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

// Two views whose boxes overlap almost exactly, in frame-relative coordinates, are one capture sent twice: a copy or a
// re-encode has another sha256 but the same evidence. Measured 2026-11-01 on saved detections: re-encodes of one photo
// scored 0.944-0.995 and the same photo or near-identical bursts 0.952-0.976; genuinely different captures of one
// block scored 0-0.52. Score: the median best IoU of each box in the other view, taken both ways, the lower one.
const DUPLICATE_VIEW_SCORE = 0.8;
function boxOverlapScore(a: ViewInference, b: ViewInference) {
  const frameBoxes = (v: ViewInference) => {
    const d = (v.detections ?? []).filter(p => [p.x, p.y, p.width, p.height].every(n => Number.isFinite(n)) && p.width! > 0 && p.height! > 0);
    const w = v.image?.width || Math.max(1, ...d.map(p => p.x! + p.width! / 2));
    const h = v.image?.height || Math.max(1, ...d.map(p => p.y! + p.height! / 2));
    return d.map(p => ({ x0: (p.x! - p.width! / 2) / w, x1: (p.x! + p.width! / 2) / w, y0: (p.y! - p.height! / 2) / h, y1: (p.y! + p.height! / 2) / h }));
  };
  type R = { x0: number; x1: number; y0: number; y1: number };
  const iou = (p: R, q: R) => {
    const i = Math.max(0, Math.min(p.x1, q.x1) - Math.max(p.x0, q.x0)) * Math.max(0, Math.min(p.y1, q.y1) - Math.max(p.y0, q.y0));
    return i / ((p.x1 - p.x0) * (p.y1 - p.y0) + (q.x1 - q.x0) * (q.y1 - q.y0) - i);
  };
  const pa = frameBoxes(a), pb = frameBoxes(b);
  if (!pa.length || !pb.length) return 0;
  const oneWay = (p: R[], q: R[]) => median(p.map(x => Math.max(...q.map(y => iou(x, y)))));
  return Math.min(oneWay(pa, pb), oneWay(pb, pa));
}
function duplicateViews(results: Record<string, ViewInference>) {
  const order = ["straight", "left", "right"];
  const duplicates: Record<string, string> = {};
  order.forEach((view, i) => {
    const earlier = order.slice(0, i).find(e => !duplicates[e] && boxOverlapScore(results[e], results[view]) >= DUPLICATE_VIEW_SCORE);
    if (earlier) duplicates[view] = earlier;
  });
  return duplicates;
}

// ---- Block grid, operator declaration and extra views (0.5.0; docs/GRID_CONTRACT_0.5.0.md).
// The block is reconstructed as an X/Y/Z grid of physical stacks: a shared corner is one stack seen by two faces, never
// two stacks. Inventory from photos, from the operator's declaration, from the elevated view and computed from the
// typical height stays separate in every cell. Occupancy is not measured by any validated reader in this release
// (Phase P was disabled, reports/cross-stack-20261101), so a layer's occupancy is known only when declared.
type BlockDeclaration = { x: number; y: number; interior: "full" | "partial" | "unknown"; missing_cells: [number, number][];
  partial_stacks: { x: number; y: number; layers: number | null }[]; cover_trays: "yes" | "no" | "unknown";
  occupancy: "egg_filled" | "unknown"; reference_height: number | null; operator: string | null; declared_at: string | null };
type TapState = "present" | "missing" | "step_up" | "step_down" | "unsure";
type TopViewTaps = { x: number; y: number; cells: { x: number; y: number; state: TapState }[] };
// 0.6.0: every cell names its evidence class; a hidden cell carries its assumed height, the neighbours it came from and
// the range they span (docs/GRID_CONTRACT_0.6.0.md). Every 0.5.0 field keeps its meaning.
type EvidenceClass = "measured" | "seen_empty" | "top_present" | "top_step" | "top_missing" | "declared_missing" | "assumed" | "conflict";
type GridCell = { physical_stack_id: string; x: number; y: number; stack_present: boolean | null; z_layers: number | null;
  filled_layers: number | null; partial_layers: number | null; empty_cover_layers: number | null; unknown_layers: number | null;
  observed_views: string[]; measurement_sources: string[]; status: string; uncertainties: string[];
  readings: Record<string, unknown>[]; pair_type: string | null;
  evidence_class: EvidenceClass; hidden: boolean; assumed_layers: number | null; assumed_range: [number, number | null] | null;
  assumed_from: string | null; neighbours: { x: number; y: number; layers: number }[]; top_tap: TapState | null; flags: string[];
  past_gap_layers: number | null; past_gap_scale: number | null };
type DepthBasis = "one_deep" | "declaration" | "corner_and_declaration" | "corner";
const MAX_DECLARATION_CHARS = 4000;
const MAX_TAPS_CHARS = 8000;
const MAX_GRID_SIDE = 40;

function parseJsonField(form: FormData, name: string, limit: number): Record<string, unknown> | null {
  const raw = form.get(name);
  if (typeof raw !== "string" || !raw || raw.length > limit) return null;
  try {
    const value = JSON.parse(raw) as unknown;
    return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
  } catch {
    return null;
  }
}
const gridInt = (v: unknown, lo: number, hi: number) => Number.isInteger(v) && (v as number) >= lo && (v as number) <= hi ? v as number : null;

/** The operator's blind declaration; malformed input is no declaration (never a refusal). */
function readDeclaration(form: FormData): BlockDeclaration | null {
  const d = parseJsonField(form, "block_declaration", MAX_DECLARATION_CHARS);
  if (!d) return null;
  const x = gridInt(d.x, 1, MAX_GRID_SIDE), y = gridInt(d.y, 1, MAX_GRID_SIDE);
  if (x === null || y === null) return null;
  const cell = (c: unknown) => Array.isArray(c) && c.length === 2 && gridInt(c[0], 0, x - 1) !== null && gridInt(c[1], 0, y - 1) !== null;
  const stacks = (Array.isArray(d.partial_stacks) ? d.partial_stacks : []).map(p => p as Record<string, unknown>)
    .filter(p => p && gridInt(p.x, 0, x - 1) !== null && gridInt(p.y, 0, y - 1) !== null)
    .map(p => ({ x: p.x as number, y: p.y as number, layers: gridInt(p.layers, 0, 200) })).slice(0, x * y);
  // A partial stack of 0 trays is a missing stack; a cell listed twice as missing is one missing stack.
  const missing = [...(Array.isArray(d.missing_cells) ? d.missing_cells : []).filter(cell) as [number, number][],
    ...stacks.filter(p => p.layers === 0).map(p => [p.x, p.y] as [number, number])]
    .filter(([cx, cy], i, all) => all.findIndex(([ox, oy]) => ox === cx && oy === cy) === i).slice(0, x * y);
  const partial = stacks.filter(p => p.layers !== 0);
  const pick = <T extends string>(v: unknown, allowed: readonly T[], fallback: T) => allowed.includes(v as T) ? v as T : fallback;
  const text = (v: unknown, max: number) => typeof v === "string" ? v.replace(UNSAFE_TEXT, " ").trim().slice(0, max) || null : null;
  // A reference height counts only when the operator says it was measured; it can only demote a stack, never add one.
  const reference = d.reference_height_measured === true ? gridInt(d.reference_height, 1, 200) : null;
  return { x, y, interior: pick(d.interior, ["full", "partial", "unknown"] as const, "unknown"), missing_cells: missing,
    partial_stacks: partial, cover_trays: pick(d.cover_trays, ["yes", "no", "unknown"] as const, "unknown"),
    occupancy: pick(d.occupancy, ["egg_filled", "unknown"] as const, "unknown"), reference_height: reference,
    operator: text(d.operator, 80), declared_at: text(d.declared_at, 40) };
}

/** The operator's reading of the elevated photo: a tap per grid position. */
function readTopViewTaps(form: FormData): TopViewTaps | null {
  const t = parseJsonField(form, "elevated_taps", MAX_TAPS_CHARS);
  if (!t) return null;
  const x = gridInt(t.x, 1, MAX_GRID_SIDE), y = gridInt(t.y, 1, MAX_GRID_SIDE);
  if (x === null || y === null) return null;
  const states = ["present", "missing", "step_up", "step_down", "unsure"] as const;
  const cells = (Array.isArray(t.cells) ? t.cells : []).map(c => c as Record<string, unknown>)
    .filter(c => c && gridInt(c.x, 0, x - 1) !== null && gridInt(c.y, 0, y - 1) !== null && states.includes(c.state as typeof states[number]))
    .map(c => ({ x: c.x as number, y: c.y as number, state: c.state as typeof states[number] })).slice(0, x * y);
  return { x, y, cells };
}

/** Width and depth from one CORNER photo: the corner stack is the nearest, so it has the largest layer pitch; the
 * columns on each side of it are the two faces (the corner counted in both). Columns only; no heights. */
function cornerReading(columns: SpanColumn[], side: string | null) {
  const ordered = [...columns].sort((a, b) => a.x_min - b.x_min);
  if (ordered.length < 2) return { side, columns: ordered.length, x: null, y: null, corner_column: null, note: "fewer than two stacks in the CORNER photo" };
  const corner = ordered.reduce((best, c, i) => c.pitch_px > ordered[best].pitch_px ? i : best, 0);
  const leftFace = corner + 1, rightFace = ordered.length - corner;
  const [x, y] = side === "front_left" ? [rightFace, leftFace] : side === "front_right" ? [leftFace, rightFace] : [null, null];
  return { side, columns: ordered.length, x, y, corner_column: corner + 1,
    note: x === null ? "corner side not given; width and depth cannot be told apart" : null };
}

type GridInputs = { declaration: BlockDeclaration | null; topView: TopViewTaps | null; corner: ReturnType<typeof cornerReading> | null;
  depthBasis?: DepthBasis | null; ruleOptions?: Partial<RuleOptions> };
const HIDDEN_NOTE = "hidden: full by the stacking rule, not seen; if the rule was broken here, this stack can be missing or shorter";

/** The physical grid, inventory and final status from the photo block plus the declaration and extra views. */
// 0.6.0: a top-view tap changes only presence (a hole is 0) and a step (the lower bound); it never counts. The declaration
// is applied after the taps and never overrides one. Nothing here raises a status: deep blocks top out at estimated,
// and confirmed is never returned (Decision 2a; a 0.5 declaration or flush top used to confirm).
// depthBasis: what the depth rests on (modelDiagnostics passes it from the side check); one_deep when Y = 1 by default.
function assembleGrid(block: ReturnType<typeof blockResult>, inputs: GridInputs) {
  const { declaration, topView, corner } = inputs;
  const conflicts: Record<string, unknown>[] = [];
  const X = block.width, Y = block.depth;
  const depthBasis: DepthBasis | null = inputs.depthBasis !== undefined ? inputs.depthBasis : Y === 1 ? "one_deep" : null;
  const empty = { grid: [] as GridCell[][], conflicts, total: block.total_trays, status: block.status, confirmed_basis: [] as string[],
    declaration_agrees: null as boolean | null, corner_agrees: null as boolean | null, top_view: null as Record<string, unknown> | null,
    suggested_views: [] as string[], depth_basis: depthBasis, cells: block.cells, computed_trays: block.computed_trays as number | null,
    rule: null as RuleSummary | null };
  if (!X || !Y || !block.cells.length) return empty;
  // The stacking rule as buildBlock applied it; a block built by blockResult alone (test fixtures) takes its typical
  // height as H, with no basis recorded.
  const ruleOptions: RuleOptions = { ...RULE_DEFAULTS, ...(block.rule?.options ?? {}), ...(inputs.ruleOptions ?? {}) };
  const hiddenCount = block.cells.filter(c => c.hidden ?? c.status === "computed").length;
  const rule: RuleSummary = block.rule ? { ...block.rule, exceptions: [], notes: [...block.rule.notes] } : (() => {
    const r: RuleSummary = { ...emptyRule(ruleOptions, hiddenCount), exceptions: [] };
    if (r.applied && block.typical_layers !== null) Object.assign(r, { height: block.typical_layers, full_heights: [block.typical_layers],
      range_heights: ruleRange(block.typical_layers, null, ruleOptions.coverRange) });
    return r;
  })();
  const ruled = rule.applied && rule.height !== null;
  const [ruleLo, ruleHi] = rule.range_heights ?? [null, null];
  const exception = (g: GridCell, kind: string) => {
    if (!ruled || !g.hidden) return;
    if (!g.flags.includes("rule_exception")) g.flags.push("rule_exception");
    rule.exceptions = [...(rule.exceptions ?? []).filter(e => e.x !== g.x || e.y !== g.y), { x: g.x, y: g.y, kind, layers: g.z_layers }];
  };
  const ruleConflict = (check: string, conflict: Record<string, unknown>) => conflicts.push({ ...conflict, check });
  // A block built by blockResult alone (test fixtures, older callers) has no assumed heights yet; assumeHidden is idempotent.
  const source = block.cells.map(c => ({ ...c, flags: [...(c.flags ?? [])] }));
  if (source.some(c => c.status === "computed" && !c.assumed_from)) assumeHidden(source, X, Y, block.typical_layers);
  const occupancyDeclared = declaration?.occupancy === "egg_filled";
  const grid: GridCell[][] = [];
  for (let y = 0; y < Y; y++) {
    const row: GridCell[] = [];
    for (let x = 0; x < X; x++) {
      const c = source.find(k => k.x === x && k.y === y)!;
      const readings = (c.readings ?? []) as unknown as Record<string, unknown>[];
      const hidden = c.hidden ?? c.status === "computed";
      const status = c.status === "observed" ? (c.verified ? "verified" : "observed") : c.status;
      const evidence: EvidenceClass = c.status === "observed" && !hidden ? "measured" : c.status === "missing" ? "seen_empty"
        : c.status === "computed" ? "assumed" : "conflict";
      const flags = [...(c.flags ?? [])];
      const uncertainties: string[] = [];
      for (const r of readings) {
        const doubts = ((r.evidence as Record<string, unknown> | undefined)?.doubts ?? []) as string[];
        for (const d of doubts) uncertainties.push(`${String(r.view).toUpperCase()}: ${d}`);
        if (((r.evidence as Record<string, unknown> | undefined)?.gap_filled as number) > 0) uncertainties.push(`${String(r.view).toUpperCase()}: gap-filled layer`);
      }
      if (c.status === "observed" && !c.verified) { uncertainties.push("read by one capture only"); flags.push("single_reading"); }
      if (c.status === "computed") uncertainties.push(HIDDEN_NOTE);
      if (c.past_gap_layers !== null && c.past_gap_layers !== undefined)
        uncertainties.push(`${c.past_gap_layers} trays seen through the gap in front are not counted: they may be this stack or another block behind`);
      const assumed = evidence === "assumed";
      row.push({ physical_stack_id: `S${x}-${y}`, x, y,
        stack_present: c.status === "missing" ? false : c.status === "observed" ? true : null,
        z_layers: c.status === "missing" ? 0 : c.layers, filled_layers: null, partial_layers: null, empty_cover_layers: null,
        unknown_layers: null, observed_views: [...new Set(readings.map(r => String(r.view)))],
        measurement_sources: hidden ? ["computed"] : ["observed"], status, uncertainties, readings,
        pair_type: c.verified ? "cross_photo" : null,
        evidence_class: evidence, hidden, assumed_layers: assumed ? c.assumed_layers ?? null : null,
        assumed_range: assumed && c.assumed_range ? [c.assumed_range[0], c.assumed_range[1]] : null,
        assumed_from: assumed ? c.assumed_from ?? null : null, neighbours: hidden ? c.neighbours ?? [] : [], top_tap: null, flags,
        past_gap_layers: c.past_gap_layers ?? null, past_gap_scale: c.past_gap_scale ?? null });
    }
    grid.push(row);
  }
  const measuredHeights = grid.flat().filter(g => g.evidence_class === "measured" && (g.z_layers ?? 0) > 0).map(g => g.z_layers!);
  // The lowest and highest neighbour (the block's measured faces when it has none): the bounds a step tap moves.
  const spread = (g: GridCell): [number, number] | null => {
    const v = g.neighbours.length ? g.neighbours.map(n => n.layers) : measuredHeights;
    return v.length ? [Math.min(...v), Math.max(...v)] : null;
  };
  const note = (g: GridCell, text: string) => [text, ...g.uncertainties.filter(u => u !== HIDDEN_NOTE)];
  // The elevated view: the operator's taps are the only look at the interior. Presence, holes and steps only.
  let topSummary: Record<string, unknown> | null = null;
  if (topView) {
    const agrees = topView.x === X && topView.y === Y;
    if (!agrees) conflicts.push({ reason: `ELEVATED: the tapped grid is ${topView.x} x ${topView.y}, the faces measure ${X} x ${Y}` });
    // One tap per cell: a repeated tap is dropped; two different taps on one cell disagree.
    const taps = new Map<string, TapState | null>();
    for (const t of agrees ? topView.cells : []) {
      const key = `${t.x},${t.y}`, earlier = taps.get(key);
      if (earlier === undefined) taps.set(key, t.state);
      else if (earlier !== null && earlier !== t.state) {
        conflicts.push({ cell: [t.x, t.y], reason: `ELEVATED: the stack is tapped both ${earlier} and ${t.state}` });
        taps.set(key, null);
      }
    }
    const count: Record<TapState, number> = { present: 0, missing: 0, step_up: 0, step_down: 0, unsure: 0 };
    for (const [key, state] of taps) {
      const [x, y] = key.split(",").map(Number);
      const g = grid[y][x];
      if (state === null) {
        if (g.hidden) Object.assign(g, { evidence_class: "conflict", status: "conflict", z_layers: null, assumed_layers: null,
          uncertainties: note(g, "ELEVATED taps on this stack disagree") });
        continue;
      }
      count[state]++;
      g.top_tap = state;
      // A tap never sets or changes a face count.
      if (!g.hidden) {
        if (state === "missing" && g.evidence_class === "measured") conflicts.push({ cell: [x, y], reason: "ELEVATED shows no stack where a face shows one" });
        else if (g.evidence_class === "seen_empty" && (state === "present" || state === "step_up" || state === "step_down"))
          conflicts.push({ cell: [x, y], reason: "ELEVATED shows a stack where a face shows a gap" });
        else if (g.evidence_class === "measured" && (state === "step_up" || state === "step_down"))
          g.uncertainties.push(`ELEVATED: ${state === "step_up" ? "higher" : "lower"} than its neighbours (a note; the face count stands)`);
        continue;
      }
      if (g.evidence_class === "conflict") continue;
      const nb = spread(g);
      if (state === "missing") {
        Object.assign(g, { stack_present: false, z_layers: 0, evidence_class: "top_missing", status: "top_view",
          measurement_sources: ["top_view"], assumed_layers: null, assumed_range: null, assumed_from: null,
          uncertainties: note(g, "no stack seen from above") });
        exception(g, "top_missing");
      }
      else if (state === "present") Object.assign(g, { stack_present: true, evidence_class: "top_present", status: "top_view",
        measurement_sources: ["top_view", "computed"],
        assumed_range: g.assumed_range ? [Math.max(1, g.assumed_range[0]), g.assumed_range[1]] : null,
        uncertainties: note(g, ruled ? "seen from above: presence only; height full by the stacking rule" : "seen from above: presence only; height assumed") });
      else if (state === "step_up") {
        // Taller than its neighbours: at least one tray more than the lowest, how many more is not seen.
        const height = g.assumed_layers === null ? null : g.assumed_layers + 1;
        Object.assign(g, { stack_present: true, evidence_class: "top_step", status: "top_view", measurement_sources: ["top_view", "computed"],
          assumed_layers: height, z_layers: height, assumed_range: nb ? [nb[0] + 1, null] : null, flags: [...g.flags, "step_up_count_unknown"],
          uncertainties: note(g, "taller than its neighbours from above: height assumed one tray over them; how many more is not seen") });
        // Under the stacking rule a hidden stack taller than its neighbours means the full height may be too low.
        if (ruled) ruleConflict("inside_step_up", { cell: [x, y], reason: "ELEVATED: a hidden stack is taller than its neighbours from above, " +
          "so the block's full height read on the faces may be too low; the stacking rule cannot set the hidden stacks" });
      } else if (state === "step_down") Object.assign(g, { stack_present: true, evidence_class: "top_step", status: "unknown",
        measurement_sources: ["top_view"], assumed_layers: null, z_layers: null, assumed_range: nb ? [1, nb[1]] : null,
        flags: [...g.flags, "step_down_count_unknown"], uncertainties: note(g, "lower than its neighbours from above; height not measured") });
      else g.flags.push("top_unsure");
    }
    topSummary = { cells_present: count.present, cells_missing: count.missing, steps: count.step_up + count.step_down,
      steps_up: count.step_up, steps_down: count.step_down, cells_unsure: count.unsure, agrees };
  }
  // The blind declaration: a separate evidence source, compared with every measured face and every tap.
  let declarationAgrees: boolean | null = null;
  if (declaration) {
    declarationAgrees = true;
    if (declaration.x !== X) { declarationAgrees = false; conflicts.push({ reason: `declared ${declaration.x} stacks wide, STRAIGHT shows ${X}` }); }
    if (declaration.y !== Y) { declarationAgrees = false; conflicts.push({ reason: `declared ${declaration.y} stacks deep, the side faces show ${Y}` }); }
    if (declarationAgrees) {
      const declaredMissing = (g: GridCell) => declaration.missing_cells.some(([x, y]) => x === g.x && y === g.y);
      const declaredPartial = (g: GridCell) => declaration.partial_stacks.some(p => p.x === g.x && p.y === g.y);
      const stepped = (g: GridCell) => g.top_tap === "step_up" || g.top_tap === "step_down";
      for (const [x, y] of declaration.missing_cells) {
        const g = grid[y][x];
        if (g.evidence_class === "measured" && (g.z_layers ?? 0) > 0) {
          declarationAgrees = false;
          conflicts.push({ cell: [x, y], reason: "declared missing, but a face shows a stack there" });
        } else if (!g.hidden || g.evidence_class === "conflict") continue;
        else if (g.top_tap === "present" || stepped(g)) conflicts.push({ cell: [x, y], reason: "declared missing, but ELEVATED shows a stack there" });
        else if (g.evidence_class === "top_missing") g.measurement_sources = [...g.measurement_sources, "declared"];
        else {
          Object.assign(g, { stack_present: false, z_layers: 0, evidence_class: "declared_missing", status: "declared",
            measurement_sources: ["declared"], assumed_layers: null, assumed_range: null, assumed_from: null, uncertainties: note(g, "declared missing") });
          exception(g, "declared_missing");
        }
      }
      // One declared height per stack: a repeated entry is dropped; two different heights on one stack disagree.
      const partials = new Map<string, BlockDeclaration["partial_stacks"][number] | null>();
      for (const p of declaration.partial_stacks) {
        const key = `${p.x},${p.y}`, earlier = partials.get(key);
        if (earlier === undefined) partials.set(key, p);
        else if (earlier !== null && earlier.layers !== p.layers) {
          conflicts.push({ cell: [p.x, p.y], reason: `declared two partial heights for one stack (${earlier.layers ?? "not given"} and ${p.layers ?? "not given"})` });
          partials.set(key, null);
          const g = grid[p.y][p.x];
          if (g.hidden && g.evidence_class !== "conflict") Object.assign(g, { evidence_class: "conflict", status: "conflict", z_layers: null,
            assumed_layers: null, assumed_range: null, uncertainties: note(g, "the declared heights of this stack disagree") });
        }
      }
      for (const p of [...partials.values()]) {
        if (p === null) continue;
        const g = grid[p.y][p.x];
        if (!g.hidden) {
          // A face that shows a gap disagrees with any declared stack, with or without a height.
          if (g.evidence_class === "seen_empty") {
            declarationAgrees = false;
            conflicts.push({ cell: [p.x, p.y], reason: "declared a partial stack, but a face shows a gap there" });
          } else if (p.layers !== null && g.z_layers !== null && g.z_layers !== p.layers) {
            declarationAgrees = false;
            conflicts.push({ cell: [p.x, p.y], reason: `declared ${p.layers} trays high, a face reads ${g.z_layers}` });
          }
          continue;
        }
        if (g.evidence_class === "conflict") continue;
        const nb = spread(g);
        if (g.stack_present === false) conflicts.push({ cell: [p.x, p.y], reason: g.evidence_class === "top_missing"
          ? "declared a partial stack, but ELEVATED shows no stack there" : "declared both missing and a partial stack" });
        else if (p.layers !== null && g.top_tap === "step_up" && g.assumed_range && p.layers < g.assumed_range[0])
          conflicts.push({ cell: [p.x, p.y], reason: `declared ${p.layers} trays high, but ELEVATED shows it taller than its neighbours (at least ${g.assumed_range[0]})` });
        else if (p.layers !== null && g.top_tap === "step_down" && g.assumed_range && p.layers > g.assumed_range[1]!)
          conflicts.push({ cell: [p.x, p.y], reason: `declared ${p.layers} trays high, but ELEVATED shows it lower than its neighbours (at most ${g.assumed_range[1]})` });
        else {
          // The class stays the tap's (or assumed); the height is the operator's, never a count.
          const legacy = g.evidence_class === "assumed" || g.top_tap === "step_down" ? (p.layers === null ? "unknown" : "declared") : g.status;
          Object.assign(g, { stack_present: true, z_layers: p.layers, assumed_layers: p.layers, assumed_from: "declared_partial", status: legacy,
            assumed_range: p.layers !== null ? [p.layers, p.layers] : stepped(g) ? g.assumed_range : nb ? [1, nb[1]] : null,
            measurement_sources: [...new Set([...g.measurement_sources, "declared"])],
            uncertainties: note(g, p.layers === null ? "declared partial, height not given" : "declared partial-height stack") });
          if (p.layers !== null) exception(g, "declared_partial");
        }
      }
      if (declaration.interior === "full") for (const g of grid.flat().filter(g => g.hidden && g.evidence_class !== "conflict")) {
        if (g.stack_present === false) {
          if (g.evidence_class === "top_missing" && !declaredMissing(g))
            conflicts.push({ cell: [g.x, g.y], reason: "the interior is declared full, but ELEVATED shows no stack here" });
          continue;
        }
        // Presence only: the height stays assumed and the status computed; it never resolves a cell.
        g.flags.push("declared_present");
        g.measurement_sources = [...new Set([...g.measurement_sources, "declared"])];
      }
      // Declared partly empty without naming the stacks: under the stacking rule nothing tells which hidden stack is short.
      if (declaration.interior === "partial") {
        for (const g of grid.flat().filter(g => g.hidden && g.stack_present !== false && g.evidence_class !== "conflict" && !declaredPartial(g)))
          g.uncertainties.push("the interior is declared partly empty");
        if (ruled && grid.flat().some(g => g.hidden)) ruleConflict("inside_declared_partial", { reason: "the interior is declared partly empty, " +
          "so the stacking rule cannot set the hidden stacks; declare which stacks are missing or short, with their heights" });
      }
      // A measured reference height only demotes: a visible stack below it (and not declared partial) is noted;
      // nothing is ever added to reach it.
      if (declaration.reference_height !== null) for (const g of grid.flat()) {
        if (g.measurement_sources.includes("observed") && g.z_layers !== null && g.z_layers > 0 && g.z_layers < declaration.reference_height && !declaredPartial(g))
          g.uncertainties.push(`below the declared reference height (${declaration.reference_height})`);
      }
      // A measured reference height cross-checks H (it never sets it): it must be one of the full heights.
      const ref = declaration.reference_height;
      if (ruled && ref !== null && (ref < ruleLo! || ref > ruleHi!))
        ruleConflict("reference_height_differs", { reason: `the declared measured reference height ${ref} differs from the block's full height ` +
          `${rule.height}${ruleLo !== ruleHi ? ` (${ruleLo}-${ruleHi} with or without a cover tray)` : ""} read on the faces; recount one full face stack by hand` });
      if (declaration.interior === "full") rule.affirmed_by_operator = true;
    }
  }
  // The CORNER photo: width and depth from one capture, so both faces are of one block by construction.
  let cornerAgrees: boolean | null = null;
  if (corner && corner.x !== null && corner.y !== null) {
    cornerAgrees = corner.x === X && corner.y === Y;
    if (!cornerAgrees) conflicts.push({ reason: `CORNER shows ${corner.x} stacks wide and ${corner.y} deep, the faces measure ${X} x ${Y}` });
  }
  // Occupancy: known only when declared.
  for (const g of grid.flat()) {
    if (g.z_layers === null) continue;
    if (occupancyDeclared) Object.assign(g, { filled_layers: g.z_layers, unknown_layers: 0 });
    else g.unknown_layers = g.z_layers;
    if (!occupancyDeclared && g.z_layers > 0) g.uncertainties.push("occupancy not measured");
  }
  const cells = grid.flat();
  const anyUnknown = cells.some(g => g.stack_present !== false && g.z_layers === null);
  const total = block.total_trays === null || anyUnknown ? null : cells.reduce((s, g) => s + (g.z_layers ?? 0), 0);
  let status = block.status;
  // A refused photo stays needs_view: its faces are not measurements to compare a declaration or view with.
  if (conflicts.length && status !== "needs_view") status = "conflict";
  // exact is for one-deep blocks with every stack seen: a depth over one stack rests on the declared size.
  if (status === "exact" && (depthBasis !== "one_deep" || Y > 1 || cells.some(g => g.hidden))) status = "estimated";
  // 0.7.0: an ELEVATED photo is never suggested (farm rule 5: photos from above are impractical); it stays optional.
  const suggested: string[] = [];
  // The legacy cells (app 0.5.0's manual-count screen) carry the same per-stack values the total uses.
  const legacyCells = source.map(c => {
    const g = grid[c.y]?.[c.x];
    return g && g.hidden ? { ...c, layers: g.z_layers, status: g.stack_present === false ? "missing" : c.status } : c;
  });
  const computed = cells.filter(g => g.hidden && g.stack_present !== false).reduce((s, g) => s + (g.z_layers ?? 0), 0);
  // Why the rule withholds: the first failed check, when every conflict comes from a rule check (any other conflict is
  // the generic "conflict"). Provisional figures are never a total: they stay out of total_trays and the inventory.
  const allConflicts = [...block.conflicts, ...conflicts];
  const ruleChecks = allConflicts.filter(c => c.check);
  rule.withheld_reason = rule.applied && ruleChecks.length && ruleChecks.length === allConflicts.length ? String(ruleChecks[0].check) : null;
  rule.provisional = rule.withheld_reason && status !== "needs_view" ? ruleProvisional(grid, rule, String(ruleChecks[0].reason)) : null;
  return { grid, conflicts, total: status === "conflict" || status === "needs_view" ? null : total, status, confirmed_basis: [] as string[],
    declaration_agrees: declarationAgrees, corner_agrees: cornerAgrees, top_view: topSummary, suggested_views: suggested,
    depth_basis: depthBasis, cells: legacyCells, computed_trays: computed as number | null, rule: rule.applied ? rule : null };
}

/** What a block withheld only by a rule check would hold: the face stacks as read (a stack the check set aside at its
 * reading), the operator's exceptions, and every other hidden stack at the full height (or the taller reading, or the
 * typical face height when no full height was found). Never a total. */
function ruleProvisional(grid: GridCell[][], rule: RuleSummary, reason: string) {
  const cells = grid.flat();
  const faces = cells.filter(g => !g.hidden && g.evidence_class === "measured").reduce((s, g) => s + (g.z_layers ?? 0), 0)
    + rule.kept_readings.reduce((s, r) => s + r.layers, 0);
  const hidden = cells.filter(g => g.hidden && g.stack_present !== false);
  const fixed = hidden.filter(g => g.assumed_from === "declared_partial");
  const atRule = hidden.length - fixed.length;
  const base = { kind: rule.withheld_reason, reason, counted_on_faces: faces, rule_height: rule.height, hidden_stacks_at_rule: atRule };
  if (fixed.some(g => g.z_layers === null))
    return { ...base, at_rule_height: null, at_rule_range: null, at_taller: null, at_typical_face_height: null };
  const at = (h: number) => faces + fixed.reduce((s, g) => s + g.z_layers!, 0) + atRule * h;
  const tallest = rule.taller.filter(t => !t.released).reduce((m, t) => Math.max(m, t.layers), 0);
  const measured = cells.filter(g => g.evidence_class === "measured" && (g.z_layers ?? 0) > 0).map(g => g.z_layers!);
  const typical = rule.height === null ? mode(measured) : null;
  return { ...base, at_rule_height: rule.height === null ? null : at(rule.height),
    at_rule_range: rule.range_heights ? [at(rule.range_heights[0]), at(rule.range_heights[1])] : null,
    at_taller: tallest ? { height: tallest, estimated_total: at(tallest) } : null,
    at_typical_face_height: typical === null ? null : { height: typical, estimated_total: at(typical) } };
}

type InventoryOptions = { status?: string; provisional?: Record<string, unknown> | null; withheld_reason?: string | null;
  rule?: RuleSummary | null };
const WITHHELD_NOTE: Record<string, string> = {
  conflict: "no inventory: the readings disagree (see conflicts)",
  needs_view: "no inventory: a photo is needed (see rescan)",
  depth_unproven: "no inventory: the depth over one stack is not proven; declare the block size",
  side_repeats_front: "no inventory: a side photo repeats the front; add a CORNER photo and declare the block size",
  // 0.7.0 stacking rule (stackingRule, assembleGrid).
  no_rule_height: "no inventory: no full height for the hidden stacks (two stacks read cleanly at one height on two faces, one a back corner); retake the named side",
  one_side_only: "no inventory: only one side face was photographed, so the stacking rule cannot set the hidden stacks",
  stack_taller_than_rule_height: "no inventory: a face stack reads above the block's full height; retake the named face",
  back_corner_below_rule_height: "no inventory: a back corner reads below the block's full height, against the stacking rule; retake the named side",
  inside_hint_below_rule: "no inventory: trays seen through a gap read below the block's full height; retake the named face",
  rule_height_ambiguous: "no inventory: more face stacks read one below the full height than at it; retake the named face",
  rule_height_out_of_range: "no inventory: the full height is outside the farm's normal range",
  inside_step_up: "no inventory: ELEVATED shows a hidden stack taller than its neighbours, so the full height may be too low",
  inside_declared_partial: "no inventory: the interior is declared partly empty; declare which stacks are missing or short",
  reference_height_differs: "no inventory: the declared reference height differs from the full height read on the faces",
};

/** Inventory with every source kept apart: trays counted on faces, trays assumed in hidden stacks (never counted), and
 * eligible egg trays only from declared occupancy with nothing assumed. Everything is in tray layers.
 * opts.status: the block's final status (default: estimated for a grid without conflicts). */
function gridInventory(grid: GridCell[][], declaration: BlockDeclaration | null, total: number | null, opts: InventoryOptions = {}) {
  const cells = grid.flat();
  const sum = (pick: (g: GridCell) => boolean) => cells.filter(pick).reduce((s, g) => s + (g.z_layers ?? 0), 0);
  const observed = sum(g => g.measurement_sources.includes("observed"));
  const declared = sum(g => g.status === "declared");
  const topView = sum(g => g.status === "top_view");
  const computed = sum(g => g.status === "computed");
  const occupancyDeclared = declaration?.occupancy === "egg_filled";
  const status = opts.status ?? (!cells.length ? "needs_view" : cells.some(g => g.evidence_class === "conflict") ? "conflict" : "estimated");
  // New numbers only for a block with a result (exact or estimated); released only with a total.
  const numbers = status === "exact" || status === "estimated";
  const released = numbers && total !== null;
  const measured = cells.filter(g => g.evidence_class === "measured" && (g.z_layers ?? 0) > 0);
  const hidden = cells.filter(g => g.hidden);
  const assumedCells = hidden.filter(g => g.stack_present !== false && g.evidence_class !== "conflict");
  const counted = measured.reduce((s, g) => s + g.z_layers!, 0);
  const assumed = assumedCells.some(g => g.z_layers === null) ? null : assumedCells.reduce((s, g) => s + g.z_layers!, 0);
  // The neighbours' spread over every present hidden stack: "if every hidden stack is there at its neighbours' heights".
  // Never a bound: it ignores holes (one missing hidden stack is 15-20 trays), and counted_trays is the only floor.
  const lo = assumedCells.every(g => g.assumed_range) ? assumedCells.reduce((s, g) => s + g.assumed_range![0], 0) : null;
  const hi = lo !== null && assumedCells.every(g => g.assumed_range![1] !== null) ? assumedCells.reduce((s, g) => s + g.assumed_range![1]!, 0) : null;
  const checked = hidden.filter(g => g.top_tap !== null && g.top_tap !== "unsure").length;
  const unchecked = assumedCells.filter(g => g.top_tap === null || g.top_tap === "unsure").length;
  const byClass = (k: EvidenceClass) => cells.filter(g => g.evidence_class === k).length;
  const cover = declaration?.cover_trays === "no" ? { value: 0, basis: "declared" }
    : declaration?.cover_trays === "yes" ? { value: null, basis: "declared present, not counted" } : { value: null, basis: "unknown" };
  const withheld = released ? null : opts.withheld_reason ?? (status === "conflict" ? "conflict" : numbers ? "height_unknown" : "needs_view");
  const eligibleWhyNot = !occupancyDeclared ? "occupancy is not measured; declare it to count eligible egg trays"
    : !released ? "no released total"
    : assumedCells.length ? "hidden stacks are assumed: their trays are not counted"
    : declaration?.cover_trays === "yes" ? "cover trays are declared present and are not counted apart"
    : null;
  const stacks = (n: number) => `${n} hidden stack${n === 1 ? "" : "s"}`;
  const removed = byClass("top_missing") + byClass("declared_missing");
  // 0.7.0: hidden stacks at the full height H by the stacking rule. Their range is the cover-tray range (Decision 4),
  // reported in rule_trays_range; the 0.6.0 neighbour ranges are null, so an app that prints them prints nothing false.
  const rule = opts.rule ?? null;
  const ruled = numbers && !!rule?.applied && rule.height !== null;
  const ruleCells = ruled ? assumedCells.filter(g => g.assumed_from === "stacking_rule") : [];
  const H = ruled ? rule!.height! : null;
  const [ruleLo, ruleHi] = ruled ? rule!.range_heights ?? [H!, H!] : [null, null];
  const ruleTrays = ruled ? ruleCells.length * H! : null;
  const ruleRangeTrays: [number, number] | null = ruled ? [ruleCells.length * ruleLo!, ruleCells.length * ruleHi!] : null;
  const declaredHeights = ruled ? assumedCells.filter(g => g.assumed_from === "declared_partial") : [];
  const doubtedLow = ruled ? rule!.doubted_low.reduce((s, d) => s + Math.max(0, H! - d.layers), 0) : 0;
  const ruleNote = !ruled ? "" : [`${counted} counted on faces`,
    ...(ruleCells.length ? [`${stacks(ruleCells.length)} x ${H} = ${ruleTrays} full by the stacking rule (not seen)`] : []),
    ...(declaredHeights.length ? [`${stacks(declaredHeights.length)} at the declared height`] : []),
    ...(removed ? [`${stacks(removed)} reported missing`] : []),
    ...(ruleRangeTrays && ruleRangeTrays[0] !== ruleRangeTrays[1] && ruleCells.length
      ? [`cover trays are sometimes used: the hidden stacks hold ${ruleRangeTrays[0]} to ${ruleRangeTrays[1]} tray layers`] : []),
    ...(assumed === null ? ["a hidden stack's height is unknown, so no total"] : [])].join("; ");
  const note = !numbers ? WITHHELD_NOTE[withheld ?? "needs_view"] ?? WITHHELD_NOTE.needs_view
    : ruled ? ruleNote
    : `${counted} counted on faces; ` + (assumedCells.length
      ? `${assumed ?? "an unknown number"} assumed in ${stacks(assumedCells.length)}, ${assumedCells.length - unchecked || "none"} checked from the top`
      : "nothing assumed") + (removed ? `; ${stacks(removed)} missing` : "") + (assumed === null ? "; a hidden stack's height is unknown, so no total" : "");
  return {
    physical_layers_observed: observed, physical_layers_computed: computed, physical_layers_declared: declared,
    physical_layers_top_view: topView,
    eligible_egg_trays: eligibleWhyNot === null
      ? { value: total, basis: "declared", note: "the operator declared that every counted tray holds eggs; occupancy is not measured" }
      : { value: null, basis: "unknown", note: eligibleWhyNot },
    empty_cover_layers: cover,
    unknown_occupancy_layers: occupancyDeclared ? 0 : cells.reduce((s, g) => s + (g.unknown_layers ?? 0), 0),
    unknown_cells: cells.filter(g => g.z_layers === null).length,
    unit: "tray_layers", released, withheld_reason: withheld, provisional: opts.provisional ?? null,
    counted_trays: numbers ? counted : null, counted_stacks: numbers ? measured.length : null,
    assumed_trays: numbers ? assumed : null, assumed_range: numbers && !ruled && lo !== null ? [lo, hi] as [number, number | null] : null,
    assumed_stacks: numbers ? assumedCells.length : null,
    estimated_total: numbers && assumed !== null ? counted + assumed : null,
    estimated_range: numbers && !ruled && lo !== null ? [counted + lo, hi === null ? null : counted + hi] as [number, number | null] : null,
    // 0.7.0 stacking rule. two_photo_stacks: face stacks read the same, cleanly, by two captures (M, in stacks).
    rule_stacks: ruled ? ruleCells.length : null, rule_height: H, rule_trays: ruleTrays, rule_trays_range: ruleRangeTrays,
    rule_full_heights: ruled ? rule!.full_heights : null, sensitivity_per_layer: ruled ? ruleCells.length : null,
    rule_exceptions: ruled ? cells.filter(g => g.flags.includes("rule_exception")).length : null,
    doubted_low_stacks: ruled ? rule!.doubted_low.length : null,
    doubted_low_up_to: ruled && doubtedLow && assumed !== null ? counted + assumed + doubtedLow : null,
    two_photo_stacks: numbers ? cells.filter(g => g.status === "verified").length : null,
    hidden_stacks: numbers ? hidden.length : null, hidden_stacks_top_checked: numbers ? checked : null,
    unchecked_hidden_stacks: numbers ? unchecked : null,
    missing_stacks: numbers ? { seen_empty: byClass("seen_empty"), top_missing: byClass("top_missing"), declared_missing: byClass("declared_missing") } : null,
    cover_trays: cover, note,
  };
}

function modelDiagnostics(scanId: string, results: Record<string, ViewInference>, cellIds: Record<string, string>, env: Bindings, latency: number,
  precomputed?: Record<string, SpanColumn[]>, rimStatus?: Record<string, string>, headings: Record<string, ViewHeading> = {},
  captures: Record<string, ViewCapture> = {},
  extras: { declaration?: BlockDeclaration | null; topView?: TopViewTaps | null; corner?: ViewInference | null; cornerSide?: string | null;
    cornerCapture?: ViewCapture; elevated?: boolean; captureIds?: Record<string, string>; rule?: Partial<RuleOptions> } = {}) {
  const columns = precomputed ?? Object.fromEntries(VIEWS.map(view => [view, spanColumns(results[view].detections ?? [], results[view].image ?? null)]));
  const capture = Object.fromEntries(VIEWS.map(view => [view,
    captureQuality(columns[view], results[view].image?.width ?? null, results[view].image?.height ?? null,
      medianBoxAspect(results[view].detections ?? []))]));
  const rejectedView = worstView(capture, VIEWS);
  // A CORNER photo counts only from the guided camera; its columns give width and depth, never heights. It is the only
  // evidence that settles the depth of a block whose sides look like its front, and only when the phone did not block it.
  const cornerColumns = extras.corner ? spanColumns(extras.corner.detections ?? [], extras.corner.image ?? null) : null;
  const corner = cornerColumns && extras.cornerCapture?.source === "captured_still" ? cornerReading(cornerColumns, extras.cornerSide ?? null) : null;
  const witness: CornerWitness | null = !extras.corner ? null : {
    x: corner?.x ?? null, y: corner?.y ?? null,
    side: extras.cornerSide === "front_left" ? "left" : extras.cornerSide === "front_right" ? "right" : null,
    problem: extras.cornerCapture?.source !== "captured_still" ? "the CORNER photo is not from the guided camera"
      : extras.cornerCapture?.blocked !== false ? "the phone's live checks blocked the CORNER photo"
      : corner?.x === null || corner?.y === null ? `the CORNER photo could not be read (${corner?.note ?? "no stacks"})` : null };
  const declaration = extras.declaration ?? null;
  const sides = sideCheck(columns, headings, witness, declaration ? { x: declaration.x, y: declaration.y } : null);
  // Wrong-way photos are retaken before a side that only needs a CORNER photo or the declared size.
  const faulty = (["left", "right"] as const).filter(side => sides[side].reason)
    .sort((a, b) => SIDE_FAULT_ORDER.indexOf(sides[a].status) - SIDE_FAULT_ORDER.indexOf(sides[b].status));
  const wrongSide = faulty[0];
  const sideConflicts = faulty.map(side => ({ reason: sides[side].reason }));
  const strays = Object.fromEntries(VIEWS.map(view => [view, strayGroups(results[view].detections ?? [])]));
  // A reading can verify a stack only when it comes from the guided camera with no blocked live check, a side photo is
  // confirmed as a side face by the heading (and does not repeat the front: a CORNER photo settles its depth, not that
  // it is another photo of other stacks), and the photo is not a copy of a view already counted. A gallery photo
  // skips every live check, and three copies of one photo gave `exact` before this rule (plan Phase J).
  const duplicates = duplicateViews(results);
  const trusted = Object.fromEntries(VIEWS.map(view => [view, captures[view]?.source === "captured_still" && captures[view]?.blocked === false
    && (view === "straight" || (sides[view].status === "turned" && !sides[view].repeats_front)) && !duplicates[view]]));
  const captureIds = Object.fromEntries(VIEWS.map(view => [view, extras.captureIds?.[view] ?? view]));
  for (const [view, original] of Object.entries(duplicates)) captureIds[view] = captureIds[original];
  // 0.7.0: which photos may set the full height H. As trusted, except that a side repeating the front counts once a
  // CORNER photo and the declared size settle it (Plan 5 Decision 3 (a)); "strict_sides" (a') uses trusted itself. A
  // side the heading confirms but whose depth is not yet declared (depth_unproven) counts too: the block is withheld for
  // its depth anyway, and its provisional "if the block is this deep" figures need H.
  const ruleOptions: RuleOptions = { ...RULE_DEFAULTS, ...(extras.rule ?? {}) };
  const eligible = ruleOptions.basis === "strict_sides" ? trusted
    : Object.fromEntries(VIEWS.map(view => [view, captures[view]?.source === "captured_still" && captures[view]?.blocked === false
      && (view === "straight" || sides[view].status === "turned" || sides[view].status === "depth_unproven") && !duplicates[view]]));
  const assembled = buildBlock(columns.straight, columns.left, columns.right,
    Object.fromEntries(VIEWS.map(view => [view, strays[view].length])), trusted, duplicates,
    { captureIds, quality: Object.fromEntries(VIEWS.map(view => [view, capture[view].accepted ? "accepted" : "refused"])), eligible,
      rule: ruleOptions });
  // When the block model names a face in its first conflict, that is the photo to retake.
  const namedFace = (() => {
    for (const c of assembled.conflicts) {
      const reason = String(c.reason ?? "");
      const m = /^(LEFT|RIGHT|STRAIGHT):/.exec(reason) ?? /STRAIGHT and (LEFT|RIGHT)/.exec(reason);
      if (m) return { view: m[1].toLowerCase(), reason };
    }
    return null;
  })();
  // A face that fails the capture gate gives no usable column counts, and a side photo that is not a side face
  // gives a false depth: either way the block total is withheld.
  const withheld = { status: "needs_view", total_trays: null, faces_consistent: false, fully_observed: false };
  // A side that is not a side face also makes the depth, the hidden stacks and the grid false: none of it is
  // returned, or the app would still draw (and an operator could add up) the block the total was withheld for.
  const block = wrongSide
    ? { ...assembled, ...withheld, depth: null, cells: [], observed_trays: null, computed_trays: null, filled_trays: null,
        rescan_cells: [], single_reading_cells: [], visible_verified_trays: null, visible_single_reading_trays: null,
        conflicts: [...sideConflicts, ...assembled.conflicts] }
    : rejectedView ? { ...assembled, ...withheld } : assembled;
  // What the depth rests on: one stack deep, or the declared size (with the CORNER photo for a side that repeats the front).
  const witnesses = (["left", "right"] as const).map(side => sides[side].depth_witness);
  const depthBasis: DepthBasis | null = wrongSide || assembled.depth === null ? null : assembled.depth === 1 ? "one_deep"
    : witnesses.includes("declaration") ? "declaration" : witnesses.includes("corner_and_declaration") ? "corner_and_declaration"
    : witnesses.includes("corner") ? "corner" : null;
  // The physical grid with the declaration and the extra views (0.5.0; hidden stacks and evidence classes 0.6.0).
  const assembledGrid = assembleGrid(block as ReturnType<typeof blockResult>, { declaration, topView: extras.topView ?? null, corner, depthBasis });
  const finalStatus = assembledGrid.status;
  const finalTotal = finalStatus === "needs_view" ? null : assembledGrid.total;
  // Provisional figures for a block withheld only for its depth (sides depth_unproven or repeating the front, no refused
  // photo): the front row counted and, when the depth is the only doubt, what the block would hold if it is as deep as
  // the sides read. Never a total: they stay out of total_trays, and a side that may be the front again gets no what-if.
  const proofSides = faulty.filter(side => sides[side].status === "depth_unproven" || sides[side].status === "turned_repeats_front");
  let provisional: Record<string, unknown> | null = null;
  if (faulty.length && proofSides.length === faulty.length && !rejectedView) {
    const kind = proofSides.some(side => sides[side].status === "turned_repeats_front") ? "side_repeats_front" : "depth_unproven";
    const front = faceColumns(columns.straight, "straight");
    let ifDepth: Record<string, unknown> | null = null;
    if (kind === "depth_unproven" && !assembled.conflicts.length) {
      const what = assembleGrid(assembled, { declaration: null, topView: extras.topView ?? null, corner: null });
      const whatInventory = gridInventory(what.grid, null, what.total, { status: what.status });
      if (what.status === "estimated") ifDepth = { y: assembled.depth, counted_trays: whatInventory.counted_trays,
        assumed_trays: whatInventory.assumed_trays, assumed_stacks: whatInventory.assumed_stacks, estimated_total: whatInventory.estimated_total };
    }
    provisional = { kind, reason: sides[faulty[0]].reason, if_depth: ifDepth,
      front_row_counted: front.every(c => c.count_agreement) ? front.filter(c => !c.recessed).reduce((s, c) => s + c.layers, 0) : null };
  }
  // A rule check names its own reason; its provisional figures stay in block.rule (app 0.6.x would title any inventory
  // provisional "DEPTH NOT PROVEN").
  const ruleSummary = wrongSide ? null : assembledGrid.rule;
  const withheldReason = rejectedView ? "needs_view" : wrongSide ? String(provisional?.kind ?? "needs_view") : ruleSummary?.withheld_reason ?? null;
  const inventory = gridInventory(assembledGrid.grid, declaration, assembledGrid.total, { status: finalStatus, provisional, withheld_reason: withheldReason,
    rule: ruleSummary });
  // An ELEVATED photo is suggested while hidden stacks are unchecked and none was sent; a total never needs one.
  let suggestedViews = extras.elevated ? [] : assembledGrid.suggested_views;
  // A CORNER photo is the next step only when nothing but a CORNER photo or the declared size is missing; a wrong-way
  // side is retaken first.
  const retakes = faulty.map(side => sides[side].retake);
  if (faulty.length && retakes.every(r => r === "corner" || r === "declaration") && retakes.includes("corner")) suggestedViews = ["corner"];
  // The declared size is an input, not a view (app 0.5.0 would show it as a photo slot).
  const declares = (side: string) => declaration !== null && declaration.x === columns.straight.length && declaration.y === columns[side].length;
  const suggestedInputs = proofSides.length && !proofSides.every(declares) ? ["declaration"] : [];
  // Model boxes are useful evidence, but not proof of cross-view identity or egg occupancy.
  // Do not substitute whole-photo voting for an unfinished spatial hybrid pipeline.
  const reason = "Model detections are available. Physical stack matching and egg occupancy remain unresolved; these per-photo counts are not a verified inventory total.";
  const rescan = rejectedView
    ? { recommended_view: rejectedView, reason: `${CAPTURE_ADVICE} (${rejectedView.toUpperCase()}: ${capture[rejectedView].reasons.join("; ")})` }
    : wrongSide
      ? { recommended_view: wrongSide, reason: sides[wrongSide].reason! }
      : namedFace
        ? { recommended_view: namedFace.view, reason: namedFace.reason }
        : { recommended_view: "straight", reason };
  return {
    // Legacy top-level fields stay "not verified" for installed APKs; result_status is the block's one result state.
    scan_id: scanId, status: "rescan_required", accepted: false, result_status: finalStatus,
    physical_stack_count: null, total_trays: null, total_eggs: null,
    eggs_per_tray: Number(env.EGGS_PER_TRAY), cell_ids: cellIds,
    model: { provider: "roboflow_serverless", model_id: env.MODEL_ID },
    processing: { mode: "model_spatial_v1", latency_ms: latency, model_version: env.MODEL_ID, timings_ms: { total: latency } },
    views: Object.fromEntries(VIEWS.map(view => [view, {
      quality: 0, accepted: false, reason, detections: results[view].detections,
      detector_mean_confidence: results[view].confidence, stack_columns: columns[view], stray_groups: strays[view],
      capture_source: captures[view]?.source ?? null, trusted: trusted[view], duplicate_of: duplicates[view] ?? null,
      image: results[view].image ?? null,
    }])),
    stacks: [{ physical_stack_id: "Per-photo model detections (unmatched)",
      counts: Object.fromEntries(VIEWS.map(view => [view, results[view].count])),
      final_count: null, confidence: 0, accepted: false, reason }],
    // Block model: STRAIGHT = X face, LEFT/RIGHT = Y faces. total_trays here is X x Y x height computed
    // from observed faces; it is not a field-validated inventory until the held-out scene test passes.
    block: { ...block, status: finalStatus, total_trays: finalTotal,
      // The legacy cells and computed_trays follow the grid (taps and the declaration applied), so a client adding up
      // cells gets the same per-stack values as the total.
      ...(assembledGrid.grid.length ? { cells: assembledGrid.cells, computed_trays: assembledGrid.computed_trays } : {}),
      conflicts: [...block.conflicts, ...assembledGrid.conflicts], contract: "block_model_v1", eggs_per_tray: Number(env.EGGS_PER_TRAY),
      verification: { method: "rim_edges", views: rimStatus ?? Object.fromEntries(VIEWS.map(v => [v, "disabled"])) },
      // Egg occupancy is not measured: this is tray capacity if every counted tray is full. Kept for app 0.5.0 (shown only
      // without a grid); null when any tray is assumed, since assumed trays are not counted.
      total_eggs: finalTotal === null || inventory.assumed_stacks ? null : finalTotal * Number(env.EGGS_PER_TRAY),
      eggs_basis: "capacity_if_every_tray_full", capture, side_check: sides,
      grid: assembledGrid.grid, inventory, confirmed_basis: [], depth_basis: assembledGrid.depth_basis,
      declaration: declaration ? { ...declaration, agrees_with_faces: assembledGrid.declaration_agrees } : null,
      corner: corner ? { ...corner, agrees: assembledGrid.corner_agrees } : null, top_view: assembledGrid.top_view,
      suggested_views: suggestedViews, suggested_inputs: suggestedInputs, grid_contract: "0.7.0",
      grid_note: "grid model from photos, not a point cloud or a measured mesh", rule: ruleSummary },
    rescan: assembledGrid.conflicts.length && !rejectedView && !wrongSide
      ? { recommended_view: "straight", reason: String(assembledGrid.conflicts[0].reason) } : rescan,
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
const PIPELINE_VERSION = "worker-0.7.0";
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
// (the photo hashes alone) and are matched on the photos only, as they were. Version 3 adds each view's capture
// source, blocked flag and phone heading, which decide the side check and whether a reading can verify a stack; a
// version 2 job is matched on its own version's fields.
const FINGERPRINT_VERSION = 3;
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
  counted_by?: string | null; second_counter?: string | null;
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
async function requestIdentity(scan: ParsedScan, version = FINGERPRINT_VERSION) {
  const cellIds = Object.fromEntries(Object.entries(scan.cellIds).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
  const fields: unknown[] = [version, ...scan.hashes, scan.scanContract, Object.entries(cellIds)];
  if (version >= 3) fields.push(VIEWS.map(view => {
    const { source, blocked, heading } = scan.captures[view];
    return source === null && blocked === null && !heading ? null : [source, blocked, heading?.yaw_deg ?? null, heading?.yaw_session ?? null];
  }));
  const extras = scan.extras;
  if (version >= 3 && extras && (extras.declaration || extras.topView || extras.cornerHash || extras.elevatedHash || extras.cornerSide)) {
    fields.push([extras.cornerHash, extras.cornerSide, extras.elevatedHash, extras.declaration, extras.topView]);
  }
  const fingerprint = toHex(await digestText(JSON.stringify(fields)));
  return { fingerprint, fingerprint_version: version, scan_contract: scan.scanContract, cell_ids: cellIds };
}

// A job written before fingerprint version 2 holds the photo hashes alone ("left|right|straight"): its missing
// contract and cell ids match any request, as they did then, so the same photos still replay.
async function sameRequest(job: JobRecord, scan: ParsedScan, fingerprint: string) {
  const version = job.fingerprint_version ?? 1;
  if (version === 1) return job.fingerprint === toHex(await digestText(scan.hashes.join("|")));
  if (version !== FINGERPRINT_VERSION) return job.fingerprint === (await requestIdentity(scan, version)).fingerprint;
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
  JSON.stringify([record.block_id, record.cells, record.notes, record.tray, record.app_version, record.app_total ?? null, record.created_at,
    record.counted_by ?? null, record.second_counter ?? null]);

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
  // Blind two-person recounts (plan step 10): who counted, and who counted again without seeing the first count.
  const counter = (v: unknown) => typeof v === "string" ? v.replace(UNSAFE_TEXT, " ").replace(/\s+/g, " ").trim().slice(0, 80) || null : null;
  const record = { kind: "manual_count_v1", scan_id: scanId, block_id: blockId, cells: clean, notes, tray, recorded_at: isoAt(Date.now()),
    created_at: createdAt, count_id: countId, app_total: appTotal as number | null, app_version: appVersion, totals, recorded_by: ownerOf(caller),
    counted_by: counter(body.counted_by), second_counter: counter(body.second_counter) };
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

export { base64, buildBlock, captureQuality, faceColumns, fuseCounts, fuseCells, medianBoxAspect, modelDiagnostics, readCellIds, readOptionalCellIds,
  strayGroups, boxOverlapScore, duplicateViews, assembleGrid, assumeHidden, gridInventory, cornerReading, readDeclaration, readTopViewTaps, blockResult,
  sideCheck, spanColumns, walkLayers, worstView, mode, stackingRule, RULE_DEFAULTS };

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
