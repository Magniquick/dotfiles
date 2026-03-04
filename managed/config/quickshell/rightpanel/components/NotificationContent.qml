import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import "../../common/materialkit" as MK
import "../../common" as Common
import "../../common/components" as CommonComponents

RowLayout {
    id: root
    property var entry
    property bool showCloseButton: false
    property bool showSourceButton: false
    property bool showSourceDetails: false
    property bool showBodyLeadIcon: true
    // Popup auto-dismiss ring around the close button.
    property bool autoDismissRingVisible: false
    property real autoDismissProgress: 0.0
    property bool autoDismissPaused: false
    // Popup notifications should stay compact. When bodyMaxLines > 0 and
    // bodyExpandable is true, the body is clamped with ellipsis and can be
    // expanded (e.g. on hover) by increasing maximumLineCount.
    property int bodyMaxLines: 0
    property bool bodyExpandable: false
    property bool showBodyChevron: false
    property bool bodyExpanded: false
    // If enabled, callers can expand the body on hover by setting bodyHoverActive.
    // Expanded previews are still capped for UI stability.
    property bool bodyExpandOnHover: false
    property bool bodyHoverActive: false
    property int bodyHoverMaxLines: 15
    // Inserts soft hyphens into long "word" tokens so line wrapping can show a
    // hyphen when breaking. Kept optional because it can interact badly with
    // rich text; we only apply it to plain segments (and allow <br>).
    property bool bodyHyphenate: false
    signal closeClicked

    readonly property string rawBody: entry && entry.body ? entry.body : ""
    readonly property var processedContent: preprocessNotification(entry, rawBody, appNameText, summaryText)
    readonly property bool isWhatsApp: processedContent.isWhatsApp
    readonly property string headerIconText: processedContent.headerIconText
    readonly property color headerIconColor: processedContent.headerIconColor
    readonly property string sourceText: buildSourceText(entry)
    readonly property string cleanBody: processedContent.cleanBody
    readonly property string displayBody: {
        const s = root.cleanBody || "";
        if (!root.bodyHyphenate || s.length === 0)
            return s;
        return hyphenateStyledTextAllowBr(s);
    }
    readonly property string titleText: {
        if (!entry || entry.title === undefined || entry.title === null)
            return "";
        if (typeof entry.title === "string")
            return entry.title.trim();
        return String(entry.title).trim();
    }
    readonly property bool hasTitle: titleText.length > 0
    readonly property string appNameText: entry && entry.appName ? entry.appName.trim() : ""
    readonly property string summaryText: entry && entry.summary ? entry.summary.trim() : ""
    readonly property string headerText: root.hasTitle ? root.titleText : (root.summaryText.length > 0 ? root.summaryText : root.appNameText)
    readonly property string detailSummaryText: root.hasTitle ? root.summaryText : ""
    readonly property bool isBatWatch: (appNameText || "").toLowerCase() === "batwatch"
    readonly property string imageSource: root.isBatWatch ? "" : (entry && entry.notification && entry.notification.image ? entry.notification.image : "")
    readonly property string resolvedImageSource: {
        if (root.imageSource.startsWith("image://icon/"))
            return Quickshell.iconPath(root.imageSource.substring(13), true);
        return root.imageSource;
    }
    property bool imageFileExists: true
    readonly property bool inListViewport: {
        const view = ListView.view;
        if (!view)
            return true;

        // Delegate y is in ListView content coordinates.
        const top = root.y;
        const bottom = root.y + root.height;
        const buffer = 64;
        return bottom >= view.contentY - buffer && top <= view.contentY + view.height + buffer;
    }

    readonly property bool bodyOverflows: root.bodyMaxLines > 0
        && root.cleanBody.length > 0
        && bodyMeasure.lineCount > root.bodyMaxLines

    readonly property int _collapsedBodyLines: root.bodyMaxLines
    readonly property int _expandedBodyLines: Math.min(15, Math.max(root.bodyMaxLines, root.bodyHoverMaxLines))
    readonly property bool _hoverExpandActive: root.bodyExpandOnHover && root.bodyHoverActive
    readonly property bool _manualExpandActive: root.bodyExpandable && root.bodyExpanded
    readonly property bool hasDefaultAction: (root.entry?.notification?.actions ?? []).some(
        action => (action && action.identifier ? String(action.identifier) : "") === "default"
    )

    onImageSourceChanged: checkImageExistence()
    Component.onCompleted: checkImageExistence()

    function checkImageExistence() {
        if (root.imageSource.length === 0) {
            root.imageFileExists = false;
            return;
        }

        let path = root.imageSource;
        if (path.startsWith("image://icon/")) {
            path = path.substring(13);
        } else if (path.startsWith("file://")) {
            path = path.substring(7);
        }

        // If it looks like an absolute path, check it.
        if (path.startsWith("/")) {
             fileCheckProcess.pathToCheck = path;
             fileCheckProcess.running = false;
             fileCheckProcess.running = true;
        } else {
            // Named icon or other resource, assume valid
            root.imageFileExists = true;
        }
    }

    Process {
        id: fileCheckProcess
        property string pathToCheck: ""
        command: ["test", "-f", pathToCheck]
        // qmllint disable signal-handler-parameters
        onExited: (code) => {
            root.imageFileExists = (code === 0);
        }
        // qmllint enable signal-handler-parameters
    }

    readonly property color urgencyColor: {
        if (!entry || !entry.urgency)
            return Common.Config.color.primary;
        if (entry.urgency === "critical")
            return Common.Config.color.error;
        if (entry.urgency === "low")
            return Common.Config.color.secondary;
        return Common.Config.color.primary;
    }

    spacing: 8

    function resolveActionIcon(identifier) {
        if (!entry || !entry.notification || !entry.notification.hasActionIcons)
            return "";
        if (!identifier || identifier.length === 0)
            return "";
        if (identifier.startsWith("/") || identifier.startsWith("file:"))
            return identifier;
        return Quickshell.iconPath(identifier, true);
    }

    function actionDisplayText(action) {
        const text = action && action.text ? action.text.trim() : "";
        return text.length > 0 ? text : "Activate";
    }

    function preprocessNotification(currentEntry, bodyText, appName, summary) {
        const summaryLower = (summary || "").toLowerCase();
        const result = {
            isWhatsApp: false,
            cleanBody: bodyText || "",
            headerIconText: "\ueb05",
            headerIconColor: Common.Config.color.on_primary_container
        };
        if (!currentEntry)
            return result;
        if ((appName || "").toLowerCase() === "batwatch") {
            // https://github.com/Magniquick/batmon
            result.headerIconText = "\udb82\udf5f";
        } else if ((appName || "").toLowerCase() === "openai-codex" || summaryLower === "claude code") {
            result.headerIconText = "\uec1e";
        } else if ((appName || "").toLowerCase() === "kitty") {
            result.headerIconText = "\uf489";
        }
        if (result.cleanBody.match(/<a\s+href="[^"]*web\.whatsapp\.com[^"]*">/i) !== null) {
            result.isWhatsApp = true;
            result.headerIconText = "\udb81\udda3";
            result.headerIconColor = "#25D366"; // Official WhatsApp brand color
            result.cleanBody = result.cleanBody.replace(/^<a\s+href="[^"]*">[^<]*<\/a>\n*/i, "");
        }
        result.cleanBody = result.cleanBody.trim().replace(/\n/g, "<br>");
        return result;
    }

    function insertSoftHyphensPlain(text) {
        // Insert a soft hyphen (\u00ad) every N characters in long alnum tokens.
        // Soft hyphen is only rendered when a line break happens there.
        const SOFT_HYPHEN = "\u00ad";
        const N = 12;
        const MIN_LEN = 18;
        return String(text).split(/(\s+)/).map(part => {
            // Keep whitespace as-is
            if (part.match(/^\s+$/))
                return part;
            // Only touch "word-like" tokens; avoid mangling punctuation-heavy strings.
            if (!part.match(/^[A-Za-z0-9]+$/) || part.length < MIN_LEN)
                return part;
            return part.replace(new RegExp("([A-Za-z0-9]{" + N + "})(?=[A-Za-z0-9])", "g"), "$1" + SOFT_HYPHEN);
        }).join("");
    }

    function hyphenateStyledTextAllowBr(styledText) {
        // We always emit <br> from preprocessNotification; treat that as a safe
        // separator. If other tags are present in a segment, skip that segment.
        const parts = String(styledText).split(/<br\s*\/?>/i);
        if (parts.length === 1) {
            return styledText.indexOf("<") === -1 ? insertSoftHyphensPlain(styledText) : styledText;
        }
        return parts.map(p => (p.indexOf("<") === -1 ? insertSoftHyphensPlain(p) : p)).join("<br>");
    }

    function stringifyValue(value) {
        if (value === undefined || value === null)
            return "";
        if (typeof value === "string")
            return value;
        try {
            return JSON.stringify(value, null, 2);
        } catch (error) {
            return String(value);
        }
    }

    function buildSourceText(currentEntry) {
        if (!currentEntry)
            return "";
        const notification = currentEntry.notification || {};
        const lines = [];
        lines.push("appName: " + (currentEntry.appName || ""));
        lines.push("summary: " + (currentEntry.summary || ""));
        lines.push("title: " + stringifyValue(currentEntry.title));
        lines.push("body: " + (currentEntry.body || ""));
        lines.push("urgency: " + (currentEntry.urgency || ""));
        lines.push("appIcon: " + (notification.appIcon || ""));
        lines.push("image: " + (notification.image || ""));

        if (notification.expireTimeout !== undefined)
            lines.push("expireTimeout: " + notification.expireTimeout);
        if (notification.hints)
            lines.push("hints: " + stringifyValue(notification.hints));
        if (notification.actions && notification.actions.length > 0) {
            const actionsText = notification.actions.map(action => {
                const identifier = action && action.identifier ? action.identifier : "";
                return "- " + actionDisplayText(action) + (identifier ? " (" + identifier + ")" : "");
            }).join("\n");
            lines.push("actions:\n" + actionsText);
        }
        return lines.join("\n");
    }

    onEntryChanged: {
        showSourceDetails = false;
        bodyExpanded = false;
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: root.headerIconText
                color: root.headerIconColor
                font.family: Common.Config.iconFontFamily
                font.pointSize: 12
                Layout.alignment: Qt.AlignBaseline
            }

            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignBaseline
                text: root.headerText
                color: Common.Config.color.on_surface
                font.family: "Kyok"
                font.weight: Font.Medium
                font.pointSize: 12
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                visible: root.headerText.length > 0
            }

            Item {
                Layout.preferredWidth: headerActions.implicitWidth
                Layout.preferredHeight: headerActions.implicitHeight
                Layout.alignment: Qt.AlignTop

                Row {
                    id: headerActions
                    spacing: 8

                    Rectangle {
                        id: leadingIcon
                        width: 32
                        height: 32
                        radius: width / 2
                        color: "transparent"
                        visible: root.imageSource.length > 0 && leadingIconImage.status !== Image.Error && root.imageFileExists

                        Image {
                            id: leadingIconImage
                            anchors.fill: parent
                            source: root.resolvedImageSource
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: false
                        }

                        Rectangle {
                            id: leadingIconMask
                            anchors.fill: parent
                            radius: width / 2
                            visible: false
                        }

                        Loader {
                            anchors.fill: parent
                            active: leadingIcon.visible
                                && root.inListViewport
                                && leadingIconImage.status === Image.Ready
                            sourceComponent: OpacityMask {
                                anchors.fill: parent
                                cached: true
                                source: leadingIconImage
                                maskSource: leadingIconMask
                            }
                        }
                    }

                    Rectangle {
                        implicitWidth: 24
                        implicitHeight: 24
                        radius: 12
                        color: "transparent"
                        visible: root.showBodyChevron
                            && root.bodyOverflows
                            && !root.showSourceDetails
                            && root.bodyMaxLines > 0
                            && root.bodyExpandable

                        Text {
                            anchors.centerIn: parent
                            text: root.bodyExpanded ? "\uf077" : "\uf078"
                            color: chevronArea.containsMouse ? Common.Config.color.primary : Common.Config.color.on_surface
                            font.family: Common.Config.iconFontFamily
                            font.pointSize: 9
                            font.weight: Font.Bold
                            opacity: 0.95

                            Behavior on color {
                                ColorAnimation {
                                    duration: Common.Config.motion.duration.shortMs
                                    easing.type: Common.Config.motion.easing.standard
                                }
                            }
                        }

                        MK.HybridRipple {
                            anchors.fill: parent
                            color: Common.Config.color.on_surface
                            pressX: chevronArea.pressX
                            pressY: chevronArea.pressY
                            pressed: chevronArea.pressed
                            radius: parent.radius
                            stateOpacity: chevronArea.containsMouse ? Common.Config.state.hoverOpacity : 0
                        }
                        MouseArea {
                            id: chevronArea
                            property real pressX: width / 2
                            property real pressY: height / 2
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.bodyExpanded = !root.bodyExpanded
                            onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
                        }
                    }

                    Rectangle {
                        implicitWidth: 24
                        implicitHeight: 24
                        radius: 12
                        color: "transparent"
                        visible: root.showCloseButton

                        // Simple built-in ring. Note: its arc radius is hardcoded
                        // internally, so we size it with arcRadius.
                        MK.CircleProgressShape {
                            anchors.centerIn: parent
                            width: parent.width
                            height: parent.height
                            // Button is 24x24; keep the ring tucked in.
                            arcRadius: Math.max(0, (height / 2) - 3)
                            progress: root.autoDismissProgress
                            strokeWidth: 2
                            visible: root.autoDismissRingVisible
                            opacity: root.autoDismissPaused ? 0.45 : 0.85
                        }

                        Text {
                            anchors.fill: parent
                            text: "\uf00d"
                            color: closeArea.containsMouse ? Common.Config.color.primary : Common.Config.color.on_surface
                            font.family: Common.Config.iconFontFamily
                            font.pointSize: 11
                            font.weight: Font.Bold
                            opacity: 0.95
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter

                            Behavior on color {
                                ColorAnimation {
                                    duration: Common.Config.motion.duration.shortMs
                                    easing.type: Common.Config.motion.easing.standard
                                }
                            }
                        }

                        MK.HybridRipple {
                            anchors.fill: parent
                            color: Common.Config.color.on_surface
                            pressX: closeArea.pressX
                            pressY: closeArea.pressY
                            pressed: closeArea.pressed
                            radius: parent.radius
                            stateOpacity: closeArea.containsMouse ? Common.Config.state.hoverOpacity : 0
                        }
                        MouseArea {
                            id: closeArea
                            property real pressX: width / 2
                            property real pressY: height / 2
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.closeClicked()
                            onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
                        }
                    }

                    Rectangle {
                        implicitWidth: 24
                        implicitHeight: 24
                        radius: 12
                        color: "transparent"
                        visible: root.showSourceButton

                        Text {
                            anchors.centerIn: parent
                            text: "\uf121"
                            color: sourceArea.containsMouse ? Common.Config.color.on_surface : Common.Config.color.surface_container_highest
                            font.family: Common.Config.iconFontFamily
                            font.pointSize: 11

                            Behavior on color {
                                ColorAnimation {
                                    duration: Common.Config.motion.duration.shortMs
                                    easing.type: Common.Config.motion.easing.standard
                                }
                            }
                        }

                        MK.HybridRipple {
                            anchors.fill: parent
                            color: Common.Config.color.on_surface
                            pressX: sourceArea.pressX
                            pressY: sourceArea.pressY
                            pressed: sourceArea.pressed
                            radius: parent.radius
                            stateOpacity: sourceArea.containsMouse ? Common.Config.state.hoverOpacity : 0
                        }
                        MouseArea {
                            id: sourceArea
                            property real pressX: width / 2
                            property real pressY: height / 2
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showSourceDetails = !root.showSourceDetails
                            onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            visible: root.showSourceButton && root.showSourceDetails && root.sourceText.length > 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: sourceEdit.contentHeight + (Common.Config.space.sm * 2)
                color: Qt.alpha(Common.Config.color.on_surface, 0.03)
                radius: Common.Config.shape.corner.sm
                border.width: 1
                border.color: Common.Config.color.outline_variant

                TextEdit {
                    id: sourceEdit
                    anchors.fill: parent
                    anchors.margins: Common.Config.space.sm
                    text: root.sourceText
                    textFormat: TextEdit.PlainText
                    color: Common.Config.color.on_surface
                    wrapMode: TextEdit.Wrap
                    font.family: "JetBrainsMono NFP"
                    font.pointSize: 11
                    readOnly: true
                    selectByMouse: true
                    cursorVisible: true
                    activeFocusOnPress: true
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: (root.detailSummaryText.length > 0 || root.cleanBody.length > 0) && !root.showSourceDetails

            Item {
                visible: root.showBodyLeadIcon
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
                Layout.alignment: Qt.AlignTop

                Text {
                    anchors.centerIn: parent
                    text: root.hasDefaultAction ? "󰁜" : "\uea9c"
                    color: Common.Config.color.primary_fixed_dim
                    font.family: Common.Config.iconFontFamily
                    font.pointSize: 12
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBaseline
                    text: root.detailSummaryText
                    textFormat: Text.PlainText
                    color: Common.Config.color.on_surface
                    font.family: "Kyok"
                    font.weight: Font.Medium
                    font.pointSize: 12
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    visible: root.detailSummaryText.length > 0
                }

                CommonComponents.LinkText {
                    id: bodyText
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBaseline
                    text: root.displayBody
                    textFormat: Text.StyledText
                    maximumLineCount: (root.bodyMaxLines > 0 && root.bodyExpandable)
                        ? ((root._hoverExpandActive || root._manualExpandActive) ? root._expandedBodyLines : root._collapsedBodyLines)
                        : 0
                    elide: (root.bodyMaxLines > 0 && root.bodyExpandable && !root._hoverExpandActive && !root._manualExpandActive)
                        ? Text.ElideRight
                        : Text.ElideNone
                    clip: (root.bodyMaxLines > 0 && root.bodyExpandable && !root._hoverExpandActive && !root._manualExpandActive)
                    color: Common.Config.color.on_surface
                    font.family: "Kyok"
                    font.weight: Font.Medium
                    font.pointSize: 12
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    visible: root.cleanBody.length > 0
                }

                // Hidden measurement text used to decide whether we should show the
                // expand chevron. Must match bodyText styling and width.
                Text {
                    id: bodyMeasure
                    visible: false
                    width: bodyText.width
                    text: root.displayBody
                    textFormat: Text.StyledText
                    color: "transparent"
                    font.family: bodyText.font.family
                    font.weight: bodyText.font.weight
                    font.pointSize: bodyText.font.pointSize
                    wrapMode: bodyText.wrapMode
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8
            visible: actionsRepeater.count > 0 && !root.showSourceDetails

            Repeater {
                id: actionsRepeater
                model: (root.entry?.notification?.actions ?? []).filter(
                    action => (action && action.identifier ? String(action.identifier) : "") !== "default"
                )

                Item {
                    id: actionWrapper
                    required property var modelData
                    required property int index
                    Layout.preferredHeight: 32
                    Layout.preferredWidth: actionContent.implicitWidth + 32

                    Rectangle {
                        id: actionButton
                        anchors.fill: parent
                        radius: 16
                        color: Qt.alpha(Common.Config.color.surface_container_high, 0.6)
                        border.width: 1
                        border.color: actionArea.containsMouse ? Qt.alpha(Common.Config.color.primary, 0.5) : Qt.alpha(Common.Config.color.outline_variant, 0.3)
                        scale: actionArea.pressed ? 0.96 : 1.0

                        Behavior on color {
                            ColorAnimation {
                                duration: Common.Config.motion.duration.shortMs
                                easing.type: Common.Config.motion.easing.standard
                            }
                        }

                        Behavior on border.color {
                            ColorAnimation {
                                duration: Common.Config.motion.duration.shortMs
                                easing.type: Common.Config.motion.easing.standard
                            }
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: Common.Config.motion.duration.shortMs
                                easing.type: Common.Config.motion.easing.standard
                            }
                        }

                        Row {
                            id: actionContent
                            anchors.centerIn: parent
                            spacing: 6

                            Image {
                                id: actionIcon
                                source: root.resolveActionIcon(actionWrapper.modelData?.identifier ?? "")
                                width: 12
                                height: 12
                                fillMode: Image.PreserveAspectFit
                                visible: source.length > 0
                            }

                            Text {
                                id: actionText
                                text: root.actionDisplayText(actionWrapper.modelData)
                                color: actionArea.containsMouse ? Common.Config.color.primary : Common.Config.color.on_surface_variant
                                font.family: "Kyok"
                                font.weight: Font.Medium
                                font.pointSize: 9

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Common.Config.motion.duration.shortMs
                                        easing.type: Common.Config.motion.easing.standard
                                    }
                                }
                            }
                        }

                        MK.HybridRipple {
                            anchors.fill: parent
                            color: Common.Config.color.on_surface
                            pressX: actionArea.pressX
                            pressY: actionArea.pressY
                            pressed: actionArea.pressed
                            radius: parent.radius
                            stateOpacity: actionArea.containsMouse ? Common.Config.state.hoverOpacity : 0
                        }
                        MouseArea {
                            id: actionArea
                            property real pressX: width / 2
                            property real pressY: height / 2
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: actionWrapper.modelData?.invoke()
                            onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8
            visible: (entry?.notification?.hasInlineReply ?? false) && !root.showSourceDetails

            Text {
                text: "\uf4ad"
                color: Common.Config.color.surface_container_high
                font.family: Common.Config.iconFontFamily
                font.pointSize: 12
                Layout.alignment: Qt.AlignBaseline
            }

            MK.TextField {
                id: inlineReplyField
                Layout.fillWidth: true
                placeholderText: entry && entry.notification && entry.notification.inlineReplyPlaceholder ? entry.notification.inlineReplyPlaceholder : "Reply"
                font.family: "Kyok"
                font.pixelSize: 14
            }

            Rectangle {
                implicitWidth: 28
                implicitHeight: 28
                radius: 14
                color: Qt.alpha(Common.Config.color.surface_container_high, 0.6)
                border.width: 1
                border.color: replyArea.containsMouse ? Qt.alpha(Common.Config.color.primary, 0.5) : Qt.alpha(Common.Config.color.outline_variant, 0.3)

                Text {
                    anchors.centerIn: parent
                    text: "\uf1d8"
                    color: replyArea.containsMouse ? Common.Config.color.primary : Common.Config.color.on_surface_variant
                    font.family: Common.Config.iconFontFamily
                    font.pointSize: 10
                }

                MK.HybridRipple {
                    anchors.fill: parent
                    color: Common.Config.color.on_surface
                    pressX: replyArea.pressX
                    pressY: replyArea.pressY
                    pressed: replyArea.pressed
                    radius: parent.radius
                    stateOpacity: replyArea.containsMouse ? Common.Config.state.hoverOpacity : 0
                }
                MouseArea {
                    id: replyArea
                    property real pressX: width / 2
                    property real pressY: height / 2
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const replyText = inlineReplyField.text.trim();
                        if (!entry || !entry.notification || replyText.length === 0)
                            return;
                        entry.notification.sendInlineReply(replyText);
                        inlineReplyField.text = "";
                    }
                    onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
                }
            }
        }
    }
}
