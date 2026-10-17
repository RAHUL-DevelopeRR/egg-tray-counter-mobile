import json

import numpy as np
import pytest

from app.vision.heatmap_sequence import solve_layer_sequence


def evidence(n=20, pitch=20):
    centres = np.arange(n) * pitch + pitch / 2
    y = np.arange(n*pitch)
    p = np.exp(-.5*((y[:, None]-centres)/1.2)**2).max(1)*.95
    ends = {name: {'visible': True, 'centre_px': float(c), 'support': .9,
                   'kind': 'layer_center', 'independent': True}
            for name, c in [('top', centres[0]), ('base', centres[-1])]}
    bands = [{'pitch_px': pitch*f, 'centres': centres.tolist(), 'support': .85,
              'independent': True, 'semantics': 'tray_layer_centres'} for f in (.5, 1, 2)]
    return p, ends, bands


def test_harmonics_remain_explicit_but_complete_twenty_is_one_candidate():
    p, ends, bands = evidence()
    r = solve_layer_sequence(p, band_hypotheses=bands, endpoints=ends, quality={'acceptable': True})
    assert r['status'] == 'candidate' and r['selected_count'] == 20
    assert {a['pitch_px'] for a in r['alternatives']} == {10, 20, 40}
    assert not r['verified'] and r['eligible_inventory_count'] is None
    assert all(row['occupancy'] == 'unknown' for row in r['ordered_layer_candidates'])
    json.dumps(r, allow_nan=False)


@pytest.mark.parametrize('count', [10, 19, 20, 40])
def test_solver_has_no_fixed_twenty_rule(count):
    p, ends, bands = evidence(count)
    r = solve_layer_sequence(p, band_hypotheses=bands, endpoints=ends, quality={'acceptable': True})
    assert r['selected_count'] == count


def test_nineteen_with_missing_base_stays_unknown():
    p, ends, bands = evidence()
    p[-20:] = 0
    ends['base'] = {'visible': False}
    r = solve_layer_sequence(p, band_hypotheses=bands, endpoints=ends, quality={'acceptable': True})
    assert r['status'] == 'unresolved' and r['selected_count'] is None
    assert len(r['heatmap_peaks']) == 19


def test_missing_peak_requires_independent_semantic_bands_and_endpoints():
    p, ends, bands = evidence()
    p[205:216] = 0
    r = solve_layer_sequence(p, band_hypotheses=bands, endpoints=ends, quality={'acceptable': True})
    assert r['selected_count'] == 20
    assert sum(row['source'] == 'independent_band_reconstruction' for row in r['ordered_layer_candidates']) == 1
    # Even exact RF centres cannot replace independent evidence.
    weak = [{**b, 'independent': False} for b in bands]
    r = solve_layer_sequence(p, band_hypotheses=weak, rf_detections=bands[1]['centres'],
                            endpoints=ends, quality={'acceptable': True})
    assert r['selected_count'] is None


def test_nearby_peaks_compete_and_cannot_inflate_the_count():
    p, ends, bands = evidence()
    p[14] = .7
    r = solve_layer_sequence(p, band_hypotheses=bands, endpoints=ends, quality={'acceptable': True})
    assert len(r['heatmap_peaks']) == 21 and r['selected_count'] == 20
    chosen = next(a for a in r['alternatives'] if a['pitch_px'] == 20)
    assert chosen['suppressed_peaks'] == [14]


def test_weak_heatmap_and_unknown_quality_cannot_return_selected_count():
    p, ends, bands = evidence()
    for probabilities, quality in [(p*.3, {'acceptable': True}), (p, {}), (p, {'acceptable': False})]:
        r = solve_layer_sequence(probabilities, band_hypotheses=bands, endpoints=ends, quality=quality)
        assert r['status'] == 'unresolved' and r['selected_count'] is None


def test_bad_inputs_are_rejected_and_rim_is_not_a_layer_endpoint():
    p, ends, bands = evidence()
    for bad in [[0, float('nan'), 1], [-.1, .2, .3], [[0, .5, 1]]]:
        with pytest.raises(ValueError):
            solve_layer_sequence(bad)
    ends['top']['kind'] = 'rim'
    assert solve_layer_sequence(p, endpoints=ends, quality={'acceptable': True})['selected_count'] is None


def test_calibrated_height_conflict_keeps_count_unresolved():
    p, ends, bands = evidence()
    r = solve_layer_sequence(p, band_hypotheses=bands, endpoints=ends, quality={'acceptable': True},
                            calibrated_height={'profile_id': 'fixture', 'version': '1', 'count_candidates': [19]})
    assert r['selected_count'] is None
