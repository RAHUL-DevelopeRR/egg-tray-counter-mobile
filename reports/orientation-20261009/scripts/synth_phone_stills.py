"""Build the camera files a Redmi Note 9 Pro (back camera, sensorOrientation 90, 1920x1080 stills, screen
1080x2400 locked portrait) would write for a scene, held upright, turned counter-clockwise (r=90) or
turned clockwise (r=270).

Camera model (CameraX with the display at ROTATION_0 writes EXIF Orientation 6 on every still):
  r=0   raw pixels = scene turned counter-clockwise   (decodes upright portrait)
  r=90  raw pixels = scene as is                      (decodes as the portrait screen showed it)
  r=270 raw pixels = scene turned 180 degrees
The scene is the labelled photo scaled to fit the part of the frame the cover-scaled screen shows
(landscape: full width x centre 80% of height; portrait: centre 80% of width x full height), padded grey.
"""
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
ORIG = ROOT / "datasets/field-2026-10/labelled-20261007/originals"
OUT = Path(__file__).resolve().parent
SCREEN_ASPECT = 1080 / 2400


def world_frame(src: Image.Image, landscape: bool) -> Image.Image:
    fw, fh = (1920, 1080) if landscape else (1080, 1920)
    vw, vh = (fw, round(fw * SCREEN_ASPECT)) if landscape else (round(fh * SCREEN_ASPECT), fh)
    scale = min(vw / src.width, vh / src.height)
    fitted = src.resize((round(src.width * scale), round(src.height * scale)), Image.LANCZOS)
    frame = Image.new("RGB", (fw, fh), (128, 128, 128))
    frame.paste(fitted, ((fw - fitted.width) // 2, (fh - fitted.height) // 2))
    return frame


def raw_still(scene: Image.Image, rotation: int) -> Image.Image:
    if rotation == 90:
        return scene.copy()
    if rotation == 270:
        return scene.rotate(180)
    return scene.transpose(Image.ROTATE_90)  # PIL ROTATE_90 is counter-clockwise


def save_tagged(im: Image.Image, path: Path, orientation: int = 6) -> None:
    exif = Image.Exif()
    exif[0x0112] = orientation
    im.save(path, quality=95, exif=exif.tobytes())


def main() -> None:
    plan = json.loads(sys.argv[1])  # [{"id": "19", "file": "img-19.jpeg", "rotations": [90, 270]}, ...]
    manifest = []
    for item in plan:
        src = Image.open(ORIG / item["file"]).convert("RGB")
        for r in item["rotations"]:
            scene = world_frame(src, landscape=r != 0)
            scene.save(OUT / f"scene-{item['id']}-r{r}.jpg", quality=95)
            raw = OUT / f"raw-{item['id']}-r{r}.jpg"
            save_tagged(raw_still(scene, r), raw)
            manifest.append({"id": item["id"], "rotation": r, "raw": str(raw), "upload": str(OUT / f"upload-{item['id']}-r{r}.jpg")})
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1))
    print(f"{len(manifest)} phone stills written to {OUT}")


if __name__ == "__main__":
    main()
