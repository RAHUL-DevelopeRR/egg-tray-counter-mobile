import assert from "node:assert/strict";
import test from "node:test";
import { fuseCounts } from "../dist/index.js";

test("accepts one count agreed by two views", () => {
  assert.equal(fuseCounts({ left: { count: 12 }, right: { count: 12 }, straight: { count: 11 } }), 12);
});

test("rejects three disagreeing views", () => {
  assert.equal(fuseCounts({ left: { count: 10 }, right: { count: 11 }, straight: { count: 12 } }), null);
});

test("rejects two-view agreement when the third view exposes a severe undercount", () => {
  assert.equal(fuseCounts({ left: { count: 19 }, right: { count: 19 }, straight: { count: 120 } }), null);
});
