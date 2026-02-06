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
import qsnative

ModuleContainer {
    id: root

    property bool hasUpdates: false
    property string lastCheckedLabel: ""
    readonly property bool moduleAvailable: root.checkupdatesAvailable && root.pacmanAvailable
    property bool checkupdatesAvailable: false
    property bool pacmanAvailable: false
    property string onClickCommand: "runapp kitty -o tab_bar_style=hidden --class yay -e yay -Syu"
    property bool refreshing: false
    property string text: "0"
    property var updateItems: []
    property string updatedIcon: ""
    property int updatesCount: 0
    property string updatesIcon: ""
    property string updatesTooltip: "System up to date"
    property bool noAur: false
    property string updatesText: ""
    property string aurUpdatesText: ""
    property int aurUpdatesCount: 0
    property bool _providerUpdatePending: false

    function markNoUpdates() {
        root.hasUpdates = false;
        root.updatesCount = 0;
        root.text = "";
        root.updatesTooltip = "System up to date";
        root.updateItems = [];
        root.updatesText = "";
        root.aurUpdatesText = "";
        root.aurUpdatesCount = 0;
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
        root.refreshing = true;
        updatesProvider.refresh(root.noAur);
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
        root.refreshing = false;
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

            onActionRequested: Quickshell.execDetached(["sh", "-c", root.onClickCommand])
        }
    }

    onTooltipRefreshRequested: root.refreshUpdates("manual")

    PacmanUpdatesProvider {
        id: updatesProvider
    }

    Timer {
        id: updatesTimer

        interval: 30000
        repeat: true
        running: root.moduleAvailable
        triggeredOnStart: true

        onTriggered: root.refreshUpdates("timer")
    }
    Timer {
        id: updatesSyncTimer

        interval: 300000
        repeat: true
        running: root.moduleAvailable
        triggeredOnStart: true

        onTriggered: updatesProvider.sync()
    }

    Component.onCompleted: {
        root.markNoUpdates();
        DependencyCheck.require("checkupdates", "UpdatesModule", function(available) {
            root.checkupdatesAvailable = available;
        });
        DependencyCheck.require("pacman", "UpdatesModule", function(available) {
            root.pacmanAvailable = available;
        });
    }

    onClicked: Quickshell.execDetached(["sh", "-c", root.onClickCommand])
    onUpdatesCountChanged: root.scheduleUpdateFromProvider()
    onAurUpdatesCountChanged: root.scheduleUpdateFromProvider()
    onUpdatesTextChanged: root.scheduleUpdateFromProvider()
    onAurUpdatesTextChanged: root.scheduleUpdateFromProvider()
    onLastCheckedLabelChanged: root.refreshing = false

    Connections {
        target: updatesProvider

        function onUpdates_countChanged() {
            root.updatesCount = updatesProvider.updates_count;
        }
        function onAur_updates_countChanged() {
            root.aurUpdatesCount = updatesProvider.aur_updates_count;
        }
        function onUpdates_textChanged() {
            root.updatesText = updatesProvider.updates_text;
        }
        function onAur_updates_textChanged() {
            root.aurUpdatesText = updatesProvider.aur_updates_text;
        }
        function onLast_checkedChanged() {
            root.lastCheckedLabel = updatesProvider.last_checked;
        }
        function onErrorChanged() {
            root.scheduleUpdateFromProvider();
        }
    }
}
