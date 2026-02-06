pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../components"
import "../../common" as Common

Item {
    id: root
    visible: false

    property string backlightDevice: "intel_backlight"
    readonly property string actualBrightnessPath: root.backlightDevice !== "" ? "/sys/class/backlight/" + root.backlightDevice + "/actual_brightness" : ""
    readonly property string maxBrightnessPath: root.backlightDevice !== "" ? "/sys/class/backlight/" + root.backlightDevice + "/max_brightness" : ""

    property bool brilloAvailable: false
    property bool udevadmAvailable: false

    property int brightnessPercent: -1
    property int sliderValue: 0

    property string onScrollDownCommand: "brillo -A 1"
    property string onScrollUpCommand: "brillo -U 1"
    property int brightnessDebounceMs: 150

    function handleUdevEvent(data) {
        const line = (data || "").trim();
        if (line === "ACTION=change") {
            root.scheduleBrightnessRefresh();
        }
    }

    function scheduleBrightnessRefresh() {
        if (!brightnessDebounceTimer.running)
            brightnessDebounceTimer.start();
    }

    function refreshBrightness() {
        if (root.actualBrightnessPath === "")
            return;
        actualBrightnessFile.reload();
        maxBrightnessFile.reload();
    }

    function setBrightness(percent) {
        if (!root.brilloAvailable)
            return;
        const next = Math.max(1, Math.min(100, percent));
        Quickshell.execDetached(["brillo", "-S", String(next)]);
    }

    function updateBrightnessFromFiles() {
        if (root.actualBrightnessPath === "" || root.maxBrightnessPath === "") {
            root.brightnessPercent = -1;
            root.sliderValue = 0;
            return;
        }
        const currentText = actualBrightnessFile.text().trim();
        const maxText = maxBrightnessFile.text().trim();
        const currentValue = parseInt(currentText, 10);
        const maxValue = parseInt(maxText, 10);
        if (!isFinite(currentValue) || !isFinite(maxValue) || maxValue <= 0) {
            root.brightnessPercent = -1;
            root.sliderValue = 0;
            return;
        }
        root.brightnessPercent = Math.round((currentValue / maxValue) * 100);
        root.sliderValue = root.brightnessPercent;
    }

    function scrollUp() {
        if (!root.brilloAvailable)
            return;
        Common.ProcessHelper.execDetached(root.onScrollUpCommand);
    }

    function scrollDown() {
        if (!root.brilloAvailable)
            return;
        Common.ProcessHelper.execDetached(root.onScrollDownCommand);
    }

    Component.onCompleted: {
        DependencyCheck.require("brillo", "BacklightService", function (available) {
            root.brilloAvailable = available;
        });
        DependencyCheck.require("udevadm", "BacklightService", function (available) {
            root.udevadmAvailable = available;
        });
        root.refreshBrightness();
    }

    onBacklightDeviceChanged: root.refreshBrightness()

    FileView {
        id: actualBrightnessFile
        blockLoading: true
        path: root.actualBrightnessPath
        onTextChanged: root.updateBrightnessFromFiles()
    }

    FileView {
        id: maxBrightnessFile
        blockLoading: true
        path: root.maxBrightnessPath
        onTextChanged: root.updateBrightnessFromFiles()
    }

    Timer {
        id: brightnessDebounceTimer
        interval: root.brightnessDebounceMs
        repeat: false
        onTriggered: root.refreshBrightness()
    }

    ProcessMonitor {
        id: udevMonitor
        command: ["udevadm", "monitor", "--subsystem-match=backlight", "--property"]
        enabled: root.udevadmAvailable && root.backlightDevice !== ""
        onOutput: data => root.handleUdevEvent(data)
    }
}
