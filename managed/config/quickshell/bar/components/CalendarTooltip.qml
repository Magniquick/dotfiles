pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."
import "./JsonUtils.js" as JsonUtils

Item {
    id: calendar

    property bool active: false
    property var calendarClient: null
    property string calendarGeneratedAt: ""
    property string calendarStatus: ""
    property date currentDate: new Date()
    readonly property int dayCellSize: Config.type.bodyMedium.size + Config.space.md
    readonly property int monthRangeYears: 5
    readonly property int monthRangeCenter: monthRangeYears * 12
    property var dayEvents: []
    property var eventsByDay: ({})
    property string refreshEnvFile: ""
    property int refreshDays: 180
    property date selectedDate: new Date()
    readonly property date today: new Date()
    readonly property int todayDay: today.getDate()
    readonly property int todayMonth: today.getMonth()
    readonly property int todayYear: today.getFullYear()
    readonly property var weekDays: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    signal dataLoaded

    function applyCalendarFromClient() {
        if (!calendar.calendarClient)
            return;
        const payload = JsonUtils.parseObject(calendar.calendarClient.events_json);
        calendar.applyCalendarData(payload);
        calendar.dataLoaded();
    }
    function applyCalendarData(payload) {
        if (!payload || typeof payload !== "object") {
            calendar.eventsByDay = ({});
            calendar.calendarStatus = "error";
            calendar.calendarGeneratedAt = "";
            calendar.updateDayEvents();
            return;
        }

        if (payload.status) {
            calendar.calendarStatus = payload.status;
            calendar.calendarGeneratedAt = payload.generatedAt || "";
            calendar.eventsByDay = payload.eventsByDay || ({});
        } else {
            calendar.calendarStatus = "legacy";
            calendar.calendarGeneratedAt = "";
            calendar.eventsByDay = payload.eventsByDay || payload || ({});
        }

        calendar.updateDayEvents();
    }
    function dayKey(date) {
        if (!date)
            return "";
        const year = date.getFullYear();
        const monthValue = date.getMonth() + 1;
        const dayNumber = date.getDate();
        const monthText = monthValue < 10 ? "0" + monthValue : String(monthValue);
        const dayText = dayNumber < 10 ? "0" + dayNumber : String(dayNumber);
        return year + "-" + monthText + "-" + dayText;
    }
    function formatEventLabel(event) {
        if (!event)
            return "";
        const candidates = [event.title, event.summary, event.name];
        let title = "Untitled";
        for (let i = 0; i < candidates.length; i++) {
            const value = candidates[i];
            if (value === undefined || value === null)
                continue;
            const trimmed = String(value).trim();
            if (trimmed !== "") {
                title = trimmed;
                break;
            }
        }
        const timeLabel = calendar.formatEventTime(event);
        return timeLabel !== "" ? timeLabel + " · " + title : title;
    }
    function formatEventTime(event) {
        if (!event || event.all_day)
            return "All day";
        const startValue = event.start ? new Date(event.start) : null;
        if (!startValue || isNaN(startValue.getTime()))
            return "";
        return Qt.formatDateTime(startValue, "hh:mm ap");
    }
    function markerCount(date) {
        const key = calendar.dayKey(date);
        if (!key || !calendar.eventsByDay || !calendar.eventsByDay[key])
            return 0;
        return Math.min(3, calendar.eventsByDay[key].length);
    }
    function refreshRequested() {
        if (!calendar.calendarClient)
            return;
        Qt.callLater(function () {
            calendar.calendarClient.refreshFromEnv(calendar.refreshEnvFile, calendar.refreshDays);
        });
    }
    function updateDayEvents() {
        const key = calendar.dayKey(calendar.selectedDate);
        const list = (key && calendar.eventsByDay && calendar.eventsByDay[key]) ? calendar.eventsByDay[key] : [];
        calendar.dayEvents = list;
    }

    implicitHeight: layout.implicitHeight

    // Fixed size to avoid jumping during scroll
    implicitWidth: 240

    Component.onCompleted: {
        calendar.updateDayEvents();
        calendar.refreshRequested();
    }
    onActiveChanged: {
        if (!calendar.active) {
            monthListView.positionViewAtIndex(calendar.monthRangeCenter, ListView.SnapPosition);
            monthListView.currentIndex = calendar.monthRangeCenter;
            return;
        }
        calendar.refreshRequested();
    }
    onCurrentDateChanged: {
        calendar.selectedDate = new Date(calendar.currentDate.getTime());
        calendar.updateDayEvents();
    }
    onEventsByDayChanged: calendar.updateDayEvents()
    onSelectedDateChanged: calendar.updateDayEvents()

    Connections {
        target: calendar.calendarClient

        function onEvents_jsonChanged() {
            calendar.applyCalendarFromClient();
        }
        function onGenerated_atChanged() {
            calendar.calendarGeneratedAt = calendar.calendarClient.generated_at;
        }
        function onStatusChanged() {
            calendar.calendarStatus = calendar.calendarClient.status;
        }
        function onErrorChanged() {
            calendar.applyCalendarFromClient();
        }
    }
    Timer {
        id: refreshTimer

        interval: 3600000
        repeat: true
        running: true

        onTriggered: calendar.refreshRequested()
    }
    ColumnLayout {
        id: layout

        anchors.fill: parent
        spacing: Config.space.sm

        ListView {
            id: monthListView

            Layout.fillWidth: true
            Layout.preferredHeight: 230 // Title + Header + Grid
            clip: true
            currentIndex: calendar.monthRangeCenter
            highlightMoveDuration: 120
            highlightRangeMode: ListView.StrictlyEnforceRange
            model: calendar.monthRangeCenter * 2
            orientation: ListView.Horizontal
            snapMode: ListView.SnapOneItem

            delegate: Item {
                id: monthDelegate

                readonly property int daysInMonth: new Date(viewYear, viewMonth + 1, 0).getDate()
                required property int index
                readonly property int monthOffset: index - calendar.monthRangeCenter
                readonly property int startOffset: new Date(viewYear, viewMonth, 1).getDay()
                readonly property date viewDate: new Date(calendar.todayYear, calendar.todayMonth + monthOffset, 1)
                readonly property int viewMonth: viewDate.getMonth()
                readonly property int viewYear: viewDate.getFullYear()

                height: monthListView.height
                width: monthListView.width

                ColumnLayout {
                    anchors.fill: parent
                    spacing: Config.space.sm

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.bottomMargin: Config.space.sm
                        Layout.topMargin: Config.space.none
                        spacing: Config.space.xs

                        Text {
                            color: Config.color.on_surface
                            font.family: Config.fontFamily
                            font.pixelSize: Config.type.headlineSmall.size
                            font.weight: Font.Bold
                            text: Qt.formatDateTime(monthDelegate.viewDate, "MMMM")
                        }
                        Text {
                            color: Config.color.on_surface_variant
                            font.family: Config.fontFamily
                            font.pixelSize: Config.type.headlineSmall.size
                            font.weight: Font.ExtraLight
                            text: Qt.formatDateTime(monthDelegate.viewDate, "yyyy")
                        }
                    }
                    GridLayout {
                        Layout.alignment: Qt.AlignHCenter
                        columnSpacing: Config.space.sm
                        columns: 7
                        rowSpacing: 0

                        Repeater {
                            model: calendar.weekDays

                            delegate: Item {
                                id: weekdayItem
                                required property int index
                                required property string modelData

                                implicitHeight: Config.type.labelSmall.size + Config.space.xs
                                implicitWidth: calendar.dayCellSize

                                Text {
                                    anchors.centerIn: parent
                                    color: Config.color.on_surface_variant
                                    font.family: Config.fontFamily
                                    font.pixelSize: Config.type.labelSmall.size
                                    font.weight: Config.type.labelSmall.weight
                                    text: weekdayItem.modelData
                                }
                            }
                        }
                    }
                    GridLayout {
                        Layout.alignment: Qt.AlignHCenter
                        columnSpacing: Config.space.sm
                        columns: 7
                        rowSpacing: Config.space.xs

                        Repeater {
                            model: 42 // 6 rows for consistent height

                            delegate: Item {
                                id: dayDelegate

                                readonly property var dateObj: inMonth ? new Date(monthDelegate.viewYear, monthDelegate.viewMonth, dayNumber) : undefined
                                readonly property int dayNumber: index - monthDelegate.startOffset + 1
                                readonly property bool inMonth: dayNumber > 0 && dayNumber <= monthDelegate.daysInMonth
                                required property int index
                                readonly property bool isSelection: inMonth && dayNumber === calendar.selectedDate.getDate() && monthDelegate.viewMonth === calendar.selectedDate.getMonth() && monthDelegate.viewYear === calendar.selectedDate.getFullYear()
                                readonly property bool isToday: inMonth && dayNumber === calendar.todayDay && monthDelegate.viewMonth === calendar.todayMonth && monthDelegate.viewYear === calendar.todayYear

                                implicitHeight: calendar.dayCellSize
                                implicitWidth: calendar.dayCellSize

                                // Event Filled Circle
                                Rectangle {
                                    anchors.centerIn: parent
                                    color: Config.color.tertiary
                                    height: parent.implicitHeight - Config.space.xs
                                    radius: width / 2
                                    visible: dayDelegate.inMonth && !dayDelegate.isToday && calendar.markerCount(dayDelegate.dateObj) > 0
                                    width: parent.implicitWidth - Config.space.xs
                                }

                                // Today Filled Circle
                                Rectangle {
                                    anchors.centerIn: parent
                                    color: Config.color.primary
                                    height: parent.implicitHeight - Config.space.xs
                                    radius: width / 2
                                    visible: dayDelegate.isToday
                                    width: parent.implicitWidth - Config.space.xs
                                }

                                // Selection Outline
                                Rectangle {
                                    anchors.centerIn: parent
                                    border.color: Config.color.primary
                                    border.width: 2
                                    color: "transparent"
                                    height: parent.implicitHeight
                                    radius: width / 2
                                    visible: dayDelegate.isSelection
                                    width: parent.implicitWidth
                                }
                                Text {
                                    anchors.centerIn: parent
                                    color: dayDelegate.isToday ? Config.color.on_primary : (dayDelegate.inMonth && calendar.markerCount(dayDelegate.dateObj) > 0 ? Config.color.on_tertiary : Config.color.on_surface)
                                    font.family: Config.fontFamily
                                    font.pixelSize: Config.type.bodyMedium.size
                                    font.weight: Config.type.bodyMedium.weight
                                    horizontalAlignment: Text.AlignHCenter
                                    text: dayDelegate.inMonth ? dayDelegate.dayNumber : ""
                                    verticalAlignment: Text.AlignVCenter
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: dayDelegate.inMonth

                                    onClicked: calendar.selectedDate = dayDelegate.dateObj
                                }
                            }
                        }
                    }
                }
            }

            // Allow wheel to scroll months
            MouseArea {
                property real lastWheelStepAtMs: 0
                property real wheelAccumulator: 0
                property int wheelCooldownMs: 180

                function wheelDelta(wheel) {
                    const ax = wheel.angleDelta.x;
                    const ay = wheel.angleDelta.y;
                    if (ax !== 0 || ay !== 0) {
                        const useX = Math.abs(ax) > Math.abs(ay);
                        return ({
                                value: useX ? ax : ay,
                                axis: useX ? "x" : "y",
                                threshold: 240
                            });
                    }

                    const px = wheel.pixelDelta.x;
                    const py = wheel.pixelDelta.y;
                    if (px !== 0 || py !== 0) {
                        const useX = Math.abs(px) > Math.abs(py);
                        return ({
                                value: useX ? px : py,
                                axis: useX ? "x" : "y",
                                threshold: 220
                            });
                    }

                    return null;
                }

                acceptedButtons: Qt.NoButton
                anchors.fill: parent

                onWheel: function (wheel) {
                    const delta = wheelDelta(wheel);
                    if (!delta)
                        return;

                    const nowMs = Date.now();
                    if (nowMs - lastWheelStepAtMs < wheelCooldownMs) {
                        wheel.accepted = true;
                        return;
                    }

                    // Normalize so positive always means "next month"
                    let amount = -delta.value;
                    if (wheel.inverted)
                        amount = -amount;

                    wheelAccumulator += amount;

                    let steps = 0;
                    const maxSteps = 1;
                    while (wheelAccumulator >= delta.threshold && steps < maxSteps) {
                        monthListView.incrementCurrentIndex();
                        wheelAccumulator -= delta.threshold;
                        steps++;
                    }
                    while (wheelAccumulator <= -delta.threshold && steps < maxSteps) {
                        monthListView.decrementCurrentIndex();
                        wheelAccumulator += delta.threshold;
                        steps++;
                    }

                    if (steps > 0) {
                        lastWheelStepAtMs = nowMs;
                        wheelAccumulator = 0;
                    }

                    wheel.accepted = true;
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Config.color.outline
            opacity: 0.18
        }
        ColumnLayout {
            id: eventListLayout

            readonly property bool isToday: calendar.selectedDate.getDate() === calendar.todayDay && calendar.selectedDate.getMonth() === calendar.todayMonth && calendar.selectedDate.getFullYear() === calendar.todayYear

            Layout.fillWidth: true
            Layout.topMargin: Config.space.sm
            spacing: Config.space.sm

            Text {
                Layout.bottomMargin: Config.space.none
                color: Config.color.primary
                font.family: Config.fontFamily
                font.letterSpacing: 1.5
                font.pixelSize: Config.type.labelSmall.size
                font.weight: Font.Black
                text: "TODAY'S EVENTS"
                visible: eventListLayout.isToday && calendar.dayEvents.length > 0
            }
            Repeater {
                model: calendar.dayEvents && calendar.dayEvents.length > 0 ? calendar.dayEvents.slice(0, 4) : []

                delegate: RowLayout {
                    id: eventRow
                    required property var modelData

                    Layout.fillWidth: true
                    spacing: Config.space.sm

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        color: eventListLayout.isToday ? Config.color.primary : Config.color.outline
                        Layout.preferredHeight: 12
                        Layout.preferredWidth: 2
                        implicitHeight: 12
                        implicitWidth: 2
                        opacity: eventListLayout.isToday ? 1.0 : 0.3
                        radius: 1
                    }
                    Text {
                        Layout.fillWidth: true
                        color: Config.color.on_surface
                        elide: Text.ElideRight
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.bodySmall.size
                        font.weight: eventListLayout.isToday ? Font.DemiBold : Config.type.bodySmall.weight
                        text: calendar.formatEventLabel(eventRow.modelData)
                    }
                }
            }
            Text {
                color: Config.color.on_surface_variant
                font.family: Config.fontFamily
                font.pixelSize: Config.type.bodySmall.size
                text: "No events"
                visible: !calendar.dayEvents || calendar.dayEvents.length === 0
            }
        }
    }
}
