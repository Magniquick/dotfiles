pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import qsnative
import ".."

Item {
    id: root
    visible: false

    property bool checkupdatesAvailable: false
    property bool pacmanAvailable: false
    readonly property bool moduleAvailable: root.checkupdatesAvailable && root.pacmanAvailable

    // Treat as global config. If you need per-screen behavior later, move this
    // into a separate config singleton and have the service bind to it.
    property bool noAur: false

    property int updatesCount: 0
    property int aurUpdatesCount: 0
    property string updatesText: ""
    property string aurUpdatesText: ""
    property string lastCheckedLabel: ""
    property string error: ""
    property bool refreshing: false

    function markNoUpdates() {
        root.updatesCount = 0;
        root.aurUpdatesCount = 0;
        root.updatesText = "";
        root.aurUpdatesText = "";
        root.error = "";
        root.refreshing = false;
    }

    function refresh(reason) {
        if (!root.moduleAvailable)
            return;
        root.refreshing = true;
        provider.refresh(root.noAur);
    }

    function sync() {
        if (!root.moduleAvailable)
            return;
        provider.sync();
    }

    PacmanUpdatesProvider {
        id: provider
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.moduleAvailable
        triggeredOnStart: true

        onTriggered: root.refresh("timer")
    }

    Timer {
        // Syncing package DBs is expensive; do it manually or on a long cadence.
        interval: 86400000
        repeat: true
        running: root.moduleAvailable
        triggeredOnStart: false

        onTriggered: root.sync()
    }

    Component.onCompleted: {
        root.markNoUpdates();
        DependencyCheck.require("checkupdates", "UpdatesService", function(available) {
            root.checkupdatesAvailable = available;
        });
        DependencyCheck.require("pacman", "UpdatesService", function(available) {
            root.pacmanAvailable = available;
        });
    }

    Connections {
        target: provider

        function onUpdates_countChanged() {
            root.updatesCount = provider.updates_count;
        }
        function onAur_updates_countChanged() {
            root.aurUpdatesCount = provider.aur_updates_count;
        }
        function onUpdates_textChanged() {
            root.updatesText = provider.updates_text;
        }
        function onAur_updates_textChanged() {
            root.aurUpdatesText = provider.aur_updates_text;
        }
        function onLast_checkedChanged() {
            root.lastCheckedLabel = provider.last_checked;
        }
        function onErrorChanged() {
            root.error = provider.error || "";
            // If provider reports an error, avoid leaving the UI in a "loading"
            // state indefinitely.
            root.refreshing = false;
        }
        function onHas_updatesChanged() {
            // Provider has completed a refresh.
            root.refreshing = false;
        }
    }
}
