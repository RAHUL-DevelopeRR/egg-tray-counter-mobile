// In-memory R2 bucket for the Worker tests. Supports what the Worker uses and nothing more:
// put (onlyIf as Headers If-None-Match / If-Match, or {etagMatches, etagDoesNotMatch}; '*' wildcard),
// get, head, list (prefix, cursor, startAfter, limit, include) and delete. Every write gets a new etag.
// A failed precondition returns null and stores nothing, as R2 does. The precondition check and the
// write run with no await in between, so concurrent requests race exactly like R2's atomic commit.

const toBytes = async (value) => {
  if (value === null || value === undefined) return new Uint8Array();
  if (typeof value === 'string') return new TextEncoder().encode(value);
  if (value instanceof Uint8Array) return new Uint8Array(value);
  if (ArrayBuffer.isView(value)) return new Uint8Array(value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength));
  if (value instanceof ArrayBuffer) return new Uint8Array(value.slice(0));
  return new Uint8Array(await new Response(value).arrayBuffer());   // ReadableStream or Blob
};

const etagList = (header) => header.split(',').map((tag) => tag.trim().replace(/^W\//, '').replace(/^"|"$/g, ''));

function preconditionHolds(onlyIf, existing) {
  if (onlyIf instanceof Headers) {
    const noneMatch = onlyIf.get('if-none-match');
    const match = onlyIf.get('if-match');
    for (const name of onlyIf.keys()) {
      if (!['if-none-match', 'if-match'].includes(name)) throw new Error(`fake R2: unsupported conditional header ${name}`);
    }
    if (noneMatch !== null && existing && (noneMatch.trim() === '*' || etagList(noneMatch).includes(existing.etag))) return false;
    if (match !== null && (!existing || (match.trim() !== '*' && !etagList(match).includes(existing.etag)))) return false;
    return true;
  }
  for (const name of Object.keys(onlyIf)) {
    if (!['etagMatches', 'etagDoesNotMatch'].includes(name)) throw new Error(`fake R2: unsupported condition ${name}`);
  }
  const { etagMatches, etagDoesNotMatch } = onlyIf;
  if (etagMatches !== undefined && (!existing || (etagMatches !== '*' && existing.etag !== etagMatches))) return false;
  if (etagDoesNotMatch !== undefined && existing && (etagDoesNotMatch === '*' || existing.etag === etagDoesNotMatch)) return false;
  return true;
}

export class FakeR2 {
  constructor({ pageCap = 1000 } = {}) {
    this.objects = new Map();
    this.ops = [];          // {op, key, conditional?, stored?} in call order
    this.pageCap = pageCap; // R2 may return fewer than `limit` objects per page; tests lower this to exercise cursors
    this.failPut = null;    // (key) => true makes that put throw, as a failing R2 write would
    this.seq = 0;
  }

  meta(object, include = ['httpMetadata', 'customMetadata']) {
    return { key: object.key, version: object.version, size: object.bytes.byteLength, etag: object.etag, httpEtag: `"${object.etag}"`,
      uploaded: object.uploaded, checksums: {}, storageClass: 'Standard',
      ...(include.includes('httpMetadata') ? { httpMetadata: { ...object.httpMetadata } } : {}),
      ...(include.includes('customMetadata') ? { customMetadata: { ...object.customMetadata } } : {}) };
  }

  async put(key, value, options = {}) {
    const bytes = await toBytes(value);
    if (this.failPut?.(key)) {
      this.ops.push({ op: 'put', key, conditional: !!options.onlyIf, stored: false, threw: true });
      throw new Error('fake R2: put failed');
    }
    const existing = this.objects.get(key);
    if (options.onlyIf && !preconditionHolds(options.onlyIf, existing)) {
      this.ops.push({ op: 'put', key, conditional: true, stored: false });
      return null;
    }
    const seq = ++this.seq;
    const object = { key, bytes, etag: seq.toString(16).padStart(32, '0'), version: `v${seq}`, uploaded: new Date(),
      httpMetadata: options.httpMetadata instanceof Headers ? Object.fromEntries(options.httpMetadata) : { ...(options.httpMetadata ?? {}) },
      customMetadata: { ...(options.customMetadata ?? {}) } };
    this.objects.set(key, object);
    this.ops.push({ op: 'put', key, conditional: !!options.onlyIf, stored: true });
    return this.meta(object);
  }

  async get(key, options = {}) {
    this.ops.push({ op: 'get', key });
    const object = this.objects.get(key);
    if (!object) return null;
    if (options.onlyIf && !preconditionHolds(options.onlyIf, object)) return this.meta(object);
    const bytes = new Uint8Array(object.bytes);
    return { ...this.meta(object), body: new Response(bytes).body, bodyUsed: false,
      arrayBuffer: async () => bytes.buffer, bytes: async () => new Uint8Array(bytes),
      text: async () => new TextDecoder().decode(bytes), json: async () => JSON.parse(new TextDecoder().decode(bytes)),
      blob: async () => new Blob([bytes]) };
  }

  async head(key) {
    this.ops.push({ op: 'head', key });
    const object = this.objects.get(key);
    return object ? this.meta(object) : null;
  }

  async list({ prefix = '', cursor, startAfter, limit = 1000, include = [] } = {}) {
    this.ops.push({ op: 'list', prefix });
    if (limit > 1000) throw new Error('fake R2: limit above 1000');
    let after = startAfter;
    if (cursor !== undefined) {
      if (!String(cursor).startsWith('c:')) throw new Error('fake R2: invalid cursor');
      after = Buffer.from(String(cursor).slice(2), 'base64url').toString('utf8');
    }
    const keys = [...this.objects.keys()].filter((key) => key.startsWith(prefix) && (after === undefined || key > after)).sort();
    const page = keys.slice(0, Math.min(limit, this.pageCap));
    const truncated = keys.length > page.length;
    // R2 returns metadata in a listing only when `include` asks for it.
    const objects = page.map((key) => this.meta(this.objects.get(key), include));
    return truncated
      ? { objects, truncated, cursor: `c:${Buffer.from(page[page.length - 1]).toString('base64url')}`, delimitedPrefixes: [] }
      : { objects, truncated, delimitedPrefixes: [] };
  }

  async delete(keys) {
    for (const key of [keys].flat()) { this.ops.push({ op: 'delete', key }); this.objects.delete(key); }
  }

  // ---- Test helpers.
  keys(prefix = '') { return [...this.objects.keys()].filter((key) => key.startsWith(prefix)).sort(); }
  stored(prefix = '') { return this.ops.filter((o) => o.op === 'put' && o.stored && o.key.startsWith(prefix)).length; }
  readJson(key) { const object = this.objects.get(key); return object ? JSON.parse(new TextDecoder().decode(object.bytes)) : null; }
  allText() { return [...this.objects.values()].map((o) => new TextDecoder().decode(o.bytes)).join('\n'); }
  async seed(key, value, customMetadata = {}) { return this.put(key, JSON.stringify(value), { customMetadata }); }
}
