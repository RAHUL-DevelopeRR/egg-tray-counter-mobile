# Field scenes — October 2026

`labelled-20261007/` holds the 52 WhatsApp photos with handwritten totals
(development set; see reports/field-labelled-20261007/).

The block field test (Day 2 of the 3-day scope) goes here as one folder per
block, following docs/FIELD_TEST_BLOCK_20261009.md:

    field-2026-10/
      tray.csv              one-time tray measurements
      counts.csv            one row per stack per block (x, y, filled, empty, missing)
      B01/
        straight.jpg        X face, square-on, fills the frame
        left.jpg            left Y face
        right.jpg           right Y face
        result.png          app result screenshot (optional)
      B02/ ...

Rules: original camera files only (no WhatsApp); nothing moves between the
three photos; number stacks x left→right as seen from STRAIGHT, y front→back,
both from 0. The on-site count in counts.csv is the only ground truth; never
derive it from the photos or the app.
