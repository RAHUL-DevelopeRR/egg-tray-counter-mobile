"""Reproducible two-view geometry diagnostic; never certifies tray inventory.

Run with two photo paths and an output directory. Unknown intrinsics are swept,
not silently treated as calibration. No count is inferred from point count.
"""
import hashlib
import json
from io import BytesIO
from PIL import Image

import cv2
import numpy as np


def exif_focal_pixels(raw, width, height):
    """Estimate intrinsics from EXIF; this is not a camera calibration."""
    try:
        with Image.open(BytesIO(raw)) as image:
            tags = image.getexif().get_ifd(34665)
            focal = float(tags.get(37386, 0))
            equivalent = float(tags.get(41989, 0))
            if focal <= 0:
                return None
            if equivalent > 0:
                return equivalent * np.hypot(width, height) / np.hypot(36, 24)
            unit_mm = {2: 25.4, 3: 10., 4: 1., 5: .001}.get(tags.get(41488))
            resolution = float(tags.get(41486, 0))
            sensor_pixels = float(tags.get(40962, image.width))
            if unit_mm and resolution > 0 and sensor_pixels > 0:
                return focal * resolution / unit_mm * image.width / sensor_pixels
    except (ValueError, TypeError, OSError, ZeroDivisionError):
        pass
    return None


def render_evidence(xyz, pixels, image, rotation, translation, median_error, inliers):
    indices = np.linspace(0, len(xyz) - 1, min(len(xyz), 2000), dtype=int)
    sample = xyz[indices]
    uv = np.rint(pixels[indices]).astype(int)
    uv[:, 0] = uv[:, 0].clip(0, image.shape[1] - 1)
    uv[:, 1] = uv[:, 1].clip(0, image.shape[0] - 1)
    rgb = image[uv[:, 1], uv[:, 0], ::-1]
    return {
        'points': np.column_stack((sample, rgb)).tolist(),
        'cameras': [
            {'centre': [0., 0., 0.], 'orientation': np.eye(3).tolist()},
            {'centre': (-rotation.T @ translation).ravel().tolist(),
             'orientation': rotation.T.tolist()},
        ],
        'bounds': {'min': xyz.min(axis=0).tolist(), 'max': xyz.max(axis=0).tolist()},
        'median_error_px': median_error, 'inlier_count': inliers,
    }


def triangulate(a, b, k, rotation, translation):
    p = k @ np.column_stack((np.eye(3), np.zeros(3)))
    q = k @ np.column_stack((rotation, translation))
    homogeneous = cv2.triangulatePoints(p, q, a.T, b.T)
    valid = np.abs(homogeneous[3]) > 1e-9
    xyz = np.full((len(a), 3), np.nan)
    xyz[valid] = (homogeneous[:3, valid] / homogeneous[3, valid]).T
    other = xyz @ rotation.T + translation.ravel()
    pa, pb = xyz @ k.T, other @ k.T
    with np.errstate(divide='ignore', invalid='ignore'):
        error = np.maximum(np.linalg.norm(pa[:, :2] / pa[:, 2:] - a, axis=1),
                           np.linalg.norm(pb[:, :2] / pb[:, 2:] - b, axis=1))
    keep = valid & (xyz[:, 2] > 0) & (other[:, 2] > 0) & (error < 3)
    return xyz, keep, error


def self_check():
    k = np.array([[800., 0, 600], [0, 800, 800], [0, 0, 1]])
    points = np.array([[0., 0, 4], [.3, .2, 5], [-.2, .4, 6]])
    t = np.array([[-1.], [0], [0]])
    def project(x):
        pixels = x @ k.T
        return pixels[:, :2] / pixels[:, 2:]
    xyz, keep, error = triangulate(project(points), project(points + t.ravel()), k, np.eye(3), t)
    assert keep.all() and np.allclose(xyz, points) and max(error) < 1e-6


