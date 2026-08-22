from __future__ import annotations

from app.vision.layer_signal import count_layers, estimate_pitch, horizontal_structure_signal
from tests.conftest import synthetic_stack


def test_signal_pitch_and_layer_count(test_settings) -> None:
    image = synthetic_stack(layers=18, width=320, height=480)
    signal = horizontal_structure_signal(image, test_settings.side_margin_fraction)
    pitch, strength = estimate_pitch(signal, test_settings.min_pitch_px, test_settings.max_pitch_px)
    result = count_layers(image, test_settings)
    assert pitch is not None
    assert 20 <= pitch <= 32
    assert strength > 0.1
    assert result.tray_count == 18
    assert result.inferred_internal_layers == 0
    assert result.quality >= 0.30


def test_internal_gap_can_be_inferred(test_settings) -> None:
    image = synthetic_stack(layers=12, width=320, height=480)
    # Erase one interior boundary; the lattice should recover one supported internal rail.
    pitch = (480 - 76) / 11
    position = round(38 + pitch * 6)
    image[position - 5 : position + 6, :] = (54, 142, 70)
    result = count_layers(image, test_settings)
    assert result.tray_count == 12
    assert result.inferred_internal_layers == 1
    assert result.inferred_internal_layers <= test_settings.max_inferred_layers
