pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../common" as Common
import "../components" as Components

Item {
    id: root
    // Don't force focus on the panel root; focus is managed explicitly by the shell
    // to avoid Wayland text-input surface churn during open/close animations.

    required property var tabs
    property int currentTabIndex: 0

    required property var messagesModel
    // Optional: used for copy-all without walking the model in QML.
    property var chatSession: null
    property bool aiBusy: false
    property string modelId: ""
    property string modelLabel: ""
    property string moodIcon: "\uf4c4"
    property string moodName: "Assistant"
    property bool connectionOnline: true
    property string connectionStatus: connectionOnline ? "online" : "offline"

    property bool showCommandPicker: false
    property string activeCommand: ""
    property var availableModels: []
    property var availableMoods: []

    property string footerLeftText: ""
    property string footerRightText: ""
    property color footerDotColor: Common.Config.color.tertiary

    // Metrics tab footer data (provided by MetricsView).
    readonly property string metricsUptime: metricsView ? metricsView.uptime : "--"
    readonly property bool metricsHealthy: metricsView ? metricsView.isHealthy : true

    signal closeRequested
    signal tabSelected(int index)
    signal sendRequested(string text, string attachmentsJson)
    signal commandTriggered(string command)
    signal regenerateRequested(string messageId)
    signal deleteRequested(string messageId)
    signal editRequested(string messageId, string newContent)
    signal modelSelected(string value)
    signal moodSelected(string value)
    signal dismissCommandPickerRequested

    function scrollToEnd() {
        Qt.callLater(() => {
            if (chatView)
                chatView.positionToEnd();
        });
    }

    function copyAllMessages() {
        if (chatView)
            chatView.copyAllMessages();
    }

    function focusComposer() {
        if (root.currentTabIndex !== 0)
            return;
        if (root.showCommandPicker)
            return;
        if (chatView && chatView.focusComposer)
            chatView.focusComposer();
    }

    function clearTextFocus() {
        if (chatView && chatView.clearTextFocus)
            chatView.clearTextFocus();
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            root.closeRequested();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Common.Config.color.surface_container
        border.width: 1
        border.color: Common.Config.color.outline
        radius: Common.Config.shape.corner.lg
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: Common.Config.space.md
        }
        spacing: Common.Config.sectionSpacing

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Common.Config.space.xs
        }

        Components.NavPill {
            Layout.alignment: Qt.AlignHCenter
            tabs: root.tabs
            currentIndex: root.currentTabIndex
            connectionStatus: root.connectionStatus
            onTabSelected: index => root.tabSelected(index)
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.currentTabIndex

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Components.ChatView {
                    id: chatView
                    anchors.fill: parent
                    messagesModel: root.messagesModel
                    chatSession: root.chatSession
                    busy: root.aiBusy
                    modelId: root.modelId
                    modelLabel: root.modelLabel
                    moodIcon: root.moodIcon
                    moodName: root.moodName
                    connectionOnline: root.connectionOnline
                    onSendRequested: function(text, attachmentsJson) {
                        root.sendRequested(text, attachmentsJson)
                    }
                    onCommandTriggered: command => root.commandTriggered(command)
                    onRegenerateRequested: messageId => root.regenerateRequested(messageId)
                    onDeleteRequested: messageId => root.deleteRequested(messageId)
                    onEditRequested: (messageId, newContent) => root.editRequested(messageId, newContent)
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.alpha(Common.Config.color.surface_dim, 0.92)
                    visible: root.showCommandPicker

                    readonly property bool isModelPicker: root.activeCommand === "model"

                    MouseArea {
                        id: overlayDismissArea
                        anchors.fill: parent
                        onClicked: mouse => {
                            if (!commandPicker || !commandPicker.visible) {
                                root.dismissCommandPickerRequested();
                                return;
                            }
                            const p = commandPicker.mapFromItem(overlayDismissArea, mouse.x, mouse.y);
                            const inside = p.x >= 0 && p.y >= 0 && p.x <= commandPicker.width && p.y <= commandPicker.height;
                            if (!inside)
                                root.dismissCommandPickerRequested();
                        }
                    }

                    Components.CommandPicker {
                        id: commandPicker
                        anchors.centerIn: parent
                        command: parent.isModelPicker ? "/MODEL" : "/MOOD"
                        options: parent.isModelPicker ? root.availableModels : root.availableMoods
                        showAllToggle: parent.isModelPicker
                        visible: root.showCommandPicker

                        onOptionSelected: value => {
                            if (root.activeCommand === "model")
                                root.modelSelected(value);
                            else
                                root.moodSelected(value);
                        }

                        onDismissed: root.dismissCommandPickerRequested()
                    }
                }
            }

            Components.MetricsView {
                id: metricsView
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            color: Common.Config.color.surface_container_low
            radius: Common.Config.shape.corner.md
            border.width: 1
            border.color: Qt.alpha(Common.Config.color.on_surface, 0.1)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Common.Config.space.md
                anchors.rightMargin: Common.Config.space.md

                Row {
                    spacing: Common.Config.space.sm

                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: root.footerDotColor
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.footerLeftText !== ""
                    }

                    Text {
                        text: root.footerLeftText
                        color: Common.Config.color.on_surface_variant
                        font.family: Common.Config.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: 0.7
                        visible: root.footerLeftText !== ""
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: root.footerRightText
                    color: Common.Config.color.on_surface_variant
                    font.family: Common.Config.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    opacity: 0.7
                    visible: root.footerRightText !== ""
                }
            }
        }
    }
}
