import QtQuick
import QtQuick.Layouts
import "../common" as Common

Item {
    id: root
    property real value: 0
    property color accent: Common.Config.color.primary
    property string label: ""
    property string icon: ""

    Layout.fillWidth: true
    Layout.preferredHeight: width + 36

    ColumnLayout {
        anchors.fill: parent
        spacing: Common.Config.space.sm

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Canvas {
                id: gauge
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height)
                height: width

                property real animatedValue: 0

                Behavior on animatedValue {
                    NumberAnimation {
                        duration: 800
                        easing.type: Easing.OutCubic
                    }
                }

                Component.onCompleted: animatedValue = root.value

                onAnimatedValueChanged: requestPaint()

                Connections {
                    target: root
                    function onValueChanged() {
                        gauge.animatedValue = root.value;
                    }
                }

                onPaint: {
                    if (width <= 0 || height <= 0)
                        return;

                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);

                    const strokeWidth = Math.max(8, width * 0.08);
                    const center = width / 2;
                    const radius = Math.max(1, (width - strokeWidth * 2) / 2);
                    const startAngle = -Math.PI / 2;
                    const endAngle = startAngle + (Math.PI * 2 * animatedValue / 100);

                    // Background track
                    ctx.lineWidth = strokeWidth;
                    ctx.strokeStyle = Qt.alpha(Common.Config.color.on_surface, 0.03);
                    ctx.lineCap = "round";
                    ctx.beginPath();
                    ctx.arc(center, center, radius, 0, Math.PI * 2);
                    ctx.stroke();

                    // Value arc
                    ctx.strokeStyle = root.accent;
                    ctx.beginPath();
                    ctx.arc(center, center, radius, startAngle, endAngle);
                    ctx.stroke();
                }
            }

            Text {
                anchors.centerIn: parent
                text: Math.round(root.value) + "%"
                color: Common.Config.color.on_surface
                font.family: Common.Config.fontFamily
                font.pixelSize: Math.max(14, gauge.width * 0.22)
                font.weight: Font.Black
            }
        }

        // Pill label
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: labelRow.implicitWidth + Common.Config.space.md * 2
            implicitHeight: 22
            radius: 11
            color: Qt.alpha(Common.Config.color.on_surface, 0.05)
            border.width: 1
            border.color: Qt.alpha(Common.Config.color.on_surface, 0.1)

            Row {
                id: labelRow
                anchors.centerIn: parent
                spacing: Common.Config.space.xs

                Text {
                    visible: root.icon !== ""
                    text: root.icon
                    color: Common.Config.color.on_surface_variant
                    font.family: Common.Config.iconFontFamily
                    font.pixelSize: 10
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: root.label
                    color: Common.Config.color.on_surface_variant
                    font.family: Common.Config.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                    font.capitalization: Font.AllUppercase
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
