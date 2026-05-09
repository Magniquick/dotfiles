import json
import subprocess
import textwrap
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def qml(path):
    return (ROOT / path).read_text()


def run_js(path, expression):
    source = (ROOT / path).read_text()
    script = textwrap.dedent(
        f"""
        const vm = require("vm");
        const source = {json.dumps(source)};
        const expression = {json.dumps(expression)};
        const context = {{}};
        vm.createContext(context);
        vm.runInContext(source + "\\nthis.__result = (" + expression + ");", context);
        process.stdout.write(JSON.stringify(context.__result));
        """
    )
    return json.loads(subprocess.check_output(["node", "-e", script], text=True))


def test_network_ip_details_use_structured_argv_commands():
    source = qml("bar/services/NetworkService.qml")

    assert '["sh", "-lc", "ip ' not in source
    assert '"-j", "-4", "addr"' in source
    assert '"-j", "route", "show", "default"' in source


def test_systemd_failed_service_uses_qsgo_provider_without_qml_text_parsers():
    source = qml("bar/services/SystemdFailedService.qml")
    provider = qml("common/modules/qs-go/internal/systemd/systemd.go")

    assert "parseFailedUnits" not in source
    assert "dbus-monitor" not in source
    assert "CommandRunner" not in source
    assert "SystemdFailedProvider" in source
    assert '"--output=json"' in provider


def test_json_utils_does_not_extract_last_object_from_mixed_logs():
    assert run_js("bar/components/JsonUtils.js", 'parseObject("noise { \\"ok\\": true }")') is None


def test_brightness_ddc_parsing_is_centralized_outside_service_qml():
    service = qml("bar/services/BrightnessService.qml")
    utils = qml("bar/components/DdcUtils.js")

    assert "function parseDdcVcp10" not in service
    assert "parseDdcDetect" in utils
    assert "parseDdcVcp10" in utils


def test_bluetooth_shell_diagnostics_are_debug_gated():
    source = qml("bar/modules/BluetoothModule.qml")

    assert "running: root.debugBluetooth" in source
    assert "requestLibrepodsBattery()" not in source


def test_sysinfo_reads_smartctl_json_not_human_labels():
    source = qml("common/modules/qs-go/cpp/QsGoSysInfo.cpp")

    assert 'QStringLiteral("-j")' in source
    assert "parseSmartctlValue" not in source
    assert "QJsonDocument" in source
