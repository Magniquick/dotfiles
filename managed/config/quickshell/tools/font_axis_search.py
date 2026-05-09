#!/usr/bin/env -S uv run --script
# /// script
# dependencies = [
#   "fonttools",
#   "pillow",
# ]
# ///
from __future__ import annotations

import argparse
import itertools
import json
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from fontTools.ttLib import TTFont
from PIL import Image, ImageChops, ImageDraw, ImageFont


DEFAULT_TEXT = "Settings  Notifications  Workspace  Quick actions\nThe quick brown fox jumps over 0123456789"
DEFAULT_SIZES = [16, 24]
DEFAULT_STYLES = [
    ("Regular", 400, "Regular"),
    ("Medium", 500, "Medium"),
    ("SemiBold", 600, "SemiBold"),
    ("Bold", 700, "Bold"),
]
BACKGROUND = 255
FOREGROUND = 0
MARGIN = 24


@dataclass(frozen=True)
class RenderCase:
    style: str
    weight: int
    size: int
    source_font: Path


def fc_match_file(pattern: str) -> Path:
    output = subprocess.check_output(["fc-match", "-f", "%{file}", pattern], text=True).strip()
    if not output:
        raise RuntimeError(f"fontconfig did not resolve {pattern!r}")
    return Path(output)


def flex_axis_order(font_path: Path) -> list[str]:
    font = TTFont(font_path)
    return [axis.axisTag for axis in font["fvar"].axes]


def axis_grid(options: dict[str, list[float]]) -> Iterable[dict[str, float]]:
    keys = list(options.keys())
    for values in itertools.product(*(options[key] for key in keys)):
        yield dict(zip(keys, values))


def axis_values(axis_order: list[str], axes: dict[str, float]) -> list[float]:
    return [axes[tag] for tag in axis_order]


