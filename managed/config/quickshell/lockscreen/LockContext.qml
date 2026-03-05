import QtQuick
import Quickshell
import Quickshell.Services.Pam

Scope {
    id: root

    signal unlocked
    signal failed

    property string currentText: ""
    property bool unlockInProgress: false
    property bool showPassword: false
    property bool showFailure: false
    property string lastMessage: ""
    property bool accountLocked: false

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

        onMessageChanged: {
            if (!message || message.length === 0)
                return;

            if (message.startsWith("The account is locked")) {
                root.lastMessage = message;
                root.accountLocked = true;
            } else if (root.lastMessage.length > 0 && message.endsWith(" left to unlock)")) {
                root.lastMessage += "\n" + message;
                root.accountLocked = true;
            } else if (message.toLowerCase().startsWith("password:") && !root.accountLocked) {
                root.accountLocked = false;
            }
        }

        onPamMessage: {
            if (responseRequired)
                respond(root.currentText);
        }

        onCompleted: function(result) {
            if (result === PamResult.Success) {
                root.currentText = "";
                root.showFailure = false;
                root.lastMessage = "";
                root.accountLocked = false;
                root.unlockInProgress = false;
                root.unlocked();
                return;
            }

            root.currentText = "";
            root.showFailure = true;
            root.lastMessage = message || "Authentication failed";
            root.unlockInProgress = false;
            root.failed();
        }

        onError: function(error) {
            root.currentText = "";
            root.showFailure = true;
            root.lastMessage = "PAM error: " + error;
            root.unlockInProgress = false;
            root.failed();
        }
    }
}
