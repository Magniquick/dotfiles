import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "./common" as Common

Item {
    id: root

    readonly property int panelWidth: 420
    readonly property int popupWidth: 360
    readonly property int popupMaxHeight: 560
    readonly property int popupTimeoutMs: 7000
    readonly property bool popupsVisible: notificationStore.popupList.length > 0
    readonly property real popupTargetOpacity: popupsVisible ? 1 : 0

    component NotificationEntry: QtObject {
        required property int notificationId
        property var notification
        property bool popup: false
        property bool isTransient: notification && notification.hints && notification.hints.transient ? true : false
        property string appName: notification && notification.appName ? notification.appName : ""
        property string summary: notification && notification.summary ? notification.summary : ""
        property string body: notification && notification.body ? notification.body : ""
        property string iconSource: {
            if (notification && notification.appIcon && notification.appIcon.length > 0) {
                return notification.appIcon;
            }
            if (notification && notification.image && notification.image.length > 0) {
                return notification.image;
            }
            return "";
        }
        property string urgency: notification && notification.urgency ? notification.urgency.toString() : "normal"
        property Timer timer

        onNotificationChanged: {
            if (notification === null) {
                notificationStore.dismissNotification(notificationId);
            }
        }
    }

    component NotificationTimeout: Timer {
        required property int notificationId
        onTriggered: notificationStore.timeoutNotification(notificationId)
    }

    QtObject {
        id: notificationStore
        property list<NotificationEntry> list: []
        property list<NotificationEntry> popupList: []
        property int idOffset: 0

        function refreshPopupList() {
            popupList = list.filter(entry => entry.popup);
        }

        function addNotification(notification) {
            notification.tracked = true;
            const entry = notificationEntryComponent.createObject(notificationStore, {
                "notificationId": notification.id + idOffset,
                "notification": notification
            });
            list = [...list, entry];

            entry.popup = true;
            if (notification.expireTimeout !== 0) {
                entry.timer = notificationTimerComponent.createObject(notificationStore, {
                    "notificationId": entry.notificationId,
                    "interval": notification.expireTimeout < 0 ? root.popupTimeoutMs : notification.expireTimeout
                });
            }
            refreshPopupList();
        }

        function dismissNotification(id) {
            const index = list.findIndex(entry => entry.notificationId === id);
            if (index === -1) {
                return;
            }
            const entry = list[index];
            if (entry.timer) {
                entry.timer.stop();
                entry.timer.destroy();
            }
            if (entry.notification) {
                entry.notification.dismiss();
            }
            list.splice(index, 1);
            list = list.slice(0);
            refreshPopupList();
        }

        function dismissAll() {
            list.forEach(entry => {
                if (entry.timer) {
                    entry.timer.stop();
                    entry.timer.destroy();
                }
                if (entry.notification) {
                    entry.notification.dismiss();
                }
            });
            list = [];
            refreshPopupList();
        }

        function timeoutNotification(id) {
            const index = list.findIndex(entry => entry.notificationId === id);
            if (index === -1) {
                return;
            }
            const entry = list[index];
            entry.popup = false;
            if (entry.isTransient) {
                dismissNotification(id);
            } else {
                list = list.slice(0);
                refreshPopupList();
            }
        }
    }

    Component {
        id: notificationEntryComponent
        NotificationEntry {}
    }

    Component {
        id: notificationTimerComponent
        NotificationTimeout {}
    }

    NotificationServer {
        id: notificationServer
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        keepOnReload: false
        persistenceSupported: true

        onNotification: notification => {
            notificationStore.addNotification(notification);
        }
    }

    PanelWindow {
        id: popupWindow
        visible: popupContent.opacity > 0.01
        color: "transparent"
        implicitWidth: root.popupWidth
        implicitHeight: Math.min(root.popupMaxHeight, popupListView.contentHeight + Common.Config.space.md * 2)

        anchors {
            top: true
            right: true
        }

        WlrLayershell.namespace: "quickshell:right-panel:popups"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0

        Item {
            id: popupContent
            anchors.fill: parent
            transformOrigin: Item.TopRight
            opacity: root.popupTargetOpacity
            scale: root.popupsVisible ? 1 : 0.98

            Behavior on opacity {
                NumberAnimation {
                    duration: Common.Config.motion.duration.shortMs
                    easing.type: Common.Config.motion.easing.standard
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: Common.Config.motion.duration.shortMs
                    easing.type: Common.Config.motion.easing.standard
                }
            }

            ListView {
                id: popupListView
                anchors {
                    top: parent.top
                    right: parent.right
                    left: parent.left
                    margins: Common.Config.space.sm
                }
                implicitWidth: parent.width - Common.Config.space.md * 2
                implicitHeight: Math.min(root.popupMaxHeight, contentHeight)
                height: implicitHeight
                spacing: Common.Config.space.sm
                interactive: popupListView.contentHeight > root.popupMaxHeight
                clip: true
                model: notificationStore.popupList

                add: Transition {
                    ParallelAnimation {
                        NumberAnimation {
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: Common.Config.motion.duration.shortMs
                            easing.type: Common.Config.motion.easing.standard
                        }
                        NumberAnimation {
                            property: "y"
                            from: 8
                            to: 0
                            duration: Common.Config.motion.duration.shortMs
                            easing.type: Common.Config.motion.easing.standard
                        }
                    }
                }

                remove: Transition {
                    ParallelAnimation {
                        NumberAnimation {
                            property: "opacity"
                            to: 0
                            duration: Common.Config.motion.duration.shortMs
                            easing.type: Common.Config.motion.easing.standard
                        }
                        NumberAnimation {
                            property: "y"
                            to: 8
                            duration: Common.Config.motion.duration.shortMs
                            easing.type: Common.Config.motion.easing.standard
                        }
                    }
                }

                delegate: NotificationCard {
                    width: ListView.view.width
                    entry: modelData
                    popup: true
                    onDismissRequested: notificationStore.dismissNotification(entry.notificationId)
                }
            }
        }
    }

    PanelWindow {
        id: panelWindow
        visible: true
        color: "transparent"
        implicitWidth: root.panelWidth

        anchors {
            top: true
            right: true
            bottom: true
        }

        WlrLayershell.namespace: "quickshell:right-panel"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusiveZone: 0

        Item {
            id: panelContent
            anchors.fill: parent
            transformOrigin: Item.TopRight
            opacity: 0
            scale: 0.98

            Rectangle {
                anchors.fill: parent
                color: Common.Config.surface
                border.width: 1
                border.color: Common.Config.outline
                radius: Common.Config.shape.corner.lg
            }

            Component.onCompleted: panelIntro.start()

            SequentialAnimation {
                id: panelIntro
                NumberAnimation {
                    target: panelContent
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Common.Config.motion.duration.shortMs
                    easing.type: Common.Config.motion.easing.standard
                }
                NumberAnimation {
                    target: panelContent
                    property: "scale"
                    from: 0.98
                    to: 1
                    duration: Common.Config.motion.duration.shortMs
                    easing.type: Common.Config.motion.easing.standard
                }
            }
        }

        component ActionButton: Rectangle {
            id: actionButton
            property string label: ""
            signal clicked()
            radius: Common.Config.shape.corner.sm
            color: actionArea.pressed
                ? Qt.alpha(Common.ColorPalette.palette.overlay2, 0.35)
                : actionArea.containsMouse
                    ? Qt.alpha(Common.ColorPalette.palette.overlay2, 0.25)
                    : Common.Config.surfaceVariant
            implicitHeight: Common.Config.space.xl
            implicitWidth: buttonText.implicitWidth + Common.Config.space.md

            Behavior on color {
                ColorAnimation {
                    duration: Common.Config.motion.duration.shortMs
                    easing.type: Common.Config.motion.easing.standard
                }
            }

            Text {
                id: buttonText
                anchors.centerIn: parent
                text: actionButton.label
                color: Common.Config.textColor
                font.family: Common.Config.fontFamily
                font.pixelSize: Common.Config.type.labelMedium.size
                font.weight: Common.Config.type.labelMedium.weight
            }

            MouseArea {
                id: actionArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: actionButton.clicked()
            }
        }

        ColumnLayout {
            parent: panelContent
            anchors {
                fill: parent
                margins: Common.Config.space.md
            }
            spacing: Common.Config.space.sm

            RowLayout {
                Layout.fillWidth: true
                spacing: Common.Config.space.sm

                Text {
                    Layout.fillWidth: true
                    text: "Notifications"
                    color: Common.Config.textColor
                    font.family: Common.Config.fontFamily
                    font.pixelSize: Common.Config.type.titleMedium.size
                    font.weight: Common.Config.type.titleMedium.weight
                }

                ActionButton {
                    label: "Clear"
                    onClicked: notificationStore.dismissAll()
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Common.Config.space.sm
                model: notificationStore.list
                clip: true

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                add: Transition {
                    ParallelAnimation {
                        NumberAnimation {
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: Common.Config.motion.duration.shortMs
                            easing.type: Common.Config.motion.easing.standard
                        }
                        NumberAnimation {
                            property: "y"
                            from: 8
                            to: 0
                            duration: Common.Config.motion.duration.shortMs
                            easing.type: Common.Config.motion.easing.standard
                        }
                    }
                }

                remove: Transition {
                    ParallelAnimation {
                        NumberAnimation {
                            property: "opacity"
                            to: 0
                            duration: Common.Config.motion.duration.shortMs
                            easing.type: Common.Config.motion.easing.standard
                        }
                        NumberAnimation {
                            property: "y"
                            to: 8
                            duration: Common.Config.motion.duration.shortMs
                            easing.type: Common.Config.motion.easing.standard
                        }
                    }
                }

                delegate: NotificationCard {
                    width: ListView.view.width
                    entry: modelData
                    onDismissRequested: notificationStore.dismissNotification(entry.notificationId)
                }
            }
        }
    }
}