def render_text(font_path: Path, size: int, text: str, axes: dict[str, float] | None = None,
                axis_order: list[str] | None = None) -> Image.Image:
    font = ImageFont.truetype(str(font_path), size=size)
    if axes is not None:
        if axis_order is None:
            raise ValueError("axis_order is required when axes are provided")
        font.set_variation_by_axes(axis_values(axis_order, axes))

    probe = Image.new("L", (1, 1), BACKGROUND)
    draw = ImageDraw.Draw(probe)
    bbox = draw.multiline_textbbox((0, 0), text, font=font, spacing=max(2, size // 5))
    width = max(1, bbox[2] - bbox[0] + MARGIN * 2)
    height = max(1, bbox[3] - bbox[1] + MARGIN * 2)
    image = Image.new("L", (width, height), BACKGROUND)
    draw = ImageDraw.Draw(image)
    draw.multiline_text((MARGIN - bbox[0], MARGIN - bbox[1]), text, font=font, fill=FOREGROUND,
                        spacing=max(2, size // 5))
    return image


def same_canvas(left: Image.Image, right: Image.Image) -> tuple[Image.Image, Image.Image]:
    width = max(left.width, right.width)
    height = max(left.height, right.height)
    left_canvas = Image.new("L", (width, height), BACKGROUND)
    right_canvas = Image.new("L", (width, height), BACKGROUND)
    left_canvas.paste(left, (0, 0))
    right_canvas.paste(right, (0, 0))
    return left_canvas, right_canvas


def diff_score(left: Image.Image, right: Image.Image) -> float:
    left_canvas, right_canvas = same_canvas(left, right)
    diff = ImageChops.difference(left_canvas, right_canvas)
    total = sum(value * count for value, count in enumerate(diff.histogram()))
    return total / (255 * diff.width * diff.height)


def diff_image(left: Image.Image, right: Image.Image) -> Image.Image:
    left_canvas, right_canvas = same_canvas(left, right)
    return ImageChops.difference(left_canvas, right_canvas).point(lambda value: min(255, value * 4))


def initial_candidate(weight: int) -> dict[str, float]:
    return {
        "opsz_delta": 0,
        "wdth": 100,
        "wght": weight,
        "GRAD": 0,
        "ROND": 0,
        "slnt": 0,
    }


def concrete_axes(candidate: dict[str, float], size: int) -> dict[str, float]:
    axes = dict(candidate)
    opsz_delta = axes.pop("opsz_delta")
    axes["opsz"] = max(6, min(144, size + opsz_delta))
    axes["wght"] = max(1, min(1000, axes["wght"]))
    return axes


def source_images(cases: list[RenderCase], text: str) -> list[tuple[RenderCase, Image.Image]]:
    return [(case, render_text(case.source_font, case.size, text)) for case in cases]


def score_candidate(candidate: dict[str, float], sources: list[tuple[RenderCase, Image.Image]], flex_font: Path,
                    axis_order: list[str], text: str) -> float:
    total = 0.0
    for case, source in sources:
        target = render_text(flex_font, case.size, text, concrete_axes(candidate, case.size), axis_order)
        total += diff_score(source, target)
    return total / len(sources)


def axis_ranges(weight: int) -> dict[str, list[float]]:
    return {
        "opsz_delta": list(range(-8, 9, 2)),
        "wdth": list(range(88, 113, 2)),
        "wght": list(range(max(1, weight - 90), min(1000, weight + 91), 10)),
        "GRAD": list(range(0, 81, 10)),
        "ROND": list(range(0, 81, 10)),
        "slnt": [0],
    }


def neighbor_candidates(seed: dict[str, float], ranges: dict[str, list[float]]) -> Iterable[dict[str, float]]:
    for axis, values in ranges.items():
        if axis == "slnt":
            continue
        for value in values:
            if value == seed[axis]:
                continue
            candidate = dict(seed)
            candidate[axis] = value
            yield candidate


def best_candidates(cases: list[RenderCase], flex_font: Path, axis_order: list[str], text: str,
                    limit: int) -> list[dict[str, object]]:
    sources = source_images(cases, text)
    ranges = axis_ranges(cases[0].weight)
    current = initial_candidate(cases[0].weight)
    ranked = [{
        "score": score_candidate(current, sources, flex_font, axis_order, text),
        "candidate": current,
    }]
    seen = {tuple(sorted(current.items()))}

    improved = True
    while improved:
        improved = False
        best = ranked[0]
        for candidate in neighbor_candidates(best["candidate"], ranges):
            key = tuple(sorted(candidate.items()))
            if key in seen:
                continue
            seen.add(key)
            ranked.append({
                "score": score_candidate(candidate, sources, flex_font, axis_order, text),
                "candidate": candidate,
            })
        ranked.sort(key=lambda item: item["score"])
        if ranked[0]["score"] < best["score"]:
            improved = True

    return ranked[:limit]


def write_preview(out_dir: Path, style: str, best: dict[str, object], cases: list[RenderCase],
                  flex_font: Path, axis_order: list[str], text: str) -> None:
    preview_dir = out_dir / style
    preview_dir.mkdir(parents=True, exist_ok=True)
    candidate = best["candidate"]
    for case in cases:
        source = render_text(case.source_font, case.size, text)
        target = render_text(flex_font, case.size, text, concrete_axes(candidate, case.size), axis_order)
        source.save(preview_dir / f"{case.size}-source.png")
        target.save(preview_dir / f"{case.size}-flex.png")
        diff_image(source, target).save(preview_dir / f"{case.size}-diff.png")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Search Google Sans Flex axes that visually match static Google Sans raster output."
    )
    parser.add_argument("--text", default=DEFAULT_TEXT)
    parser.add_argument("--sizes", default=",".join(str(size) for size in DEFAULT_SIZES),
                        help="Comma-separated pixel sizes to compare.")
    parser.add_argument("--top", type=int, default=8)
    parser.add_argument("--out", type=Path, default=Path("/tmp/google-sans-flex-search"))
    parser.add_argument("--json", type=Path, default=None)
    parser.add_argument("--styles", default=",".join(style[0] for style in DEFAULT_STYLES),
                        help="Comma-separated static Google Sans styles to compare.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    sizes = [int(value) for value in args.sizes.split(",") if value]
    flex_font = fc_match_file("Google Sans Flex")
    axis_order = flex_axis_order(flex_font)
    args.out.mkdir(parents=True, exist_ok=True)

    results = {
        "source": "Google Sans static faces",
        "candidate": "Google Sans Flex",
        "flex_font": str(flex_font),
        "axis_order": axis_order,
        "sizes": sizes,
        "styles": {},
    }

    requested_styles = {style.strip() for style in args.styles.split(",") if style.strip()}

    for style_name, weight, fc_style in DEFAULT_STYLES:
        if style_name not in requested_styles:
            continue
        source_font = fc_match_file(f"Google Sans:style={fc_style}")
        cases = [RenderCase(style_name, weight, size, source_font) for size in sizes]
        top = best_candidates(cases, flex_font, axis_order, args.text, args.top)
        write_preview(args.out, style_name, top[0], cases, flex_font, axis_order, args.text)
        results["styles"][style_name] = {
            "source_font": str(source_font),
            "top": top,
            "preview_dir": str(args.out / style_name),
        }

    payload = json.dumps(results, indent=2)
    print(payload)
    if args.json:
        args.json.write_text(payload + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
