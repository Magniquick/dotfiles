pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../common" as Common
import "../../common/modules/rounded_polygon_qmljs" as RoundedPoly
import Qcm.Material as MD
import "../../common/modules/rounded_polygon_qmljs/material-shapes.js" as MaterialShapes

Item {
    id: root
    property bool busy: false
    property string placeholderText: "Type a message..."
    property alias text: inputEdit.text
    property var chatSession: null
    readonly property int maxLines: 5
    readonly property int maxInputHeight: Math.ceil(inputMetrics.lineSpacing * root.maxLines) + inputEdit.topPadding + inputEdit.bottomPadding

    signal send(string text, string attachmentsJson)
    signal commandTriggered(string command)

    implicitHeight: composerContainer.implicitHeight

    property var pendingAttachments: []

    // Command suggestion state
    property var suggestionList: []
    property int selectedSuggestion: -1
    readonly property var chatCommands: {
        if (!root.chatSession || !root.chatSession.commandsJson) return [];
        try { return JSON.parse(root.chatSession.commandsJson); } catch(e) { return []; }
    }

    function acceptSuggestion(name) {
        inputEdit.text = name + " ";
        inputEdit.cursorPosition = inputEdit.text.length;
        root.suggestionList = [];
        root.selectedSuggestion = -1;
        root.focusInput();
    }

    function focusInput() {
        // Avoid forcing focus while the panel window is mid-transition or not visible yet.
        if (!root.visible)
            return;
        if (root.QsWindow && root.QsWindow.window && !root.QsWindow.window.visible)
            return;
        inputEdit.forceActiveFocus();
    }

    function clearFocus() {
        inputEdit.focus = false;
    }

    function attachmentSource(a) {
        if (!a)
            return "";
        const p = (a.path || "").trim();
        if (p.length > 0)
            return "file://" + p;
        const mime = (a.mime || "").trim();
        const b64 = (a.b64 || "").trim();
        if (mime.length > 0 && b64.length > 0)
            return "data:" + mime + ";base64," + b64;
        return "";
    }

    function isPdfAttachment(a) {
        if (!a)
            return false;
        const mime = String(a.mime || "").trim().toLowerCase();
        if (mime === "application/pdf")
            return true;
        const p = String(a.path || "").trim().toLowerCase();
        return p.endsWith(".pdf");
    }

    function attachmentLabel(a) {
        const p = String((a || {}).path || "").trim();
        if (!p)
            return "Attachment";
        const parts = p.split("/");
        return parts.length ? parts[parts.length - 1] : p;
    }

    function tryPasteImageFromClipboard() {
        if (!root.chatSession || !root.chatSession.pasteImageFromClipboard)
            return false;

        const json = String(root.chatSession.pasteImageFromClipboard() || "").trim();
        if (!json)
            return false;

        let parsed = null;
        try {
            parsed = JSON.parse(json);
        } catch (e) {
            parsed = null;
        }

        if (!parsed)
            return false;

        // Normalize to array in case the backend returns a single object.
        const items = Array.isArray(parsed) ? parsed : [parsed];
        for (let i = 0; i < items.length; i++) {
            const a = items[i] || {};
            // Only accept things we can render or send.
            if (!a.path && !a.b64)
                continue;
            root.pendingAttachments = root.pendingAttachments.concat([a]);
        }
        return true;
    }

    function tryPasteAttachmentFromClipboard() {
        if (!root.chatSession || !root.chatSession.pasteAttachmentFromClipboard)
            return false;

        const json = String(root.chatSession.pasteAttachmentFromClipboard() || "").trim();
        if (!json)
            return false;

        let parsed = null;
        try {
            parsed = JSON.parse(json);
        } catch (e) {
            parsed = null;
        }

        if (!parsed)
            return false;

        const items = Array.isArray(parsed) ? parsed : [parsed];
        for (let i = 0; i < items.length; i++) {
            const a = items[i] || {};
            if (!a.path && !a.b64)
                continue;
            root.pendingAttachments = root.pendingAttachments.concat([a]);
        }
        return true;
    }

    function handleSend() {
        const text = inputEdit.text.trim();
        if (text.length === 0 && root.pendingAttachments.length === 0)
            return;

        if (text.startsWith("/")) {
            root.commandTriggered(text);
        } else {
            root.send(text, JSON.stringify(root.pendingAttachments || []));
            root.pendingAttachments = [];
        }

        // Reset to the default single-line height after sending.
        inputEdit.text = "";
        textFlick.contentY = 0;
        root.focusInput();
    }

    component GlowLayer: Rectangle {
        property real marginSize: 2
        property real focusedOpacity: 0.3
        property real unfocusedOpacity: 0.1

        anchors.fill: inputContainer
        anchors.margins: -marginSize
        radius: Common.Config.shape.corner.lg + marginSize
        opacity: inputEdit.activeFocus ? focusedOpacity : unfocusedOpacity
        visible: !root.busy

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: Common.Config.color.primary
            }
            GradientStop {
                position: 1.0
                color: Common.Config.color.primary
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutCubic
            }
        }
    }

    Item {
        id: composerContainer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        implicitHeight: suggestionStrip.visible
            ? (suggestionStrip.implicitHeight + Math.floor(inputWrapper.implicitHeight / 2))
            : inputWrapper.implicitHeight

        // ── Command suggestion strip ──────────────────────────────────────
        Item {
            id: suggestionStrip
            visible: root.suggestionList.length > 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            implicitHeight: Math.min(suggestionListView.contentHeight + 2, 5 * 40 + 2) + Math.floor(inputWrapper.implicitHeight / 2)
            Rectangle {
                anchors.fill: parent
                color: Common.Config.color.surface_container_high
                radius: Common.Config.shape.corner.md
                border.width: 1
                border.color: Common.Config.color.outline_variant

                ListView {
                    id: suggestionListView
                    anchors.fill: parent
                    anchors.margins: 1
                    anchors.bottomMargin: Math.floor(inputWrapper.implicitHeight / 2) + 1
                    clip: true
                    model: root.suggestionList
                    spacing: 0

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    Connections {
                        target: root
                        function onSelectedSuggestionChanged() {
                            if (root.selectedSuggestion >= 0)
                                suggestionListView.positionViewAtIndex(root.selectedSuggestion, ListView.Contain);
                        }
                    }

                    delegate: Rectangle {
                        required property var modelData
                        required property int index

                        width: ListView.view.width
                        height: 40
                        radius: Common.Config.shape.corner.sm
                        color: index === root.selectedSuggestion
                            ? Common.Config.color.primary_container
                            : "transparent"

                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Common.Config.space.sm
                            anchors.rightMargin: Common.Config.space.sm
                            spacing: Common.Config.space.sm

                            Text {
                                text: modelData.name
                                color: index === root.selectedSuggestion
                                    ? Common.Config.color.on_primary_container
                                    : Common.Config.color.on_surface
                                font.family: Common.Config.fontFamily
                                font.pixelSize: Common.Config.type.labelMedium.size
                                font.weight: Font.Medium
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.description || ""
                                color: index === root.selectedSuggestion
                                    ? Qt.alpha(Common.Config.color.on_primary_container, 0.7)
                                    : Common.Config.color.on_surface_variant
                                font.family: Common.Config.fontFamily
                                font.pixelSize: Common.Config.type.labelSmall.size
                                elide: Text.ElideRight
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                        }

                        HoverHandler {
                            onHoveredChanged: if (hovered) root.selectedSuggestion = index
                        }

                        HybridRipple {
                            anchors.fill: parent
                            color: Common.Config.color.on_surface
                            pressX: suggestionArea.pressX
                            pressY: suggestionArea.pressY
                            pressed: suggestionArea.pressed
                            radius: parent.radius
                            stateOpacity: 0
                        }
                        MouseArea {
                            id: suggestionArea
                            property real pressX: width / 2
                            property real pressY: height / 2
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.acceptSuggestion(modelData.name)
                            onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
                        }
                    }
                }
            }
        }

        // ── Input box (glow + container) ──────────────────────────────────
        Item {
            id: inputWrapper
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            implicitHeight: inputContainer.height

            GlowLayer {
                marginSize: 2
                focusedOpacity: 0.3
                unfocusedOpacity: 0.1
            }
            GlowLayer {
                marginSize: 4
                focusedOpacity: 0.15
                unfocusedOpacity: 0
            }

            Rectangle {
                id: inputContainer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            implicitHeight: inputRow.implicitHeight + attachmentStrip.implicitHeight + Common.Config.space.sm * 2
            height: implicitHeight
            color: Common.Config.color.surface_container_highest
            radius: Common.Config.shape.corner.lg
            border.width: 1
            border.color: inputEdit.activeFocus ? Common.Config.color.primary : Common.Config.color.outline

            Behavior on border.color {
                ColorAnimation {
                    duration: 200
                }
            }

            HoverHandler { id: composerHover }
            TapHandler {
                id: composerTap
                onTapped: root.focusInput()
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Common.Config.space.sm
                spacing: Common.Config.space.sm

                Item {
                    id: attachmentStrip
                    Layout.fillWidth: true
                    visible: root.pendingAttachments.length > 0
                    implicitHeight: visible ? 56 : 0

                    Flickable {
                        anchors.fill: parent
                        contentWidth: attachmentsRow.implicitWidth
                        contentHeight: height
                        clip: true

                        Row {
                            id: attachmentsRow
                            spacing: Common.Config.space.sm
                            height: parent.height

                            Repeater {
                                model: root.pendingAttachments
                                delegate: Item {
                                    required property var modelData
                                    required property int index

                                    width: 56
                                    height: 56

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Common.Config.shape.corner.md
                                        color: Qt.alpha(Common.Config.color.on_surface, 0.04)
                                        border.width: 1
                                        border.color: Qt.alpha(Common.Config.color.on_surface, 0.10)
                                        clip: true

                                        Image {
                                            anchors.fill: parent
                                            anchors.margins: 4
                                            source: root.attachmentSource(modelData)
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            cache: false
                                            visible: !root.isPdfAttachment(modelData)
                                        }

                                        Item {
                                            anchors.fill: parent
                                            visible: root.isPdfAttachment(modelData)

                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "\uf1c1" // file-pdf
                                                color: Common.Config.color.on_surface_variant
                                                font.family: Common.Config.iconFontFamily
                                                font.pixelSize: 22
                                            }

                                            Text {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.bottom: parent.bottom
                                                anchors.margins: 4
                                                text: root.attachmentLabel(modelData)
                                                elide: Text.ElideRight
                                                maximumLineCount: 1
                                                color: Common.Config.color.on_surface_variant
                                                font.family: Common.Config.fontFamily
                                                font.pixelSize: 9
                                            }
                                        }

                                        Rectangle {
                                            width: 18
                                            height: 18
                                            radius: 9
                                            anchors.top: parent.top
                                            anchors.right: parent.right
                                            anchors.topMargin: 3
                                            anchors.rightMargin: 3
                                            color: Qt.alpha(Common.Config.color.surface_container_highest, 0.85)
                                            border.width: 1
                                            border.color: Qt.alpha(Common.Config.color.on_surface, 0.12)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "\uf00d"
                                                color: Common.Config.color.on_surface_variant
                                                font.family: Common.Config.iconFontFamily
                                                font.pixelSize: 10
                                            }

                                            HybridRipple {
                                                anchors.fill: parent
                                                color: Common.Config.color.error
                                                pressX: deleteArea.pressX
                                                pressY: deleteArea.pressY
                                                pressed: deleteArea.pressed
                                                radius: parent.radius
                                                stateOpacity: deleteArea.containsMouse ? Common.Config.state.hoverOpacity : 0
                                            }
                                            MouseArea {
                                                id: deleteArea
                                                property real pressX: width / 2
                                                property real pressY: height / 2
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                hoverEnabled: true
                                                onClicked: {
                                                    const next = [];
                                                    for (let i = 0; i < root.pendingAttachments.length; i++) {
                                                        if (i !== index)
                                                            next.push(root.pendingAttachments[i]);
                                                    }
                                                    root.pendingAttachments = next;
                                                }
                                                onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    id: inputRow
                    Layout.fillWidth: true
                    spacing: Common.Config.space.sm

                    Item {
                        id: inputWrap
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(48, Math.min(textFlick.contentHeight, root.maxInputHeight))

                    function scrollToThumbY(localY) {
                        const maxThumbY = Math.max(0, inputWrap.height - scrollThumb.height);
                        const clampedY = Math.max(0, Math.min(maxThumbY, localY - scrollThumb.height / 2));
                        const range = Math.max(1, textFlick.contentHeight - inputWrap.height);
                        textFlick.contentY = maxThumbY > 0 ? (clampedY / maxThumbY) * range : 0;
                    }

                    Flickable {
                        id: textFlick
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: inputEdit.height
                        clip: true

                        TextEdit {
                            id: inputEdit
                            width: textFlick.width
                            height: contentHeight + topPadding + bottomPadding
                            y: Math.max(0, (inputWrap.height - height) / 2)
                            text: ""
                            wrapMode: TextEdit.Wrap
                            color: Common.Config.color.on_surface
                            font.family: Common.Config.fontFamily
                            font.pixelSize: Common.Config.type.bodyMedium.size + 1
                            selectionColor: Common.Config.color.primary
                            selectedTextColor: Common.Config.color.on_primary
                            readOnly: false
                            cursorVisible: inputEdit.activeFocus && !root.busy
                            focus: false
                            activeFocusOnPress: true
                            topPadding: 4
                            bottomPadding: 4
                            leftPadding: 0
                            rightPadding: 8
                            onActiveFocusChanged: {
                                if (!activeFocus) {
                                    inputEdit.cursorPosition = inputEdit.text.length;
                                }
                            }

                            onTextChanged: {
                                // Keep the scroll pinned to bottom only when needed.
                                Qt.callLater(function() {
                                    if (textFlick.contentHeight > textFlick.height)
                                        textFlick.contentY = textFlick.contentHeight - textFlick.height;
                                    else
                                        textFlick.contentY = 0;
                                });

                                // Command suggestions: show when typing a bare /word with no space yet.
                                const t = inputEdit.text;
                                if (t.startsWith("/") && t.indexOf(" ") < 0) {
                                    const query = t.substring(1).toLowerCase();
                                    root.suggestionList = root.chatCommands.filter(
                                        cmd => cmd.name.substring(1).startsWith(query)
                                    );
                                    root.selectedSuggestion = root.suggestionList.length > 0 ? 0 : -1;
                                } else {
                                    root.suggestionList = [];
                                    root.selectedSuggestion = -1;
                                }
                            }

                            Keys.onPressed: event => {
                                // Navigate / accept suggestions.
                                if (root.suggestionList.length > 0) {
                                    if (event.key === Qt.Key_Tab) {
                                        root.acceptSuggestion(root.suggestionList[Math.max(0, root.selectedSuggestion)].name);
                                        event.accepted = true;
                                        return;
                                    }
                                    if (event.key === Qt.Key_Up) {
                                        root.selectedSuggestion = Math.max(0, root.selectedSuggestion - 1);
                                        event.accepted = true;
                                        return;
                                    }
                                    if (event.key === Qt.Key_Down) {
                                        root.selectedSuggestion = Math.min(root.suggestionList.length - 1, root.selectedSuggestion + 1);
                                        event.accepted = true;
                                        return;
                                    }
                                }

                                // Prefer image paste over text paste when clipboard contains an image.
                                if (!root.busy
                                    && ((event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier))
                                        || (event.key === Qt.Key_Insert && (event.modifiers & Qt.ShiftModifier)))) {
                                    if (root.tryPasteImageFromClipboard()) {
                                        event.accepted = true;
                                        return;
                                    }
                                    if (root.tryPasteAttachmentFromClipboard()) {
                                        event.accepted = true;
                                        return;
                                    }
                                }
                                if (event.key === Qt.Key_Return && !(event.modifiers & Qt.ShiftModifier)) {
                                    root.handleSend();
                                    event.accepted = true;
                                }
                            }
                        }

                        ScrollBar.vertical: null
                    }

                    Rectangle {
                        id: scrollTrack
                        anchors.right: parent.right
                        anchors.rightMargin: 0
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 6
                        color: "transparent"
                        visible: scrollThumb.visible
                        z: 2

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: event => inputWrap.scrollToThumbY(event.y)
                            onPositionChanged: event => {
                                if (pressed)
                                    inputWrap.scrollToThumbY(event.y);
                            }
                        }
                    }

                    Rectangle {
                        id: scrollThumb
                        anchors.right: parent.right
                        anchors.rightMargin: 1
                        width: 4
                        height: Math.max(12, inputWrap.height * (inputWrap.height / Math.max(1, textFlick.contentHeight)))
                        y: Math.min(inputWrap.height - height, textFlick.contentY / Math.max(1, textFlick.contentHeight - inputWrap.height) * (inputWrap.height - height))
                        radius: 2
                        color: Common.Config.color.on_surface_variant
                        visible: textFlick.contentHeight > inputWrap.height + 1
                        z: 3
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        color: Common.Config.color.on_surface_variant
                        font.family: Common.Config.fontFamily
                        font.pixelSize: Common.Config.type.bodyMedium.size + 1
                        text: root.placeholderText
                        visible: inputEdit.text.length === 0
                        opacity: 0.8
                    }
                }

                Rectangle {
                    id: sendButton
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: Common.Config.space.xs
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    implicitWidth: 44
                    implicitHeight: 44
                    radius: Common.Config.shape.corner.md
                    color: root.busy
                        ? (sendButtonArea.containsMouse ? Common.Config.color.error : Qt.alpha(Common.Config.color.error, 0.18))
                        : Common.Config.color.primary
                    border.width: 1
                    border.color: root.busy
                        ? Qt.alpha(Common.Config.color.error, 0.35)
                        : Qt.alpha(Common.Config.color.on_primary, 0.0)

                    scale: sendButtonArea.pressed ? 0.92 : (sendButtonArea.containsMouse ? 1.05 : 1.0)

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 100
                            easing.type: Easing.OutCubic
                        }
                    }

                    Item {
                        anchors.centerIn: parent
                        width: parent.width
                        height: parent.height

                        Item {
                            id: sendGlyphWrap
                            anchors.fill: parent

                            // Keep animations off when the window isn't visible (idle CPU).
                            readonly property bool animOk: root.visible
                                && (!root.QsWindow || !root.QsWindow.window || root.QsWindow.window.visible)

                            // While generating, keep morphing between a small set of shapes.
                            // When idle, show a stable "send" glyph.
                            property int busyShapeIndex: 0
                            readonly property var busyShapeGetters: [
                                MaterialShapes.getCircle,
                                MaterialShapes.getSquare,
                                MaterialShapes.getSlanted,
                                MaterialShapes.getArch,
                                MaterialShapes.getFan,
                                MaterialShapes.getArrow,
                                MaterialShapes.getSemiCircle,
                                MaterialShapes.getOval,
                                MaterialShapes.getPill,
                                MaterialShapes.getTriangle,
                                MaterialShapes.getDiamond,
                                MaterialShapes.getClamShell,
                                MaterialShapes.getPentagon,
                                MaterialShapes.getGem,
                                MaterialShapes.getSunny,
                                MaterialShapes.getVerySunny,
                                MaterialShapes.getCookie4Sided,
                                MaterialShapes.getCookie6Sided,
                                MaterialShapes.getCookie7Sided,
                                MaterialShapes.getCookie9Sided,
                                MaterialShapes.getCookie12Sided,
                                MaterialShapes.getGhostish,
                                MaterialShapes.getClover4Leaf,
                                MaterialShapes.getClover8Leaf,
                                MaterialShapes.getBurst,
                                MaterialShapes.getSoftBurst,
                                MaterialShapes.getBoom,
                                MaterialShapes.getSoftBoom,
                                MaterialShapes.getFlower,
                                MaterialShapes.getPuffy,
                                MaterialShapes.getPuffyDiamond,
                                MaterialShapes.getPixelCircle,
                                MaterialShapes.getPixelTriangle,
                                MaterialShapes.getBun,
                                MaterialShapes.getHeart
                            ]

                            Timer {
                                interval: 650
                                repeat: true
                                running: root.busy && sendGlyphWrap.animOk
                                onTriggered: sendGlyphWrap.busyShapeIndex =
                                    (sendGlyphWrap.busyShapeIndex + 1) % sendGlyphWrap.busyShapeGetters.length
                            }

                            Connections {
                                target: root
                                function onBusyChanged() {
                                    // Reset to a deterministic start when entering/leaving busy.
                                    sendGlyphWrap.busyShapeIndex = 0;
                                }
                            }

                            // Idle: arrow shape. Busy: hidden in favour of stop icon below.
                            RoundedPoly.ShapeCanvas {
                                id: sendGlyph
                                anchors.fill: parent
                                anchors.margins: 10
                                polygonIsNormalized: true
                                visible: !root.busy

                                color: Common.Config.color.on_primary
                                borderWidth: 0
                                borderColor: Qt.alpha(Common.Config.color.on_surface, 0.0)

                                roundedPolygon: MaterialShapes.getArrow()

                                Component.onCompleted: requestPaint()
                            }

                            // Stop icon shown while a stream is in progress.
                            Text {
                                anchors.centerIn: parent
                                visible: root.busy
                                text: "\uf04d"
                                font.family: Common.Config.iconFontFamily
                                font.pixelSize: 18
                                color: sendButtonArea.containsMouse
                                    ? Common.Config.color.on_error
                                    : Common.Config.color.error

                                Behavior on color {
                                    ColorAnimation { duration: 120 }
                                }
                            }
                        }
                    }

                    HybridRipple {
                        anchors.fill: parent
                        color: Common.Config.color.on_primary
                        pressX: sendButtonArea.pressX
                        pressY: sendButtonArea.pressY
                        pressed: sendButtonArea.pressed
                        radius: parent.radius
                        stateOpacity: 0
                    }
                    MouseArea {
                        id: sendButtonArea
                        property real pressX: width / 2
                        property real pressY: height / 2
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        enabled: true
                        onClicked: {
                            if (root.busy) {
                                if (root.chatSession && root.chatSession.cancel)
                                    root.chatSession.cancel();
                            } else {
                                root.handleSend();
                            }
                        }
                        onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
                    }
                }
            }
        }
        } // inputWrapper
    } // composerContainer
    } // extra closing for composerContainer Item outer wrapper

    FontMetrics {
        id: inputMetrics

        font.family: Common.Config.fontFamily
        font.pixelSize: Common.Config.type.bodyMedium.size + 1
    }
}
