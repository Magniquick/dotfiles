pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets

import "../common" as Common

WrapperRectangle {
    id: root

    required property var colors
    required property string mode // region | window | screen
    required property string recordingState // idle | selecting | countdown | recording
    required property bool screenFrozen
    required property bool saveToDisk
    required property bool recordMode

    signal modeSelected(string mode)
    signal screenFrozenToggled(bool frozen)
    signal saveToDiskToggled(bool enabled)
    signal recordRequested

    color: Qt.alpha(root.colors.surface, 0.93)
    margin: 8
    radius: 12
    opacity: root.recordingState === "recording" ? 0 : 1
    visible: opacity > 0.05

    Behavior on opacity {
        NumberAnimation {
            duration: 180
            easing.type: Easing.InOutQuad
        }
    }

    Row {
        id: settingRow
        anchors.margins: root.margin
        anchors.centerIn: parent
        spacing: 16

        Row {
            id: buttonRow
            enabled: root.recordingState !== "countdown" && root.recordingState !== "recording"
            spacing: 8

            Repeater {
                model: [
                    { mode: "region", icon: "region" },
                    { mode: "window", icon: "window" },
                    { mode: "screen", icon: "screen" }
                ]

                delegate: Button {
                    id: modeButton
                    required property var modelData

                    implicitHeight: 48
                    implicitWidth: 48

                    background: Rectangle {
                        color: {
                            if (root.mode === modeButton.modelData.mode)
                                return Qt.alpha(root.colors.primary, 0.5);
                            if (modeButton.hovered)
                                return Qt.alpha(root.colors.surface_container_high, 0.5);
                            return Qt.alpha(root.colors.surface_container, 0.5);
                        }
                        radius: 8

                        Behavior on color {
                            ColorAnimation { duration: 100 }
                        }
                    }

                    contentItem: Item {
                        anchors.fill: parent

                        Image {
                            anchors.centerIn: parent
                            fillMode: Image.PreserveAspectFit
                            height: 24
                            width: 24
                            source: Qt.resolvedUrl(`../icons/${modeButton.modelData.icon}.svg`)
                        }
                    }

                    onClicked: root.modeSelected(modeButton.modelData.mode)
                }
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.alpha(root.colors.surface_container_high, 0.8)
            height: 32
            width: 1
        }

        Row {
            id: switchRow
            anchors.verticalCenter: buttonRow.verticalCenter
            spacing: 8

            Button {
                id: freezeButton

                Accessible.name: root.screenFrozen ? "Screen frozen" : "Screen live"
                checkable: false
                enabled: root.recordingState !== "countdown" && root.recordingState !== "recording"
                implicitHeight: 48
                implicitWidth: 48

                background: Rectangle {
                    color: {
                        if (root.screenFrozen)
                            return Qt.alpha(root.colors.primary, 0.5);
                        if (freezeButton.hovered)
                            return Qt.alpha(root.colors.surface_container_high, 0.5);
                        return Qt.alpha(root.colors.surface_container, 0.5);
                    }
                    radius: 8

                    Behavior on color {
                        ColorAnimation { duration: 100 }
                    }
                }

                contentItem: Item {
                    anchors.fill: parent

                    Text {
                        anchors.centerIn: parent
                        color: root.colors.on_surface
                        font.family: Common.Config.iconFontFamily
                        font.pixelSize: 24
                        text: root.screenFrozen ? "" : ""
                    }
                }

                onClicked: root.screenFrozenToggled(!root.screenFrozen)
            }

            Button {
                id: saveButton

                Accessible.name: "Save to disk"
                checkable: false
                enabled: root.recordingState !== "countdown" && root.recordingState !== "recording"
                implicitHeight: 48
                implicitWidth: 48

                background: Rectangle {
                    color: {
                        if (root.saveToDisk)
                            return Qt.alpha(root.colors.primary, 0.5);
                        if (saveButton.hovered)
                            return Qt.alpha(root.colors.surface_container_high, 0.5);
                        return Qt.alpha(root.colors.surface_container, 0.5);
                    }
                    radius: 8

                    Behavior on color {
                        ColorAnimation { duration: 100 }
                    }
                }

                contentItem: Item {
                    anchors.fill: parent

                    Image {
                        anchors.centerIn: parent
                        fillMode: Image.PreserveAspectFit
                        height: 24
                        width: 24
                        source: Qt.resolvedUrl("../icons/save.svg")
                    }
                }

                onClicked: root.saveToDiskToggled(!root.saveToDisk)
            }

            Button {
                id: recordButton

                Accessible.name: "Recording indicator"
                checkable: false
                height: 48
                width: 48
                scale: root.recordMode ? 1.05 : 1
                transformOrigin: Item.Center

                background: Rectangle {
                    color: {
                        if (root.recordMode)
                            return Qt.alpha(root.colors.primary, 0.6);
                        if (recordButton.hovered)
                            return Qt.alpha(root.colors.surface_container_high, 0.5);
                        return Qt.alpha(root.colors.surface_container, 0.5);
                    }
                    radius: 8

                    Behavior on color {
                        ColorAnimation { duration: 100 }
                    }
                }

                contentItem: Item {
                    anchors.fill: parent

                    Image {
                        anchors.centerIn: parent
                        fillMode: Image.PreserveAspectFit
                        height: 24
                        width: 24
                        source: (root.recordingState === "selecting" || root.recordingState === "countdown")
                            ? Qt.resolvedUrl("../icons/start.svg")
                            : Qt.resolvedUrl("../icons/record.svg")
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: 140
                        easing.type: Easing.InOutQuad
                    }
                }

                onClicked: root.recordRequested()
            }
        }
    }
}
