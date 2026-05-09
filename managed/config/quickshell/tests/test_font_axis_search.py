from pathlib import Path
import importlib.util
import sys

from PIL import Image


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "font_axis_search.py"
SPEC = importlib.util.spec_from_file_location("font_axis_search", SCRIPT)
font_axis_search = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = font_axis_search
SPEC.loader.exec_module(font_axis_search)


def test_diff_score_is_zero_for_identical_images():
    image = Image.new("L", (8, 8), 255)

    assert font_axis_search.diff_score(image, image.copy()) == 0


def test_diff_score_pads_different_sizes():
    left = Image.new("L", (8, 8), 255)
    right = Image.new("L", (10, 8), 255)

    assert font_axis_search.diff_score(left, right) == 0


def test_axis_grid_includes_defaults_and_bounds():
    grid = list(font_axis_search.axis_grid({
        "wght": [400, 500],
        "wdth": [96, 100],
    }))

    assert {"wght": 400, "wdth": 100} in grid
    assert {"wght": 500, "wdth": 96} in grid
    assert len(grid) == 4
