from app.vision.block_model import build_block, render_boxes


def col(i, layers, pitch=40.0, boxes=None, span=None, gradient=None):
    return {"column": i, "model_boxes": layers if boxes is None else boxes,
            "span_count": layers if span is None else span, "walk_count": layers,
            "perspective_gradient": gradient, "pitch_px": pitch, "x_min": i * 100.0, "x_max": i * 100.0 + 80}


def face(n, layers=20):
    return [col(i, layers) for i in range(n)]


def test_five_by_four_block_from_three_faces():
    block = build_block(face(5), left=face(4), right=face(4))
    assert (block["width"], block["depth"]) == (5, 4)
    assert len([c for c in block["cells"] if c["status"] == "observed"]) == 5 + 3 + 3
    assert block["observed_trays"] == 11 * 20 and block["computed_trays"] == 9 * 20
    assert block["total_trays"] == 400
    assert block["faces_consistent"] is True and block["fully_observed"] is False


def test_single_row_block_is_fully_observed():
    block = build_block(face(5), left=face(1))
    assert block["fully_observed"] is True and block["total_trays"] == 100


def test_left_right_depth_disagreement_blocks_total():
    block = build_block(face(5), left=face(4), right=face(3))
    assert block["conflicts"][0]["reason"].startswith("depth differs")
    assert block["total_trays"] is None


def test_corner_height_conflict_blocks_total():
    block = build_block(face(2), left=[col(0, 20), col(1, 17)])   # left corner = last column = 17
    assert any("corner" in c["reason"] for c in block["conflicts"])
    assert block["total_trays"] is None


def test_recessed_front_column_marks_missing_and_promotes_stack_behind():
    straight = [col(0, 20), col(1, 18, pitch=30.0), col(2, 20)]
    block = build_block(straight, left=face(2))
    by = {(c["x"], c["y"]): c for c in block["cells"]}
    assert by[(1, 0)]["status"] == "missing" and by[(1, 0)]["layers"] == 0
    assert by[(1, 1)]["status"] == "observed" and by[(1, 1)]["layers"] == 18
    assert block["observed_trays"] == 3 * 20 + 18 and block["computed_trays"] == 20
    assert block["total_trays"] == 4 * 20 + 18


def test_one_inflated_pitch_column_does_not_recess_the_rest():
    straight = [col(0, 20), col(1, 20), col(2, 20), col(3, 20, pitch=60.0)]
    block = build_block(straight, left=face(1))
    assert all(c["status"] == "observed" for c in block["cells"][:3])
    assert block["total_trays"] == 80


def test_recessed_stack_with_no_room_behind_is_a_conflict_not_a_loss():
    straight = [col(0, 20), col(1, 18, pitch=30.0), col(2, 20)]
    block = build_block(straight, left=face(1))        # faces say depth 1
    assert block["total_trays"] is None
    assert any("no room" in c["reason"] for c in block["conflicts"])


def test_corner_recessed_on_one_face_only_is_a_conflict():
    straight = [col(0, 18, pitch=25.0), col(1, 20), col(2, 20)]    # STRAIGHT says corner set back
    block = build_block(straight, left=[col(0, 20), col(1, 20)])
    assert any("set back on one face only" in c["reason"] for c in block["conflicts"])
    assert block["total_trays"] is None


def test_face_seeing_a_stack_another_face_calls_missing_is_a_conflict():
    straight = [col(0, 20), col(1, 18, pitch=30.0)]    # (1,0) missing, (1,1) seen with 18
    # right says (1,1) missing, (0,1) seen with 16
    right = [col(0, 20), col(1, 16, pitch=30.0)]
    block = build_block(straight, right=right)
    assert block["total_trays"] is None
    assert any("disagree" in c["reason"] for c in block["conflicts"])


def test_two_faces_promoting_different_heights_into_one_cell_conflict():
    straight = [col(0, 20), col(1, 18, pitch=30.0), col(2, 20)]   # promotes (1,1)=18
    # LEFT: front corner is right-most; y=1 recessed -> promotes (1,1)=16
    left = [col(0, 16, pitch=30.0), col(1, 20)]
    block = build_block(straight, left=left)
    by = {(c["x"], c["y"]): c for c in block["cells"]}
    assert by[(1, 1)]["status"] == "conflict" and block["total_trays"] is None


def test_two_faces_promoting_the_same_height_agree():
    straight = [col(0, 20), col(1, 18, pitch=30.0), col(2, 20)]
    left = [col(0, 18, pitch=30.0), col(1, 20)]   # y=1 recessed on LEFT, promotes (1,1)=18 too
    block = build_block(straight, left=left)
    by = {(c["x"], c["y"]): c for c in block["cells"]}
    assert by[(1, 1)]["status"] == "observed" and by[(1, 1)]["layers"] == 18
    # observed (0,0),(2,0) = 40; missing (1,0),(0,1); promoted (1,1) = 18; computed (2,1) = 20
    assert block["total_trays"] == 40 + 18 + 20


def test_disagreeing_column_requests_rescan():
    block = build_block([col(0, 20), col(1, 20, span=23)], left=face(1))
    assert block["rescan_cells"] == [[1, 0]] and block["total_trays"] is None


def test_steep_perspective_requests_rescan():
    block = build_block([col(0, 20), col(1, 20, gradient=1.8)], left=face(1))
    assert block["rescan_cells"] == [[1, 0]] and block["total_trays"] is None
    assert build_block([col(0, 20), col(1, 20, gradient=1.3)], left=face(1))["total_trays"] == 40


def test_even_count_median_rounds_half_to_even():
    block = build_block([col(0, 19), col(1, 20)], left=[col(0, 20), col(1, 19)])
    assert block["typical_layers"] in (19, 20)   # 19.5 -> 20 (half-even); documented behaviour
    assert block["typical_layers"] == 20


def test_empty_faces_do_not_raise():
    block = build_block([], left=face(1))
    assert block["total_trays"] is None and block["cells"] == []
    block = build_block(face(2), left=[])
    assert block["total_trays"] is None


def test_render_boxes_skip_missing_cells():
    block = build_block([col(0, 20), col(1, 18, pitch=30.0)], right=face(2))
    assert all(b["layers"] > 0 for b in render_boxes(block))


def test_side_face_corner_with_steep_perspective_reports_its_reason():
    block = build_block(face(2), left=[col(0, 20), col(1, 20, gradient=2.5)])  # LEFT corner = last column
    reasons = [c["reason"] for c in block["conflicts"]]
    assert any("hold the phone level" in r and r.startswith("LEFT") for r in reasons)
    assert block["total_trays"] is None


def test_confident_rim_disagreement_requests_rescan_but_low_confidence_does_not():
    disagree = col(1, 20)
    disagree.update(rim_count=19, rim_confidence=0.9)
    block = build_block([col(0, 20), disagree], left=face(1))
    assert block["rescan_cells"] == [[1, 0]] and block["total_trays"] is None
    assert any("rim edges count 19" in c["reason"] for c in block["conflicts"])
    unsure = col(1, 20)
    unsure.update(rim_count=19, rim_confidence=0.2)
    assert build_block([col(0, 20), unsure], left=face(1))["total_trays"] == 40
    agree = col(1, 20)
    agree.update(rim_count=20, rim_confidence=0.9)
    assert build_block([col(0, 20), agree], left=face(1))["total_trays"] == 40
