// Stacking-rule cases (tier S) for Worker 0.7.0: docs/PLAN_5_MULTI_PHOTO.md §7 Phase 1, cases FR01-FR21. Every case is a
// guided-camera walk-around (camera headings, captured stills) through modelDiagnostics, as the Worker runs it after
// inference; no network, no detector call. Used by test/rule.test.mjs and scripts/replay_stacking_rule.mjs.
//
// Base block FR01, 5 wide and 3 deep (grid x across the front from the left, y into the block from the front):
//   front (y = 0)   20 20 20 19 12      the 19 is a full stack without its cover tray; the 12 a partial stack
//   LEFT by depth   20 20 20            (0,0) (0,1) (0,2)
//   RIGHT by depth  12 20 20            (4,0) (4,1) (4,2)
// 9 face stacks = 171 counted; (5-2) x (3-1) = 6 hidden stacks at H = 20: 291. Sides are framed a little differently
// (separate captures, not copies) and the honest block size 5 x 3 is declared, so the depth is proven.
import { syntheticFace, syntheticCorner, declared, CAMERA, capturesFor, replayViews, judge } from './replay_benchmark.mjs';

const S = syntheticFace;
// The LEFT photo shows the front corner right-most, so its stacks by depth are drawn in reverse.
const leftPhoto = (byDepth, opts = {}) => S([...byDepth].reverse(), { shift: 1, ...opts });
const rightPhoto = (byDepth, opts = {}) => S(byDepth, { shift: 2, ...opts });
const FRONT = [20, 20, 20, 19, 12], LEFT = [20, 20, 20], RIGHT = [12, 20, 20];
export const BASE = { straight: () => S(FRONT), left: () => leftPhoto(LEFT), right: () => rightPhoto(RIGHT) };
const block = (front = FRONT, left = LEFT, right = RIGHT, opts = {}) =>
  ({ straight: S(front, opts.straight), left: leftPhoto(left, opts.left), right: rightPhoto(right, opts.right) });
const decl = (over = {}) => declared(5, 3, { interior: 'unknown', ...over });

// ---- A column of a face photo that mixes two stacks (FR13): a short partial stack in the face row with the full stack
// behind it showing above it, or a partial standing in front of a full face stack. Geometry of syntheticFace: layer j
// from the floor of a near stack at y = 860 - 40 j; a stack at scale s (s < 1 farther, s > 1 nearer) is drawn about a
// horizon at y = 480 and the image's centre column. Tray depth and stand-off are not measured (Plan 5 FR13 note).
function mixedColumn(xi, cx, dy, { partial = 8, scale = 0.9, outside = false } = {}) {
  const boxes = [];
  const at = (j, s) => ({ x: cx + (xi - cx) * s, y: 480 + (380 - 40 * j) * s + dy, width: 100 * s, height: 36 * s });
  // outside: the partial (nearer, at scale 1/0.9) stands in front of a full face stack, whose upper layers show above it.
  const near = outside ? 1 / 0.9 : 1, far = outside ? 1 : scale;
  for (let j = 0; j < partial; j++) boxes.push(at(j, near));
  const top = at(partial - 1, near);
  for (let j = 0; j < 20; j++) { const b = at(j, far); if (b.y + b.height / 2 < top.y - top.height / 2) boxes.push(b); }
  return boxes.map(b => ({ class: 'egg_tray', confidence: 0.9, ...b }));
}
/** A face with column `index` replaced by a mixed column. heights: the other columns (the mixed one's entry is ignored). */
export function mixedFace(heights, index, opts = {}, shift = 0) {
  const face = S(heights.map((h, i) => i === index ? 0 : h), { shift });
  const dx = 37 * shift, dy = 11 * shift;
  face.detections.push(...mixedColumn(100 + index * 100 + dx, face.image.width / 2, dy, opts));
  return face;
}

// A face whose column `index` is set back (a gap in the face row) and shows `behind` trays of a stack farther in.
function recessedFace(heights, index, behind, shift = 0) {
  const face = S(heights.map((h, i) => i === index ? 0 : h), { shift });
  const dx = 37 * shift, dy = 11 * shift;
  for (let k = 0; k < behind; k++) face.detections.push({ class: 'egg_tray', confidence: 0.9, x: 100 + index * 100 + dx,
    y: 100 + (20 - behind + k) * 30 + 200 + dy, width: 75, height: 27 });
  return face;
}

const camera = (views, extras = {}, rule = undefined) => ({ views, headings: CAMERA, extras: { ...decl(), ...extras, ...(rule ? { rule } : {}) } });

