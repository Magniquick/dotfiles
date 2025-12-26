pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "./JsonUtils.js" as JsonUtils

Item {
    id: calendar
    property date currentDate: new Date()
    property bool active: false
    property string cacheDir: ""
    property string refreshCommand: ""
    readonly property string eventsPath: calendar.cacheDir !== "" ? calendar.cacheDir + "/events.json" : ""
    property var eventsByDay: ({})
    property var dayEvents: []
    property date selectedDate: new Date()
    property string calendarStatus: ""
    property string calendarGeneratedAt: ""
    signal dataLoaded

    // Fixed size to avoid jumping during scroll
    implicitWidth: 240
    implicitHeight: layout.implicitHeight

    readonly property date today: new Date()
    readonly property int todayDay: today.getDate()
    readonly property int todayMonth: today.getMonth()
    readonly property int todayYear: today.getFullYear()

    readonly property var weekDays: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
    readonly property int dayCellSize: Config.type.bodyMedium.size + Config.space.md

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

    function updateDayEvents() {
        const key = calendar.dayKey(calendar.selectedDate);
        const list = (key && calendar.eventsByDay && calendar.eventsByDay[key]) ? calendar.eventsByDay[key] : [];
        calendar.dayEvents = list;
    }

    function markerCount(date) {
        const key = calendar.dayKey(date);
        if (!key || !calendar.eventsByDay || !calendar.eventsByDay[key])
            return 0;
        return Math.min(3, calendar.eventsByDay[key].length);
    }

    function formatEventTime(event) {
        if (!event || event.all_day)
            return "All day";
        const startValue = event.start ? new Date(event.start) : null;
        if (!startValue || isNaN(startValue.getTime()))
            return "";
        return Qt.formatDateTime(startValue, "hh:mm ap");
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

    CommandRunner {
        id: refreshRunner
        intervalMs: 3600000
        enabled: calendar.refreshCommand !== ""
        command: calendar.refreshCommand
        onRan: function () {
            if (calendar.active)
                eventsRunner.trigger();
        }
    }

    CommandRunner {
        id: eventsRunner
        intervalMs: 0
        enabled: true
        command: calendar.eventsPath !== "" ? "cat " + calendar.eventsPath : ""
        onRan: function (output) {
            calendar.applyCalendarData(JsonUtils.parseObject(output));
            calendar.dataLoaded();
        }
    }

    onSelectedDateChanged: calendar.updateDayEvents()
    onEventsByDayChanged: calendar.updateDayEvents()
    onActiveChanged: {
        if (!calendar.active)
            return;
        if (calendar.refreshCommand !== "")
            refreshRunner.trigger();
        else
            eventsRunner.trigger();
    }

    function refreshRequested() {
        if (calendar.refreshCommand !== "")
            refreshRunner.trigger();
        else
            eventsRunner.trigger();
    }

    onCurrentDateChanged: {
        calendar.selectedDate = new Date(calendar.currentDate.getTime());
        calendar.updateDayEvents();
    }

    Component.onCompleted: {
        if (calendar.refreshCommand !== "")
            refreshRunner.trigger();
        calendar.updateDayEvents();
    }

    ColumnLayout {
        id: layout
        anchors.fill: parent
        spacing: Config.space.sm

        ListView {
            id: monthListView
            Layout.fillWidth: true
            Layout.preferredHeight: 230 // Title + Header + Grid
            orientation: ListView.Horizontal
            snapMode: ListView.SnapOneItem
            highlightRangeMode: ListView.StrictlyEnforceRange
            model: 2400 // covering 200 years for "infinite" feel
            currentIndex: 1200 // start in the middle
            clip: true

            // Allow wheel to scroll months
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                property real wheelAccumulator: 0
                property real lastWheelStepAtMs: 0
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

            delegate: Item {
                id: monthDelegate
                required property int index
                width: monthListView.width
                height: monthListView.height

                readonly property int monthOffset: index - 1200
                readonly property date viewDate: new Date(calendar.todayYear, calendar.todayMonth + monthOffset, 1)
                readonly property int viewYear: viewDate.getFullYear()
                readonly property int viewMonth: viewDate.getMonth()
                readonly property int daysInMonth: new Date(viewYear, viewMonth + 1, 0).getDate()
                readonly property int startOffset: new Date(viewYear, viewMonth, 1).getDay()

                ColumnLayout {
                    anchors.fill: parent
                    spacing: Config.space.sm

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Config.space.none
                        Layout.bottomMargin: Config.space.sm
                        spacing: Config.space.xs

                        Text {
                            text: Qt.formatDateTime(monthDelegate.viewDate, "MMMM")
                            color: Config.textColor
                            font.family: Config.fontFamily
                            font.pixelSize: Config.type.headlineSmall.size
                            font.weight: Font.Bold
                        }

                        Text {
                            text: Qt.formatDateTime(monthDelegate.viewDate, "yyyy")
                            color: Config.textMuted
                            font.family: Config.fontFamily
                            font.pixelSize: Config.type.headlineSmall.size
                            font.weight: Font.ExtraLight
                        }
                    }

                    GridLayout {
                        columns: 7
                        columnSpacing: Config.space.sm
                        rowSpacing: 0
                        Layout.alignment: Qt.AlignHCenter

                        Repeater {
                            model: calendar.weekDays
                            delegate: Item {
                                required property int index
                                required property string modelData
                                implicitWidth: calendar.dayCellSize
                                implicitHeight: Config.type.labelSmall.size + Config.space.xs

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: Config.textMuted
                                    font.family: Config.fontFamily
                                    font.pixelSize: Config.type.labelSmall.size
                                    font.weight: Config.type.labelSmall.weight
                                }
                            }
                        }
                    }

                    GridLayout {
                        columns: 7
                        rowSpacing: Config.space.xs
                        columnSpacing: Config.space.sm
                        Layout.alignment: Qt.AlignHCenter

                        Repeater {
                            model: 42 // 6 rows for consistent height
                            delegate: Item {
                                id: dayDelegate
                                required property int index
                                readonly property int dayNumber: index - monthDelegate.startOffset + 1
                                readonly property bool inMonth: dayNumber > 0 && dayNumber <= monthDelegate.daysInMonth
                                readonly property var dateObj: inMonth ? new Date(monthDelegate.viewYear, monthDelegate.viewMonth, dayNumber) : undefined

                                readonly property bool isToday: inMonth && dayNumber === calendar.todayDay && monthDelegate.viewMonth === calendar.todayMonth && monthDelegate.viewYear === calendar.todayYear

                                readonly property bool isSelection: inMonth && dayNumber === calendar.selectedDate.getDate() && monthDelegate.viewMonth === calendar.selectedDate.getMonth() && monthDelegate.viewYear === calendar.selectedDate.getFullYear()

                                implicitWidth: calendar.dayCellSize
                                implicitHeight: calendar.dayCellSize

                                // Event Filled Circle
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.implicitWidth - Config.space.xs
                                    height: parent.implicitHeight - Config.space.xs
                                    radius: width / 2
                                    color: Config.green
                                    visible: dayDelegate.inMonth && !dayDelegate.isToday && calendar.markerCount(dayDelegate.dateObj) > 0
                                }

                                // Today Filled Circle
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.implicitWidth - Config.space.xs
                                    height: parent.implicitHeight - Config.space.xs
                                    radius: width / 2
                                    color: Config.primary
                                    visible: dayDelegate.isToday
                                }

                                // Selection Outline
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.implicitWidth
                                    height: parent.implicitHeight
                                    radius: width / 2
                                    color: "transparent"
                                    border.width: 2
                                    border.color: Config.primary
                                    visible: dayDelegate.isSelection
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: dayDelegate.inMonth ? dayDelegate.dayNumber : ""
                                    color: dayDelegate.isToday ? Config.onPrimary : (dayDelegate.inMonth && calendar.markerCount(dayDelegate.dateObj) > 0 ? Config.m3.onSuccess : Config.textColor)
                                    font.family: Config.fontFamily
                                    font.pixelSize: Config.type.bodyMedium.size
                                    font.weight: Config.type.bodyMedium.weight
                                    horizontalAlignment: Text.AlignHCenter
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
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Config.outline
            opacity: 0.18
        }

        ColumnLayout {
            id: eventListLayout
            spacing: Config.space.sm
            Layout.fillWidth: true
            Layout.topMargin: Config.space.sm

            readonly property bool isToday: calendar.selectedDate.getDate() === calendar.todayDay && calendar.selectedDate.getMonth() === calendar.todayMonth && calendar.selectedDate.getFullYear() === calendar.todayYear

            Text {
                text: "TODAY'S EVENTS"
                color: Config.primary
                font.family: Config.fontFamily
                font.pixelSize: Config.type.labelSmall.size
                font.weight: Font.Black
                font.letterSpacing: 1.5
                visible: eventListLayout.isToday && calendar.dayEvents.length > 0
                Layout.bottomMargin: Config.space.none
            }

            Repeater {
                model: calendar.dayEvents && calendar.dayEvents.length > 0 ? calendar.dayEvents.slice(0, 4) : []
                delegate: RowLayout {
                    required property var modelData
                    spacing: Config.space.sm
                    Layout.fillWidth: true

                    Rectangle {
                        width: 2
                        height: 12
                        radius: 1
                        color: eventListLayout.isToday ? Config.primary : Config.outline
                        opacity: eventListLayout.isToday ? 1.0 : 0.3
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        text: calendar.formatEventLabel(modelData)
                        color: Config.textColor
                        font.family: Config.fontFamily
                        font.pixelSize: Config.type.bodySmall.size
                        font.weight: eventListLayout.isToday ? Font.DemiBold : Config.type.bodySmall.weight
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
            }

            Text {
                text: "No events"
                color: Config.textMuted
                font.family: Config.fontFamily
                font.pixelSize: Config.type.bodySmall.size
                visible: !calendar.dayEvents || calendar.dayEvents.length === 0
            }
        }
    }
}
