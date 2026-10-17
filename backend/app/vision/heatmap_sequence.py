"""Research layer sequence evidence. Never certifies inventory or egg occupancy.

All y coordinates are pixels in the rectified heatmap. Endpoint centres must be
observed layer centres, not the image border or a tray rim. RF predictions remain
diagnostics: another learned detector does not independently prove a missing row.
"""
from __future__ import annotations

import numpy as np
from scipy.signal import find_peaks


def solve_layer_sequence(
    probabilities, *, band_centres=(), band_hypotheses=(), rf_detections=(),
    endpoints=None, quality=None, calibrated_height=None,
    peak_threshold=.5, spacing_tolerance=.25,
):
    """Enumerate pitch-constrained paths without accepting an expected truth count.

    Bands use analyze_rims' pitch_px/centres/support fields. Reconstruction additionally
    requires explicitly reviewed semantics='tray_layer_centres', independent=True,
    strong band support AND independent complete endpoints or calibrated height.
    quality.acceptable must be explicitly True; unknown quality stays unresolved.
    calibrated_height is calibrated_height_evidence output; no arbitrary scalar count.
    """
    p = np.asarray(probabilities, dtype=float)
    if p.ndim != 1 or len(p) < 3 or not np.isfinite(p).all() or ((p < 0) | (p > 1)).any():
        raise ValueError('A finite 1D probability array in [0, 1] is required')
    if not 0 < peak_threshold <= 1 or not 0 < spacing_tolerance < .5:
        raise ValueError('Invalid peak threshold or spacing tolerance')
    height = len(p)

    def positions(values):
        result = np.asarray(values, dtype=float)
        if result.ndim != 1 or not np.isfinite(result).all() or ((result < 0) | (result >= height)).any():
            raise ValueError('Centres must be finite in-frame heatmap pixel coordinates')
        return np.sort(result)

    bands = positions(band_centres)
    rf = positions([d.get('y', (d['bbox'][1] + d['bbox'][3]) / 2)
                    if isinstance(d, dict) and 'bbox' in d else
                    d['y'] if isinstance(d, dict) else d for d in rf_detections])
    endpoints = endpoints or {}
    anchors = {}
    for name in ('top', 'base'):
        evidence = endpoints.get(name) or {}
        if 'centre_px' in evidence:
            positions([evidence['centre_px']])
        support = evidence.get('support', 0)
        if not np.isfinite(support) or not 0 <= support <= 1:
            raise ValueError('Endpoint support must be in [0, 1]')
        if (evidence.get('visible') is True and evidence.get('kind') == 'layer_center'
                and support >= .75 and 'centre_px' in evidence):
            anchors[name] = float(evidence['centre_px'])
    complete = len(anchors) == 2
    if complete and anchors['base'] <= anchors['top']:
        raise ValueError('Base layer centre must follow top layer centre')
    strong_endpoints = complete and all(endpoints[n].get('independent') is True for n in anchors)
    height_candidates = ()
    if calibrated_height:
        if not calibrated_height.get('profile_id') or not calibrated_height.get('version'):
            raise ValueError('Height evidence requires a versioned calibration profile')
        height_candidates = tuple(calibrated_height.get('count_candidates', ()))
        if any(not isinstance(n, int) or isinstance(n, bool) or n < 1 for n in height_candidates):
            raise ValueError('Height count candidates must be positive integers')

    raw_peaks = find_peaks(p, height=peak_threshold, plateau_size=True)[0].tolist()
    # scipy excludes endpoints, but an observed layer centre may be on a crop edge.
    if p[0] >= peak_threshold and p[0] > p[1]:
        raw_peaks.insert(0, 0)
    if p[-1] >= peak_threshold and p[-1] > p[-2]:
        raw_peaks.append(height - 1)
    hypotheses = []
    for source in band_hypotheses:
        pitch, support = float(source['pitch_px']), float(source.get('support', 0))
        if not np.isfinite(pitch) or not 1 <= pitch < height or not np.isfinite(support) or not 0 <= support <= 1:
            raise ValueError('Band pitch/support is outside its valid range')
        centres = positions(source.get('centres', bands))
        hypotheses.append({**source, 'pitch_px': pitch, 'support': support,
                           'centres': centres.tolist(), 'source': 'bands'})
    if len(raw_peaks) >= 3:
        pitch = float(np.median(np.diff(raw_peaks)))
        if pitch >= 1 and not any(abs(h['pitch_px'] - pitch) < .5 for h in hypotheses):
            hypotheses.append({'pitch_px': pitch, 'centres': bands.tolist(), 'support': 0,
                               'source': 'heatmap_spacing'})

    alternatives = []
    for hypothesis in hypotheses:
        pitch = hypothesis['pitch_px']
        tolerance = max(.5, pitch * spacing_tolerance)
        # Non-maximum suppression permits one winner per physical neighbourhood.
        winners = []
        suppressed = []
        for index in sorted(raw_peaks, key=lambda i: (-p[i], i)):
            if any(abs(index - other) < pitch * .5 for other in winners):
                suppressed.append(index)
            else:
                winners.append(index)
        winners.sort()
        reasons = []
        rows = []
        if winners:
            start = anchors.get('top', float(winners[0]))
            end = anchors.get('base', float(winners[-1]))
            span = (end - start) / pitch
            intervals = max(0, round(span))
            if abs(span - intervals) > spacing_tolerance:
                reasons.append('endpoint_span_conflicts_with_pitch')
            grid = [start + k * pitch for k in range(intervals + 1)]
            used = set()
            independent_bands = (hypothesis.get('independent') is True
                                 and hypothesis.get('semantics') == 'tray_layer_centres'
                                 and hypothesis['support'] >= .75)
            for position_index, y in enumerate(grid, 1):
                eligible = [i for i in winners if i not in used and abs(i - y) <= tolerance]
                if eligible:
                    index = max(eligible, key=lambda i: (p[i], -abs(i - y)))
                    used.add(index)
                    rows.append({'position_index': position_index, 'y_px': float(index), 'probability': float(p[index]),
                                 'source': 'heatmap', 'occupancy': 'unknown'})
                elif (independent_bands and
                      any(abs(c - y) <= tolerance for c in hypothesis['centres']) and
                      (strong_endpoints or (len(height_candidates) == 1 and height_candidates[0] == len(grid)))):
                    rows.append({'position_index': position_index, 'y_px': float(y), 'probability': None,
                                 'source': 'independent_band_reconstruction', 'occupancy': 'unknown'})
                else:
                    reasons.append('missing_position_without_independent_support')
            unexplained = [i for i in winners if i not in used]
            if unexplained:
                reasons.append('unexplained_heatmap_peaks')
            if len(rows) > 1 and any(abs((b['y_px']-a['y_px'])/pitch-1) > spacing_tolerance
                                     for a, b in zip(rows, rows[1:])):
                reasons.append('irregular_layer_spacing')
            if height_candidates and len(grid) not in height_candidates:
                reasons.append('calibrated_height_conflict')
        else:
            grid, unexplained = [], []
            reasons.append('no_strong_heatmap_peaks')
        rf_alignment = float(np.mean([any(abs(c-r['y_px']) <= tolerance for c in rf)
                                      for r in rows])) if len(rf) and rows else None
        alternatives.append({'pitch_px': pitch, 'source': hypothesis['source'],
                             'band_feature': hypothesis.get('feature'),
                             'band_count': hypothesis.get('count'),
                             'nominal_span_count': round(height / pitch),
                             'band_support': hypothesis['support'], 'sequence_count': len(grid),
                             'observed_count': sum(r['source']=='heatmap' for r in rows),
                             'ordered_layer_candidates': rows, 'suppressed_peaks': suppressed,
                             'unexplained_peaks': unexplained, 'rf_alignment': rf_alignment,
                             'compatible': not reasons, 'reasons': sorted(set(reasons))})

    compatible = [a for a in alternatives if a['compatible']]
    counts = {a['sequence_count'] for a in compatible}
    reasons = []
    if (quality or {}).get('acceptable') is not True:
        reasons.append('quality_unknown_or_insufficient')
    if not complete:
        reasons.append('top_or_base_layer_centre_unresolved')
    if len(counts) != 1:
        reasons.append('pitch_or_sequence_unresolved')
    selected = max(compatible, key=lambda a: (a['observed_count'], a['band_support'])) if compatible else None
    candidate = selected is not None and not reasons
    return {'schema_version': 'heatmap_sequence_v1', 'status': 'candidate' if candidate else 'unresolved',
            'selected_count': selected['sequence_count'] if candidate else None,
            'ordered_layer_candidates': selected['ordered_layer_candidates'] if selected else [],
            'heatmap_peaks': [{'y_px': i, 'probability': float(p[i])} for i in raw_peaks],
            'alternatives': alternatives, 'reasons': reasons, 'quality': quality or {},
            'band_centres': bands.tolist(), 'rf_centres': rf.tolist(),
            'endpoints': endpoints, 'occupancy': 'unknown', 'verified': False,
            'eligible_inventory_count': None}
