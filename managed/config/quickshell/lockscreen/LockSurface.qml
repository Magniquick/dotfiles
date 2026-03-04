import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell

WlSessionLockSurface {
    id: root

    required property LockContext context
    property var now: new Date()

    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    ScreencopyView {
        id: background
        anchors.fill: parent
        captureSource: root.screen
        live: false
        layer.enabled: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1.0
            blurMax: 32
            brightness: -0.2
            saturation: 0.05
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#0b0e13"
        opacity: 0.5
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: 430
        spacing: 14

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(root.now, "HH:mm")
            color: "#e1e2e8"
            font.pixelSize: 80
            font.family: "Google Sans"
            font.weight: Font.DemiBold
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(root.now, "dddd, dd MMM")
            color: "#c3c6cf"
            font.pixelSize: 24
            font.family: "Google Sans"
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 16
            radius: 22
            color: "#1d2024"
            border.width: 1
            border.color: "#43474e"
            implicitHeight: inputRow.implicitHeight + 24

            RowLayout {
                id: inputRow
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 14
                spacing: 12

                Text {
                    text: "\uf023"
                    color: "#a3c9fe"
                    font.family: "JetBrainsMono NFP"
                    font.pixelSize: 20
                }

                TextField {
                    id: passField
                    Layout.fillWidth: true
                    placeholderText: root.context.unlockInProgress ? "Unlocking..." : "Enter password"
                    echoMode: TextInput.Password
                    color: "#e1e2e8"
                    placeholderTextColor: "#8d9199"
                    font.family: "Google Sans"
                    font.pixelSize: 18
                    enabled: !root.context.unlockInProgress
                    selectByMouse: false

                    background: Rectangle {
                        color: "transparent"
                    }

                    onTextChanged: {
                        root.context.currentText = text;
                        if (text.length > 0)
                            root.context.clearError();
                    }

                    onAccepted: root.context.tryUnlock()

                    Component.onCompleted: forceActiveFocus()
                }

                Button {
                    text: root.context.unlockInProgress ? "..." : "Unlock"
                    enabled: !root.context.unlockInProgress
                    onClicked: root.context.tryUnlock()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            visible: root.context.showFailure
            radius: 14
            color: "#93000a"
            border.width: 1
            border.color: "#ffb4ab"
            implicitHeight: failureText.implicitHeight + 16

            Text {
                id: failureText
                anchors.fill: parent
                anchors.margins: 8
                text: root.context.lastMessage.length > 0 ? root.context.lastMessage : "Authentication failed"
                wrapMode: Text.WordWrap
                color: "#ffdad6"
                font.family: "Google Sans"
                font.pixelSize: 13
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }
}
