"""Training uses the same implementation as the diagnostic backend."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "backend"))
from app.vision.heatmap_model import StackHeatmap, gaussian_target, image_tensor, load_model

__all__ = ["StackHeatmap", "gaussian_target", "image_tensor", "load_model"]