/**
 * Each case: id, inputs (views, headings, extras), truth (tray layers in the X x Y block; null when unknown), check (as in
 * replay_benchmark.mjs judge, plus 'withheld:<reason>' and 'in_range': the truth lies in the printed rule range), and
 * expect: what Plan 5 §7 expects, in words. residual: a case that documents a known risk the rule cannot catch.
 */
export function ruleCases() {
  const FR13_SCALES = [0.80, 0.83, 0.85, 0.87, 0.90, 0.93, 0.95, 0.97];
  return [
    { id: 'FR01 5x3: front 20 20 20 19 12, LEFT 20 20 20, RIGHT 12 20 20', ...camera(block()), truth: 291, check: 'total_ok',
      expect: '291 = 171 counted + 6 x 20' },
    { id: 'FR02 FR01 with front x=2 at 21', ...camera(block([20, 20, 21, 19, 12])), truth: 291, check: 'withheld:stack_taller_than_rule_height',
      expect: 'withheld, retake straight, provisional 292 at H 20 or 298 at 21' },
    { id: 'FR03 FR01 with front 21 21 20 19 12 (two over-reads in one photo)', ...camera(block([21, 21, 20, 19, 12])), truth: 291,
      check: 'withheld:stack_taller_than_rule_height', expect: 'H = 20 (the 21s are on one face), the 21s are taller, withheld' },
    { id: 'FR04 every face under-read by 2', ...camera(block([18, 18, 18, 17, 10], [18, 18, 18], [10, 18, 18])), truth: 291,
      check: 'no_wrong_total', residual: true, expect: 'stretch: documents the residual risk (two faces agreeing on an under-read)' },
    { id: 'FR05 FR01 with the LEFT back corner at 18', ...camera(block(FRONT, [20, 20, 18])), truth: null,
      check: 'withheld:back_corner_below_rule_height', expect: 'back_corner_below_rule_height, retake left' },
    { id: 'FR06 5x1 row 20 20 20 20 19', views: { straight: S([20, 20, 20, 20, 19]), left: S([20], { shift: 1 }), right: S([19], { shift: 2 }) },
      headings: CAMERA, extras: {}, truth: 99, check: 'total_ok', expect: 'the same answer as 0.6.0 (no hidden stack: the rule is not used)' },
    { id: 'FR08 FR01, declared missing (2,1)', ...camera(block(), decl({ missing_cells: [[2, 1]] })), truth: 271, check: 'total_ok',
      expect: '271 with rule_exception' },
    { id: 'FR09 FR01, interior declared partly empty', ...camera(block(), decl({ interior: 'partial' })), truth: null,
      check: 'withheld:inside_declared_partial', expect: 'withheld' },
    { id: 'FR10 FR01, ELEVATED step_up tap at (2,2)', ...camera(block(), { topView: { x: 5, y: 3, cells: [{ x: 2, y: 2, state: 'step_up' }] }, elevated: true }),
      truth: null, check: 'withheld:inside_step_up', expect: 'withheld' },
    { id: 'FR11 FR01 with front x=2 a gap, 14 trays seen through it on hidden (2,1)',
      views: { straight: recessedFace(FRONT, 2, 14), left: leftPhoto(LEFT), right: rightPhoto(RIGHT) }, headings: CAMERA, extras: decl(),
      truth: null, check: 'withheld:inside_hint_below_rule', expect: 'withheld' },
    { id: 'FR12 a 2-tray stack at front x=2, declared 5 x 3', ...camera(block([20, 20, 2, 19, 12])), truth: 273, check: 'withheld',
      expect: 'withheld (width 4 vs 5), never wrong' },
    ...FR13_SCALES.map(scale => ({ id: `FR13 front x=1: 8 trays with the full stack behind showing above, scale ${scale.toFixed(2)}`,
      views: { straight: mixedFace(FRONT, 1, { scale }), left: leftPhoto(LEFT), right: rightPhoto(RIGHT) }, headings: CAMERA, extras: decl(),
      truth: 279, check: 'no_wrong_total', sweep: 'FR13', expect: 'no_wrong_total at every scale; if any fails, Phase 1b' })),
    ...FR13_SCALES.map(scale => ({ id: `FR13-side LEFT y=1: 8 trays with the full stack behind, scale ${scale.toFixed(2)}`,
      views: { straight: S(FRONT), left: (() => { const f = mixedFace([...LEFT].reverse(), 1, { scale }, 1); return f; })(), right: rightPhoto(RIGHT) },
      headings: CAMERA, extras: decl(), truth: 279, check: 'no_wrong_total', sweep: 'FR13-side', expect: 'no_wrong_total' })),
    ...FR13_SCALES.map(scale => ({ id: `FR13-corner front-left corner: 8 trays, misread the same way by STRAIGHT and LEFT, scale ${scale.toFixed(2)}`,
      views: { straight: mixedFace(FRONT, 0, { scale }), left: mixedFace([...LEFT].reverse(), 2, { scale }, 1), right: rightPhoto(RIGHT) },
      headings: CAMERA, extras: decl(), truth: 279, check: 'no_wrong_total', sweep: 'FR13-corner',
      expect: 'no_wrong_total; the corner is never "read twice" at the wrong value' })),
    { id: 'FR13-outside a partial of 8 standing in front of front x=1, declared 5 x 3',
      views: { straight: mixedFace(FRONT, 1, { outside: true }), left: leftPhoto(LEFT), right: rightPhoto(RIGHT) }, headings: CAMERA, extras: decl(),
      truth: 299, check: 'no_wrong_total', expect: 'withheld or flagged (Decision 18: where partials stand)' },
    { id: 'FR14 FR01 with hidden (2,1) missing, no tap', ...camera(block()), truth: 271, check: 'no_wrong_total', residual: true,
      expect: "stretch: released 20 high (S29's twin)" },
    { id: 'FR15 every reading cut by the frame edge',
      views: { straight: S(FRONT, { cutBottom: true }), left: leftPhoto(LEFT, { cutBottom: true }), right: rightPhoto(RIGHT, { cutBottom: true }) },
      headings: CAMERA, extras: decl(), truth: 291, check: 'withheld:no_rule_height', expect: 'no_rule_height' },
    { id: 'FR16 FR01, measured reference height 21', ...camera(block(), decl({ reference_height: 21 })), truth: 291,
      check: 'withheld:reference_height_differs', expect: 'withheld' },
    { id: 'FR17 cover trays on 3 of 8 full face stacks (front 21 20 21 20 12, LEFT 21 20 21); 2 of 6 hidden stacks covered',
      ...camera(block([21, 20, 21, 20, 12], [21, 20, 21])), truth: 297, check: 'in_range',
      expect: 'released with the cover range: covered stacks are the partner height, never taller; the truth inside the printed range' },
    { id: 'FR18 FR01 with front x=1 and the LEFT back corner over-read at 21', ...camera(block([20, 21, 20, 19, 12], [20, 20, 21])), truth: 291,
      check: 'in_range', expect: 'H = 21, 20 its partner, hidden range 120-126; the true total inside the printed range' },
    { id: 'FR20 FR01 with front x=3 (19) gap-filled (doubted)', ...camera(block(FRONT, LEFT, RIGHT, { straight: { drop: [[3, 10]] } })), truth: 291,
      check: 'total_ok', expect: '291, "up to 292"' },
    { id: 'FR21 S21 with the sides framed differently: 3x3 of 20s, CORNER photo, declared 3 x 3',
      views: { straight: S([20, 20, 20]), left: S([20, 20, 20], { shift: 1 }), right: S([20, 20, 20], { shift: 2 }) }, headings: CAMERA,
      extras: { ...syntheticCorner(3, 3), ...declared(3, 3, { interior: 'unknown' }) }, truth: 180, check: 'total_ok',
      expect: '180: the sides repeat the front, settled by the CORNER photo and the declaration, and count for H (Decision 3 (a))' },
  ];
}

