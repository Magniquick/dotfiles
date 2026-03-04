import QtQuick
import ".."

Rectangle {
    id: root

    property var rxHistory: []
    property var txHistory: []
    property real adaptiveMax: 1024
    property real minScaleFloor: 1024
    property color upColor: Config.color.secondary
    property color downColor: Config.color.tertiary
    property color graphBackground: Config.barModuleBackground
    property color graphBorderColor: Config.color.outline_variant
    property int graphBorderWidth: Config.barModuleBorderWidth
    property color graphLineColor: Qt.alpha(Config.color.outline_variant, 0.45)
    property real lineWidth: 1.5
    property real downFillOpacity: 0.16
    property int horizontalPadding: Config.space.sm
    property int verticalPadding: Config.space.xs

    color: root.graphBackground
    border.color: root.graphBorderColor
    border.width: root.graphBorderWidth
    radius: Config.shape.corner.md

    function clampedSample(value) {
        if (!isFinite(value) || value < 0)
            return 0;
        return value;
    }

    function scaleMax() {
        const max = isFinite(root.adaptiveMax) ? root.adaptiveMax : root.minScaleFloor;
        return Math.max(root.minScaleFloor, max);
    }

    Canvas {
        id: canvas

        anchors.fill: parent
        renderStrategy: Canvas.Cooperative

        function sampleAt(series, index) {
            if (!series || index < 0 || index >= series.length)
                return 0;
            return root.clampedSample(series[index]);
        }

        onPaint: {
            const ctx = canvas.getContext("2d");
            ctx.reset();
            ctx.clearRect(0, 0, canvas.width, canvas.height);

            const rxSeries = root.rxHistory || [];
            const txSeries = root.txHistory || [];
            const samples = Math.max(rxSeries.length, txSeries.length);
            if (samples < 2)
                return;

            const left = root.horizontalPadding;
            const right = canvas.width - root.horizontalPadding;
            const top = root.verticalPadding;
            const bottom = canvas.height - root.verticalPadding;
            const drawWidth = Math.max(1, right - left);
            const drawHeight = Math.max(1, bottom - top);
            const maxVal = root.scaleMax();

            const xForIndex = index => {
                if (samples <= 1)
                    return left;
                return left + (drawWidth * index) / (samples - 1);
            };
            const yForValue = value => {
                const normalized = Math.max(0, Math.min(1, root.clampedSample(value) / maxVal));
                return bottom - normalized * drawHeight;
            };

            // subtle horizontal guides
            ctx.strokeStyle = Qt.alpha(root.graphLineColor, 0.5);
            ctx.lineWidth = 1;
            for (let i = 1; i <= 2; i++) {
                const y = top + (drawHeight * i) / 3;
                ctx.beginPath();
                ctx.moveTo(left, y);
                ctx.lineTo(right, y);
                ctx.stroke();
            }

            // fill under download line
            const down = root.downColor;
            const downFill = Qt.rgba(down.r, down.g, down.b, root.downFillOpacity);
            ctx.fillStyle = downFill;
            ctx.beginPath();
            ctx.moveTo(xForIndex(0), bottom);
            for (let i = 0; i < samples; i++)
                ctx.lineTo(xForIndex(i), yForValue(canvas.sampleAt(rxSeries, i)));
            ctx.lineTo(xForIndex(samples - 1), bottom);
            ctx.closePath();
            ctx.fill();

            // download (RX) line
            ctx.strokeStyle = root.downColor;
            ctx.lineWidth = root.lineWidth;
            ctx.beginPath();
            for (let i = 0; i < samples; i++) {
                const x = xForIndex(i);
                const y = yForValue(canvas.sampleAt(rxSeries, i));
                if (i === 0)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
            }
            ctx.stroke();

            // upload (TX) line
            ctx.strokeStyle = root.upColor;
            ctx.lineWidth = root.lineWidth;
            ctx.beginPath();
            for (let i = 0; i < samples; i++) {
                const x = xForIndex(i);
                const y = yForValue(canvas.sampleAt(txSeries, i));
                if (i === 0)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
            }
            ctx.stroke();
        }

        Connections {
            target: root

            function onRxHistoryChanged() {
                canvas.requestPaint();
            }
            function onTxHistoryChanged() {
                canvas.requestPaint();
            }
            function onAdaptiveMaxChanged() {
                canvas.requestPaint();
            }
            function onWidthChanged() {
                canvas.requestPaint();
            }
            function onHeightChanged() {
                canvas.requestPaint();
            }
        }
    }
}
