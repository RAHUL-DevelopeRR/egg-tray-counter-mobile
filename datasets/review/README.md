# Label Studio review queue

This folder contains 299 generated review tasks. `tasks.json` references the
files in `images/`, and `label_config.xml` defines the `egg_tray` rectangle label.
The generated boxes are suggestions, not approved ground truth.

Label Studio 1.23.0 is installed in the isolated project environment. To serve
this original queue from the project root:

```powershell
.\scripts\run_label_studio.ps1 -ReviewSet review
```

In the Label Studio UI, create a project, use `label_config.xml` as its labeling
interface, and import `tasks.json`. Check every suggested box, remove duplicates,
fix loose/invalid geometry, and explicitly approve or reject each task before
exporting. Keep capture sessions together when assigning train/validation/test
splits.

Do not import `tasks.json` more than once into the same project. The launcher
only serves local files and does not import tasks automatically.

The current Roboflow version 2 includes only the 99 non-empty, tagged labels that
passed the automated upload path. Completing this queue requires human judgment
and is not claimed as finished.
