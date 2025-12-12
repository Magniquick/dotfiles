import QtQuick
import QtQuick.Controls
import "./Label.qml"
import "../theme"
import "../Colors.js" as RawColors

Item {
  id: root
  property date now: new Date()
  property string display: formatTime(now)
  property string altDisplay: formatAlt(now)
  property bool showAlt: false
  property string tooltipText: calendarHtml(now)
  implicitHeight: label.implicitHeight
  implicitWidth: label.implicitWidth

  function formatTime(d) {
    return Qt.formatTime(d, "hh:mm AP");
  }

  function formatAlt(d) {
    return Qt.formatDate(d, "dd/MM/yy");
  }

  function calendarHtml(d) {
    const year = d.getFullYear();
    const month = d.getMonth();
    const first = new Date(year, month, 1);
    const startDay = first.getDay(); // 0-6
    const days = new Date(year, month + 1, 0).getDate();
    let rows = "<big>" + Qt.formatDate(d, "MMMM yyyy") + "</big><br/><small>";
    rows += "Su Mo Tu We Th Fr Sa<br/>";
    let day = 1;
    for (let w = 0; w < 6 && day <= days; w++) {
      let line = "";
      for (let wd = 0; wd < 7; wd++) {
        if (w === 0 && wd < startDay || day > days) {
          line += "   ";
        } else {
          const padded = day < 10 ? " " + day : day;
          if (day === d.getDate())
            line += `<span style=\"color:${RawColors.palette.pink}\"><b>${padded}</b></span>`;
          else
            line += padded;
          day++;
        }
        if (wd < 6)
          line += " ";
      }
      rows += line + "<br/>";
    }
    rows += "</small>";
    return rows;
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      now = new Date();
      display = formatTime(now);
      altDisplay = formatAlt(now);
      tooltipText = calendarHtml(now);
    }
  }

  Label {
    id: label
    text: showAlt ? altDisplay : display
    color: Theme.colors.lavender
    textFormat: Text.RichText
    ToolTip.visible: mouseArea.containsMouse
    ToolTip.text: tooltipText
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    onClicked: {
      showAlt = !showAlt;
      label.text = showAlt ? altDisplay : display;
    }
  }
}
