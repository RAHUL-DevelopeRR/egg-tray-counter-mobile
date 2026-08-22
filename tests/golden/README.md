# Golden regression scenes

Each directory must contain `left.jpg`, `right.jpg`, `straight.jpg`, and
`ground_truth.json`. A scene is accepted only when the total and every stack
count are exactly correct. Add real, consented scenes only; photographs are not
retained by the normal application flow.

```json
{
  "scene_id": "golden_001",
  "total_trays": 126,
  "stacks": [
    {"physical_stack_id": "stack_01", "tray_count": 18}
  ]
}
```
