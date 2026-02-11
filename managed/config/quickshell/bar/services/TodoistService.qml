pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qsnative
import "../components/JsonUtils.js" as JsonUtils
import ".."

Item {
    id: root
    visible: false

    readonly property string todoistEnvFile: Config.envFile

    property var data: ({})
    property string lastUpdatedLabel: ""
    property bool loading: false
    property bool parseError: false
    property string error: ""
    property bool usingCache: false

    function refresh(reason) {
        if (root.loading)
            return;
        root.loading = true;
        root.parseError = false;
        root.error = "";
        todoistClient.listTasks(root.todoistEnvFile);
    }

    TodoistClient {
        id: todoistClient
    }

    Timer {
        interval: 300000 // 5 minutes
        repeat: true
        running: true
        triggeredOnStart: true

        onTriggered: root.refresh("timer")
    }

    Connections {
        target: todoistClient

        function onData_jsonChanged() {
            const parsed = JsonUtils.parseObject(todoistClient.data_json);
            if (!parsed) {
                root.parseError = true;
                root.error = "Failed to parse data_json payload";
                root.loading = false;
                return;
            }

            root.data = parsed;
            const updatedAt = todoistClient.last_updated ? new Date(todoistClient.last_updated) : null;
            if (updatedAt && !isNaN(updatedAt.getTime()))
                root.lastUpdatedLabel = Qt.formatDateTime(updatedAt, "hh:mm ap");
            root.parseError = false;
            root.error = "";
            root.usingCache = false;
            root.loading = false;
        }

        function onErrorChanged() {
            const err = todoistClient.error || "";
            if (err !== "") {
                root.parseError = true;
                root.error = err;
            }
            root.loading = false;
        }
    }
}
