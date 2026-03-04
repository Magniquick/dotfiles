import QtQuick
import Quickshell
import Quickshell.Services.Pam

Scope {
    id: root

    signal unlocked

    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false
    property string lastMessage: ""

    onCurrentTextChanged: showFailure = false

    function tryUnlock() {
        if (root.currentText.length === 0 || root.unlockInProgress)
            return;

        root.unlockInProgress = true;
        pam.start();
    }

    function clearError() {
        root.showFailure = false;
        root.lastMessage = "";
    }

    PamContext {
        id: pam

        configDirectory: "/etc/pam.d"
        config: "login"
        user: Quickshell.env("USER")

        onPamMessage: {
            if (responseRequired)
                respond(root.currentText);
        }

        onCompleted: function(result) {
            if (result === PamResult.Success) {
                root.currentText = "";
                root.showFailure = false;
                root.lastMessage = "";
                root.unlockInProgress = false;
                root.unlocked();
                return;
            }

            root.currentText = "";
            root.showFailure = true;
            root.lastMessage = message || "Authentication failed";
            root.unlockInProgress = false;
        }

        onError: function(error) {
            root.currentText = "";
            root.showFailure = true;
            root.lastMessage = "PAM error: " + error;
            root.unlockInProgress = false;
        }
    }
}
