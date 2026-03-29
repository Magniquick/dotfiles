pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import qsgo
import "../components/JsonUtils.js" as JsonUtils
import ".."

Item {
    id: root
    visible: false

    readonly property string envFile: Config.envFile
    property int days: 180

    readonly property var client: calendarClient

    property string status: ""
    property string generatedAt: ""
    property string error: ""
    property string eventsJson: ""
    property bool refreshing: false

    function applyClientPayload() {
        root.eventsJson = calendarClient.events_json || "";

        const parsed = JsonUtils.parseObject(root.eventsJson);
        if (!parsed || typeof parsed !== "object") {
            root.status = "error";
            root.generatedAt = "";
            root.error = calendarClient.error || "Failed to parse calendar payload";
            root.refreshing = false;
            return;
        }

        root.status = parsed.status ? String(parsed.status) : "";
        root.generatedAt = parsed.generatedAt ? String(parsed.generatedAt) : "";
        root.error = parsed.error ? String(parsed.error) : (calendarClient.error || "");
        root.refreshing = false;
    }

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

        function onErrorChanged() {
            if (calendarClient.error)
                root.error = calendarClient.error;
            root.refreshing = false;
        }
        function onEvents_jsonChanged() {
            root.applyClientPayload();
        }
    }
}
