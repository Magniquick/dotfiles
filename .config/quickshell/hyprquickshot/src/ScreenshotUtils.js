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
  const audioDevice = String(opts.audioDevice || "");
  const argv = ["wl-screenrec"];

  if (mode === "screen" && targetScreen && targetScreen.name) {
    argv.push("--output", String(targetScreen.name));
  } else {
    const x = Math.round(_asNumber(opts.x, 0));
    const y = Math.round(_asNumber(opts.y, 0));
    const width = Math.round(_asNumber(opts.width, 0));
    const height = Math.round(_asNumber(opts.height, 0));
    argv.push("--geometry", x + "," + y + " " + width + "x" + height);
  }

  if (audioMode === "monitor" || audioMode === "defaultMic")
    argv.push("--audio");

  if ((audioMode === "monitor" || audioMode === "defaultMic") && audioDevice !== "")
    argv.push("--audio-device", audioDevice);

  argv.push("--filename", outputPath);

  return {
    audioMode: audioMode,
    audioDevice: audioDevice,
    command: argv,
    outputPath: outputPath,
    outputDir: videosDir
  };
}
