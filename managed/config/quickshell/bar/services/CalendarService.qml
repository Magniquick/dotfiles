pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qsnative
import ".."

Item {
    id: root
    visible: false

    readonly property string envFile: Quickshell.shellPath(((Quickshell.shellDir || "").endsWith("/bar") ? "" : "bar/") + ".env")
    property int days: 180

    readonly property var client: calendarClient

    property string status: ""
    property string generatedAt: ""
    property string error: ""
    property string eventsJson: ""
    property bool refreshing: false

    function refresh(reason) {
        root.refreshing = true;
        calendarClient.refreshFromEnv(root.envFile, root.days);
    }

    IcalCache {
        id: calendarClient
    }

    Timer {
        interval: 3600000
        repeat: true
        running: true
        triggeredOnStart: true

        onTriggered: root.refresh("timer")
    }

    Connections {
        target: calendarClient

        function onStatusChanged() {
            root.status = calendarClient.status || "";
            root.refreshing = false;
        }
        function onGenerated_atChanged() {
            root.generatedAt = calendarClient.generated_at || "";
        }
        function onErrorChanged() {
            root.error = calendarClient.error || "";
            root.refreshing = false;
        }
        function onEvents_jsonChanged() {
            root.eventsJson = calendarClient.events_json || "";
        }
    }
}
