pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../components"

ModuleContainer {
    id: root

    readonly property string actualBrightnessPath: root.backlightDevice !== "" ? "/sys/class/backlight/" + root.backlightDevice + "/actual_brightness" : ""
    property string backlightDevice: "intel_backlight"
    property int brightnessPercent: -1
    readonly property string iconText: root.iconForBrightness()
    property var icons: ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "󰃚"]
    readonly property string maxBrightnessPath: root.backlightDevice !== "" ? "/sys/class/backlight/" + root.backlightDevice + "/max_brightness" : ""
    property string onScrollDownCommand: "brillo -A 1"
    property string onScrollUpCommand: "brillo -U 1"
    property int sliderValue: 0

    function iconForBrightness() {
        const percent = root.brightnessPercent;
        if (percent < 0)
            return root.icons[root.icons.length - 1];
        const step = 100 / root.icons.length;
        const index = Math.min(root.icons.length - 1, Math.floor(percent / step));
        return root.icons[index];
    }
    function refreshBrightness() {
        if (root.actualBrightnessPath === "")
            return;
        actualBrightnessFile.reload();
        maxBrightnessFile.reload();
    }
    function setBrightness(percent) {
        const next = Math.max(1, Math.min(100, percent));
        Quickshell.execDetached(["sh", "-c", "brillo -S " + next]);
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

    tooltipHoverable: true
    tooltipText: ""
    tooltipTitle: "Brightness"

    content: [
        IconLabel {
            color: Config.yellow
            text: root.iconText
        }
    ]
    tooltipContent: Component {
        ColumnLayout {
            spacing: Config.space.md
            width: 240

            // Header Section
            RowLayout {
                Layout.fillWidth: true
                spacing: Config.space.md

                Item {
                    Layout.preferredHeight: Config.space.xxl * 2
                    Layout.preferredWidth: Config.space.xxl * 2

                    Text {
                        anchors.centerIn: parent
                        color: Config.yellow
                        font.pixelSize: Config.type.headlineLarge.size
                        text: root.iconText
                    }
                }
                ColumnLayout {
                    spacing: Config.space.none

                    Text {
                        Layout.fillWidth: true
                        color: Config.textColor
                        elide: Text.ElideRight
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.headlineSmall.size
                        font.weight: Font.Bold
                        text: "Brightness"
                    }
                    Text {
                        color: Config.textMuted
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.labelMedium.size
                        text: root.brightnessPercent >= 0 ? root.brightnessPercent + "%" : "Unavailable"
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
            }

            // Details Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Config.space.xs

                Text {
                    Layout.bottomMargin: Config.space.xs
                    color: Config.primary
                    font.family: Config.fontFamily
                    font.letterSpacing: 1.5
                    font.pixelSize: Config.type.labelSmall.size
                    font.weight: Font.Black
                    text: "BRIGHTNESS DETAILS"
                }
                LevelSlider {
                    Layout.fillWidth: true
                    enabled: root.brightnessPercent >= 0
                    fillColor: Config.yellow
                    maximum: 100
                    minimum: 1
                    value: root.sliderValue

                    onUserChanged: {
                        root.sliderValue = Math.round(value);
                        root.setBrightness(root.sliderValue);
                    }
                }
                InfoRow {
                    Layout.fillWidth: true
                    label: "Device"
                    value: root.backlightDevice
                    visible: root.backlightDevice !== ""
                }
            }
            TooltipActionsRow {
                spacing: Config.space.sm

                ActionChip {
                    Layout.fillWidth: true
                    text: "20%"

                    onClicked: root.setBrightness(20)
                }
                ActionChip {
                    Layout.fillWidth: true
                    text: "50%"

                    onClicked: root.setBrightness(50)
                }
                ActionChip {
                    Layout.fillWidth: true
                    text: "80%"

                    onClicked: root.setBrightness(80)
                }
                ActionChip {
                    Layout.fillWidth: true
                    text: "100%"

                    onClicked: root.setBrightness(100)
                }
            }
        }
    }

    Component.onCompleted: {
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
    Process {
        id: udevMonitor

        command: ["udevadm", "monitor", "--subsystem-match=backlight", "--property"]
        running: root.backlightDevice !== ""

        stdout: SplitParser {
            onRead: function (data) {
                root.refreshBrightness();
            }
        }
    }
    MouseArea {
        anchors.fill: parent

        onWheel: function (wheel) {
            if (wheel.angleDelta.y > 0)
                Quickshell.execDetached(["sh", "-c", root.onScrollUpCommand]);
            else if (wheel.angleDelta.y < 0)
                Quickshell.execDetached(["sh", "-c", root.onScrollDownCommand]);
        }
    }
}
