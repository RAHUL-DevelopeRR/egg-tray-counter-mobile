# Stack-face pre-annotation review queue

This queue is separate from `datasets/review` and does not alter the canonical
`egg_tray` labels. `tasks.json` contains rectangular polygon suggestions created
by vertically clustering existing tray boxes. They are deliberately assigned low
confidence and are **not ground truth**.

To regenerate the queue:

```powershell
python .\ml\preannotate_stack_faces.py
```

Label Studio 1.23.0 is installed in an isolated project environment. From the
project root, start it with this queue selected:

```powershell
.\scripts\run_label_studio.ps1
```

Create a new Label Studio project, paste `label_config.xml` into its labeling
interface, and import `tasks.json` once. For every image, correct the polygon boundary,
split envelopes that combine separate physical stacks, merge fragments belonging
to one stack, add missed stacks, and delete false suggestions. Images with no
suggestion still require review. Export only after a human has checked every task.

The heuristic uses no scene identity, depth, or multi-view correspondence. Its
output must not be used to claim exact-count accuracy or to train a production
model without review.
