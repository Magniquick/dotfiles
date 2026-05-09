from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCREENSHOT_UTILS = ROOT / "hyprquickshot" / "src" / "ScreenshotUtils.js"
HYPRQUICKSHOT = ROOT / "hyprquickshot" / "HyprQuickshot.qml"


def test_recording_plan_uses_argv_not_shell_string():
    source = SCREENSHOT_UTILS.read_text()

    assert "function _quote(" not in source
    assert "commandString" not in source
    assert "audio_device:" not in source
    assert "command: argv" in source
    assert '"wl-screenrec"' in source


def test_recording_process_uses_plan_command_directly():
    source = HYPRQUICKSHOT.read_text()

    assert "ProcessHelper.shell(plan.commandString)" not in source
    assert "recordProcess.command = plan.command" in source
    assert "audio_device:" not in source
