import assert from 'node:assert/strict';
import test from 'node:test';
import { base64 } from '../dist/index.js';

test('native encoding preserves bytes and subarray boundaries', () => {
  const bytes = new Uint8Array(2 * 1024 * 1024 + 7);
  for (let i = 0; i < bytes.length; i++) bytes[i] = i % 256;
  for (const slice of [bytes, bytes.subarray(3, bytes.length - 2), bytes.subarray(0, 0)]) {
    assert.deepEqual(new Uint8Array(Buffer.from(base64(slice), 'base64')), slice);
  }
});
