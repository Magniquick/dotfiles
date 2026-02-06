import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import "../../common" as Common

RowLayout {
    id: root
    property var entry
    property bool showCloseButton: false
    property bool showSourceButton: false
    property bool showSourceDetails: false
    property bool showBodyLeadIcon: true
    signal closeClicked

    readonly property string rawBody: entry && entry.body ? entry.body : ""
    readonly property var processedContent: preprocessNotification(entry, rawBody, appNameText)
    readonly property bool isWhatsApp: processedContent.isWhatsApp
    readonly property string headerIconText: processedContent.headerIconText
    readonly property color headerIconColor: processedContent.headerIconColor
    readonly property string sourceText: buildSourceText(entry)
    readonly property string cleanBody: processedContent.cleanBody
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

    function preprocessNotification(currentEntry, bodyText, appName) {
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
        } else if ((appName || "").toLowerCase() === "openai-codex") {
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

    onEntryChanged: showSourceDetails = false

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
                            source: root.imageSource
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
                        color: closeArea.containsMouse ? Qt.alpha(Common.Config.color.surface_variant, 0.25) : "transparent"
                        visible: root.showCloseButton

                        Behavior on color {
                            ColorAnimation {
                                duration: Common.Config.motion.duration.shortMs
                                easing.type: Common.Config.motion.easing.standard
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "\uf00d"
                            color: closeArea.containsMouse ? Common.Config.color.on_surface : Common.Config.color.surface_container_highest
                            font.family: Common.Config.iconFontFamily
                            font.pixelSize: 11

                            Behavior on color {
                                ColorAnimation {
                                    duration: Common.Config.motion.duration.shortMs
                                    easing.type: Common.Config.motion.easing.standard
                                }
                            }
                        }

                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.closeClicked()
                        }
                    }

                    Rectangle {
                        implicitWidth: 24
                        implicitHeight: 24
                        radius: 12
                        color: sourceArea.containsMouse ? Qt.alpha(Common.Config.color.surface_variant, 0.25) : "transparent"
                        visible: root.showSourceButton

                        Behavior on color {
                            ColorAnimation {
                                duration: Common.Config.motion.duration.shortMs
                                easing.type: Common.Config.motion.easing.standard
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "\uf121"
                            color: sourceArea.containsMouse ? Common.Config.color.on_surface : Common.Config.color.surface_container_highest
                            font.family: Common.Config.iconFontFamily
                            font.pixelSize: 11

                            Behavior on color {
                                ColorAnimation {
                                    duration: Common.Config.motion.duration.shortMs
                                    easing.type: Common.Config.motion.easing.standard
                                }
                            }
                        }

                        MouseArea {
                            id: sourceArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showSourceDetails = !root.showSourceDetails
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
                    font.pixelSize: 11
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

            Text {
                visible: root.showBodyLeadIcon
                text: "\uea9c"
                color: Common.Config.color.primary_fixed_dim
                font.family: Common.Config.iconFontFamily
                font.pointSize: 12
                Layout.alignment: Qt.AlignTop
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

                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBaseline
                    text: root.cleanBody
                    textFormat: Text.StyledText
                    color: Common.Config.color.on_surface
                    font.family: "Kyok"
                    font.weight: Font.Medium
                    font.pointSize: 12
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    visible: root.cleanBody.length > 0
                    onLinkActivated: link => Qt.openUrlExternally(link)
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
                model: root.entry?.notification?.actions ?? []

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
                        color: actionArea.pressed ? Qt.alpha(Common.Config.color.primary, 0.25) : actionArea.containsMouse ? Qt.alpha(Common.Config.color.surface_container_highest, 0.8) : Qt.alpha(Common.Config.color.surface_container_high, 0.6)
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

                        MouseArea {
                            id: actionArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: actionWrapper.modelData?.invoke()
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

            TextField {
                id: inlineReplyField
                Layout.fillWidth: true
                placeholderText: entry && entry.notification && entry.notification.inlineReplyPlaceholder ? entry.notification.inlineReplyPlaceholder : "Reply"
                font.family: "Kyok"
                font.pointSize: 10
            }

            Rectangle {
                implicitWidth: 28
                implicitHeight: 28
                radius: 14
                color: replyArea.pressed ? Qt.alpha(Common.Config.color.primary, 0.25) : replyArea.containsMouse ? Qt.alpha(Common.Config.color.surface_container_highest, 0.8) : Qt.alpha(Common.Config.color.surface_container_high, 0.6)
                border.width: 1
                border.color: replyArea.containsMouse ? Qt.alpha(Common.Config.color.primary, 0.5) : Qt.alpha(Common.Config.color.outline_variant, 0.3)

                Text {
                    anchors.centerIn: parent
                    text: "\uf1d8"
                    color: replyArea.containsMouse ? Common.Config.color.primary : Common.Config.color.on_surface_variant
                    font.family: Common.Config.iconFontFamily
                    font.pixelSize: 10
                }

                MouseArea {
                    id: replyArea
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
                }
            }
        }
    }
}
