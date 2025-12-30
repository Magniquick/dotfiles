import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ModuleContainer {
    id: root

    readonly property string calendarBinary: Quickshell.shellPath(((Quickshell.shellDir || "").endsWith("/bar") ? "" : "bar/") + "scripts/ical-cache")
    readonly property string calendarCacheDir: {
        const homeDir = Quickshell.env("HOME");
        return homeDir && homeDir !== "" ? homeDir + "/.cache/quickshell/ical" : "/tmp/quickshell-ical";
    }
    readonly property string calendarEnvFile: Quickshell.shellPath(((Quickshell.shellDir || "").endsWith("/bar") ? "" : "bar/") + ".env")
    readonly property string calendarRefreshCommand: root.loginShell + " -lc '" + root.calendarBinary + " --cache-dir " + root.calendarCacheDir + " --env-file " + root.calendarEnvFile + "'"
    property string calendarRefreshTime: ""
    readonly property string loginShell: {
        const shellValue = Quickshell.env("SHELL");
        return shellValue && shellValue !== "" ? shellValue : "sh";
    }
    property bool refreshing: false
    property bool showDate: false

    function dateText() {
        return Qt.formatDateTime(clock.date, "dd/MM/yy");
    }
    function timeText() {
        return Qt.formatDateTime(clock.date, "hh:mm ap");
    }
    Component.onCompleted: {
        calendarFile.reload();
        root.updateCalendarRefreshTime();
    }
    function updateCalendarRefreshTime() {
        const generatedAt = calendarAdapter.generatedAt;
        if (generatedAt && String(generatedAt).trim() !== "") {
            const dt = new Date(generatedAt);
            root.calendarRefreshTime = Qt.formatDateTime(dt, "hh:mm ap");
            return;
        }
        root.calendarRefreshTime = "";
    }

    tooltipHoverable: true
    tooltipRefreshing: root.refreshing
    tooltipSubtitle: calendarRefreshTime
    tooltipTitle: "Calendar"

    content: [
        BarLabel {
            color: Config.m3.tertiary
            text: root.showDate ? root.dateText() : root.timeText()
        }
    ]
    tooltipContent: Component {
        ColumnLayout {
            spacing: Config.space.sm

            TooltipCard {
                backgroundColor: "transparent"
                outlined: false

                content: [
                    CalendarTooltip {
                        id: calendarRef

                        active: root.tooltipActive
                        cacheDir: root.calendarCacheDir
                        currentDate: clock.date
                        refreshCommand: root.calendarRefreshCommand

                        onDataLoaded: function () {
                            root.refreshing = false;
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

    onTooltipActiveChanged: {
        if (tooltipActive) {
            calendarFile.reload();
            root.updateCalendarRefreshTime();
        }
    }
    FileView {
        id: calendarFile

        path: root.calendarCacheDir + "/events.json"
        watchChanges: true
        blockLoading: true

        onFileChanged: {
            reload();
            root.updateCalendarRefreshTime();
        }

        JsonAdapter {
            id: calendarAdapter

            property string status: ""
            property string generatedAt: ""
            property var eventsByDay: ({})

            onGeneratedAtChanged: root.updateCalendarRefreshTime()
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
}
