import ".."
import "../components"
import "../components/JsonUtils.js" as JsonUtils
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ModuleContainer {
    id: root

    property bool moduleAvailable: false
    property bool hasUpdates: false
    property bool processEnabled: true
    property bool refreshing: false
    property string updatedIcon: ""
    property string updatesIcon: ""
    property string text: "0"
    property string updatesTooltip: "System up to date"
    property var updateItems: []
    property int updatesCount: 0
    property string lastCheckedLabel: ""
    property string onClickCommand: "runapp kitty -o tab_bar_style=hidden --class yay -e yay -Syu"
    readonly property string updatesCommand: "waybar-module-pacman-updates --tooltip-align-columns " + "--no-zero-output --interval-seconds 30 --network-interval-seconds 300"
    readonly property string loginShell: {
        const shellValue = Quickshell.env("SHELL");
        return shellValue && shellValue !== "" ? shellValue : "sh";
    }

    function normalizeClassList(value) {
        if (!value)
            return [];

        if (Array.isArray(value))
            return value;

        if (typeof value === "string")
            return [value];

        return [];
    }

    function markNoUpdates() {
        root.hasUpdates = false;
        root.updatesCount = 0;
        root.text = "";
        root.updatesTooltip = "System up to date";
        root.updateItems = [];
    }

    function decodeHtmlEntities(text) {
        if (!text)
            return "";

        return String(text).replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&#39;/g, "'");
    }

    function stripTags(text) {
        if (!text)
            return "";

        return String(text).replace(/<[^>]*>/g, "");
    }

    function parseUpdateItemsFromTooltip(tooltipText) {
        if (!tooltipText || String(tooltipText).trim() === "")
            return [];

        const cleaned = root.decodeHtmlEntities(root.stripTags(tooltipText)).replace(/\r\n/g, "\n").replace(/\r/g, "\n").trim();
        if (cleaned === "")
            return [];

        const lines = cleaned.split("\n").map(line => {
            return line.trim();
        }).filter(line => {
            return line !== "";
        });
        const items = [];
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const match = line.match(/^(\S+)\s+(.+?)\s+->\s+(.+)$/);
            if (match) {
                const name = match[1];
                const fromVersion = match[2].trim();
                const toVersion = match[3].trim();
                items.push({
                    "name": name,
                    "fromVersion": fromVersion,
                    "toVersion": toVersion,
                    "detail": fromVersion + " → " + toVersion
                });
                continue;
            }
            const parts = line.split(/\s+/);
            const name = parts[0] || line;
            const detail = parts.slice(1).join(" ").trim();
            items.push({
                "name": name,
                "detail": detail
            });
        }
        return items;
    }

    function updateFromPayloadText(payloadText) {
        root.refreshing = false;
        root.recordCheck();
        if (!payloadText) {
            root.markNoUpdates();
            return;
        }
        const trimmed = payloadText.trim();
        if (trimmed === "") {
            root.markNoUpdates();
            return;
        }
        const payload = JsonUtils.parseObject(trimmed);
        if (!payload || typeof payload !== "object") {
            const count = parseInt(trimmed, 10);
            if (isFinite(count) && count > 0) {
                root.hasUpdates = true;
                root.updatesCount = count;
                root.text = String(count);
                root.updateItems = [];
                root.updatesTooltip = root.text + " updates";
            } else {
                root.markNoUpdates();
            }
            return;
        }
        const textValue = payload.text ? String(payload.text).trim() : "";
        const altValue = payload.alt ? String(payload.alt).trim() : "";
        const classNames = root.normalizeClassList(payload.class);
        const classHasUpdates = classNames.indexOf("has-updates") >= 0 || altValue === "has-updates";
        const classUpdated = classNames.indexOf("updated") >= 0 || altValue === "updated";
        const hasTextUpdates = textValue !== "" && textValue !== "0";
        root.hasUpdates = classHasUpdates || (hasTextUpdates && !classUpdated);
        const tooltipValue = payload.tooltip ? String(payload.tooltip).trim() : "";
        const parsedItems = root.parseUpdateItemsFromTooltip(tooltipValue);
        root.updateItems = root.hasUpdates ? parsedItems : [];
        const parsedCount = parseInt(textValue, 10);
        const countFromText = isFinite(parsedCount) ? parsedCount : 0;
        root.updatesCount = root.hasUpdates ? (countFromText > 0 ? countFromText : parsedItems.length) : 0;
        root.text = root.hasUpdates ? (textValue !== "" ? textValue : String(root.updatesCount)) : "";
        root.updatesTooltip = root.hasUpdates ? root.updatesCount + " updates" : "System up to date";
    }

    function recordCheck() {
        root.lastCheckedLabel = Qt.formatDateTime(new Date(), "hh:mm ap");
    }

    function refreshUpdates(source) {
        if (!root.moduleAvailable)
            return;

        root.refreshing = true;
        root.processEnabled = false;
        updatesRestartTimer.restart();
    }

    tooltipTitle: "Updates"
    tooltipHoverable: true
    tooltipShowRefreshIcon: true
    tooltipSubtitle: root.lastCheckedLabel !== "" ? ("Last check " + root.lastCheckedLabel) : ""
    tooltipRefreshing: root.refreshing
    tooltipText: root.hasUpdates ? root.updatesTooltip : "System up to date"
    collapsed: !root.moduleAvailable || (!root.hasUpdates && root.updatedIcon === "")
    onTooltipRefreshRequested: root.refreshUpdates("manual")
    content: [
        IconTextRow {
            spacing: root.contentSpacing
            iconText: root.hasUpdates ? root.updatesIcon : root.updatedIcon
            text: root.hasUpdates ? root.text : ""
        }
    ]

    CommandRunner {
        id: availabilityRunner

        intervalMs: 0
        command: root.loginShell + " -lc 'command -v waybar-module-pacman-updates'"
        onRan: function (output) {
            root.moduleAvailable = output.trim() !== "";
        }
    }

    Process {
        id: updatesProcess

        command: ["sh", "-c", root.updatesCommand]
        running: root.moduleAvailable && root.processEnabled
        Component.onCompleted: root.markNoUpdates()

        stdout: SplitParser {
            onRead: function (data) {
                root.updateFromPayloadText(data);
            }
        }
    }

    Timer {
        id: updatesRestartTimer

        interval: 120
        repeat: false
        onTriggered: root.processEnabled = true
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Quickshell.execDetached(["sh", "-c", root.onClickCommand])
    }

    tooltipContent: Component {
        UpdatesTooltip {
            width: 360
            updates: root.updateItems
            count: root.updatesCount
            hasUpdates: root.hasUpdates
            iconText: root.updatesIcon
            actionText: root.hasUpdates ? "Update" : "Open"
            refreshing: root.refreshing
            onActionRequested: Quickshell.execDetached(["sh", "-c", root.onClickCommand])
        }
    }
}
