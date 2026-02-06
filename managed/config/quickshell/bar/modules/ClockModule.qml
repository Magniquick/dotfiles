/**
 * @module ClockModule
 * @description Time and calendar module with iCal integration
 *
 * Features:
 * - Time display (hh:mm ap format)
 * - Date display toggle on click
 * - Calendar tooltip with event integration
 * - iCal cache for calendar events
 *
 * Dependencies:
 * - common/modules/qs-native: CXX-Qt QML module for iCal fetching
 * - bar/.env: Environment file with calendar URLs
 */
pragma ComponentBehavior: Bound
import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell

ModuleContainer {
    id: root

    property string calendarRefreshTime: ""
    readonly property bool refreshing: CalendarService.refreshing
    property bool showDate: false

    function dateText() {
        return Qt.formatDateTime(clock.date, "dd/MM/yy");
    }
    function timeText() {
        return Qt.formatDateTime(clock.date, "hh:mm ap");
    }
    Component.onCompleted: {
        root.updateCalendarRefreshTime();
    }
    function updateCalendarRefreshTime() {
        const generatedAt = CalendarService.generatedAt;
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
            color: Config.color.tertiary
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
                        calendarClient: CalendarService.client
                        currentDate: clock.date
                        refreshEnvFile: CalendarService.envFile
                        refreshDays: CalendarService.days

                        onDataLoaded: function () {
                            // CalendarService controls refreshing state.
                        }

                        // Handle refresh signal from parent
                        Connections {
                            function onTooltipRefreshRequested() {
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
            CalendarService.refresh("tooltip");
            root.updateCalendarRefreshTime();
        }
    }
    Connections {
        target: CalendarService

        function onGeneratedAtChanged() {
            root.updateCalendarRefreshTime();
        }
    }
    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    onClicked: root.showDate = !root.showDate
}
