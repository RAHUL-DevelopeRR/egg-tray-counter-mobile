"""Run the same two-view geometry diagnostic used by the hosted service."""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
from app.vision.reconstruction import run, self_check

if __name__ == '__main__':
    self_check()
    parser = argparse.ArgumentParser()
    parser.add_argument('first', type=Path)
    parser.add_argument('second', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = run([args.first, args.second], args.output)
    summary = {key: value for key, value in result.items() if key not in ('inlier_pixels', 'sources')}
    summary['focal_hypotheses'] = [{k: v for k, v in h.items() if k != 'points_unit_baseline'}
                                 for h in result['focal_hypotheses']]
    print(json.dumps(summary, indent=2))
