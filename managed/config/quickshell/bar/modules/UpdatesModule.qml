/**
 * @module UpdatesModule
 * @description Package update checker for Arch Linux
 *
 * Features:
 * - Shows pending update count
 * - Tooltip lists available updates
 * - Click opens yay for system upgrade
 *
 * Dependencies:
 * - qsnative PacmanUpdatesProvider (checkupdates + pacman -Qm + AUR API)
 * - yay: AUR helper for updates (click action)
 */
pragma ComponentBehavior: Bound
import ".."
import "../components"
import QtQuick
import Quickshell
import "../../common" as Common

ModuleContainer {
    id: root

    property bool hasUpdates: false
    readonly property string lastCheckedLabel: UpdatesService.lastCheckedLabel
    readonly property bool moduleAvailable: UpdatesService.moduleAvailable
    property string onClickCommand: "runapp kitty -o tab_bar_style=hidden --class yay -e yay -Syu"
    readonly property bool refreshing: UpdatesService.refreshing
    property string text: "0"
    property var updateItems: []
    property string updatedIcon: ""
    readonly property int updatesCount: UpdatesService.updatesCount
    property string updatesIcon: ""
    property string updatesTooltip: "System up to date"
    readonly property string updatesText: UpdatesService.updatesText
    readonly property string aurUpdatesText: UpdatesService.aurUpdatesText
    readonly property int aurUpdatesCount: UpdatesService.aurUpdatesCount
    property bool _providerUpdatePending: false

    function markNoUpdates() {
        root.hasUpdates = false;
        root.text = "";
        root.updatesTooltip = "System up to date";
        root.updateItems = [];
    }
    function parseUpdateItemsFromTooltip(linesText) {
        if (!linesText || String(linesText).trim() === "")
            return [];

        const cleaned = String(linesText).replace(/\r\n/g, "\n").replace(/\r/g, "\n").trim();
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
    function refreshUpdates(source) {
        UpdatesService.refresh(source);
    }
    function scheduleUpdateFromProvider() {
        if (root._providerUpdatePending)
            return;

        root._providerUpdatePending = true;
        Qt.callLater(() => {
            root._providerUpdatePending = false;
            root.updateFromProvider();
        });
    }
    function updateFromProvider() {
        const totalCount = root.updatesCount + root.aurUpdatesCount;
        root.hasUpdates = totalCount > 0;
        const combinedText = [root.updatesText, root.aurUpdatesText].filter(text => text && text.trim() !== "").join("\n");
        const parsedItems = root.parseUpdateItemsFromTooltip(combinedText);
        root.updateItems = root.hasUpdates ? parsedItems : [];
        root.text = root.hasUpdates ? String(totalCount) : "";
        root.updatesTooltip = root.hasUpdates ? totalCount + " updates" : "System up to date";
    }

    collapsed: !root.moduleAvailable || (!root.hasUpdates && root.updatedIcon === "")
    tooltipHoverable: true
    tooltipRefreshing: root.refreshing
    tooltipShowRefreshIcon: true
    tooltipSubtitle: root.lastCheckedLabel !== "" ? ("Last check " + root.lastCheckedLabel) : ""
    tooltipText: root.hasUpdates ? root.updatesTooltip : "System up to date"
    tooltipTitle: "Updates"

    content: [
        IconTextRow {
            iconText: root.hasUpdates ? root.updatesIcon : root.updatedIcon
            spacing: root.contentSpacing
            text: root.hasUpdates ? root.text : ""
        }
    ]
    tooltipContent: Component {
        UpdatesTooltip {
            actionText: root.hasUpdates ? "Update" : "Open"
            count: root.updatesCount + root.aurUpdatesCount
            hasUpdates: root.hasUpdates
            iconText: root.updatesIcon
            refreshing: root.refreshing
            updates: root.updateItems
            width: 360

            onActionRequested: Common.ProcessHelper.execDetached(root.onClickCommand)
        }
    }

    onTooltipRefreshRequested: root.refreshUpdates("manual")

    onClicked: Common.ProcessHelper.execDetached(root.onClickCommand)

    Component.onCompleted: root.markNoUpdates()

    Connections {
        target: UpdatesService

        function onUpdatesCountChanged() { root.scheduleUpdateFromProvider(); }
        function onAurUpdatesCountChanged() { root.scheduleUpdateFromProvider(); }
        function onUpdatesTextChanged() { root.scheduleUpdateFromProvider(); }
        function onAurUpdatesTextChanged() { root.scheduleUpdateFromProvider(); }
        function onErrorChanged() { root.scheduleUpdateFromProvider(); }
        function onLastCheckedLabelChanged() { root.scheduleUpdateFromProvider(); }
    }
}
