pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Qcm.Material as MD
import "../common" as Common
import "./components" as Components

Item {
    id: root

    readonly property int popupWidth: 320
    readonly property int popupMaxHeight: 560
    readonly property int maxNotifications: 50
    readonly property bool inGroupFocusView: notificationStore.focusedGroupKey.length > 0
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
        property bool popupExiting: false
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
        property Timer popupExitTimer

        onNotificationChanged: {
            if (!dismissing && notification === null) {
                notificationStore.dismissNotification(notificationId);
                return;
            }
            if (notification) {
                notification.closed.connect(function() {
                    if (!dismissing)
                        notificationStore.dismissNotification(notificationId);
                });
            }
        }
        onTitleChanged: notificationStore.updateGroupedModel()
        onSummaryChanged: notificationStore.updateGroupedModel()
        onAppNameChanged: notificationStore.updateGroupedModel()
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
        property var groupedModel: []
        property string focusedGroupKey: ""
        property string focusedGroupTitle: ""
        property var focusedEntries: []

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
            pruneOldestNotifications();
        }

        function pruneOldestNotifications() {
            while (notificationsModel.count > root.maxNotifications) {
                const oldestIndex = notificationsModel.count - 1;
                const oldestItem = notificationsModel.get(oldestIndex);
                if (!oldestItem || !oldestItem.entryObj) {
                    notificationsModel.remove(oldestIndex);
                    continue;
                }

                const oldestId = oldestItem.notificationId;
                const oldestEntry = oldestItem.entryObj;

                if (oldestEntry.timer) {
                    oldestEntry.timer.stop();
                    oldestEntry.timer.destroy();
                }

                oldestEntry.dismissing = true;
                requestDismiss(oldestEntry.notification);
                notificationsModel.remove(oldestIndex);

                const popupIndex = findIndexById(popupsModel, oldestId);
                if (popupIndex !== -1)
                    popupsModel.remove(popupIndex);

                oldestEntry.destroy();
            }

            updateGroupedModel();
        }

        function dismissNotification(id) {
            // If this notification is currently visible as a popup, animate it out
            // first, then complete the dismissal.
            const popupIndex = findIndexById(popupsModel, id);
            if (popupIndex !== -1) {
                const popupEntry = popupsModel.get(popupIndex).entryObj;
                if (popupEntry && !popupEntry.popupExiting) {
                    popupEntry.popupExiting = true;
                    if (!popupEntry.popupExitTimer) {
                        popupEntry.popupExitTimer = Qt.createQmlObject(
                            'import QtQuick; Timer { repeat: false }',
                            popupEntry,
                            'PopupExitTimer'
                        );
                        popupEntry.popupExitTimer.triggered.connect(function() {
                            // Complete dismissal after the popup exit motion.
                            notificationStore.dismissNotificationImmediate(id);
                        });
                    }
                    popupEntry.popupExitTimer.interval = Common.Config.motion.duration.longMs;
                    popupEntry.popupExitTimer.restart();
                    return;
                }
            }
            notificationStore.dismissNotificationImmediate(id);
        }

        function dismissNotificationImmediate(id) {
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
            if (popupIndex !== -1)
                popupsModel.remove(popupIndex);
            entry.destroy();
            updateGroupedModel();
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
            groupedModel = [];
            focusedGroupKey = "";
            focusedGroupTitle = "";
            focusedEntries = [];
        }

        function normalizeGroupKey(text) {
            const raw = text === undefined || text === null ? "" : String(text);
            return raw.trim().replace(/\s+/g, " ").toLowerCase();
        }

        function autoDetectedTitle(entry) {
            if (!entry)
                return "Notifications";

            const titleRaw = entry.title === undefined || entry.title === null ? "" : String(entry.title).trim();
            const title = normalizeGroupKey(titleRaw);
            if (title.length > 0)
                return titleRaw;

            const summaryRaw = entry.summary === undefined || entry.summary === null ? "" : String(entry.summary).trim();
            const summary = normalizeGroupKey(summaryRaw);
            if (summary.length > 0)
                return summaryRaw;

            const appNameRaw = entry.appName === undefined || entry.appName === null ? "" : String(entry.appName).trim();
            const appName = normalizeGroupKey(appNameRaw);
            if (appName.length > 0)
                return appNameRaw;
            return "Notifications";
        }

        function updateGroupedModel() {
            const seenKeys = {};
            const groups = {};
            const orderedKeys = [];

            for (let i = 0; i < notificationsModel.count; i++) {
                const item = notificationsModel.get(i);
                const entry = item ? item.entryObj : null;
                if (!entry)
                    continue;

                const detectedTitle = autoDetectedTitle(entry);
                const key = normalizeGroupKey(detectedTitle);

                if (!seenKeys[key]) {
                    seenKeys[key] = true;
                    orderedKeys.push(key);
                    groups[key] = {
                        groupKey: key,
                        title: detectedTitle,
                        entries: []
                    };
                }

                groups[key].entries.push(entry);
            }

            const nextGroupedModel = [];
            for (let i = 0; i < orderedKeys.length; i++) {
                const key = orderedKeys[i];
                const group = groups[key];
                nextGroupedModel.push({
                    groupKey: key,
                    title: group.title,
                    count: group.entries.length,
                    entries: group.entries
                });
            }

            groupedModel = nextGroupedModel;

            if (focusedGroupKey.length === 0) {
                focusedGroupTitle = "";
                focusedEntries = [];
                return;
            }

            const focusedGroup = nextGroupedModel.find(group => group.groupKey === focusedGroupKey);
            if (!focusedGroup) {
                focusedGroupKey = "";
                focusedGroupTitle = "";
                focusedEntries = [];
                return;
            }

            focusedGroupTitle = focusedGroup.title;
            focusedEntries = focusedGroup.entries;
        }

        function enterGroupFocus(key) {
            if (!key || key.length === 0)
                return;
            focusedGroupKey = key;
            updateGroupedModel();
        }

        function leaveGroupFocus() {
            focusedGroupKey = "";
            focusedGroupTitle = "";
            focusedEntries = [];
        }

        function timeoutNotification(id) {
            const index = findIndexById(notificationsModel, id);
            if (index === -1) {
                return;
            }
            const entry = notificationsModel.get(index).entryObj;
            const popupIndex = findIndexById(popupsModel, id);
            if (popupIndex === -1)
                return;

            if (entry.popupExiting)
                return;

            entry.popupExiting = true;
            if (!entry.popupExitTimer) {
                entry.popupExitTimer = Qt.createQmlObject(
                    'import QtQuick; Timer { repeat: false }',
                    entry,
                    'PopupTimeoutExitTimer'
                );
                entry.popupExitTimer.triggered.connect(function() {
                    // Remove from popup stack after exit animation.
                    const pi = findIndexById(popupsModel, id);
                    if (pi !== -1)
                        popupsModel.remove(pi);
                    entry.popup = false;
                    entry.popupExiting = false;

                    // Transient notifications fully disappear after timeout.
                    if (entry.isTransient) {
                        notificationStore.dismissNotificationImmediate(id);
                    }
                });
            }
            entry.popupExitTimer.interval = Common.Config.motion.duration.longMs;
            entry.popupExitTimer.restart();
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
                keepOnReload: false
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

    MD.Pane {
        anchors.fill: parent
        radius: Common.Config.shape.corner.lg
        backgroundColor: Common.Config.color.surface_container

        Rectangle {
            anchors.fill: parent
            border.width: 1
            border.color: Common.Config.color.outline
            color: "transparent"
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
            id: headerRow
            Layout.fillWidth: true
            spacing: Common.Config.space.sm

            readonly property int headerNotificationCount: root.inGroupFocusView
                ? notificationStore.focusedEntries.length
                : notificationStore.model.count

            Item {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18

                Text {
                    anchors.centerIn: parent
                    text: "\uf0f3"
                    color: Common.Config.color.primary
                    font.family: Common.Config.iconFontFamily
                    font.pixelSize: 16
                }

                Rectangle {
                    visible: headerRow.headerNotificationCount > 1
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -4
                    anchors.topMargin: -4
                    color: Common.Config.color.error
                    radius: height / 2
                    implicitHeight: 14
                    implicitWidth: Math.max(14, badgeText.implicitWidth + 6)

                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: headerRow.headerNotificationCount > 99 ? "99+" : headerRow.headerNotificationCount.toString()
                        color: Common.Config.color.on_error
                        font.family: Common.Config.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.rightMargin: Common.Config.space.xl
                text: root.inGroupFocusView
                    ? notificationStore.focusedGroupTitle
                    : "Notifications"
                color: Common.Config.color.on_surface
                font.family: Common.Config.fontFamily
                font.pixelSize: Common.Config.type.titleMedium.size
                font.weight: Common.Config.type.titleMedium.weight
                elide: Text.ElideRight
            }

            Components.ActionButton {
                visible: root.inGroupFocusView
                label: "Back"
                icon: "\uf060"
                onClicked: notificationStore.leaveGroupFocus()
            }

            Components.ActionButton {
                visible: notificationStore.model.count > 0
                label: "Clear"
                icon: "\uf1f8"
                onClicked: {
                    if (root.inGroupFocusView) {
                        const entries = notificationStore.focusedEntries.slice();
                        entries.forEach(entry => notificationStore.dismissNotification(entry.notificationId));
                        return;
                    }
                    notificationStore.dismissAll();
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Common.Config.space.sm
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

            MD.ListView {
                id: notificationList
                anchors.fill: parent
                visible: notificationStore.model.count > 0
                spacing: Common.Config.space.sm
                model: root.inGroupFocusView ? notificationStore.focusedEntries : notificationStore.groupedModel
                clip: true

                T.ScrollBar.vertical: MD.ScrollBar {
                    policy: T.ScrollBar.AsNeeded
                }

                add: Transition {
                    ParallelAnimation {
                        NumberAnimation {
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: 0
                            easing.type: Common.Config.motion.easing.standard
                        }
                        NumberAnimation {
                            property: "x"
                            from: notificationList.width + (2 * Common.Config.space.sm)
                            to: 0
                            duration: Common.Config.motion.duration.longMs
                            easing.type: Common.Config.motion.easing.standard
                        }
                    }
                }

                remove: Transition {
                    ParallelAnimation {
                        NumberAnimation {
                            property: "opacity"
                            to: 0
                            duration: 0
                            easing.type: Common.Config.motion.easing.standard
                        }
                        NumberAnimation {
                            property: "x"
                            to: notificationList.width + (2 * Common.Config.space.sm)
                            duration: Common.Config.motion.duration.longMs
                            easing.type: Common.Config.motion.easing.standard
                        }
                    }
                }

                delegate: Loader {
                    id: delegateLoader
                    required property var modelData
                    width: ListView.view.width
                    sourceComponent: root.inGroupFocusView ? focusedEntryDelegate : groupedEntryDelegate
                    onLoaded: item.modelData = Qt.binding(function() { return delegateLoader.modelData; })
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

    Component {
        id: groupedEntryDelegate

        Item {
            id: groupedRoot
            property var modelData
            readonly property var group: modelData ?? ({ groupKey: "", title: "Notifications", count: 0, entries: [] })

            width: ListView.view ? ListView.view.width : 0
            implicitHeight: groupedColumn.implicitHeight
            height: implicitHeight

            Column {
                id: groupedColumn
                width: parent.width
                spacing: Common.Config.space.xs

                Components.NotificationCard {
                    width: groupedColumn.width
                    entry: groupedRoot.group.entries[0]
                    onDismissRequested: notificationStore.dismissNotification(entry.notificationId)
                }
            }
        }
    }

    Component {
        id: focusedEntryDelegate

        Components.NotificationCard {
            property var modelData
            width: ListView.view ? ListView.view.width : 0
            entry: modelData
            onDismissRequested: notificationStore.dismissNotification(entry.notificationId)
        }
    }

    PanelWindow {
        id: popupWindow
        visible: popupContent.opacity > 0.01
        color: "transparent"
        implicitWidth: root.popupWidth
        implicitHeight: Math.min(root.popupMaxHeight, popupFlick.contentHeight + Common.Config.space.md * 2)
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

            Flickable {
                id: popupFlick
                anchors {
                    top: parent.top
                    right: parent.right
                    left: parent.left
                    margins: Common.Config.space.sm
                }
                contentWidth: width
                contentHeight: popupColumn.implicitHeight
                height: Math.min(root.popupMaxHeight, contentHeight)
                interactive: contentHeight > root.popupMaxHeight
                clip: true
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds
                boundsMovement: Flickable.StopAtBounds

                Column {
                    id: popupColumn
                    width: popupFlick.width
                    spacing: Common.Config.space.sm

	                    Repeater {
	                        model: notificationStore.popupModel

	                        Item {
	                            id: popupDelegate
	                            required property int notificationId
	                            required property var entryObj

	                            width: popupColumn.width
	                            implicitHeight: popupNotif.implicitHeight
	                            height: implicitHeight

	                            Components.PopupNotification {
	                                id: popupNotif
	                                width: parent.width
	                                entry: popupDelegate.entryObj
	                                onDismissRequested: notificationStore.dismissNotification(popupDelegate.notificationId)
	                            }
	                        }
	                    }
	                }
            }
        }
    }
}
