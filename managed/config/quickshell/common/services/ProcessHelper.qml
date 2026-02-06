pragma Singleton
import QtQml
import Quickshell

QtObject {
    function shell(command) {
        return ["sh", "-c", command];
    }

    function normalize(command) {
        return Array.isArray(command) ? command : shell(command);
    }

    function execDetached(command, opts) {
        if (opts && typeof opts === "object") {
            const ctx = { command: normalize(command) };
            if (opts.environment)
                ctx.environment = opts.environment;
            if (opts.clearEnvironment !== undefined)
                ctx.clearEnvironment = opts.clearEnvironment;
            if (opts.workingDirectory)
                ctx.workingDirectory = opts.workingDirectory;
            Quickshell.execDetached(ctx);
            return;
        }

        Quickshell.execDetached(normalize(command));
    }
}

