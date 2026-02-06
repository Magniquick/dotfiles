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

function _resolveTempDir(env) {
  return env.XDG_RUNTIME_DIR || "/tmp";
}

function _stripFileUrl(s) {
  return String(s || "").replace("file://", "");
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
  const picturesDir = _resolvePicturesDir(env);
  const tempDir = _resolveTempDir(env);

  const now = opts.now || new Date();
  const timestamp = Qt.formatDateTime(now, "yyyy-MM-dd_hh-mm-ss-zzz");

  const saveToDisk = !!opts.saveToDisk;
  const outputPath = saveToDisk
    ? (picturesDir + "/screenshot-" + timestamp + ".png")
    : (tempDir + "/hyprquickshot-preview-" + timestamp + ".png");

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
  const ensureDirCommand = saveToDisk ? ("mkdir -p -- \"" + picturesDir + "\" && ") : "";

  const commandString = ensureDirCommand
    + captureCommand
    + ("magick \"" + sourcePath + "\" -crop " + scaledWidth + "x" + scaledHeight + "+" + scaledX + "+" + scaledY + " \"" + outputPath + "\" && ")
    + ("rm -f -- \"" + tempPath + "\"");

  return {
    outputPath: outputPath,
    lastScreenshotTemporary: !saveToDisk,
    commandString: commandString
  };
}
