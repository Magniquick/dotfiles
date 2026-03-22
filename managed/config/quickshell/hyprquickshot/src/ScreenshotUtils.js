.pragma library

function _asNumber(value, fallback) {
  const n = Number(value);
  return isFinite(n) ? n : fallback;
}

function _resolvePicturesDir(env) {
  const homeDir = env.HOME || "";
  if (env.HQS_DIR)
    return env.HQS_DIR;
  if (env.XDG_SCREENSHOTS_DIR)
    return env.XDG_SCREENSHOTS_DIR;
  if (env.XDG_PICTURES_DIR)
    return env.XDG_PICTURES_DIR + "/Screenshots";
  if (homeDir)
    return homeDir + "/Pictures/Screenshots";
  // Preserve previous behavior: if HOME is empty this becomes "/Pictures".
  return homeDir + "/Pictures";
}

function _resolveVideosDir(env) {
  const homeDir = env.HOME || "";
  if (env.XDG_VIDEOS_DIR)
    return env.XDG_VIDEOS_DIR + "/Screencasts";
  if (homeDir)
    return homeDir + "/Videos/Screencasts";
  return _resolveTempDir(env);
}

function _resolveTempDir(env) {
  return env.XDG_RUNTIME_DIR || "/tmp";
}

function _stripFileUrl(s) {
  return String(s || "").replace("file://", "");
}

