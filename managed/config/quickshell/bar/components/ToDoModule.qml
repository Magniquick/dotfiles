pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import ".."
import "./JsonUtils.js" as JsonUtils

ColumnLayout {
    id: root
    spacing: Config.space.sm
    Layout.fillWidth: true

    property var tasks: []
    property var rawData: ({})
    property string currentProject: "Today"
    property bool loading: false
    property bool parseError: false
    property bool usingCache: false
    property string lastUpdated: ""
    readonly property bool dropdownActive: projectSelector.popup.visible
    readonly property string apiPath: "/home/magni/Projects/todoist-api/main.py"
    readonly property int iconSlot: Config.space.xxl * 2
    readonly property int minorSpace: Config.spaceHalfXs

    readonly property string cacheDir: {
        const homeDir = Quickshell.env("HOME");
        return homeDir && homeDir !== "" ? homeDir + "/.cache/quickshell/todoist" : "/tmp/quickshell-todoist";
    }

    readonly property string cachePath: root.cacheDir + "/tasks.json"

    function scheduleProjectSelectorClose() {
        if (projectSelector.popup.visible)
            projectSelectorCloseTimer.restart();
    }

    function cancelProjectSelectorClose() {
        projectSelectorCloseTimer.stop();
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

    onVisibleChanged: {
        if (!visible && projectSelector.popup.visible)
            projectSelector.popup.close();
    }

    readonly property string loginShell: {
        const shellValue = Quickshell.env("SHELL");
        return shellValue && shellValue !== "" ? shellValue : "sh";
    }

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

    function refresh() {
        root.loading = true;
        root.parseError = false;
        listRunner.trigger();
    }

    CommandRunner {
        id: listRunner
        command: "uv run " + root.apiPath + " list"
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
                cacheReader.trigger();
            }
            root.loading = false;
        }
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

    CommandRunner {
        id: cacheReader
        intervalMs: 0
        enabled: root.cachePath !== ""
        command: root.cachePath !== "" ? ("cat \"" + root.cachePath + "\"") : ""
        onRan: function (output) {
            const wrapper = JsonUtils.parseObject(output);
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
    }

    CommandRunner {
        id: cacheWriter
        intervalMs: 0
        enabled: true
        command: ""
    }

    CommandRunner {
        id: addRunner
        onRan: function (output) {
            root.refresh();
        }
    }

    CommandRunner {
        id: actionRunner
        onRan: function (output) {
            root.refresh();
        }
    }

    readonly property var taskColors: [Config.lavender, Config.pink, Config.flamingo, Config.primary, Config.yellow, Config.green]

    function getTaskColor(index) {
        return taskColors[index % taskColors.length];
    }

    function taskCountLabel(count) {
        return count === 1 ? "1 Task" : count + " Tasks";
    }

    // Hero Section (Battery Style)
    RowLayout {
        Layout.fillWidth: true
        spacing: Config.space.md

        Item {
            width: root.iconSlot
            height: root.iconSlot

            Text {
                anchors.centerIn: parent
                text: "󰄭"
                font.pixelSize: Config.type.headlineLarge.size
                color: Config.lavender
            }
        }

        ColumnLayout {
            spacing: Config.space.none

            Text {
                text: root.loading ? "Loading tasks…" : (root.parseError ? (root.tasks.length > 0 ? (root.taskCountLabel(root.tasks.length) + " (cached)") : "Tasks unavailable") : root.taskCountLabel(root.tasks.length))
                color: Config.textColor
                font.family: Config.fontFamily
                font.pixelSize: Config.type.headlineMedium.size
                font.weight: Font.Bold
            }
            Text {
                text: root.loading ? "Fetching from Todoist…" : (root.parseError ? (root.usingCache ? "Todoist error — showing cached data." : "Todoist error — no cached data.") : "remaining to be completed.")
                color: Config.textMuted
                font.family: Config.fontFamily
                font.pixelSize: Config.type.labelMedium.size
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

            onActivated: index => {
                root.currentProject = model[index];
                root.updateTasks();
            }

            background: Item {
                implicitWidth: 140
                implicitHeight: Config.type.bodySmall.line + root.minorSpace
            }

            contentItem: Row {
                spacing: Config.space.xs
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    id: selectorLabel
                    text: projectSelector.displayText.toUpperCase()
                    color: Config.lavender
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.labelSmall.size
                    font.weight: Font.Black
                    font.letterSpacing: root.minorSpace
                    verticalAlignment: Text.AlignVCenter
                    width: Math.min(implicitWidth, Math.max(0, projectSelector.width - dropdownIndicator.implicitWidth - (Config.space.xs + root.minorSpace)))
                    elide: Text.ElideRight
                }

                Text {
                    id: dropdownIndicator
                    text: "󰄼"
                    font.family: Config.iconFontFamily
                    font.pixelSize: Config.type.labelMedium.size
                    color: Config.lavender
                    rotation: projectSelector.popup.visible ? 90 : 0

                    Behavior on rotation {
                        NumberAnimation {
                            duration: Config.motion.duration.shortMs
                            easing.type: Config.motion.easing.standard
                        }
                    }
                }
            }

            indicator: Item {
                implicitWidth: 0
                implicitHeight: 0
            }

            delegate: ItemDelegate {
                id: delegateRoot
                width: ListView.view.width
                height: Config.barHeight
                required property var modelData
                required property int index
                highlighted: projectSelector.highlightedIndex === index

                contentItem: Text {
                    text: delegateRoot.modelData
                    color: delegateRoot.highlighted ? Config.onPrimary : Config.textColor
                    font: projectSelector.font
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: Config.space.sm
                }

                background: Rectangle {
                    anchors.fill: parent
                    anchors.margins: root.minorSpace
                    radius: Config.shape.corner.xs
                    color: delegateRoot.highlighted ? Config.primary : (delegateRoot.hovered ? Config.surfaceContainerHigh : "transparent")

                    Behavior on color {
                        ColorAnimation {
                            duration: Config.motion.duration.shortMs
                        }
                    }
                }
            }

            popup: Popup {
                y: projectSelector.height + Config.space.xs
                width: projectSelector.width
                implicitHeight: contentItem.implicitHeight
                padding: Config.space.xs
                focus: true
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent | Popup.CloseOnFocusLost

                onOpened: {
                    root.cancelProjectSelectorClose();
                    forceActiveFocus();
                }
                onActiveFocusChanged: if (!activeFocus)
                    close()

                Connections {
                    target: Qt.application
                    function onActiveChanged() {
                        if (!Qt.application.active) {
                            projectSelector.popup.close();
                        }
                    }
                }

                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: {
                        // This helps catch taps that might not be handled by the ComboBox itself
                        // to ensure focus is maintained or closed as expected.
                    }
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

                Component.onCompleted: {
                    if (projectSelector.popup) {
                        projectSelector.popup.closePolicy = Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent | Popup.CloseOnFocusLost;
                    }
                }

                enter: Transition {
                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Config.motion.duration.shortMs
                    }
                    NumberAnimation {
                        property: "scale"
                        from: 0.95
                        to: 1
                        duration: Config.motion.duration.shortMs
                        easing.type: Easing.OutBack
                    }
                }

                exit: Transition {
                    NumberAnimation {
                        property: "opacity"
                        to: 0
                        duration: Config.motion.duration.shortMs
                    }
                }

                contentItem: ListView {
                    clip: true
                    interactive: false
                    implicitHeight: contentHeight
                    model: projectSelector.popup.visible ? projectSelector.delegateModel : null
                    currentIndex: projectSelector.highlightedIndex

                    ScrollIndicator.vertical: ScrollIndicator {}
                }

                background: Rectangle {
                    color: Config.surface
                    radius: Config.shape.corner.md
                    border.color: Config.outline
                    border.width: 1

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Qt.rgba(0, 0, 0, 0.2)
                        shadowBlur: 0.4
                        shadowVerticalOffset: 2
                    }
                }
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
                required property var modelData
                required property int index
                spacing: Config.space.md
                Layout.fillWidth: true

                property bool completing: false
                property bool deleting: false
                readonly property int stripeWidth: root.minorSpace + Math.round(root.minorSpace / 2)

                Rectangle {
                    Layout.preferredWidth: stripeWidth
                    Layout.fillHeight: true
                    Layout.preferredHeight: Config.type.bodySmall.line + root.minorSpace
                    radius: Config.shape.corner.xs
                    color: root.getTaskColor(taskItem.index)
                    opacity: 0.8
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Config.space.none
                    opacity: taskItem.completing || taskItem.deleting ? 0.3 : 1.0

                    Text {
                        text: taskItem.modelData.title
                        color: root.getTaskColor(taskItem.index)
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.bodyMedium.size
                        font.weight: Font.Medium
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Text {
                        text: taskItem.modelData.notes || ""
                        color: Config.textMuted
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.labelSmall.size
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        visible: text !== ""
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }

                Text {
                    text: taskItem.modelData.due_human || ""
                    color: root.getTaskColor(taskItem.index)
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.labelSmall.size
                    font.weight: Font.Bold
                    visible: text !== ""
                    opacity: 0.7
                }

                // Complete Button
                Text {
                    text: "󰄬"
                    color: Config.green
                    font.family: Config.iconFontFamily
                    font.pixelSize: Config.type.titleSmall.size
                    font.weight: Font.Black
                    opacity: taskItem.completing ? 0.2 : 0.7
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: if (!taskItem.completing)
                            parent.opacity = 1.0
                        onExited: if (!taskItem.completing)
                            parent.opacity = 0.7
                        onClicked: {
                            taskItem.completing = true;
                            actionRunner.command = "uv run " + root.apiPath + " complete " + taskItem.modelData.id;
                            actionRunner.trigger();
                        }
                    }
                }
            }
        }

        Text {
            text: "All caught up! 🎉"
            color: Config.textMuted
            font.family: Config.fontFamily
            font.pixelSize: Config.type.bodySmall.size
            font.italic: true
            visible: root.tasks.length === 0 && !root.loading
        }
    }

    // Add Task Input & Footer
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Config.space.sm

        RowLayout {
            Layout.fillWidth: true
            spacing: Config.space.sm

            TextField {
                id: taskInput
                Layout.fillWidth: true
                placeholderText: "Start something new..."
                font.family: Config.fontFamily
                font.pixelSize: Config.type.bodySmall.size
                color: Config.textColor
                placeholderTextColor: Config.textMuted
                leftPadding: Config.space.sm
                rightPadding: Config.space.sm
                topPadding: Math.round(Config.space.md / 2)
                bottomPadding: Math.round(Config.space.md / 2)

                background: Rectangle {
                    color: Config.surfaceVariant
                    radius: Config.shape.corner.sm
                    opacity: 0.4
                    border.width: 1
                    border.color: taskInput.activeFocus ? Config.lavender : "transparent"
                }

                onAccepted: {
                    if (taskInput.text.trim() !== "") {
                        addRunner.command = "uv run " + root.apiPath + " add \"" + taskInput.text.replace(/"/g, '\\"') + "\"";
                        addRunner.trigger();
                        taskInput.text = "";
                    }
                }
            }

            Button {
                id: addButton
                flat: true
                onClicked: taskInput.accepted()

                background: Rectangle {
                    color: addButton.hovered ? Config.surfaceContainerHigh : "transparent"
                    radius: Config.shape.corner.xs
                    opacity: 0.6

                    Behavior on color {
                        ColorAnimation {
                            duration: Config.motion.duration.shortMs
                        }
                    }
                }

                contentItem: Text {
                    text: "ADD"
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.labelSmall.size
                    font.weight: Font.Black
                    color: Config.lavender
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    opacity: addButton.hovered ? 1.0 : 0.7
                }
            }
        }
    }

    function shSingleQuote(value) {
        // Wrap for POSIX shell single-quoted string: ' -> '\''.
        return String(value).replace(/'/g, "'\\''");
    }

    Component.onCompleted: cacheReader.trigger()
}
