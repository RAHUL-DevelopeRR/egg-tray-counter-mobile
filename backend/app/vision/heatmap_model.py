"""Small layer-existence heatmap; no scalar inventory or occupancy output."""
import numpy as np
import torch
from torch import nn
from torch.nn import functional as F
from torchvision.models import MobileNet_V3_Small_Weights, mobilenet_v3_small


class StackHeatmap(nn.Module):
    def __init__(self, pretrained=True, backbone_mode="frozen"):
        super().__init__()
        if backbone_mode not in ("frozen", "last-block"):
            raise ValueError("backbone_mode must be frozen or last-block")
        weights = MobileNet_V3_Small_Weights.DEFAULT if pretrained else None
        # Stride eight retains several feature samples between adjacent layers.
        self.backbone = mobilenet_v3_small(weights=weights).features[:4]
        self.backbone.requires_grad_(False)
        if backbone_mode == "last-block":
            self.backbone[-1].requires_grad_(True)
        self.head = nn.Sequential(nn.Conv1d(24, 32, 3, padding=1), nn.ReLU(), nn.Conv1d(32, 1, 1))

    def train(self, mode=True):
        super().train(mode)
        self.backbone.eval()  # Keep BN statistics frozen even when the last block learns.
        return self

    def forward(self, image):
        features = self.backbone(image).mean(dim=3)
        return F.interpolate(self.head(features), size=image.shape[2], mode="linear", align_corners=False)[:, 0]


def image_tensor(rgb, height=640, width=192):
    from PIL import Image
    resized = Image.fromarray(rgb).resize((width, height), Image.Resampling.BILINEAR)
    tensor = torch.from_numpy(np.asarray(resized).copy()).permute(2, 0, 1).float() / 255
    mean = torch.tensor([.485, .456, .406])[:, None, None]
    std = torch.tensor([.229, .224, .225])[:, None, None]
    return (tensor - mean) / std


def gaussian_target(centres, height=640, sigma=3.0):
    if not centres or any(not np.isfinite(y) or not 0 <= y <= 1 for y in centres):
        raise ValueError("Reviewed normalized layer centres required")
    y = torch.arange(height, dtype=torch.float32)[:, None]
    peaks = torch.tensor(centres)[None, :] * (height - 1)
    return torch.exp(-.5 * ((y - peaks) / sigma) ** 2).max(dim=1).values


def load_model(path):
    checkpoint = torch.load(path, map_location="cpu", weights_only=True)
    model = StackHeatmap(pretrained=False)
    model.load_state_dict(checkpoint["model"])
    return model.eval(), checkpoint["config"]
