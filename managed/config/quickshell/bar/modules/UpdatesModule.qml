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
 * - qsgo PacmanUpdatesProvider (checkupdates + pacman -Qm + AUR API)
 * - yay: AUR helper for updates (click action)
 */
pragma ComponentBehavior: Bound
import ".."
import "../components"
import QtQuick
import "../../common" as Common

ModuleContainer {
    id: root

    property bool hasUpdates: false
    readonly property string lastCheckedLabel: UpdatesService.lastCheckedLabel
    property string onClickCommand: "runapp kitty -o tab_bar_style=hidden --class yay -e yay -Syu"
    readonly property bool refreshing: UpdatesService.refreshing
    property string text: "0"
    property string updatedIcon: ""
    readonly property int updatesCount: UpdatesService.updatesCount
    property string updatesIcon: ""
    property string updatesTooltip: "System up to date"
    readonly property int aurUpdatesCount: UpdatesService.aurUpdatesCount
    readonly property int itemsCount: UpdatesService.itemsCount
    property bool _providerUpdatePending: false

    function markNoUpdates() {
        root.hasUpdates = false;
        root.text = "";
        root.updatesTooltip = "System up to date";
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
        root.text = root.hasUpdates ? String(totalCount) : "";
        root.updatesTooltip = root.hasUpdates ? totalCount + " updates" : "System up to date";
    }

    collapsed: !root.hasUpdates && root.updatedIcon === ""
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
            detailsCount: root.itemsCount
            errorText: UpdatesService.error || ""
            updatesModel: UpdatesService.updatesModel
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
        function onItemsCountChanged() { root.scheduleUpdateFromProvider(); }
        function onErrorChanged() { root.scheduleUpdateFromProvider(); }
        function onLastCheckedLabelChanged() { root.scheduleUpdateFromProvider(); }
    }
}
