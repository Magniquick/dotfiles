import QtQuick
import Qcm.Material as MD
import "../../common" as Common

Item {
    id: root
    property var entry
    signal dismissRequested

    property real dismissProgress: 0.0
    property int dismissTotalMs: 0
    readonly property bool autoDismissEnabled: root.entry && root.entry.timer && root.entry.timer.interval > 0
    property bool autoDismissPaused: false

    width: 320
    implicitHeight: frame.implicitHeight
    // ListView positions delegates using `height`; bind it so late implicitHeight
    // changes (e.g. async image checks / text wrap) trigger relayout instead of
    // overlapping the previous item.
    height: implicitHeight

    // Simple slide-in from the left on creation. Keep it transform-based so it
    // doesn't affect layout or stacking.
    property bool _entered: false
    // Right panel is anchored on the right; slide in from the right edge.
    property real _enterOffsetX: {
        if (root.entry && root.entry.popupExiting)
            return width + (2 * Common.Config.space.sm);
        return _entered ? 0 : (width + (2 * Common.Config.space.sm));
    }

    transform: Translate {
        x: root._enterOffsetX
    }

    Behavior on _enterOffsetX {
        NumberAnimation {
            duration: Common.Config.motion.duration.longMs
            easing.type: Common.Config.motion.easing.standard
        }
    }

    Component.onCompleted: {
        root._entered = true;
        resetAutoDismiss();
    }

    HoverHandler {
        id: cardHover

        onHoveredChanged: {
            if (cardHover.hovered)
                root.pauseAutoDismiss();
            else
                root.resumeAutoDismiss();
        }
    }

    function resetAutoDismiss() {
        progressAnim.stop();
        dismissProgress = 0.0;
        dismissTotalMs = autoDismissEnabled ? root.entry.timer.interval : 0;
        autoDismissPaused = false;

        if (!autoDismissEnabled)
            return;

        if (cardHover.hovered) {
            autoDismissPaused = true;
            root.entry.timer.stop();
            return;
        }

        progressAnim.duration = dismissTotalMs;
        progressAnim.from = 0;
        progressAnim.to = 1;
        progressAnim.start();
    }

    function pauseAutoDismiss() {
        if (!autoDismissEnabled)
            return;
        if (autoDismissPaused)
            return;
        autoDismissPaused = true;
        root.entry.timer.stop();
        progressAnim.stop();
    }

    function resumeAutoDismiss() {
        if (!autoDismissEnabled)
            return;
        if (!autoDismissPaused)
            return;
        autoDismissPaused = false;

        const remainingMs = (1 - dismissProgress) * dismissTotalMs;
        if (remainingMs <= 0) {
            // Let the existing timeout path remove the popup.
            root.entry.timer.interval = 1;
            root.entry.timer.restart();
            dismissProgress = 1.0;
            return;
        }

        root.entry.timer.interval = remainingMs;
        root.entry.timer.restart();

        progressAnim.duration = remainingMs;
        progressAnim.from = dismissProgress;
        progressAnim.to = 1;
        progressAnim.start();
    }

    NumberAnimation {
        id: progressAnim
        target: root
        property: "dismissProgress"
        easing.type: Easing.Linear
        running: false
    }

    Connections {
        target: root.entry
        function onTimerChanged() {
            root.resetAutoDismiss();
        }
    }

    onEntryChanged: resetAutoDismiss()

    function activatePopup() {
        const notification = root.entry ? root.entry.notification : null;
        const actions = notification && notification.actions ? notification.actions : [];
        let invoked = false;

        for (let i = 0; i < actions.length; i++) {
            const action = actions[i];
            const identifier = action && action.identifier ? String(action.identifier) : "";
            if (identifier === "default" && typeof action.invoke === "function") {
                action.invoke();
                invoked = true;
                break;
            }
        }

        // Match common notification UX: activate first, then close popup.
        // If no default action exists, this still dismisses as a fallback.
        root.dismissRequested();
        return invoked;
    }

    NotificationFrame {
        id: frame
        anchors {
            left: parent.left
            right: parent.right
        }
        // Popups sit on an overlay layer; the drop shadow makes the container
        // edge harder to read against busy backgrounds.
        elevation: MD.Token.elevation.level0
        frameBorderWidth: 1
        frameBorderColor: Qt.alpha(Common.Config.color.outline, 0.42)
        onClicked: root.activatePopup()

        NotificationContent {
            id: content
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            entry: root.entry
            showCloseButton: true
            autoDismissRingVisible: autoDismissEnabled
            autoDismissProgress: root.dismissProgress
            autoDismissPaused: root.autoDismissPaused
            bodyMaxLines: 3
            bodyExpandable: true
            bodyExpandOnHover: true
            bodyHoverActive: cardHover.hovered
            bodyHoverMaxLines: 15
            bodyHyphenate: true
            onCloseClicked: root.dismissRequested()
        }
    }
}
