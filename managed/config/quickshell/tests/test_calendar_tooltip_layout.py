from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
CALENDAR = ROOT / "bar" / "components" / "CalendarTooltip.qml"
SPACE = ROOT / "common" / "types" / "Space.qml"
TYPE_SCALE = ROOT / "common" / "types" / "TypeScale.qml"


def qml_int_property(path: Path, name: str) -> int:
    match = re.search(rf"\breadonly property int {name}: (\d+)\b", path.read_text())
    assert match, f"missing {name} in {path}"
    return int(match.group(1))


def text_style_values(name: str) -> tuple[int, int]:
    match = re.search(
        rf"\breadonly property TextStyle {name}: TextStyle \{{ line: (\d+); size: (\d+);",
        TYPE_SCALE.read_text(),
    )
    assert match, f"missing {name} style"
    return int(match.group(1)), int(match.group(2))


def calendar_month_viewport_height() -> int:
    qml = CALENDAR.read_text()

    property_match = re.search(r"\breadonly property int monthViewportHeight: ([^\n]+)", qml)
    if property_match:
        return evaluate_calendar_expression(property_match.group(1).strip())

    preferred_match = re.search(r"\bLayout\.preferredHeight: (\d+)\b", qml)
    assert preferred_match, "missing calendar month viewport height"
    return int(preferred_match.group(1))


def evaluate_calendar_expression(expression: str) -> int:
    xs = qml_int_property(SPACE, "xs")
    sm = qml_int_property(SPACE, "sm")
    md = qml_int_property(SPACE, "md")
    headline_small_line, _ = text_style_values("headlineSmall")
    _, label_small_size = text_style_values("labelSmall")
    _, body_medium_size = text_style_values("bodyMedium")
    day_cell_size = body_medium_size + md
    weekday_row_height = label_small_size + xs
    day_grid_height = day_cell_size * 6 + xs * 5

    replacements = {
        "Config.type.headlineSmall.line": headline_small_line,
        "Config.type.labelSmall.size": label_small_size,
        "Config.space.xs": xs,
        "Config.space.sm": sm,
        "dayCellSize": day_cell_size,
        "weekdayRowHeight": weekday_row_height,
        "dayGridHeight": day_grid_height,
    }
    parsed = expression
    for token, value in replacements.items():
        parsed = parsed.replace(token, str(value))

    assert re.fullmatch(r"[0-9+\-*/ ().]+", parsed), f"unsupported expression: {expression}"
    return int(eval(parsed, {"__builtins__": {}}, {}))


def test_month_viewport_fits_six_week_calendar_grid():
    xs = qml_int_property(SPACE, "xs")
    sm = qml_int_property(SPACE, "sm")
    md = qml_int_property(SPACE, "md")
    headline_small_line, _ = text_style_values("headlineSmall")
    _, label_small_size = text_style_values("labelSmall")
    _, body_medium_size = text_style_values("bodyMedium")

    day_cell_size = body_medium_size + md
    weekday_height = label_small_size + xs
    day_grid_height = day_cell_size * 6 + xs * 5
    required_height = headline_small_line + sm + sm + weekday_height + sm + day_grid_height

    assert calendar_month_viewport_height() >= required_height
