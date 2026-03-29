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