/** One case through the Worker build `w`; rule: Partial<RuleOptions> to override the defaults (Decision 3 options). */
export function runRuleCase(w, c, rule = undefined) {
  const extras = { ...(c.extras ?? {}), ...(rule ? { rule } : {}) };
  return replayViews(w, c.views, c.headings, capturesFor('captured_still', c.headings), extras);
}

export function ruleSummary(result) {
  const b = result.block, inv = b.inventory;
  return { status: b.status, total: b.total_trays, withheld_reason: inv.withheld_reason, rule_height: b.rule?.height ?? null,
    rule_partner: b.rule?.partner ?? null, counted: inv.counted_trays, assumed: inv.assumed_trays, rule_trays_range: inv.rule_trays_range ?? null,
    // The printed total range: the estimate with the rule stacks moved across their cover-tray range.
    estimated_range_by_rule: inv.rule_trays_range && inv.estimated_total !== null
      ? inv.rule_trays_range.map(t => inv.estimated_total - inv.rule_trays + t) : null,
    doubted_low_up_to: inv.doubted_low_up_to ?? null, two_photo_stacks: inv.two_photo_stacks ?? null, rescan_view: result.rescan.recommended_view,
    provisional: b.rule?.provisional ?? inv.provisional ?? null };
}

/** The judge for rule cases: replay_benchmark's checks plus 'in_range' (the truth inside the printed total range). */
export function judgeRule(check, s, truth) {
  if (check === 'in_range') return s.total !== null && s.estimated_range_by_rule !== null
    && truth >= s.estimated_range_by_rule[0] && truth <= s.estimated_range_by_rule[1];
  return judge(check, s, truth);
}
