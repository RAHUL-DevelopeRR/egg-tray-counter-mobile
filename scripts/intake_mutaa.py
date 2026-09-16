"""Archive unmodified images, metadata and a contact sheet. No truth inference."""

import argparse
import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps, ExifTags


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    originals = args.output / "originals"
    originals.mkdir()
    records, seen, tiles = [], {}, []
    for source in sorted(args.source.rglob("*")):
        if not source.is_file() or source.suffix.lower() not in {
            ".jpg",
            ".jpeg",
            ".png",
            ".webp",
            ".tif",
            ".tiff",
            ".bmp",
        }:
            continue
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        image_id = f"image-{len(records) + 1:02d}"
        target = originals / (image_id + source.suffix.lower())
        shutil.copy2(source, target)
        record = dict(
            id=image_id,
            filename=str(source.relative_to(args.source)),
            sha256=digest,
            bytes=source.stat().st_size,
            original=str(target.relative_to(args.output)),
            duplicate_of=seen.get(digest),
            physical_ground_truth=None,
        )
        seen.setdefault(digest, image_id)
        try:
            with Image.open(source) as image:
                record["dimensions"] = list(image.size)
                record["exif"] = {
                    ExifTags.TAGS.get(k, str(k)): str(v)
                    for k, v in image.getexif().items()
                }
                thumb = ImageOps.exif_transpose(image).convert("RGB")
                thumb.thumbnail((300, 230))
                tile = Image.new("RGB", (320, 265), "white")
                tile.paste(thumb, ((320 - thumb.width) // 2, 0))
                ImageDraw.Draw(tile).text(
                    (8, 238), image_id + "  " + str(image.size), fill="black"
                )
                tiles.append(tile)
                record["decodable"] = True
        except (OSError, ValueError):
            record["decodable"] = False
        records.append(record)
    sheet = Image.new("RGB", (320 * 5, 265 * ((len(tiles) + 4) // 5)), "#ddd")
    for i, tile in enumerate(tiles):
        sheet.paste(tile, ((i % 5) * 320, (i // 5) * 265))
    sheet.save(args.output / "contact-sheet.jpg", quality=90)
    (args.output / "manifest.json").write_text(
        json.dumps({"source": str(args.source), "images": records}, indent=2),
        encoding="utf-8",
    )
    print(f"Archived {len(records)} images; {len(seen)} byte-unique")


if __name__ == "__main__":
    main()
