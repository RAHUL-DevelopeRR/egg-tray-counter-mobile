# Annotation policy

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
