type Bindings = Env & { ROBOFLOW_API_KEY: string };

type Prediction = { class?: string; confidence?: number };
type ViewInference = { count: number; confidence: number };

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

function base64(bytes: Uint8Array) {
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary);
}

async function infer(file: File, env: Bindings): Promise<ViewInference> {
  const url = new URL(`https://serverless.roboflow.com/${env.MODEL_ID}`);
  url.searchParams.set("api_key", env.ROBOFLOW_API_KEY);
  url.searchParams.set("confidence", env.CONFIDENCE);
  url.searchParams.set("overlap", env.OVERLAP);
  url.searchParams.set("classes", "egg_tray");
  url.searchParams.set("format", "json");
  const body = base64(new Uint8Array(await file.arrayBuffer()));
  let response: Response | undefined;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      response = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body,
      });
      if (!RETRYABLE.has(response.status)) break;
    } catch {
      response = undefined;
    }
    if (attempt < 2) await new Promise((resolve) => setTimeout(resolve, 250 * 2 ** attempt));
  }
  if (!response?.ok) {
    console.error(JSON.stringify({ event: "roboflow_error", status: response?.status ?? 0 }));
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
    (item) => item.class === "egg_tray" && typeof item.confidence === "number",
  );
  return {
    count: predictions.length,
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
  if (!request.headers.get("content-type")?.startsWith("multipart/form-data")) {
    throw new HttpError(415, "invalid_content_type", "Expected multipart form data");
  }
  const form = await request.formData();
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
  const hashes = await Promise.all(VIEWS.map((view) => sha256(files[view] as File)));
  if (new Set(hashes).size !== 3) {
    throw new HttpError(422, "duplicate_view", "LEFT, RIGHT, and STRAIGHT must be distinct photographs");
  }

  const started = Date.now();
  const results = {} as Record<string, ViewInference>;
  for (const view of VIEWS) results[view] = await infer(files[view] as File, env);
  const finalCount = fuseCounts(results, Number(env.MAX_VIEW_COUNT_RATIO));
  const accepted = finalCount !== null;
  const latency = Date.now() - started;
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
  console.log(JSON.stringify({ event: "scan_complete", scan_id: rawScanId, accepted, counts, latency_ms: latency }));
  return json({
    scan_id: rawScanId,
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

export { fuseCounts };

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);
    try {
      if (request.method === "GET" && url.pathname === "/health") return json({ status: "ok" });
      if (request.method === "GET" && url.pathname === "/ready") {
        return json({ status: env.ROBOFLOW_API_KEY ? "ready" : "not_ready", provider: "roboflow_serverless", model_reference: env.MODEL_ID }, env.ROBOFLOW_API_KEY ? 200 : 503);
      }
      if (request.method === "POST" && url.pathname === "/v1/scans/count") return await countScan(request, env);
      return json({ detail: { code: "not_found", message: "Route not found" } }, 404);
    } catch (error) {
      if (error instanceof HttpError) return json({ detail: { code: error.code, message: error.message } }, error.status);
      console.error(JSON.stringify({ event: "request_failed", message: error instanceof Error ? error.message : "unknown" }));
      return json({ detail: { code: "internal_error", message: "Scan could not be processed" } }, 500);
    }
  },
} satisfies ExportedHandler<Bindings>;
