# Individual-tray photo intake — 2026-09-15

14 attachments, 6 byte-unique images. Source bytes retained unchanged with
SHA-256 and attachment-to-file mapping in [manifest.json](manifest.json).
This is local annotation preparation, not fresh inference, retraining or an
accuracy result. No backend deployment or APK change.

| Archive | Attachments | Visual review | Use |
| --- | --- | --- | --- |
| [Image 1](image-01.jpg) | 1,7,8,14 | Four foreground trays visibly contain eggs; background stacks clipped | Draft foreground reference |
| [Image 2](image-02.jpg) | 2,9 | Four foreground trays visibly contain eggs, low angle | Draft foreground reference |
| [Image 3](image-03.jpg) | 3,10 | Strong motion/defocus blur | Keep for capture-quality failure review |
| [Image 4](image-04.jpg) | 4,11 | One central egg-containing tray from above; other tray objects at edges | Draft central reference |
| [Image 5](image-05.jpg) | 5,12 | Similar central tray, different capture | Draft central reference |
| [Image 6](image-06.jpg) | 6,13 | Loaded stacks, nested empty-looking stacks, sparse contents and shells | Needs layer and occupancy review |

[Draft annotation JSON](foreground-annotations.draft.json) records ten selected
foreground tray observations across four photos, with approximate manual xyxy
boxes. These are repeated observations, **not ten distinct physical trays**.
Background objects are not exhaustively labelled, so annotation_complete and
training_ready are false. Do not upload these as fully labelled detector images:
unlabelled background trays would become erroneous negative examples. Complete
all visible-object labels or use reviewed foreground crops before training.

Filled means contains eggs, including partially filled trays; it is not an egg
quantity or all-slots-filled label. Shell-only trays must not be labelled filled
merely because white shell fragments are visible. The room image cannot prove
hidden layer occupancy or how many nested empty trays are present. No whole-room
ground-truth count is assigned. These captures are not assumed to be the original
84/90/87 triplet or the unchanged 100-filled-tray arrangement.

All photos stay in one provisional capture-session group to prevent similar
views or duplicates leaking across training and held-out evaluation. Splits are
unassigned; this is development data. Global Laplacian variance in the manifest
is descriptive, not a calibrated blur acceptance threshold. Image 3 is visibly
blurred and has variance10.91 versus97.76 for the clearer low-angle image2.

Next: review foreground box extents, annotate complete physical tray instances
and distinguish intact eggs from shell-only/unknown contents in image6. Obtain
physical counts for its small stacks before claiming count accuracy. Then run
traceable existing-model inference on these photos and compare matched instances.
No model was retrained in this intake. More diverse reviewed stack scenes remain
necessary before a retraining/validation claim.
