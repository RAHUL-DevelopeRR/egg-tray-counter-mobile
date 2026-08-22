# Label Studio setup report

Status: **installed and startup-verified** on 2026-08-21.

## Installation

- Label Studio: `1.23.0`
- Python: `3.12.13`
- Isolated environment: `tools/labelstudio/.venv`
- Application data and SQLite database: `tools/labelstudio/data`
- Backend environment isolation: verified; `label-studio` is absent from the project backend `.venv`.

The first package-install attempt failed because pip tried to write built wheels
under the sandboxed Windows AppData cache (`WinError 5`). The successful retry
used `tools/labelstudio/.pip-cache` and `tools/labelstudio/tmp`. No global Python
installation or backend environment was changed.

## Runtime verification

Label Studio was started on `127.0.0.1:8080` with its database and local-file
roots inside the project. `GET http://127.0.0.1:8080/health` returned:

```json
{"status": "UP"}
```

The verification server was then stopped and port 8080 was confirmed closed.
The initialized database contains zero projects and zero tasks, so no review
queue was silently imported or duplicated.

## Review queues

The priority queue is `datasets/stack_face_review`:

- 137 tasks
- 264 heuristic `stack_face` polygon suggestions
- Label interface: `datasets/stack_face_review/label_config.xml`
- Import file: `datasets/stack_face_review/tasks.json`
- Human review is mandatory; suggestions are not ground truth.

The original `datasets/review` queue remains available:

- 299 `egg_tray` review tasks
- Label interface: `datasets/review/label_config.xml`
- Import file: `datasets/review/tasks.json`

## Run

From the project root:

```powershell
.\scripts\run_label_studio.ps1
```

This defaults to `stack_face_review`. To serve the original queue instead:

```powershell
.\scripts\run_label_studio.ps1 -ReviewSet review
```

Create one project in the UI, paste the printed label configuration into the
labeling interface, and import the printed `tasks.json` path once. The launcher
intentionally does not auto-import tasks, preventing duplicate imports on later
runs. It binds to localhost by default and is a development annotation service,
not an internet-facing production deployment.

