import QtQuick
import Quickshell
import Quickshell.Io
import "../common" as Common

Item {
  id: root

  readonly property string locationsDir: "/tmp/findmy_locations"
  property var device: null
  property bool isLoading: false
  property string placeName: ""
  property bool isGeocodingLoading: false
  property date lastRefreshTime: new Date()

  readonly property var location: device && device.locations.length > 0 ? device.locations[0] : null
  readonly property bool hasData: device !== null && location !== null

  function refresh() {
    isLoading = true;
    placeName = "";
    lastRefreshTime = new Date();
    queryProc.running = true;
  }

  function loadLatest() {
    listProc.running = true;
  }

  function reverseGeocode(lat, lon) {
    isGeocodingLoading = true;
    geocodeProc.command = [
      "curl", "-sS",
      `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lon}&format=json&zoom=16`,
      "-H", "User-Agent: QuickshellFindMy/1.0"
    ];
    geocodeProc.running = true;
  }


  Component.onCompleted: loadLatest()

  Process {
    id: queryProc
    workingDirectory: Quickshell.env("HOME") + "/Projects/GoogleFindMyTools"
    command: ["uv", "run", "main.py"]

    onRunningChanged: {
      if (!running) {
        root.loadLatest();
      }
    }
  }

  Process {
    id: listProc
    command: ["sh", "-c", `ls -t "${root.locationsDir}"/*.json 2>/dev/null | head -1`]

    stdout: StdioCollector {
      onStreamFinished: {
        const file = text.trim();
        if (!file) {
          root.device = null;
          root.isLoading = false;
          return;
        }
        readProc.command = ["cat", file];
        readProc.running = true;
      }
    }
  }

  Process {
    id: readProc

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(text);
          root.device = {
            deviceName: data.device_name || "Unknown",
            canonicId: data.canonic_id || "",
            queryTime: data.query_time || "",
            locations: data.locations || []
          };
          if (root.location && root.location.latitude && root.location.longitude) {
            root.reverseGeocode(root.location.latitude, root.location.longitude);
          }
        } catch (e) {
          root.device = null;
        }
        root.isLoading = false;
      }
    }
  }

  Process {
    id: geocodeProc

    stdout: StdioCollector {
      onStreamFinished: {
        root.isGeocodingLoading = false;
        try {
          const data = JSON.parse(text);
          if (data.display_name) {
            const parts = data.display_name.split(", ");
            root.placeName = parts.slice(0, 3).join(", ");
          } else if (data.error) {
            root.placeName = "";
          }
        } catch (e) {
          root.placeName = "";
        }
      }
    }
  }

  // Content area
  Item {
    anchors.fill: parent
    anchors.margins: Common.Config.space.md

    // Refresh button
    Rectangle {
      anchors.right: parent.right
      anchors.top: parent.top
      width: 32
      height: 32
      radius: Common.Config.shape.corner.md
      color: "transparent"
      border.width: 1
      border.color: refreshArea.containsMouse ? Common.Config.m3.success : Qt.alpha(Common.Config.textColor, 0.1)
      visible: root.hasData
      z: 10

      Behavior on border.color { ColorAnimation { duration: 150 } }

      Text {
        anchors.centerIn: parent
        text: "\ue348"
        color: refreshArea.containsMouse ? Common.Config.m3.success : Common.Config.textMuted
        font.family: Common.Config.iconFontFamily
        font.pixelSize: 14

        Behavior on color { ColorAnimation { duration: 150 } }
      }

      MouseArea {
        id: refreshArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.refresh()
      }
    }

    // Empty state
    Column {
      anchors.centerIn: parent
      spacing: Common.Config.space.md
      visible: !root.hasData && !root.isLoading

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "\ueadb"
        color: Common.Config.textMuted
        font.family: Common.Config.iconFontFamily
        font.pixelSize: 48
        opacity: 0.3
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "No device data"
        color: Common.Config.textMuted
        font.family: Common.Config.fontFamily
        font.pixelSize: Common.Config.type.bodyMedium.size
      }
    }

    // Device content
    Column {
      anchors.fill: parent
      spacing: Common.Config.space.md
      visible: root.hasData

      // Device name row
      Row {
        width: parent.width
        spacing: Common.Config.space.sm

        Text {
          text: "\ueadb"
          color: Common.Config.m3.info
          font.family: Common.Config.iconFontFamily
          font.pixelSize: 24
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          width: parent.width - 120
          anchors.verticalCenter: parent.verticalCenter
          text: root.device?.deviceName ?? "Unknown"
          color: Common.Config.textColor
          font.family: Common.Config.fontFamily
          font.pixelSize: Common.Config.type.titleMedium.size
          font.weight: Font.Medium
          elide: Text.ElideRight
        }

        Rectangle {
          visible: root.location?.is_own_report === true
          width: liveRow.width + Common.Config.space.sm * 2
          height: 22
          radius: 11
          color: "transparent"
          border.width: 1
          border.color: Common.Config.m3.success
          anchors.verticalCenter: parent.verticalCenter

          Row {
            id: liveRow
            anchors.centerIn: parent
            spacing: 4

            Rectangle {
              width: 6
              height: 6
              radius: 3
              color: Common.Config.m3.success
              anchors.verticalCenter: parent.verticalCenter

              SequentialAnimation on opacity {
                running: root.location?.is_own_report === true && root.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 800 }
                NumberAnimation { to: 1.0; duration: 800 }
              }
            }

            Text {
              text: "LIVE"
              color: Common.Config.m3.success
              font.family: Common.Config.fontFamily
              font.pixelSize: 10
              font.weight: Font.Bold
            }
          }
        }

      }

      // Place name
      Row {
        width: parent.width
        spacing: Common.Config.space.sm
        visible: root.placeName.length > 0 || root.isGeocodingLoading

        Text {
          text: "\uf450"
          color: Common.Config.m3.tertiary
          font.family: Common.Config.iconFontFamily
          font.pixelSize: 14
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          width: parent.width - 24
          text: root.isGeocodingLoading ? "Loading location..." : root.placeName
          color: root.isGeocodingLoading ? Common.Config.textMuted : Common.Config.textColor
          font.family: Common.Config.fontFamily
          font.pixelSize: Common.Config.type.bodyMedium.size
          font.italic: root.isGeocodingLoading
          wrapMode: Text.WordWrap
          elide: Text.ElideRight
          maximumLineCount: 2
        }
      }

      // Coordinates box
      Rectangle {
        width: parent.width
        height: coordsCol.height + Common.Config.space.md * 2
        radius: Common.Config.shape.corner.lg
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(Common.Config.textColor, 0.1)

        Column {
          id: coordsCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Common.Config.space.md
          spacing: Common.Config.space.sm

          Row {
            width: parent.width
            spacing: Common.Config.space.sm

            Text {
              text: "LAT"
              color: Common.Config.textMuted
              font.family: Common.Config.fontFamily
              font.pixelSize: 9
              font.weight: Font.Bold
              font.letterSpacing: 2
              width: 32
              opacity: 0.5
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: root.location?.latitude?.toFixed(7) ?? "--"
              color: Common.Config.textColor
              font.family: "JetBrains Mono"
              font.pixelSize: Common.Config.type.bodyMedium.size
            }
          }

          Row {
            width: parent.width
            spacing: Common.Config.space.sm

            Text {
              text: "LON"
              color: Common.Config.textMuted
              font.family: Common.Config.fontFamily
              font.pixelSize: 9
              font.weight: Font.Bold
              font.letterSpacing: 2
              width: 32
              opacity: 0.5
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: root.location?.longitude?.toFixed(7) ?? "--"
              color: Common.Config.textColor
              font.family: "JetBrains Mono"
              font.pixelSize: Common.Config.type.bodyMedium.size
            }
          }

          Row {
            width: parent.width
            spacing: Common.Config.space.sm

            Text {
              text: "ALT"
              color: Common.Config.textMuted
              font.family: Common.Config.fontFamily
              font.pixelSize: 9
              font.weight: Font.Bold
              font.letterSpacing: 2
              width: 32
              opacity: 0.5
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: root.location?.altitude !== undefined ? `${root.location.altitude}m` : "--"
              color: Common.Config.textColor
              font.family: "JetBrains Mono"
              font.pixelSize: Common.Config.type.bodyMedium.size
            }
          }
        }
      }

      // Open in Maps button
      Rectangle {
        width: parent.width
        height: 44
        radius: Common.Config.shape.corner.lg
        color: "transparent"
        border.width: 1
        border.color: mapsArea.containsMouse ? Common.Config.m3.success : Qt.alpha(Common.Config.textColor, 0.1)
        scale: mapsArea.pressed ? 0.98 : 1.0

        Behavior on border.color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 100 } }

        MouseArea {
          id: mapsArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.location?.google_maps_link) {
              Qt.openUrlExternally(root.location.google_maps_link);
            }
          }
        }

        Row {
          anchors.centerIn: parent
          spacing: Common.Config.space.sm

          Text {
            text: "\udb80\udfcc"
            color: mapsArea.containsMouse ? Common.Config.m3.success : Common.Config.textMuted
            font.family: Common.Config.iconFontFamily
            font.pixelSize: 14
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 150 } }
          }

          Text {
            text: "OPEN IN BROWSER"
            color: mapsArea.containsMouse ? Common.Config.m3.success : Common.Config.textMuted
            font.family: Common.Config.fontFamily
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 1.5
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 150 } }
          }
        }
      }

      // Timestamp
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Refreshed: " + root.lastRefreshTime.toLocaleTimeString()
        color: Common.Config.textMuted
        font.family: Common.Config.fontFamily
        font.pixelSize: Common.Config.type.labelSmall.size
        opacity: 0.7
      }
    }
  }
}
