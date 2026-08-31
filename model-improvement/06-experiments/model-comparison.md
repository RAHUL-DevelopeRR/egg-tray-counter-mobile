# Architecture comparison

| Approach | Strength | Known risk | Test decision |
|---|---|---|---|
| Individual tray detection | Existing labels and deployment path | repetitive/overlapping tiny targets; viewpoint sensitivity | retain as controlled data-quality baseline |
| Stronger detector / NAS | may improve small-object recall | cannot repair inconsistent labels | run only after cleaned frozen version |
| Higher resolution / tiling | preserves distant tray boundaries | duplicate detections and latency | compare on same holdout with merge audit |
| Stack-face + periodicity | uses strong repeated horizontal structure | needs good face rectification and separate adjacent stacks | highest-priority alternative |
| Direct count regression | directly optimizes count | weak interpretability and likely scene memorization | defer until at least 240 counted scenes exist |
| View-specific models | targets proven view shift | triples maintenance and data requirement | use only if balanced universal model fails |

The existing Python backend already implements stack-face rectification and horizontal periodicity counting. That makes experiment F cheaper and more auditable than adding a new regression network. It is not production evidence yet: the current production Worker bypasses that Python pipeline and the stack-face review queue has zero human-approved tasks.
