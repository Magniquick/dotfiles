pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * @singleton DependencyCheck
 * @description Centralized dependency checking with user notification
 *
 * Usage:
 *   // Check command in PATH
 *   DependencyCheck.require("nmcli", "NetworkModule")
 *   DependencyCheck.require("brillo", "BacklightModule", function(available) {
 *       root.brilloAvailable = available;
 *   })
 *
 *   // Check executable script/file
 *   DependencyCheck.requireExecutable("/path/to/script.sh", "PrivacyModule", callback)
 *
 * If missing, sends a desktop notification via notify-send.
 */
QtObject {
    id: root

    // Track which deps we've already notified about to avoid spam
    property var notifiedDeps: ({})

    function require(command, moduleName, callback) {
        _check(`command -v ${command}`, command, moduleName, callback, "not found in PATH");
    }

    function requireExecutable(path, moduleName, callback) {
        _check(`test -f "${path}" && test -x "${path}" && echo found`, path, moduleName, callback, "not found or not executable");
    }

    function _check(shellCommand, depName, moduleName, callback, errorSuffix) {
        const proc = checkProcess.createObject(root, {
            shellCommand: shellCommand,
            depName: depName,
            moduleName: moduleName || "Quickshell",
            callback: callback || null,
            errorSuffix: errorSuffix
        });
        proc.running = true;
    }

    property Component checkProcess: Component {
        Process {
            id: proc

            property string shellCommand: ""
            property string depName: ""
            property string moduleName: ""
            property var callback: null
            property string errorSuffix: ""

            command: ["sh", "-c", shellCommand]

            stdout: SplitParser {
                onRead: data => {
                    // Dependency exists
                    if (proc.callback)
                        proc.callback(true);
                    proc.destroy();
                }
            }

            onExited: code => {
                if (code !== 0) {
                    // Dependency not found
                    if (proc.callback)
                        proc.callback(false);

                    // Only notify once per dependency
                    if (!root.notifiedDeps[proc.depName]) {
                        root.notifiedDeps[proc.depName] = true;
                        console.warn(`${proc.moduleName}: ${proc.depName} ${proc.errorSuffix}`);
                        Quickshell.exec(["notify-send",
                            "-a", "Quickshell",
                            "-u", "normal",
                            "Dependency Missing",
                            `${proc.moduleName}: '${proc.depName}' ${proc.errorSuffix}`
                        ]);
                    }
                }
                proc.destroy();
            }
        }
    }
}
