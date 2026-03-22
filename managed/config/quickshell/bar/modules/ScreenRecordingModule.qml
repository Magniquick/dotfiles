pragma ComponentBehavior: Bound
import ".."
import "../components"
import QtQuick

ModuleContainer {
    id: root

    function audioModeLabel() {
        if (GlobalState.screenRecordingAudioMode === "monitor")
            return "Monitor";
        if (GlobalState.screenRecordingAudioMode === "defaultMic")
            return "Mic";
        return "Off";
    }
    function tooltipBody() {
        const parts = [
            "State: " + GlobalState.screenRecordingState,
            "Audio: " + root.audioModeLabel()
        ];

        if (GlobalState.screenRecordingAudioDevice !== "")
            parts.push("Source: " + GlobalState.screenRecordingAudioDevice);
        if (GlobalState.screenRecordingPath !== "")
            parts.push("File: " + GlobalState.screenRecordingPath);
        if (GlobalState.screenRecordingPid > 0)
            parts.push("PID: " + GlobalState.screenRecordingPid);

        return parts.join("<br/>");
    }

    backgroundColor: Qt.alpha(Config.color.error, 0.16)
    collapsed: !GlobalState.screenRecordingActive
    tooltipText: root.tooltipBody()
    tooltipTitle: "Screen Recording"

    content: [
        IconTextRow {
            iconColor: Config.color.error
            iconText: ""
            spacing: root.contentSpacing
            text: GlobalState.screenRecordingAudioMode === "defaultMic" ? "REC MIC" : "REC"
            textColor: Config.color.error
        }
    ]

    onClicked: GlobalState.stopScreenRecording()
}
