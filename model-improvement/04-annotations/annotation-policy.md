# Annotation policy

## Active warehouse expansion contract (2026-09-08)

For every warehouse image, `egg_tray` means one **individual physically distinguishable tray layer**, never a whole stack face. This supersedes the September 7 stack-face expansion experiment. Its three wh018/wh019/wh020 uploads remain isolated under `stack-face-only-20260907`; they require complete re-annotation before use in a tray-layer version. Do not rename a stack-face box and treat it as a corrected tray label. Frozen V2/V3/V4 and production are unchanged.

The 74 full-frame source images are NOT annotation-approved merely because three foreground crops were reviewed. Every foreground/background target must be checked, including borders and occlusion; crop annotations do not cover their full-frame parent. No automatic predictions may be promoted as ground truth without box-by-box review. Full-frame physical inventory truth and visible-object annotation counts are separate fields.

**Scope confirmed by user September 8: count only egg-filled trays.** Empty trays, including tightly nested stacks, are non-targets. Annotate every distinguishable egg-filled tray separately; never one box per stack, one box per egg, or two boxes for two faces of the same physical tray. If loading cannot be established visually, flag the region for review rather than inventing a label. A tray count times 30 is only egg capacity unless every tray is known full. Full-frame review is still incomplete; no new training is authorized until all requested gates are satisfied.

## Individual tray-layer detector

- Class: `egg_tray` means one physically distinguishable 30-egg tray layer.
- Draw one tight box around the visible tray layer/front boundary, not the whole multi-layer stack.
- Label a partial tray only when at least half of its tray boundary is visible and its identity is unambiguous.
- Do not invent boxes for fully occluded trays.
- Do not box individual eggs, empty holes, retail cartons, tray fragments, or background patterns.
- Adjacent trays must have separate boxes; duplicate boxes on the same tray are forbidden.
- Boxes may overlap because of perspective, but each box must correspond to one physical tray.

## Stack-face alternative

- Class: `stack_face` means one continuous visible face of one physical stack.
- Use a polygon enclosing only the face whose horizontal tray boundaries can be counted.
- Do not merge two stacks, even if touching.
- Record `stack_id` and independently counted `tray_count_gt` as metadata; never infer it from model output.

## Review and split rules

- Every generated/pre-annotation must be human approved.
- A reviewer must check missed trays, duplicates, fragments, and the partial-visibility rule.
- All views of a physical scene stay in one split.
- Acceptance scenes are never uploaded to a training version.
- Any disputed image is marked `ground_truth_uncertain` and excluded from count metrics until resolved.