function _quote(value) {
  return "\"" + String(value || "").replace(/(["\\$`])/g, "\\$1") + "\"";
}

function _waitForFiles(paths, attempts, delaySeconds) {
  const files = Array.isArray(paths) ? paths : [];
  const maxAttempts = Math.max(1, Number(attempts) || 1);
  const delay = String(delaySeconds || "0.1");
  let command = "ok=0; ";
  command += "for i in $(seq 1 " + maxAttempts + "); do ";
  command += "ok=1; ";
  for (let index = 0; index < files.length; index += 1)
    command += "[ -s " + _quote(files[index]) + " ] || ok=0; ";
  command += "[ \"$ok\" -eq 1 ] && exit 0; ";
  command += "sleep " + delay + "; ";
  command += "done; exit 1";
  return command;
}

function _resolveScreenshotOutput(opts) {
  const env = opts.env || {};
  const picturesDir = _resolvePicturesDir(env);
  const tempDir = _resolveTempDir(env);
  const now = opts.now || new Date();
  const timestamp = Qt.formatDateTime(now, "yyyy-MM-dd_hh-mm-ss-zzz");
  const saveToDisk = !!opts.saveToDisk;
  const outputPath = saveToDisk
    ? (picturesDir + "/screenshot-" + timestamp + ".png")
    : (tempDir + "/hyprquickshot-preview-" + timestamp + ".png");

  return {
    outputDir: picturesDir,
    outputPath: outputPath,
    saveToDisk: saveToDisk,
    temporary: !saveToDisk
  };
}

function resolveScreenshotOutput(opts) {
  return _resolveScreenshotOutput(opts);
}

function stripFileUrl(value) {
  return _stripFileUrl(value);
}

function planScreenshot(opts) {
  const x = _asNumber(opts.x, 0);
  const y = _asNumber(opts.y, 0);
  const width = _asNumber(opts.width, 0);
  const height = _asNumber(opts.height, 0);

  const rawScale = _asNumber(opts.monitorScale, 1);
  const scale = rawScale > 0 ? rawScale : 1;

  const scaledX = Math.round(x * scale);
  const scaledY = Math.round(y * scale);
  const scaledWidth = Math.round(width * scale);
  const scaledHeight = Math.round(height * scale);

  const env = opts.env || {};
  const output = _resolveScreenshotOutput(opts);
  const outputPath = output.outputPath;

  const tempPath = String(opts.tempPath || "");
  let sourcePath = tempPath;

  const screenFrozen = !!opts.screenFrozen;
  const frozenFrame = String(opts.frozenFrame || "");
  if (screenFrozen && frozenFrame !== "")
    sourcePath = _stripFileUrl(frozenFrame);

  const screenX = _asNumber(opts.screenX, 0);
  const screenY = _asNumber(opts.screenY, 0);
  const screenWidth = _asNumber(opts.screenWidth, 0);
  const screenHeight = _asNumber(opts.screenHeight, 0);
  const geometry = screenX + "," + screenY + " " + screenWidth + "x" + screenHeight;

  const captureCommand = (!screenFrozen) ? ("grim -g \"" + geometry + "\" \"" + sourcePath + "\" && ") : "";
  const ensureDirCommand = output.saveToDisk ? ("mkdir -p -- \"" + output.outputDir + "\" && ") : "";

  const commandString = ensureDirCommand
    + captureCommand
    + ("magick \"" + sourcePath + "\" -crop " + scaledWidth + "x" + scaledHeight + "+" + scaledX + "+" + scaledY + " \"" + outputPath + "\" && ")
    + ("rm -f -- \"" + tempPath + "\"");

  return {
    outputPath: outputPath,
    lastScreenshotTemporary: output.temporary,
    commandString: commandString
  };
}

function planWindowScreenshot(opts) {
  const output = _resolveScreenshotOutput(opts);
  const stableId = String(opts.stableId || "");
  const ensureDirCommand = output.saveToDisk ? ("mkdir -p -- " + _quote(output.outputDir) + " && ") : "";
  const waitCommand = _waitForFiles([output.outputPath], 40, "0.1");

  return {
    outputPath: output.outputPath,
    lastScreenshotTemporary: output.temporary,
    commandString: ensureDirCommand
      + "grim -T " + _quote(stableId) + " " + _quote(output.outputPath) + " && "
      + waitCommand
  };
}

function planFrozenWindowFinalize(opts) {
  const output = _resolveScreenshotOutput(opts);
  const sourcePath = String(opts.sourcePath || "");
  const ensureDirCommand = output.saveToDisk ? ("mkdir -p -- " + _quote(output.outputDir) + " && ") : "";

  return {
    outputPath: output.outputPath,
    lastScreenshotTemporary: output.temporary,
    commandString: ensureDirCommand + "cp -- " + _quote(sourcePath) + " " + _quote(output.outputPath)
  };
}

function planFrozenWindowCache(opts) {
  const targets = Array.isArray(opts.targets) ? opts.targets : [];
  if (targets.length === 0) {
    return {
      commandString: ":"
    };
  }

  let commandString = "set -e; ";
  for (let index = 0; index < targets.length; index += 1) {
    const target = targets[index] || {};
    commandString += "rm -f -- " + _quote(target.imagePath || "") + "; ";
    commandString += "grim -T " + _quote(target.stableId || "") + " " + _quote(target.imagePath || "") + " & ";
  }
  commandString += _waitForFiles(targets.map(target => target.imagePath || ""), 60, "0.1") + "; ";

  return {
    commandString: commandString
  };
}

function planRecording(opts) {
  const env = opts.env || {};
  const now = opts.now || new Date();
  const timestamp = Qt.formatDateTime(now, "yyyy-MM-dd_hh-mm-ss-zzz");
  const videosDir = _resolveVideosDir(env);
  const outputPath = videosDir + "/screenrecord-" + timestamp + ".mp4";
  const mode = String(opts.mode || "region");
  const targetScreen = opts.targetScreen || null;
  const audioMode = String(opts.audioMode || "monitor");

  let captureArg = "";
  if (mode === "screen" && targetScreen && targetScreen.name) {
    captureArg = "--output \"" + String(targetScreen.name).replace(/"/g, "\\\"") + "\"";
  } else {
    const x = Math.round(_asNumber(opts.x, 0));
    const y = Math.round(_asNumber(opts.y, 0));
    const width = Math.round(_asNumber(opts.width, 0));
    const height = Math.round(_asNumber(opts.height, 0));
    captureArg = "--geometry \"" + x + "," + y + " " + width + "x" + height + "\"";
  }

  let audioResolveCommand = "";
  if (audioMode === "monitor") {
    audioResolveCommand = "audio_device=\"$(pactl get-default-sink 2>/dev/null)\"; " +
      "if [ -z \"$audio_device\" ]; then echo \"Could not resolve default sink\" >&2; exit 1; fi; " +
      "audio_device=\"$audio_device.monitor\"; " +
      "if ! pactl list short sources 2>/dev/null | awk '{print $2}' | grep -Fx -- \"$audio_device\" >/dev/null; then " +
      "echo \"Monitor source not found: $audio_device\" >&2; exit 1; fi; ";
  } else if (audioMode === "defaultMic") {
    audioResolveCommand = "audio_device=\"$(pactl get-default-source 2>/dev/null)\"; " +
      "if [ -z \"$audio_device\" ]; then echo \"Could not resolve default source\" >&2; exit 1; fi; " +
      "case \"$audio_device\" in *.monitor) " +
      "audio_device=\"$(pactl list short sources 2>/dev/null | awk '$2 !~ /\\.monitor$/ {print $2; exit}')\" ;; esac; " +
      "if [ -z \"$audio_device\" ]; then echo \"No non-monitor microphone source found\" >&2; exit 1; fi; ";
  }

  const quotedOutputPath = "\"" + outputPath.replace(/"/g, "\\\"") + "\"";
  const quotedVideosDir = "\"" + videosDir.replace(/"/g, "\\\"") + "\"";
  let commandString = "mkdir -p -- " + quotedVideosDir + " && ";
  commandString += audioResolveCommand;
  if (audioMode === "monitor" || audioMode === "defaultMic")
    commandString += "printf 'audio_device:%s\\n' \"$audio_device\"; ";
  commandString += "exec wl-screenrec " + captureArg + " --filename " + quotedOutputPath;

  if (audioMode === "monitor" || audioMode === "defaultMic")
    commandString += " --audio --audio-device \"$audio_device\"";

  return {
    audioMode: audioMode,
    commandString: commandString,
    outputPath: outputPath,
    outputDir: videosDir
  };
}
