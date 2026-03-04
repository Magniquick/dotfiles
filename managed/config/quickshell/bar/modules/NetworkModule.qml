/**
 * @module NetworkModule
 * @description Presentational network module backed by `NetworkService`.
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../../common" as Common
import "../../common/materialkit" as MK

ModuleContainer {
    id: root

    property string disconnectedIcon: "󰖪"
    property string ethernetIcon: "󰈀"
    property string linkedIcon: "󰤣"
    property string usbEthernetIcon: ""
    property var wifiIcons: ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
    property string onClickCommand: "runapp nmgui"

    readonly property string connectionState: NetworkService.connectionState
    readonly property string connectionType: NetworkService.connectionType
    readonly property string deviceName: NetworkService.deviceName
    readonly property int frequencyMhz: NetworkService.frequencyMhz
    readonly property string gateway: NetworkService.gateway
    readonly property string ipAddress: NetworkService.ipAddress
    readonly property double rxBytesPerSec: NetworkService.rxBytesPerSec
    readonly property var rxHistory: NetworkService.rxHistory
    readonly property int signalPercent: NetworkService.signalPercent
    readonly property string ssid: NetworkService.ssid
    readonly property var sourceEntries: NetworkService.sourceEntries
    readonly property bool sourceSwitching: NetworkService.sourceSwitching
    readonly property string sourceSwitchingName: NetworkService.sourceSwitchingName
    readonly property string sourceError: NetworkService.sourceError
    readonly property double txBytesPerSec: NetworkService.txBytesPerSec
    readonly property var txHistory: NetworkService.txHistory
    readonly property real trafficScaleMax: NetworkService.trafficScaleMax
    readonly property string ethernetSubsystem: NetworkService.ethernetSubsystem
    readonly property string ethernetDeviceLabel: NetworkService.ethernetDeviceLabel

    property bool _tooltipHeld: false
    property bool detailsExpanded: false
    property int sourceRowHeight: 42

    function iconForSignal() {
        const percent = root.signalPercent;
        if (percent <= 0)
            return root.wifiIcons[0];
        if (percent < 25)
            return root.wifiIcons[1];
        if (percent < 50)
            return root.wifiIcons[2];
        if (percent < 75)
            return root.wifiIcons[3];
        return root.wifiIcons[4];
    }

    function formatFrequency(mhz) {
        if (!mhz || mhz <= 0)
            return "";
        const ghz = mhz / 1000;
        return ghz.toFixed(1) + " GHz";
    }

    function formatRate(bytesPerSecond) {
        if (!bytesPerSecond || bytesPerSecond <= 0)
            return "0B/s";
        const units = ["B/s", "KB/s", "MB/s", "GB/s"];
        let value = bytesPerSecond;
        let unitIndex = 0;
        while (value >= 1024 && unitIndex < units.length - 1) {
            value /= 1024;
            unitIndex += 1;
        }
        const decimals = value >= 100 ? 0 : 1;
        return value.toFixed(decimals) + units[unitIndex];
    }

    function ethernetLabel() {
        return root.ethernetSubsystem === "usb" ? "USB Ethernet" : "Ethernet";
    }

    function ethernetDescription() {
        return root.ethernetDeviceLabel !== "" ? root.ethernetDeviceLabel : root.ethernetLabel();
    }

    function connectionLabel() {
        if (root.connectionType === "wifi")
            return root.connectionState === "connected" ? "Wi-Fi connected" : "Wi-Fi disconnected";
        if (root.connectionType === "ethernet") {
            if (root.connectionState === "connected (externally)")
                return root.ethernetDescription() + " linked";
            return root.connectionState === "connected" ? root.ethernetDescription() + " connected" : root.ethernetDescription() + " disconnected";
        }
        return "Offline";
    }

    function connectionIcon() {
        if (root.connectionType === "wifi") {
            if (root.connectionState === "connected")
                return root.iconForSignal();
            return root.disconnectedIcon;
        }
        if (root.connectionType === "ethernet") {
            if (root.connectionState === "connected")
                return root.ethernetSubsystem === "usb" ? root.usbEthernetIcon : root.ethernetIcon;
            if (root.connectionState === "connected (externally)")
                return root.linkedIcon;
            return root.ethernetIcon;
        }
        return root.disconnectedIcon;
    }

    function sourceIcon(sourceType) {
        if (sourceType === "wifi")
            return "󰖩";
        if (sourceType === "ethernet")
            return root.ethernetIcon;
        return root.disconnectedIcon;
    }

    function sourceTypeLabel(sourceType) {
        if (sourceType === "wifi")
            return "Wi-Fi";
        if (sourceType === "ethernet")
            return "Ethernet";
        return "Network";
    }

    tooltipHoverable: true
    tooltipText: ""
    tooltipTitle: root.connectionType === "wifi" ? "Wi-Fi" : (root.connectionType === "ethernet" ? root.ethernetLabel() : "Ethernet")

    content: [
        IconLabel {
            color: root.connectionState === "connected" ? Config.color.tertiary : Config.color.on_surface_variant
            text: root.connectionIcon()
        }
    ]

    Component {
        id: sourceRowDelegate

        Rectangle {
            required property var modelData

            readonly property bool active: !!modelData && !!modelData.active
            readonly property string sourceName: modelData ? String(modelData.name || "") : ""
            readonly property string sourceType: modelData ? String(modelData.type || "") : ""
            readonly property string sourceDevice: modelData ? String(modelData.device || "") : ""
            readonly property bool connectable: modelData ? !!modelData.connectable : false
            readonly property bool switching: root.sourceSwitching && root.sourceSwitchingName === sourceName

            Layout.fillWidth: true
            Layout.preferredHeight: root.sourceRowHeight
            radius: Config.shape.corner.md
            color: rowMouseArea.containsMouse
                ? Qt.alpha(Config.color.surface_variant, 0.45)
                : (active ? Qt.alpha(Config.color.primary_container, 0.45) : Config.color.surface_container_high)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Config.space.sm
                anchors.rightMargin: Config.space.sm
                spacing: Config.space.sm

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: 28
                    Layout.preferredWidth: 28
                    color: active ? Qt.alpha(Config.color.primary, 0.7) : Config.color.surface_variant
                    radius: width / 2

                    Text {
                        anchors.centerIn: parent
                        color: active ? Config.color.on_primary : Config.color.on_surface
                        font.family: Config.iconFontFamily
                        font.pixelSize: Config.type.labelLarge.size
                        text: root.sourceIcon(sourceType)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Config.space.none

                    Text {
                        Layout.fillWidth: true
                        color: active ? Config.color.on_primary_container : Config.color.on_surface
                        elide: Text.ElideRight
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.bodyLarge.size
                        font.weight: Config.type.bodyLarge.weight
                        text: sourceName !== "" ? sourceName : root.sourceTypeLabel(sourceType)
                    }
                    Text {
                        Layout.fillWidth: true
                        color: Config.color.on_surface_variant
                        elide: Text.ElideRight
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.labelMedium.size
                        text: sourceDevice !== "" ? (root.sourceTypeLabel(sourceType) + " • " + sourceDevice) : root.sourceTypeLabel(sourceType)
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: activeLabel.implicitHeight + Config.spaceHalfXs
                    Layout.preferredWidth: activeLabel.implicitWidth + Config.space.sm
                    color: switching ? Qt.alpha(Config.color.secondary, 0.95) : Qt.alpha(Config.color.tertiary, 0.9)
                    radius: Config.shape.corner.sm
                    visible: switching

                    Text {
                        id: activeLabel

                        anchors.centerIn: parent
                        color: switching ? Config.color.on_secondary : Config.color.on_tertiary
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.labelSmall.size
                        font.weight: Font.Bold
                        text: "SWITCHING"
                    }
                }
            }

            MK.HybridRipple {
                anchors.fill: parent
                color: active ? Config.color.on_primary_container : Config.color.on_surface
                pressX: rowMouseArea.pressX
                pressY: rowMouseArea.pressY
                pressed: rowMouseArea.pressed
                radius: parent.radius
                stateLayerEnabled: false
                stateOpacity: 0
            }

            MouseArea {
                id: rowMouseArea

                property real pressX: width / 2
                property real pressY: height / 2

                anchors.fill: parent
                enabled: connectable && !active && !root.sourceSwitching
                hoverEnabled: true
                onClicked: function() {
                    NetworkService.switchSource(modelData);
                }
                onPressed: function(mouse) {
                    pressX = mouse.x;
                    pressY = mouse.y;
                }
            }
        }
    }

    tooltipContent: Component {
        ColumnLayout {
            id: menu

            readonly property int maxMenuWidth: 520
            readonly property int minMenuWidth: 240
            readonly property int menuWidth: Math.min(menu.maxMenuWidth, Math.max(menu.minMenuWidth, headerRow.implicitWidth))

            implicitWidth: menu.menuWidth
            spacing: Config.space.md
            width: menu.menuWidth

            RowLayout {
                id: headerRow

                Layout.fillWidth: true
                spacing: Config.space.md

                Item {
                    Layout.preferredHeight: Config.space.xxl * 2
                    Layout.preferredWidth: Config.space.xxl * 2

                    Rectangle {
                        anchors.centerIn: parent
                        color: Qt.alpha(root.connectionState === "connected" ? Config.color.tertiary : Config.color.on_surface_variant, 0.12)
                        height: parent.height
                        radius: height / 2
                        width: parent.width
                    }
                    Text {
                        anchors.centerIn: parent
                        color: root.connectionState === "connected" ? Config.color.tertiary : Config.color.on_surface_variant
                        font.pixelSize: Config.type.headlineLarge.size
                        text: root.connectionIcon()
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitHeight: headerContent.implicitHeight

                    ColumnLayout {
                        id: headerContent

                        anchors.fill: parent
                        spacing: Config.space.none

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Config.space.xs

                            Text {
                                id: headerTitleText

                                Layout.minimumWidth: 0
                                color: Config.color.on_surface
                                elide: Text.ElideRight
                                font.family: Config.fontFamily
                                font.pixelSize: Config.type.headlineSmall.size
                                font.weight: Font.Bold
                                text: root.connectionType === "wifi"
                                    ? (root.ssid !== "" ? root.ssid : "Wi-Fi")
                                    : (root.connectionType === "ethernet" ? root.ethernetLabel() : "Disconnected")
                            }
                            Text {
                                color: Config.color.on_surface_variant
                                font.family: Config.iconFontFamily
                                font.pixelSize: Config.type.labelLarge.size
                                text: root.connectionType === "wifi" ? (root.detailsExpanded ? "󰅀" : "󰅂") : ""
                                visible: root.connectionType === "wifi"
                            }
                            Item { Layout.fillWidth: true }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            color: Config.color.on_surface_variant
                            elide: Text.ElideRight
                            font.family: Config.fontFamily
                            font.pixelSize: Config.type.labelMedium.size
                            text: root.connectionLabel()
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: root.connectionType === "wifi" ? Qt.PointingHandCursor : Qt.ArrowCursor
                        enabled: root.connectionType === "wifi"
                        onClicked: root.detailsExpanded = !root.detailsExpanded
                    }
                }
                Item { Layout.fillWidth: true }
            }

            ProgressBar {
                Layout.fillWidth: true
                Layout.preferredHeight: Config.space.xs
                fillColor: Config.color.tertiary
                trackColor: Config.color.surface_variant
                value: root.signalPercent / 100
                visible: root.connectionType === "wifi" && root.connectionState === "connected"
            }

            StackLayout {
                Layout.fillWidth: true
                currentIndex: root.connectionType === "wifi" && root.detailsExpanded ? 1 : 0

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Config.space.md

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Config.space.xs
                        visible: root.connectionType !== "wifi"

                        SectionHeader { text: "NETWORK DETAILS" }

                        InfoRow {
                            Layout.fillWidth: true
                            label: "Device"
                            value: root.deviceName
                            visible: root.deviceName !== ""
                        }
                        InfoRow {
                            Layout.fillWidth: true
                            label: "IP Address"
                            value: root.ipAddress
                            visible: root.ipAddress !== ""
                        }
                        InfoRow {
                            Layout.fillWidth: true
                            label: "Gateway"
                            value: root.gateway
                            visible: root.gateway !== ""
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Config.space.xs
                        visible: root.connectionState === "connected"

                        SectionHeader { text: "TRAFFIC" }

                        TrafficGraph {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 72
                            adaptiveMax: root.trafficScaleMax
                            downColor: Qt.alpha(Config.color.on_surface_variant, 0.9)
                            downFillOpacity: 0.08
                            lineWidth: 1.35
                            rxHistory: root.rxHistory
                            txHistory: root.txHistory
                            upColor: Qt.alpha(Config.color.on_surface, 0.82)
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Config.space.sm

                            Text {
                                color: Config.color.secondary
                                font.family: Config.fontFamily
                                font.pixelSize: Config.type.labelMedium.size
                                text: "Up " + root.formatRate(root.txBytesPerSec)
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                color: Config.color.tertiary
                                font.family: Config.fontFamily
                                font.pixelSize: Config.type.labelMedium.size
                                text: "Down " + root.formatRate(root.rxBytesPerSec)
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Config.space.xs
                        visible: root.sourceEntries.length > 0 || root.sourceSwitching || root.sourceError !== ""

                        SectionHeader { text: "INTERNET SOURCES" }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Config.space.xs

                            Repeater {
                                model: root.sourceEntries
                                delegate: sourceRowDelegate
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            color: Config.color.on_surface_variant
                            font.family: Config.fontFamily
                            font.pixelSize: Config.type.labelMedium.size
                            text: "Applying " + root.sourceSwitchingName + "..."
                            visible: root.sourceSwitching && root.sourceSwitchingName !== ""
                        }

                        Text {
                            Layout.fillWidth: true
                            color: Config.color.error
                            font.family: Config.fontFamily
                            font.pixelSize: Config.type.labelMedium.size
                            text: root.sourceError
                            visible: root.sourceError !== ""
                            wrapMode: Text.Wrap
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Config.space.xs

                    SectionHeader { text: "NETWORK DETAILS" }

                    InfoRow {
                        Layout.fillWidth: true
                        label: "Device"
                        value: root.deviceName
                        visible: root.deviceName !== ""
                    }
                    InfoRow {
                        Layout.fillWidth: true
                        label: "IP Address"
                        value: root.ipAddress
                        visible: root.ipAddress !== ""
                    }
                    InfoRow {
                        Layout.fillWidth: true
                        label: "Gateway"
                        value: root.gateway
                        visible: root.gateway !== ""
                    }
                    InfoRow {
                        Layout.fillWidth: true
                        label: "Frequency"
                        value: root.formatFrequency(root.frequencyMhz)
                        visible: root.connectionType === "wifi" && root.frequencyMhz > 0
                    }
                }
            }

            TooltipActionsRow {
                spacing: Config.space.sm

                ActionChip {
                    Layout.fillWidth: true
                    text: "Open Settings"
                    onClicked: Common.ProcessHelper.execDetached(root.onClickCommand)
                }
                ActionChip {
                    Layout.fillWidth: true
                    text: "Refresh"
                    onClicked: NetworkService.refreshNetwork()
                }
            }
        }
    }

    onTooltipActiveChanged: {
        if (root.tooltipActive && !root._tooltipHeld) {
            root._tooltipHeld = true;
            NetworkService.addTooltipUser();
        } else if (!root.tooltipActive && root._tooltipHeld) {
            root._tooltipHeld = false;
            NetworkService.removeTooltipUser();
        }
    }

    Component.onDestruction: {
        if (root._tooltipHeld) {
            root._tooltipHeld = false;
            NetworkService.removeTooltipUser();
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Common.ProcessHelper.execDetached(root.onClickCommand)
    }
}
