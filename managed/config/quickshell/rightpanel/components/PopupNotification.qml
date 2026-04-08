import QtQuick
import "../../common" as Common

Item {
    id: root
    property var entry
    signal dismissRequested

    property real dismissProgress: 0.0
    property int dismissTotalMs: 0
    readonly property bool autoDismissEnabled: root.entry && root.entry.timer && root.entry.timer.interval > 0
    property bool autoDismissPaused: false
    property double dismissElapsedMs: 0
    property double dismissStartedAtMs: 0
    property real dismissAnimationFrom: 0.0
    property int dismissAnimationDurationMs: 0
    property int dismissAnimationKey: 0

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
        dismissProgress = 0.0;
        dismissTotalMs = autoDismissEnabled ? root.entry.timer.interval : 0;
        autoDismissPaused = false;
        dismissElapsedMs = 0;
        dismissStartedAtMs = 0;
        dismissAnimationFrom = 0.0;
        dismissAnimationDurationMs = 0;
        dismissAnimationKey++;

        if (!autoDismissEnabled)
            return;

        if (cardHover.hovered) {
            autoDismissPaused = true;
            root.entry.timer.stop();
            return;
        }

        root.startAutoDismissVisual(dismissTotalMs, 0.0);
    }

    function pauseAutoDismiss() {
        if (!autoDismissEnabled)
            return;
        if (autoDismissPaused)
            return;
        autoDismissPaused = true;
        root.captureElapsedProgress();
        root.entry.timer.stop();
        dismissAnimationDurationMs = 0;
        dismissAnimationKey++;
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
        root.startAutoDismissVisual(remainingMs, dismissProgress);
    }

    function captureElapsedProgress() {
        if (dismissTotalMs <= 0)
            return;

        if (dismissStartedAtMs > 0)
            dismissElapsedMs += Math.max(0, Date.now() - dismissStartedAtMs);

        dismissElapsedMs = Math.max(0, Math.min(dismissTotalMs, dismissElapsedMs));
        dismissStartedAtMs = 0;
        dismissProgress = dismissTotalMs > 0 ? (dismissElapsedMs / dismissTotalMs) : dismissProgress;
    }

    function startAutoDismissVisual(durationMs, fromProgress) {
        dismissAnimationDurationMs = Math.max(0, Math.round(Number(durationMs) || 0));
        dismissAnimationFrom = Math.max(0, Math.min(1, Number(fromProgress) || 0));
        dismissProgress = dismissAnimationFrom;
        dismissStartedAtMs = Date.now();

        if (dismissAnimationDurationMs <= 0 || dismissAnimationFrom >= 1.0)
            return;

        dismissAnimationKey++;
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
        elevation: 0
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
            autoDismissRingVisible: root.autoDismissEnabled
            autoDismissProgress: root.dismissProgress
            autoDismissAnimating: root.autoDismissEnabled && !root.autoDismissPaused && root.dismissAnimationDurationMs > 0
            autoDismissAnimationFrom: root.dismissAnimationFrom
            autoDismissAnimationDurationMs: root.dismissAnimationDurationMs
            autoDismissAnimationKey: root.dismissAnimationKey
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
