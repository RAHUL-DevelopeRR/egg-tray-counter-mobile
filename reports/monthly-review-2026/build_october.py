"""Build the October 2026 monthly review and the five October weekly progress reports (DOCX).

Facts come from october-2026-weeks.json: extracted on 3 November 2026 from PROGRESS.md, the git history and the
reports each entry links, every measured number with its source. The monthly review condenses the same facts.
PDFs: python render_review_pdfs.py <the DOCX names printed here>.

  python build_october.py
"""

import json
from pathlib import Path

from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.shared import Inches

from build_reviews import OUT, ROOT, add_text, base, photo_pair, table

PREPARED = "3 November 2026"
WEEKS = json.loads((OUT / "october-2026-weeks.json").read_text(encoding="utf-8"))["weeks"]

# The PDF renderer uses the standard Times faces (WinAnsi): characters outside it would print as boxes.
_PLAIN = {"→": " to ", "≥": ">=", "≤": "<=", "≈": "~", "−": "-", " ": " ", " ": " "}


def clean(text):
    text = "".join(_PLAIN.get(ch, ch) for ch in str(text)).replace("->", " to ").replace("  ", " ")
    return text.encode("cp1252", errors="replace").decode("cp1252")


def bullets(doc, items):
    for item in items:
        add_text(doc, "• " + clean(item))


def photo_single(doc, file, caption):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.add_run().add_picture(str(ROOT / file), width=Inches(4.6))
    add_text(doc, clean(caption))


def figures(doc, figs):
    if len(figs) >= 2:
        photo_pair(doc, figs[0]["path"], figs[1]["path"], (clean(figs[0]["caption"]), clean(figs[1]["caption"])))
    elif figs:
        photo_single(doc, figs[0]["path"], figs[0]["caption"])


def weekly(w):
    n = w["week"]
    d = base("October", title="WEEKLY PROGRESS REPORT", period=f"OCTOBER 2026  •  WEEK {n} ({w['dates'].upper()})",
             prepared=f"{PREPARED} from the project record", footer_text=f"EG-Counter  •  October 2026  •  Week {n}")
    d.add_heading("1. Summary of the Week", 1)
    add_text(d, clean(w["summary"]))
    add_text(d, "Phase: " + clean(w["phase"]) + ".")
    d.add_heading("2. Work Completed This Week", 1)
    for i, item in enumerate(w["work"], 1):
        d.add_heading(f"2.{i} " + clean(item["title"]), 2)
        add_text(d, clean(item["detail"]))
    if w["results"]:
        d.add_heading("3. Measured Results", 1)
        table(d, ["Measurement", "Value", "What it shows"],
              [(clean(r["item"]), clean(r["value"]), clean(r["meaning"])) for r in w["results"]])
        add_text(d, "None of these figures is a physical recount of trays: the references are handwritten labels, counts "
                    "made by eye from photos, or software checks, as each row says.")
    section = 4 if w["results"] else 3
    if w["figures"]:
        d.add_heading(f"{section}. Photo Evidence", 1)
        figures(d, w["figures"])
        section += 1
    d.add_heading(f"{section}. Challenges Faced", 1)
    bullets(d, w["challenges"])
    d.add_heading(f"{section + 1}. Plan for the Next Week" if n < 5 else f"{section + 1}. Plan for November", 1)
    bullets(d, w["next_week"])
    d.add_heading(f"{section + 2}. Status at the End of the Week", 1)
    add_text(d, clean(w["versions_end_of_week"]))
    add_text(d, "Evidence: " + clean("; ".join(w["evidence"])) + ".")
    name = f"October_2026_Week_{n}_Progress_Report.docx"
    d.save(OUT / name)
    return name


