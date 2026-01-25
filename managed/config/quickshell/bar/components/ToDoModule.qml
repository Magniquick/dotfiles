pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import ".."
import "../components"
import "../components/JsonUtils.js" as JsonUtils

ColumnLayout {
    id: root

    readonly property string cacheDir: {
        const homeDir = Quickshell.env("HOME");
        return homeDir && homeDir !== "" ? homeDir + "/.cache/quickshell/todoist" : "/tmp/quickshell-todoist";
    }
    readonly property string cachePath: root.cacheDir + "/tasks.json"
    property string currentProject: "Today"
    readonly property bool dropdownActive: projectSelector.popup.visible
    readonly property int iconSlot: Config.space.xxl * 2
    property string lastUpdated: ""
    property bool loading: false
    readonly property int minorSpace: Config.spaceHalfXs
    property bool parseError: false
    property var rawData: ({})
    readonly property var taskColors: [Config.color.tertiary, Config.color.secondary, Config.color.tertiary, Config.color.primary, Config.color.secondary, Config.color.tertiary]
    property var tasks: []
    readonly property string todoistBinary: Quickshell.shellPath(((Quickshell.shellDir || "").endsWith("/bar") ? "" : "bar/") + "scripts/todoist-api")
    readonly property string todoistEnvFile: Quickshell.shellPath(((Quickshell.shellDir || "").endsWith("/bar") ? "" : "bar/") + ".env")
    property bool usingCache: false

    function applyTodoistData(data, fromCache) {
        if (!data || typeof data !== "object")
            return;

        root.rawData = data;
        root.usingCache = !!fromCache;

        let projects = ["Today"];
        if (data.projects) {
            projects = projects.concat(Object.keys(data.projects));
        }
        projectSelector.model = projects;

        // Keep selection stable across refreshes
        let idx = projects.indexOf(root.currentProject);
        if (idx !== -1) {
            projectSelector.currentIndex = idx;
        } else {
            root.currentProject = "Today";
            projectSelector.currentIndex = 0;
        }

        root.updateTasks();
    }
    function cancelProjectSelectorClose() {
        projectSelectorCloseTimer.stop();
    }
    function getTaskColor(index) {
        return taskColors[index % taskColors.length];
    }
    function refresh() {
        root.loading = true;
        root.parseError = false;
        listRunner.trigger();
    }
    function scheduleProjectSelectorClose() {
        if (projectSelector.popup.visible)
            projectSelectorCloseTimer.restart();
    }
    function loadCache() {
        if (root.cachePath === "")
            return;
        cacheFile.reload();
        const wrapper = JsonUtils.parseObject(cacheFile.text());
        const cached = wrapper && wrapper.payload ? wrapper.payload : null;
        if (cached && typeof cached === "object") {
            root.applyTodoistData(cached, true);
            const cachedAt = wrapper.cachedAt ? new Date(wrapper.cachedAt) : null;
            if (cachedAt && !isNaN(cachedAt.getTime()))
                root.lastUpdated = Qt.formatDateTime(cachedAt, "hh:mm ap");
        } else {
            root.usingCache = false;
            if (root.parseError && (!root.rawData || Object.keys(root.rawData).length === 0))
                root.tasks = [];
        }
    }
    function shSingleQuote(value) {
        // Wrap for POSIX shell single-quoted string: ' -> '\''.
        return String(value).replace(/'/g, "'\\''");
    }
    function taskCountLabel(count) {
        return count === 1 ? "1 Task" : count + " Tasks";
    }
    function todoistCommand(args) {
        return root.todoistBinary + " --env-file '" + root.shSingleQuote(root.todoistEnvFile) + "' " + args;
    }
    function updateTasks() {
        if (!root.rawData)
            return;
        if (root.currentProject === "Today") {
            root.tasks = root.rawData.today || [];
        } else if (root.rawData.projects && root.rawData.projects[root.currentProject]) {
            root.tasks = root.rawData.projects[root.currentProject];
        } else {
            root.tasks = [];
        }
    }

    Layout.fillWidth: true
    spacing: Config.space.sm

    Component.onCompleted: root.loadCache()
    onVisibleChanged: {
        if (!visible && projectSelector.popup.visible)
            projectSelector.popup.close();
    }

    Timer {
        id: projectSelectorCloseTimer

        interval: 200
        repeat: false

        onTriggered: {
            if (!rootHover.hovered && !projectSelectorPopupHover.hovered && projectSelector.popup.visible)
                projectSelector.popup.close();
        }
    }
    HoverHandler {
        id: rootHover

        target: root

        onHoveredChanged: {
            if (hovered)
                root.cancelProjectSelectorClose();
            else
                root.scheduleProjectSelectorClose();
        }
    }
    CommandRunner {
        id: listRunner

        command: root.todoistCommand("list")
        intervalMs: 300000 // 5 minutes

        onRan: function (output) {
            const data = JsonUtils.parseObject(output);
            if (data) {
                root.applyTodoistData(data, false);
                root.lastUpdated = Qt.formatDateTime(new Date(), "hh:mm ap");
                root.parseError = false;

                const cachePayload = JSON.stringify({
                    cachedAt: new Date().toISOString(),
                    payload: data
                });
                cacheWriter.command = "mkdir -p \"" + root.cacheDir + "\" && printf %s '" + root.shSingleQuote(cachePayload) + "' > \"" + root.cachePath + "\"";
                cacheWriter.trigger();
            } else {
                root.parseError = true;
                root.loadCache();
            }
            root.loading = false;
        }
    }
    FileView {
        id: cacheFile

        path: root.cachePath
        watchChanges: true
        blockLoading: true

        onFileChanged: root.loadCache()
    }
    CommandRunner {
        id: cacheWriter

        command: ""
        enabled: true
        intervalMs: 0
    }
    CommandRunner {
        id: actionRunner

        onRan: function (output) {
            root.refresh();
        }
    }

    // Hero Section (Battery Style)
    RowLayout {
        Layout.fillWidth: true
        spacing: Config.space.md

        Item {
            Layout.preferredHeight: root.iconSlot
            Layout.preferredWidth: root.iconSlot
            implicitHeight: root.iconSlot
            implicitWidth: root.iconSlot

            Text {
                anchors.centerIn: parent
                color: Config.color.tertiary
                font.pixelSize: Config.type.headlineLarge.size
                text: "󰄭"
            }
        }
        ColumnLayout {
            spacing: Config.space.none

            Text {
                color: Config.color.on_surface
                font.family: Config.fontFamily
                font.pixelSize: Config.type.headlineMedium.size
                font.weight: Font.Bold
                text: root.loading ? "Loading tasks…" : (root.parseError ? (root.tasks.length > 0 ? (root.taskCountLabel(root.tasks.length) + " (cached)") : "Tasks unavailable") : root.taskCountLabel(root.tasks.length))
            }
            Text {
                color: Config.color.on_surface_variant
                font.family: Config.fontFamily
                font.pixelSize: Config.type.labelMedium.size
                text: root.loading ? "Fetching from Todoist…" : (root.parseError ? (root.usingCache ? "Todoist error — showing cached data." : "Todoist error — no cached data.") : "remaining to be completed.")
            }
        }
        Item {
            Layout.fillWidth: true
        }
    }

    // Branding Header & Project Selector
    RowLayout {
        Layout.fillWidth: true
        spacing: Config.space.md

        ComboBox {
            id: projectSelector

            Layout.preferredWidth: 140
            leftPadding: Config.space.none
            rightPadding: Config.space.none

            background: Item {
                implicitHeight: Config.type.bodySmall.line + root.minorSpace
                implicitWidth: 140
            }
            contentItem: Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Config.space.xs

                Text {
                    id: selectorLabel

                    color: Config.color.tertiary
                    elide: Text.ElideRight
                    font.family: Config.fontFamily
                    font.letterSpacing: root.minorSpace
                    font.pixelSize: Config.type.labelSmall.size
                    font.weight: Font.Black
                    text: projectSelector.displayText.toUpperCase()
                    verticalAlignment: Text.AlignVCenter
                    width: Math.min(implicitWidth, Math.max(0, projectSelector.width - dropdownIndicator.implicitWidth - (Config.space.xs + root.minorSpace)))
                }
                Text {
                    id: dropdownIndicator

                    color: Config.color.tertiary
                    font.family: Config.iconFontFamily
                    font.pixelSize: Config.type.labelMedium.size
                    rotation: projectSelector.popup.visible ? 90 : 0
                    text: "󰄼"

                    Behavior on rotation {
                        NumberAnimation {
                            duration: Config.motion.duration.shortMs
                            easing.type: Config.motion.easing.standard
                        }
                    }
                }
            }
            delegate: ItemDelegate {
                id: delegateRoot

                required property int index
                required property var modelData

                height: Config.barHeight
                highlighted: projectSelector.highlightedIndex === index
                width: ListView.view.width

                background: Rectangle {
                    anchors.fill: parent
                    anchors.margins: root.minorSpace
                    color: delegateRoot.highlighted ? Config.color.primary : (delegateRoot.hovered ? Config.color.surface_container_high : "transparent")
                    radius: Config.shape.corner.xs

                    Behavior on color {
                        ColorAnimation {
                            duration: Config.motion.duration.shortMs
                        }
                    }
                }
                contentItem: Text {
                    color: delegateRoot.highlighted ? Config.color.on_primary : Config.color.on_surface
                    elide: Text.ElideRight
                    font: projectSelector.font
                    leftPadding: Config.space.sm
                    text: delegateRoot.modelData
                    verticalAlignment: Text.AlignVCenter
                }
            }
            indicator: Item {
                implicitHeight: 0
                implicitWidth: 0
            }
            popup: Popup {
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent
                focus: true
                implicitHeight: contentItem.implicitHeight
                padding: Config.space.xs
                width: projectSelector.width
                y: projectSelector.height + Config.space.xs

                background: Rectangle {
                    border.color: Config.color.outline
                    border.width: 1
                    color: Config.color.surface
                    layer.enabled: true
                    radius: Config.shape.corner.md

                    layer.effect: MultiEffect {
                        shadowBlur: 0.4
                        shadowColor: Qt.alpha(Config.color.shadow, 0.2)
                        shadowEnabled: true
                        shadowVerticalOffset: 2
                    }
                }
                contentItem: ListView {
                    clip: true
                    currentIndex: projectSelector.highlightedIndex
                    implicitHeight: contentHeight
                    interactive: false
                    model: projectSelector.popup.visible ? projectSelector.delegateModel : null

                    ScrollIndicator.vertical: ScrollIndicator {}
                }
                enter: Transition {
                    NumberAnimation {
                        duration: Config.motion.duration.shortMs
                        from: 0
                        property: "opacity"
                        to: 1
                    }
                    NumberAnimation {
                        duration: Config.motion.duration.shortMs
                        easing.type: Easing.OutBack
                        from: 0.95
                        property: "scale"
                        to: 1
                    }
                }
                exit: Transition {
                    NumberAnimation {
                        duration: Config.motion.duration.shortMs
                        property: "opacity"
                        to: 0
                    }
                }

                Component.onCompleted: {
                    if (projectSelector.popup) {
                        projectSelector.popup.closePolicy = Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent;
                    }
                }
                onActiveFocusChanged: if (!activeFocus)
                    close()
                onOpened: {
                    root.cancelProjectSelectorClose();
                    forceActiveFocus();
                }

                Connections {
                    function onActiveChanged() {
                        if (Application.state !== Qt.ApplicationActive) {
                            projectSelector.popup.close();
                        }
                    }

                    target: Qt.application
                }
                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                }
                HoverHandler {
                    id: projectSelectorPopupHover

                    onHoveredChanged: {
                        if (hovered)
                            root.cancelProjectSelectorClose();
                        else
                            root.scheduleProjectSelectorClose();
                    }
                }
            }

            onActivated: index => {
                root.currentProject = model[index];
                root.updateTasks();
            }
        }
        Item {
            Layout.fillWidth: true
        }
    }
    // Task List
    ColumnLayout {
        id: taskListLayout

        Layout.fillWidth: true
        spacing: Config.space.sm

        Repeater {
            model: root.tasks

            delegate: RowLayout {
                id: taskItem

                property bool completing: false
                property bool deleting: false
                required property int index
                required property var modelData
                readonly property int stripeWidth: root.minorSpace + Math.round(root.minorSpace / 2)

                Layout.fillWidth: true
                spacing: Config.space.md

                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredHeight: Config.type.bodySmall.line + root.minorSpace
                    Layout.preferredWidth: taskItem.stripeWidth
                    implicitWidth: taskItem.stripeWidth
                    color: root.getTaskColor(taskItem.index)
                    opacity: 0.8
                    radius: Config.shape.corner.xs
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    opacity: taskItem.completing || taskItem.deleting ? 0.3 : 1.0
                    spacing: Config.space.none

                    Text {
                        Layout.fillWidth: true
                        color: root.getTaskColor(taskItem.index)
                        elide: Text.ElideRight
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.bodyMedium.size
                        font.weight: Font.Medium
                        text: taskItem.modelData.title
                    }
                    Text {
                        Layout.fillWidth: true
                        color: Config.color.on_surface_variant
                        elide: Text.ElideRight
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.labelSmall.size
                        maximumLineCount: 2
                        text: taskItem.modelData.notes || ""
                        visible: text !== ""
                        wrapMode: Text.WordWrap
                    }
                }
                Text {
                    color: root.getTaskColor(taskItem.index)
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.labelSmall.size
                    font.weight: Font.Bold
                    opacity: 0.7
                    text: taskItem.modelData.due_human || ""
                    visible: text !== ""
                }

                // Complete Button
                Text {
                    color: Config.color.tertiary
                    font.family: Config.iconFontFamily
                    font.pixelSize: Config.type.titleSmall.size
                    font.weight: Font.Black
                    opacity: taskItem.completing ? 0.2 : 0.7
                    text: "󰄬"

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true

                        onClicked: {
                            taskItem.completing = true;
                            actionRunner.command = root.todoistCommand("complete " + root.shSingleQuote(taskItem.modelData.id));
                            actionRunner.trigger();
                        }
                        onEntered: if (!taskItem.completing)
                            parent.opacity = 1.0
                        onExited: if (!taskItem.completing)
                            parent.opacity = 0.7
                    }
                }
            }
        }
        Text {
            color: Config.color.on_surface_variant
            font.family: Config.fontFamily
            font.italic: true
            font.pixelSize: Config.type.bodySmall.size
            text: "All caught up! 🎉"
            visible: root.tasks.length === 0 && !root.loading
        }
    }
}
