import numpy as np

from app.vision.cross_stack import CrossStackParams, cross_stack, read_layer


def _layer_image(rows, *, cell=20, pitch=30, width=6 * 20 + 40, top=80):
    """Green plastic strip with one row of white 'eggs' per layer; rows lists the eggs per layer, top
    to bottom."""
    height = top + pitch * len(rows) + 80
    image = np.zeros((height, width, 3), np.uint8)
    image[:, :] = (110, 110, 110)  # grey wall and floor around the stack
    image[top : top + pitch * len(rows), 20 : 20 + 6 * cell] = (40, 160, 40)  # green plastic (BGR)
    for k, eggs in enumerate(rows):
        y = top + k * pitch + pitch // 2
        offset = (6 - eggs) * cell // 2
        for e in range(eggs):
            x = 20 + offset + e * cell + cell // 2
            image[y - 7 : y + 7, x - 6 : x + 6] = (235, 235, 235)
    column = {
        "column": 1,
        "x_min": 20.0,
        "x_max": float(20 + 6 * cell),
        "y_first": float(top + pitch // 2),
        "y_last": float(top + (len(rows) - 1) * pitch + pitch // 2),
        "pitch_px": float(pitch),
        "walk_count": len(rows),
    }
    return image, column


def test_alternating_rows_give_the_parity_of_the_layer_count():
    image, column = _layer_image([5, 6] * 5)  # ten layers: 5 at the top, 6 at the bottom
    result = cross_stack(image, [column])[0]
    assert result["readable"] is True
    assert (result["top"]["type"], result["bottom"]["type"], result["parity"]) == (5, 6, "even")
    assert result["walk_parity_ok"] is True and result["doubts"] == []


def test_a_count_that_breaks_parity_is_doubted_never_corrected():
    image, column = _layer_image([5, 6] * 5)
    column = {**column, "walk_count": 9}
    result = cross_stack(image, [column])[0]
    assert "parity_mismatch" in result["doubts"] and result["walk_parity_ok"] is False
    assert "count" not in result  # parity never proposes a count


def test_an_egg_layer_beyond_the_detector_end_is_found():
    image, column = _layer_image([6, 5, 6, 5, 6, 5])
    boxed = {
        **column,
        "y_first": column["y_first"] + 30.0,
        "walk_count": 5,
    }  # the detector missed the top layer
    result = cross_stack(image, [boxed])[0]
    assert result["unboxed_above"] == 1 and "unboxed_egg_layer" in result["doubts"]


def test_partial_and_empty_layers_are_not_typed():
    image, column = _layer_image([3, 0, 6])
    hsv = __import__("cv2").cvtColor(image, __import__("cv2").COLOR_BGR2HSV)
    params = CrossStackParams()
    partial = read_layer(hsv, column["y_first"], 30.0, 20, 140, params)
    empty = read_layer(hsv, column["y_first"] + 30.0, 30.0, 20, 140, params)
    assert (partial["occupancy"], partial["type"]) == ("partial", None)
    assert (empty["occupancy"], empty["type"]) == ("empty", None)


def test_degenerate_input_is_unreadable_without_raising():
    assert cross_stack(None, [{"x_min": 0}])[0]["readable"] is False
    assert cross_stack(np.zeros((50, 50, 3), np.uint8), ["not a dict"])[0]["readable"] is False
    assert cross_stack(np.zeros((50, 50, 3), np.uint8), []) == []