def october():
    d = base("October", prepared=PREPARED)
    d.add_heading("1. Monthly Progress Summary", 1)
    add_text(d, "October moved EG-Counter from counting single photos to counting a whole block of tray stacks from a "
                "front photo and two side photos. A block model, a guided camera, network retries, per-phone approval "
                "keys and a same-face guard were built. Version 0.4.12 of the app now runs on the farm's Redmi phone "
                "against the test (staging) server. The first test on 52 hand-labelled farm photos, and the first "
                "warehouse scans, showed close counts on close, straight-on photos and large undercounts on angled or "
                "distant photos.")
    add_text(d, "Current phase: field rollout on the test server. No physical recount of trays exists yet. Every "
                "accuracy figure in this review compares the app with handwritten labels or with counts made by eye "
                "from photos, never with trays counted on site.")

    d.add_heading("2. Work Completed This Month", 1)
    d.add_heading("2.1 First test on 52 hand-labelled farm photos (1-7 October)", 2)
    add_text(d, "The user sent 52 farm photos with tray totals written on them by hand. The unchanged production "
                "model (Roboflow projec-mutta/2) was run on every photo without seeing the labels: 5 of 52 were exact, "
                "the mean absolute error (MAE) was 45.1 trays, and the model counted 2,839 trays against 5,041 labelled. "
                "Straight-on photos where one face fills the frame were usually close (12 of 18 within 5%); angled, "
                "corner and distant photos all failed (0 of 16 and 0 of 5 within 5%). An experimental 3D photo-matching "
                "service on AWS matched picture points between two photos but identified no trays and gave no count.")
    d.add_heading("2.2 Counting a whole block from three photos (8-14 October)", 2)
    add_text(d, "A block model combines the front photo (width and stack heights) with the side photos (depth), "
                "computes the hidden inner stacks, and draws the block in 3D on the phone. A new 'walk' layer counter "
                "was exact on 51 of 53 reference stacks (the older method: 40 of 53; these are development photos). "
                "A blind manual-count screen stores the operator's own count next to each scan. The camera screen was "
                "rebuilt, and uploads were made to survive the weak Jio connection (IPv6 lost 40-66% of packets to the "
                "server address). On the Redmi phone, a real 99-tray block was counted as 20/20/20/20/19 = 99 in 25 s.")
    d.add_heading("2.3 First warehouse scans and counting fixes (13-14 October)", 2)
    add_text(d, "Seven warehouse scans arrived on 13 October, none with an on-site count. On a close 4 x 3 block the "
                "app gave 165 (105 seen + 60 computed) against 164 counted by eye from the photos. A far 5 x 4 corner "
                "block read about half the layers, and the app held its total back. On 26 October the far-block "
                "comparison was corrected: it had set assumed trays against assumed trays, so it does not measure "
                "detector misses. The counting rules were then fixed: merged face readings, a one-layer disagreement "
                "gives 'estimated', bounded gap filling, a step-closer request and one result status per scan.")
    d.add_heading("2.4 Version 0.4.12: approved phones and resumable scans (15-28 October)", 2)
    add_text(d, "Each phone now creates its own key, and an administrator approves it. A scan interrupted by the "
                "network can be resumed instead of being counted again. All automated tests passed (Worker 111/111, "
                "app 167/167). An offline check of the counting rules on the labelled photos gave 10 accepted label "
                "clusters (9 exact, 1 wrong: 78 for 80) and 12 withheld, on photos the rules were tuned on. After a "
                "move to a new laptop (26 October), 0.4.12 went to the test server in observe mode, and the app was "
                "signed with a new release key.")
    d.add_heading("2.5 The app on the farm phone and the same-face guard (29-31 October)", 2)
    add_text(d, "App 0.4.12 was installed on the Redmi Note 9 Pro and approved on the test server. A network test on "
                "Jio LTE passed 20 of 20 checks over IPv4 and over IPv6, and 3 of 3 photo uploads. On eight sets of "
                "earlier field photos, the server's stack counts equalled the eye count on 9 of 10 close, straight-on "
                "stacks. But three front photos of block L-100, sent as front, left and right, made the server report "
                "500 'estimated' for a 100-tray block. A same-face guard, using the phone's turn sensor, was built and "
                "tested (Worker 122/122, app 176/176) but not yet deployed.")
    d.add_heading("2.6 Photo evidence and measured counts", 2)
    table(d, ["Measurement", "Reference used", "App / model result", "What it shows"], [
        ("52 hand-labelled farm photos (7 Oct)", "Handwritten totals, 5,041 trays", "2,839 trays; 5/52 exact; MAE 45.1", "Large undercount overall; not a physical recount"),
        ("Straight-on photos, one face filling the frame", "Handwritten totals", "12/18 within 5% (median 4.2%)", "Close when the photo is good"),
        ("Angled, corner or multi-block photos", "Handwritten totals", "0/16 within 5% (median 70.2%)", "Camera angle causes the large errors"),
        ("Walk counter, 53 reference stacks (9 Oct)", "Per-stack reference from labels and inspection", "51/53 exact (older method 40/53)", "Development photos, not new data"),
        ("Real 99-tray block on the Redmi (12 Oct)", "20/20/20/20/19 entered by hand", "20/20/20/20/19 = 99 in 25 s", "One block; photos used in tuning"),
        ("Close warehouse block 9b4c783e (13 Oct)", "164, counted by eye from photos", "165 (105 seen + 60 computed)", "Hidden stacks assumed; a cover tray counted"),
        ("Close straight-on faces, field sets (31 Oct)", "Eye count by three counting agents", "9/10 stacks equal, 1 off by one", "Visual reference, not physical"),
        ("Block L-100 with wrong photo roles (31 Oct)", "100 (handwritten and eye count)", "500 'estimated'", "Led to the same-face guard"),
    ])
    photo_pair(d, "reports/staging-block-20261008/phone-e2e/13-0.4.9-gallery-99-block.png", "reports/field-scans-20261013/app-vs-hand-3d.png", (
        "App 0.4.9 on the Redmi phone, 12 October: a real block counted as 20/20/20/20/19 = 99 trays in 25 s.",
        "First warehouse scans, 13 October: the app's 3D block next to a count made by eye from the same photos."))

    d.add_heading("3. Challenges Faced", 1)
    bullets(d, [
        "Angled, corner and distant photos fail badly: none of 16 angled and none of 5 distant block photos came within "
        "5%, and far cross-stacked faces read about half the layers.",
        "There is no physical truth yet: 0 physical counts by 31 October. The two stored manual counts cannot serve as "
        "truth (one came from a pre-filled form, the other was entered by the assistant).",
        "Wrong photo roles produced a confident wrong total (500 for 100 on L-100). The same-face guard is built but not "
        "yet on the server or the phone.",
        "Most trays of a big block are hidden inside it (W05: 196 visible of about 1,366), and careful eye counters "
        "disagreed widely on depth (L-115: 771 / 897 / 1,455).",
        "The move to a new laptop lost the test server's admin token, old APKs and the signing key. The new release key "
        "meant uninstalling 0.4.11, which deleted the phone's earlier history.",
    ])
    d.add_heading("4. Plan for November", 1)
    bullets(d, [
        "Deploy Worker 0.4.13 to the test server and install APK 0.4.13 on the Redmi; check the same-face guard with a "
        "real walk around a block.",
        "Photograph genuine front, left and right sets of real blocks and count their trays physically, stack by stack, "
        "with independent counters.",
        "Retrain the tray detector on far and cross-stacked faces, keeping some blocks aside to test it.",
        "Set a rule for the hidden inside of big blocks: declared by the operator, or shown as estimated with the "
        "visible share stated.",
        "Switch the test server from observe to enforce mode so that only approved phones are accepted.",
    ])
    d.add_heading("5. Overall Project Status", 1)
    table(d, ["Phase", "Status at 31 October", "Measured progress"], [
        ("Labelled field-photo baseline", "Measured against handwritten labels", "5/52 exact; frontal 12/18 within 5%"),
        ("Block (3D grid) counting", "Built; running on the test server", "99-block read 20/20/20/20/19 on the phone"),
        ("Android app", "0.4.12 on the Redmi, test server", "Network test 20/20 on IPv4 and IPv6"),
        ("Phone approval (security)", "Observe mode on the test server", "Requests without a key refused (401)"),
        ("Same-face guard (0.4.13)", "Built and tested; not deployed", "Worker 122/122, app 176/176 tests"),
        ("Exact warehouse inventory", "Not verified", "0 physical counts"),
    ])
    d.add_heading("5.1 Overall Progress", 2)
    add_text(d, "October delivered the whole counting chain for a block of stacks, from guided capture to the block "
                "drawing and per-phone approval, running on the farm's phone against the test server. Accuracy on real "
                "blocks is still unmeasured, because every reference so far is a handwritten label or a count made by "
                "eye. Overall completion cannot be quantified. The next milestone is a field round with genuine front, "
                "left and right photos and independent physical per-stack counts. Work from 1 November (release 0.5.0, "
                "the photo validation and Plan 4) belongs to the November review.")
    add_text(d, "Evidence: PROGRESS.md entries 1-31 October; reports/field-labelled-20261007, staging-block-20261008, "
                "network-20261012, field-scans-20261013, eval-20261015, experiment-walk-fill-20261015, "
                "mutaa-manual-vs-backend-20261031 and rollout-20261031; docs/SCAN_JOBS_AND_DEVICES.md; the weekly "
                "reports for October and october-2026-weeks.json.")
    d.save(OUT / "October_2026_Monthly_Progress_Review.docx")
    return "October_2026_Monthly_Progress_Review.docx"


if __name__ == "__main__":
    names = [october()] + [weekly(w) for w in WEEKS]
    print(" ".join(names))