def run(paths, output):
    output.mkdir(parents=True, exist_ok=True)
    images, sources, focals = [], [], []
    for index, path in enumerate(paths):
        raw = path.read_bytes()
        image = cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_COLOR)
        if image is None:
            raise ValueError(f'Invalid image: {path.name}')
        (output / f'input-{index + 1}.jpg').write_bytes(raw)
        images.append(image)
        focals.append(exif_focal_pixels(raw, image.shape[1], image.shape[0]))
        sources.append({'filename': path.name, 'sha256': hashlib.sha256(raw).hexdigest(),
                        'width': image.shape[1], 'height': image.shape[0]})
    if images[0].shape != images[1].shape:
        raise ValueError('Diagnostic currently requires equal image dimensions')
    cv2.setRNGSeed(0)
    sift = cv2.SIFT_create(nfeatures=6000)
    features = [sift.detectAndCompute(cv2.cvtColor(i, cv2.COLOR_BGR2GRAY), None) for i in images]
    matcher = cv2.BFMatcher()
    def matches(x, y, ratio=.65):
        if x is None or y is None or len(y) < 2:
            return []
        return [m for pair in matcher.knnMatch(x, y, k=2) if len(pair) == 2
                for m, n in [pair] if m.distance < ratio * n.distance]
    forward = matches(features[0][1], features[1][1])
    backward = {(m.trainIdx, m.queryIdx) for m in matches(features[1][1], features[0][1])}
    good = [m for m in forward if (m.queryIdx, m.trainIdx) in backward]
    a = np.array([features[0][0][m.queryIdx].pt for m in good], dtype=np.float64).reshape(-1, 2)
    b = np.array([features[1][0][m.trainIdx].pt for m in good], dtype=np.float64).reshape(-1, 2)
    result = {'sources': sources, 'mutual_matches': len(good), 'physical_trays': None,
              'verified': False, 'calibration': None, 'stable_scene_confirmed': False,
              'status': 'insufficient_matches', 'reason': 'Too few shared features. Capture views with more overlap.',
              'scale': 'arbitrary_unit_baseline', 'focal_hypotheses': [],
              'note': 'Feature points are not trays. Assumed intrinsics, arbitrary scale; no occupancy or stack identity certified.'}
    result['matching_sensitivity'] = []
    for ratio in (.65, .75, .85):
        fw = matches(features[0][1], features[1][1], ratio)
        bw = {(m.trainIdx, m.queryIdx) for m in matches(features[1][1], features[0][1], ratio)}
        candidates = [m for m in fw if (m.queryIdx, m.trainIdx) in bw]
        trial = {'ratio': ratio, 'mutual_candidates': len(candidates),
                 'accepted_physical_identity': False}
        if len(candidates) >= 8:
            ca = np.float64([features[0][0][m.queryIdx].pt for m in candidates])
            cb = np.float64([features[1][0][m.trainIdx].pt for m in candidates])
            cv2.setRNGSeed(0)
            fm, support = cv2.findFundamentalMat(ca, cb, cv2.FM_RANSAC, 2., .999)
            _, planar = cv2.findHomography(ca, cb, cv2.RANSAC, 3.)
            trial['fundamental_inliers'] = int(support.sum()) if support is not None else 0
            trial['homography_inliers'] = int(planar.sum()) if planar is not None else 0
            trial['note'] = 'Unvalidated matches; RANSAC support alone does not establish stack identity.'
        result['matching_sensitivity'].append(trial)
    if len(good) >= 8:
        result.update(status='pose_failed', reason='A stable camera pose could not be recovered. Capture more overlapping views.')
        fundamental, mask = cv2.findFundamentalMat(a, b, cv2.FM_RANSAC, 2., .999)
        homography, hm = cv2.findHomography(a, b, cv2.RANSAC, 3.)
        result['fundamental_inliers'] = int(mask.sum()) if mask is not None else 0
        result['homography_inliers'] = int(hm.sum()) if hm is not None else 0
        if fundamental is not None and fundamental.shape == (3, 3) and mask is not None:
            inliers = mask.ravel().astype(bool)
            aa, bb = a[inliers], b[inliers]
            result['inlier_pixels'] = {'first': aa.tolist(), 'second': bb.tolist()}
            h, w = images[0].shape[:2]
            # ponytail: focal sweep diagnoses calibration sensitivity, not automatic calibration.
            hypotheses = [(str(f), f) for f in (.7, 1., 1.4)]
            if all(f is not None and np.isfinite(f) and f > 0 for f in focals):
                if abs(focals[0] - focals[1]) / max(focals) < .01:
                    hypotheses.append(('exif_focal', float(np.mean(focals)) / w))
            result['exif_focal_estimates_px'] = focals
            for label, factor in hypotheses:
                k = np.array([[w * factor, 0, w / 2], [0, w * factor, h / 2], [0, 0, 1.]])
                try:
                    essential, em = cv2.findEssentialMat(aa, bb, k, cv2.RANSAC, .999, 2.)
                    if essential is None or essential.shape != (3, 3):
                        continue
                    _, r, t, pose_mask = cv2.recoverPose(essential, aa, bb, k, mask=em)
                    xyz, keep, errors = triangulate(aa, bb, k, r, t)
                    keep &= pose_mask.ravel() > 0
                except cv2.error:
                    continue
                if keep.sum() < 8:
                    continue
                median_error = float(np.median(errors[keep]))
                result['focal_hypotheses'].append({'label': label, 'focal_width_factor': factor,
                    'intrinsics_source': 'exif_estimate' if label == 'exif_focal' else 'assumed',
                    'render': render_evidence(xyz[keep], aa[keep], images[0], r, t, median_error, len(aa)),
                    'triangulated_points': int(keep.sum()), 'rotation': r.tolist(),
                    'translation_unit_baseline': t.ravel().tolist(),
                    'points_unit_baseline': xyz[keep][np.linspace(0, int(keep.sum()) - 1, min(int(keep.sum()), 2000), dtype=int)].tolist(),
                    'median_error_px': float(np.median(errors[keep])) if keep.any() else None})
                with (output / f'hypothesis-{factor}.ply').open('w') as file:
                    file.write(f'ply\nformat ascii 1.0\ncomment UNCALIBRATED HYPOTHESIS NOT INVENTORY\nelement vertex {keep.sum()}\nproperty float x\nproperty float y\nproperty float z\nend_header\n')
                    np.savetxt(file, xyz[keep], fmt='%.6f')
            if result['focal_hypotheses']:
                result.update(status='reconstructed', reason='Sparse geometry recovered using estimated intrinsics and arbitrary scale; no inventory count.')
            good = [m for m, keep in zip(good, inliers) if keep]
    overlay = cv2.drawMatches(images[0], features[0][0], images[1], features[1][0], good, None,
                              flags=cv2.DrawMatchesFlags_NOT_DRAW_SINGLE_POINTS)
    cv2.imwrite(str(output / 'matches.jpg'), overlay)
    (output / 'result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    return result

