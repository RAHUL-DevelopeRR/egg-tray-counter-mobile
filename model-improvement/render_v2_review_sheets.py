"""Render compact annotation sheets for the frozen-V2 policy review."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def boxes(path: Path) -> list[tuple[float, float, float, float]]:
    result = []
    for line in path.read_text(encoding="utf-8").splitlines():
        values = line.split()
        if len(values) >= 5:
            result.append(tuple(map(float, values[1:5])))
    return result


def tile(row: dict[str, str], index: int, size: tuple[int, int]) -> Image.Image:
    width, height = size
    header = 54
    source = Image.open(row["image"]).convert("RGB")
    scale = min(width / source.width, (height - header) / source.height)
    resized = source.resize((round(source.width * scale), round(source.height * scale)))
    canvas = Image.new("RGB", size, "white")
    left = (width - resized.width) // 2
    top = header + (height - header - resized.height) // 2
    canvas.paste(resized, (left, top))
    draw = ImageDraw.Draw(canvas)
    for center_x, center_y, box_width, box_height in boxes(Path(row["label"])):
        x1 = left + (center_x - box_width / 2) * resized.width
        y1 = top + (center_y - box_height / 2) * resized.height
        x2 = left + (center_x + box_width / 2) * resized.width
        y2 = top + (center_y + box_height / 2) * resized.height
        draw.rectangle((x1, y1, x2, y2), outline="red", width=2)
    name = Path(row["image"]).name.split(".rf.")[0]
    draw.text((6, 4), f"#{index:02d} p{row['priority']} n={row['annotations']}", fill="black", font=ImageFont.load_default())
    draw.text((6, 22), name[:46], fill="black", font=ImageFont.load_default())
    return canvas


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review", type=Path, default=Path("model-improvement/01-dataset-audit/v2-label-policy-review.csv"))
    parser.add_argument("--output", type=Path, default=Path("work/v2-review-sheets"))
    args = parser.parse_args()
    rows = list(csv.DictReader(args.review.open(encoding="utf-8")))
    args.output.mkdir(parents=True, exist_ok=True)
    columns, rows_per_sheet = 3, 3
    tile_size = (420, 350)
    per_sheet = columns * rows_per_sheet
    for sheet_index in range(math.ceil(len(rows) / per_sheet)):
        sheet = Image.new("RGB", (columns * tile_size[0], rows_per_sheet * tile_size[1]), "#dddddd")
        for offset, row in enumerate(rows[sheet_index * per_sheet : (sheet_index + 1) * per_sheet]):
            item_index = sheet_index * per_sheet + offset + 1
            item = tile(row, item_index, tile_size)
            sheet.paste(item, ((offset % columns) * tile_size[0], (offset // columns) * tile_size[1]))
        sheet.save(args.output / f"v2-review-{sheet_index + 1:02d}.jpg", quality=92)
    print(f"images={len(rows)} sheets={math.ceil(len(rows) / per_sheet)} output={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
