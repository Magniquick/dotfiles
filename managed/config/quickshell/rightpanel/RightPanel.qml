pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "../common" as Common
import "./components" as Components

Item {
    id: root

    readonly property int popupWidth: 320
    readonly property int popupMaxHeight: 560
    property bool notificationServerActive: false
    property int _notificationStatusFailures: 0
    property int _notificationStatusIntervalMs: 10000

    // Timeouts per urgency (matching dunst config)
    readonly property int timeoutLowMs: 3000
    readonly property int timeoutNormalMs: 8000
    readonly property int timeoutCriticalMs: 0  // 0 = no timeout

    function getTimeoutForUrgency(urgency) {
        if (urgency === "critical" || urgency === "2")
            return root.timeoutCriticalMs;
        if (urgency === "low" || urgency === "0")
            return root.timeoutLowMs;
        return root.timeoutNormalMs;
    }
    readonly property bool popupsVisible: notificationStore.popupModel.count > 0
    readonly property real popupTargetOpacity: popupsVisible ? 1 : 0

    component NotificationEntry: QtObject {
        required property int notificationId
        property var notification
        property bool popup: false
        property bool dismissing: false
        property bool isTransient: notification && notification.hints && notification.hints.transient ? true : false
        property string appName: notification && notification.appName ? notification.appName : ""
        property var title: notification ? notification.title : undefined
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
            if (!dismissing && notification === null) {
                notificationStore.dismissNotification(notificationId);
            }
        }
    }

    component NotificationTimeout: Timer {
        required property int notificationId
        running: true
        onTriggered: notificationStore.timeoutNotification(notificationId)
    }

    ListModel {
        id: notificationsModel
    }

    ListModel {
        id: popupsModel
    }

    QtObject {
        id: notificationStore
        property alias model: notificationsModel
        property alias popupModel: popupsModel
        property int idOffset: 0

        function findIndexById(model, id) {
            for (let i = 0; i < model.count; i++) {
                if (model.get(i).notificationId === id) {
                    return i;
                }
            }
            return -1;
        }

        function requestDismiss(notification) {
            if (!notification) {
                return;
            }
            if (typeof notification.dismiss === "function") {
                notification.dismiss();
                return;
            }
            if (typeof notification.close === "function") {
                notification.close();
                return;
            }
            if (typeof notification.expire === "function") {
                notification.expire();
            }
        }

        function addNotification(notification) {
            notification.tracked = true;
            const id = notification.id + idOffset;
            const entry = notificationEntryComponent.createObject(notificationStore, {
                "notificationId": id,
                "notification": notification
            });
            notificationsModel.insert(0, {
                "notificationId": id,
                "entryObj": entry
            });

            entry.popup = true;
            popupsModel.insert(0, {
                "notificationId": id,
                "entryObj": entry
            });
            // qmllint disable missing-property
            const urgencyTimeout = root.getTimeoutForUrgency(entry.urgency);
            // qmllint enable missing-property
            // Use notification's timeout if set, otherwise use urgency-based default
            // expireTimeout: 0 = never, -1 = use default, >0 = use value
            if (notification.expireTimeout !== 0 && urgencyTimeout !== 0) {
                const timeout = notification.expireTimeout > 0 ? notification.expireTimeout : urgencyTimeout;
                entry.timer = notificationTimerComponent.createObject(notificationStore, {
                    "notificationId": id,
                    "interval": timeout
                });
            }
        }

        function dismissNotification(id) {
            const index = findIndexById(notificationsModel, id);
            if (index === -1) {
                return;
            }
            const entry = notificationsModel.get(index).entryObj;
            if (entry.timer) {
                entry.timer.stop();
                entry.timer.destroy();
            }
            entry.dismissing = true;
            requestDismiss(entry.notification);
            notificationsModel.remove(index);

            const popupIndex = findIndexById(popupsModel, id);
            if (popupIndex !== -1) {
                popupsModel.remove(popupIndex);
            }
            entry.destroy();
        }

        function dismissAll() {
            const entries = [];
            for (let i = 0; i < notificationsModel.count; i++) {
                entries.push(notificationsModel.get(i).entryObj);
            }
            entries.forEach(entry => {
                if (entry.timer) {
                    entry.timer.stop();
                    entry.timer.destroy();
                }
                entry.dismissing = true;
                requestDismiss(entry.notification);
            });
            notificationsModel.clear();
            popupsModel.clear();
            entries.forEach(entry => entry.destroy());
        }

        function timeoutNotification(id) {
            const index = findIndexById(notificationsModel, id);
            if (index === -1) {
                return;
            }
            const entry = notificationsModel.get(index).entryObj;
            entry.popup = false;

            const popupIndex = findIndexById(popupsModel, id);
            if (popupIndex !== -1) {
                popupsModel.remove(popupIndex);
            }

            if (entry.isTransient) {
                dismissNotification(id);
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

    Loader {
        id: notificationServerLoader
        active: true
        sourceComponent: Component {
            NotificationServer {
                id: notificationServer
                actionIconsSupported: true
                actionsSupported: true
                bodyHyperlinksSupported: true
                bodyImagesSupported: true
                bodyMarkupSupported: true
                bodySupported: true
                extraHints: []
                imageSupported: true
                inlineReplySupported: true
                keepOnReload: true
                persistenceSupported: true

                onNotification: notification => {
                    notificationStore.addNotification(notification);
                }
            }
        }
    }

    Timer {
        id: notificationStatusTimer
        interval: root._notificationStatusIntervalMs
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!notificationStatusProcess.running) {
                notificationStatusProcess.running = true;
            }
        }
    }

    Process {
        id: notificationStatusProcess
        command: ["busctl", "--user", "status", "org.freedesktop.Notifications"]
        onExited: code => {
            if (code === 0) {
                root.notificationServerActive = true;
                root._notificationStatusFailures = 0;
                root._notificationStatusIntervalMs = 10000;
                return;
            }

            // Avoid thrashing the NotificationServer Loader if busctl is missing
            // or the bus is transient. Back off status checks instead.
            root.notificationServerActive = false;
            root._notificationStatusFailures += 1;

            const next = Math.min(300000, 10000 * Math.pow(2, root._notificationStatusFailures));
            root._notificationStatusIntervalMs = Math.round(next);
        }
    }

    Rectangle {
        anchors.fill: parent
        border.width: 1
        border.color: Common.Config.color.outline
        radius: Common.Config.shape.corner.lg
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Common.Config.color.surface_dim
            }
            GradientStop {
                position: 1.0
                color: Common.Config.color.surface_container
            }
        }
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

        RowLayout {
            Layout.fillWidth: true
            spacing: Common.Config.space.sm

            Text {
                text: "\uf0f3"
                color: Common.Config.color.primary
                font.family: Common.Config.iconFontFamily
                font.pixelSize: 16
            }

            Text {
                Layout.fillWidth: true
                text: "Notifications"
                color: Common.Config.color.on_surface
                font.family: Common.Config.fontFamily
                font.pixelSize: Common.Config.type.titleMedium.size
                font.weight: Common.Config.type.titleMedium.weight
            }

            Text {
                visible: notificationStore.model.count > 0
                text: notificationStore.model.count.toString()
                color: Common.Config.color.on_surface_variant
                font.family: Common.Config.fontFamily
                font.pixelSize: Common.Config.type.labelMedium.size
                font.weight: Common.Config.type.labelMedium.weight

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -Common.Config.space.xs
                    radius: Common.Config.shape.corner.sm
                    color: Common.Config.color.surface_variant
                    z: -1
                }
            }

            Components.ActionButton {
                visible: notificationStore.model.count > 0
                label: "Clear"
                icon: "\uf1f8"
                onClicked: notificationStore.dismissAll()
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                anchors.centerIn: parent
                visible: notificationStore.model.count === 0
                text: "No notifications"
                color: Common.Config.color.on_surface_variant
                font.family: Common.Config.fontFamily
                font.pixelSize: Common.Config.type.bodyMedium.size
                font.weight: Common.Config.type.bodyMedium.weight
            }

            ListView {
                id: notificationList
                anchors.fill: parent
                visible: notificationStore.model.count > 0
                spacing: Common.Config.space.sm
                model: notificationStore.model
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

                delegate: Components.NotificationCard {
                    required property var entryObj

                    width: ListView.view.width
                    entry: entryObj
                    onDismissRequested: notificationStore.dismissNotification(entry.notificationId)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            color: "transparent"
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
                        // qmllint disable missing-property
                        color: root.notificationServerActive ? Common.Config.color.tertiary : Common.Config.color.error
                        // qmllint enable missing-property
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "NOTIFICATION SERVER"
                        color: Common.Config.color.on_surface_variant
                        font.family: Common.Config.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: 0.7
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    // qmllint disable missing-property
                    text: root.notificationServerActive ? "ACTIVE" : "INACTIVE"
                    // qmllint enable missing-property
                    color: Common.Config.color.on_surface_variant
                    font.family: Common.Config.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                    opacity: 0.5
                }
            }
        }
    }

    PanelWindow {
        id: popupWindow
        visible: popupContent.opacity > 0.01
        color: "transparent"
        implicitWidth: root.popupWidth
        implicitHeight: Math.min(root.popupMaxHeight, popupListView.contentHeight + Common.Config.space.md * 2)
        // Keep popups on the same output as the owning right panel window.
        screen: root.QsWindow.window ? root.QsWindow.window.screen : null

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
                model: notificationStore.popupModel

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

                delegate: Components.PopupNotification {
                    required property var entryObj

                    width: ListView.view.width
                    entry: entryObj
                    onDismissRequested: notificationStore.dismissNotification(entry.notificationId)
                }
            }
        }
    }
}
