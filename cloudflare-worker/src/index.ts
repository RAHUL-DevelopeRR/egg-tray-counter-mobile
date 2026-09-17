import { Buffer } from "node:buffer";

type Bindings = Env & { ROBOFLOW_API_KEY: string };

type Prediction = { class?: string; confidence?: number; x?: number; y?: number; width?: number; height?: number };
type ViewInference = { count: number; confidence: number; detections?: Prediction[] };

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
  const payload = (await response.json()) as { predictions?: Prediction[] };
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
  return {
    count: predictions.length,
    detections: predictions.map(({class: label, confidence, x, y, width, height}) =>
      ({class: label, confidence, x, y, width, height})),
    confidence: predictions.length
      ? predictions.reduce((sum, item) => sum + item.confidence!, 0) / predictions.length
      : 0,
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
    return modelDiagnostics(rawScanId, results, cellIds, env, Date.now() - started);
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

function modelDiagnostics(scanId: string, results: Record<string, ViewInference>, cellIds: Record<string, string>, env: Bindings, latency: number) {
  // Model boxes are useful evidence, but not proof of cross-view identity or egg occupancy.
  // Do not substitute whole-photo voting for an unfinished spatial hybrid pipeline.
  const reason = "Model detections are available. Physical stack matching and egg occupancy remain unresolved; these per-photo counts are not a verified inventory total.";
  return json({
    scan_id: scanId, status: "rescan_required", accepted: false,
    physical_stack_count: null, total_trays: null, total_eggs: null,
    eggs_per_tray: Number(env.EGGS_PER_TRAY), cell_ids: cellIds,
    model: { provider: "roboflow_serverless", model_id: env.MODEL_ID },
    processing: { mode: "model_spatial_v1", latency_ms: latency, model_version: env.MODEL_ID, timings_ms: { total: latency } },
    views: Object.fromEntries(VIEWS.map(view => [view, {
      quality: 0, accepted: false, reason, detections: results[view].detections,
      detector_mean_confidence: results[view].confidence,
    }])),
    stacks: [{ physical_stack_id: "Per-photo model detections (unmatched)",
      counts: Object.fromEntries(VIEWS.map(view => [view, results[view].count])),
      final_count: null, confidence: 0, accepted: false, reason }],
    rescan: { recommended_view: "straight", reason },
  });
}

export { base64, fuseCounts, fuseCells, readCellIds, readOptionalCellIds };

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);
    try {
      if (request.method === "GET" && url.pathname === "/health") return json({ status: "ok", scan_contract: "cell_identity_v1", scan_contracts: ["cell_identity_v1", "model_spatial_v1"], hybrid_ready: false });
      if (request.method === "GET" && url.pathname === "/ready") {
        return json({ status: env.ROBOFLOW_API_KEY ? "ready" : "not_ready", provider: "roboflow_serverless", model_reference: env.MODEL_ID }, env.ROBOFLOW_API_KEY ? 200 : 503);
      }
      if (request.method === "POST" && url.pathname === "/v1/scans/count") return await countScan(request, env);
      return json({ detail: { code: "not_found", message: "Route not found" } }, 404);
    } catch (error) {
      if (error instanceof HttpError) return json({ detail: { code: error.code, message: error.message } }, error.status);
      console.error(JSON.stringify({ event: "request_failed", error_type: "unexpected_error" }));
      return json({ detail: { code: "internal_error", message: "Scan could not be processed" } }, 500);
    }
  },
} satisfies ExportedHandler<Bindings>;
