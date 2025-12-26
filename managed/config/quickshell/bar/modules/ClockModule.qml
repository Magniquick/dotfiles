import ".."
import "../components"
import "../components/JsonUtils.js" as JsonUtils
import QtQuick
import QtQuick.Layouts
import Quickshell

ModuleContainer {
    id: root

    property bool showDate: false
    property string calendarRefreshTime: ""
    property bool refreshing: false
    readonly property string loginShell: {
        const shellValue = Quickshell.env("SHELL");
        return shellValue && shellValue !== "" ? shellValue : "sh";
    }
    readonly property string calendarCacheDir: {
        const homeDir = Quickshell.env("HOME");
        return homeDir && homeDir !== "" ? homeDir + "/.cache/quickshell/ical" : "/tmp/quickshell-ical";
    }
    readonly property string calendarBinary: Quickshell.shellPath(((Quickshell.shellDir || "").endsWith("/bar") ? "" : "bar/") + "scripts/ical-cache/target/release/ical-cache")
    readonly property string calendarEnvFile: Quickshell.shellPath(((Quickshell.shellDir || "").endsWith("/bar") ? "" : "bar/") + ".env")
    readonly property string calendarRefreshCommand: root.loginShell + " -lc '" + root.calendarBinary + " --cache-dir " + root.calendarCacheDir + " --env-file " + root.calendarEnvFile + "'"

    function timeText() {
        return Qt.formatDateTime(clock.date, "hh:mm ap");
    }

    function dateText() {
        return Qt.formatDateTime(clock.date, "dd/MM/yy");
    }

    tooltipTitle: "Calendar"
    tooltipSubtitle: calendarRefreshTime
    tooltipRefreshing: root.refreshing
    tooltipHoverable: true
    onTooltipActiveChanged: {
        if (tooltipActive)
            eventsReader.trigger();
    }
    content: [
        BarLabel {
            text: root.showDate ? root.dateText() : root.timeText()
            color: Config.lavender
        }
    ]

    CommandRunner {
        id: eventsReader

        command: "cat " + root.calendarCacheDir + "/events.json"
        onRan: function (output) {
            const data = JsonUtils.parseObject(output);
            if (data && data.generatedAt) {
                const dt = new Date(data.generatedAt);
                root.calendarRefreshTime = Qt.formatDateTime(dt, "hh:mm ap");
            } else {
                root.calendarRefreshTime = "";
            }
        }
    }

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.showDate = !root.showDate
    }

    tooltipContent: Component {
        ColumnLayout {
            spacing: Config.space.sm

            TooltipCard {
                backgroundColor: "transparent"
                outlined: false
                content: [
                    CalendarTooltip {
                        id: calendarRef

                        currentDate: clock.date
                        active: root.tooltipActive
                        cacheDir: root.calendarCacheDir
                        refreshCommand: root.calendarRefreshCommand
                        onDataLoaded: function () {
                            root.refreshing = false;
                            eventsReader.trigger();
                        }

                        // Handle refresh signal from parent
                        Connections {
                            function onTooltipRefreshRequested() {
                                root.refreshing = true;
                                calendarRef.refreshRequested();
                            }

                            target: root
                        }
                    }
                ]
            }
        }
    }
}
