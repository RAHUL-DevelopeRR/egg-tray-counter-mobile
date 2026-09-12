import assert from "node:assert/strict";
import test from "node:test";
import { fuseCounts } from "../dist/index.js";

test("accepts one count agreed by two views", () => {
  assert.equal(fuseCounts({ left: { count: 12, confidence: .9 }, right: { count: 12, confidence: .9 }, straight: { count: 11, confidence: .9 } }), 12);
});

test("rejects three disagreeing views", () => {
  assert.equal(fuseCounts({ left: { count: 10, confidence: .9 }, right: { count: 11, confidence: .9 }, straight: { count: 12, confidence: .9 } }), null);
});

test("rejects two-view agreement when the third view exposes a severe undercount", () => {
  assert.equal(fuseCounts({ left: { count: 19, confidence: .9 }, right: { count: 19, confidence: .9 }, straight: { count: 120, confidence: .9 } }), null);
});
