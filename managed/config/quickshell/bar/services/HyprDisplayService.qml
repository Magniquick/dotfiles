pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../../common" as Common

Item {
  id: root
  visible: false

  readonly property var hyprland: Hyprland
  readonly property bool isHyprlandSession: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "") !== ""
  readonly property string hyprConfigDir: Quickshell.env("HOME") + "/.config/hypr/hyprland"
  readonly property string monitorsPath: hyprConfigDir + "/monitors.conf"

  property bool hyprctlAvailable: false
  property var liveOutputs: ({})
  property var parsedConfigOutputs: ({})
  property string preservedPrefix: ""
  property string preservedSuffix: ""
  property string lastError: ""
  property bool loading: false
  property bool applying: false

  signal dataChanged()
  signal applyFinished(bool ok, string message)

  function _ensureManagedBlock(text) {
    const begin = "# BEGIN managed-by-quickshell-display-config";
    const end = "# END managed-by-quickshell-display-config";
    if (text.indexOf(begin) >= 0 && text.indexOf(end) >= 0)
      return text;
    const trimmed = text.trim();
    if (trimmed.length === 0)
      return begin + "\n" + end + "\n";
    return text + (text.endsWith("\n") ? "" : "\n") + "\n" + begin + "\n" + end + "\n";
  }

  function _splitManaged(text) {
    const begin = "# BEGIN managed-by-quickshell-display-config";
    const end = "# END managed-by-quickshell-display-config";
    const t = _ensureManagedBlock(text);
    const bi = t.indexOf(begin);
    const ei = t.indexOf(end);
    if (bi < 0 || ei < 0 || ei < bi)
      return { prefix: "", managed: "", suffix: "" };
    const managedStart = bi + begin.length;
    const managed = t.slice(managedStart, ei).replace(/^\n+/, "").replace(/\n+$/, "");
    return {
      prefix: t.slice(0, managedStart) + "\n",
      managed: managed,
      suffix: "\n" + t.slice(ei)
    };
  }

  function _parseManaged(text) {
    const outputs = {};
    const lines = (text || "").split("\n");
    let currentBlock = null;

    function commitCurrentBlock() {
      if (!currentBlock || !currentBlock.output)
        return;
      const position = String(currentBlock.position || "0x0");
      const posM = position.match(/(-?\d+)x(-?\d+)/);
      outputs[currentBlock.output] = {
        name: currentBlock.output,
        disabled: currentBlock.disabled === true,
        mode: currentBlock.mode || "preferred",
        x: posM ? parseInt(posM[1]) : 0,
        y: posM ? parseInt(posM[2]) : 0,
        scale: isFinite(Number(currentBlock.scale)) ? Number(currentBlock.scale) : 1.0,
        transform: Math.round(Number(currentBlock.transform || 0)),
        vrr: Math.round(Number(currentBlock.vrr || 0)),
        mirror: String(currentBlock.mirror || ""),
        bitdepth: Math.round(Number(currentBlock.bitdepth || 8)),
        cm: String(currentBlock.cm || "auto"),
        sdrbrightness: isFinite(Number(currentBlock.sdrbrightness)) ? Number(currentBlock.sdrbrightness) : 1.0,
        sdrsaturation: isFinite(Number(currentBlock.sdrsaturation)) ? Number(currentBlock.sdrsaturation) : 1.0
      };
    }

    function parseBoolean(value) {
      return /^(1|true|yes|on)$/i.test(String(value || "").trim());
    }

    for (const raw of lines) {
      const line = raw.trim();
      if (!line || line.startsWith("#"))
        continue;
      if (line === "monitorv2 {") {
        commitCurrentBlock();
        currentBlock = {};
        continue;
      }
      if (line === "}") {
        commitCurrentBlock();
        currentBlock = null;
        continue;
      }
      if (currentBlock) {
        const kv = line.match(/^([a-zA-Z_]+)\s*=\s*(.+)$/);
        if (!kv)
          continue;
        const key = kv[1].trim();
        const value = kv[2].trim();
        if (key === "disabled")
          currentBlock.disabled = parseBoolean(value);
        else
          currentBlock[key] = value;
        continue;
      }
      const disabledMatch = line.match(/^monitor\s*=\s*([^,]+),\s*disable\s*$/);
      if (disabledMatch) {
        const name = disabledMatch[1].trim();
        outputs[name] = {
          name: name,
          disabled: true,
          mode: "preferred",
          x: 0,
          y: 0,
          scale: 1.0,
          transform: 0,
          vrr: 0,
          mirror: "",
          bitdepth: 8,
          cm: "auto",
          sdrbrightness: 1.0,
          sdrsaturation: 1.0
        };
        continue;
      }
      const m = line.match(/^monitor\s*=\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^,]+)(.*)$/);
      if (!m)
        continue;
      const name = m[1].trim();
      const mode = m[2].trim();
      const pos = m[3].trim();
      const scale = parseFloat(m[4].trim());
      const rest = m[5] || "";
      let x = 0;
      let y = 0;
      const posM = pos.match(/(-?\d+)x(-?\d+)/);
      if (posM) {
        x = parseInt(posM[1]);
        y = parseInt(posM[2]);
      }
      let transform = 0;
      let vrr = 0;
      let mirror = "";
      let bitdepth = 8;
      let cm = "auto";
      let sdrbrightness = 1.0;
      let sdrsaturation = 1.0;
      const tM = rest.match(/,\s*transform,\s*(\d+)/);
      if (tM)
        transform = parseInt(tM[1]);
      const vM = rest.match(/,\s*vrr,\s*(\d+)/);
      if (vM)
        vrr = parseInt(vM[1]);
      const mirM = rest.match(/,\s*mirror,\s*([^,\s]+)/);
      if (mirM)
        mirror = mirM[1];
      const bdM = rest.match(/,\s*bitdepth,\s*(\d+)/);
      if (bdM)
        bitdepth = parseInt(bdM[1]);
      const cmM = rest.match(/,\s*cm,\s*([^,\s]+)/);
      if (cmM)
        cm = cmM[1];
      const sbrM = rest.match(/,\s*sdrbrightness,\s*([\d.]+)/);
      if (sbrM)
        sdrbrightness = parseFloat(sbrM[1]);
      const ssM = rest.match(/,\s*sdrsaturation,\s*([\d.]+)/);
      if (ssM)
        sdrsaturation = parseFloat(ssM[1]);
      outputs[name] = {
        name: name,
        disabled: false,
        mode: mode,
        x: x,
        y: y,
        scale: isFinite(scale) ? scale : 1.0,
        transform: transform,
        vrr: vrr,
        mirror: mirror,
        bitdepth: bitdepth,
        cm: cm,
        sdrbrightness: sdrbrightness,
        sdrsaturation: sdrsaturation
      };
    }
    commitCurrentBlock();
    return outputs;
  }

  function _monitorModeString(out) {
    if (out.width > 0 && out.height > 0 && out.refresh > 0)
      return out.width + "x" + out.height + "@" + Number(out.refresh).toFixed(3);
    return "preferred";
  }

  function _buildFromLive(monitors) {
    const next = {};
    for (const m of monitors || []) {
      const name = m.name || "";
      if (!name)
        continue;
      const mode = root._monitorModeString({
        width: m.width || 0,
        height: m.height || 0,
        refresh: m.refreshRate || 0
      });
      next[name] = {
        name: name,
        description: m.description || "",
        make: m.make || "",
        model: m.model || "",
        serial: m.serial || "",
        disabled: false,
        mode: mode,
        availableModes: (m.availableModes || []).map(x => String(x)),
        x: m.x || 0,
        y: m.y || 0,
        scale: m.scale || 1.0,
        transform: m.transform || 0,
        vrr: m.vrr || 0,
        mirror: m.mirrorOf || "",
        bitdepth: 8,
        cm: "auto",
        sdrbrightness: 1.0,
        sdrsaturation: 1.0
      };
    }
    return next;
  }

  function _mergeConfigIntoLive() {
    const merged = JSON.parse(JSON.stringify(root.liveOutputs || {}));
    for (const name in root.parsedConfigOutputs) {
      if (!merged[name])
        merged[name] = JSON.parse(JSON.stringify(root.parsedConfigOutputs[name]));
      else
        Object.assign(merged[name], root.parsedConfigOutputs[name]);
    }
    return merged;
  }

  function _liveMonitorData() {
    const monitors = [];
    for (const screen of Quickshell.screens || []) {
      const monitor = root.hyprland.monitorFor(screen);
      if (monitor && monitor.lastIpcObject)
        monitors.push(monitor.lastIpcObject);
    }
    return monitors;
  }

  function _syncLiveOutputsFromHyprland() {
    root.liveOutputs = root._buildFromLive(root._liveMonitorData());
    root.dataChanged();
    root.loading = false;
  }

  function refresh() {
    if (!root.isHyprlandSession || !root.hyprctlAvailable)
      return;
    root.loading = true;
    root.hyprland.refreshMonitors();
    Qt.callLater(root._syncLiveOutputsFromHyprland);
    monitorsConfigFile.reload();
    root.loadConfig();
  }

  function generateManagedBlock(outputsMap) {
    const names = Object.keys(outputsMap || {}).sort((a, b) => {
      const oa = outputsMap[a] || {};
      const ob = outputsMap[b] || {};
      return (oa.x || 0) - (ob.x || 0) || (oa.y || 0) - (ob.y || 0);
    });
    const lines = [];
    for (const name of names) {
      const o = outputsMap[name];
      if (!o)
        continue;
      if (o.disabled) {
        lines.push("monitorv2 {");
        lines.push("  output = " + name);
        lines.push("  disabled = true");
        lines.push("}");
        continue;
      }
      const mode = o.mode || "preferred";
      const pos = (o.x || 0) + "x" + (o.y || 0);
      const scale = isFinite(o.scale) ? o.scale : 1.0;
      lines.push("monitorv2 {");
      lines.push("  output = " + name);
      lines.push("  mode = " + mode);
      lines.push("  position = " + pos);
      lines.push("  scale = " + scale);
      if ((o.transform || 0) !== 0)
        lines.push("  transform = " + Math.round(o.transform));
      if ((o.vrr || 0) > 0)
        lines.push("  vrr = " + Math.round(o.vrr));
      if ((o.mirror || "") !== "")
        lines.push("  mirror = " + o.mirror);
      if ((o.bitdepth || 8) !== 8)
        lines.push("  bitdepth = " + Math.round(o.bitdepth));
      if ((o.cm || "auto") !== "auto")
        lines.push("  cm = " + o.cm);
      if ((o.sdrbrightness || 1.0) !== 1.0)
        lines.push("  sdrbrightness = " + Number(o.sdrbrightness).toFixed(2));
      if ((o.sdrsaturation || 1.0) !== 1.0)
        lines.push("  sdrsaturation = " + Number(o.sdrsaturation).toFixed(2));
      lines.push("}");
    }
    return lines.join("\n\n");
  }

  function writeAndApply(outputsMap) {
    if (root.applying)
      return;
    root.applying = true;
    root.lastError = "";
    const managed = root.generateManagedBlock(outputsMap);
    const finalText = (root.preservedPrefix || "# BEGIN managed-by-quickshell-display-config\n")
      + managed
      + (managed ? "\n" : "")
      + (root.preservedSuffix || "\n# END managed-by-quickshell-display-config\n");
    monitorsConfigFile.setText(finalText);
    monitorsConfigFile.reload();
    root.loadConfig();
    writeApplyProc.command = ["hyprctl", "reload"];
    writeApplyProc.running = true;
  }

  function loadConfig() {
    const split = root._splitManaged(monitorsConfigFile.text() || "");
    root.preservedPrefix = split.prefix;
    root.preservedSuffix = split.suffix;
    root.parsedConfigOutputs = root._parseManaged(split.managed);
    root.dataChanged();
  }

  Component.onCompleted: {
    Common.DependencyCheck.require("hyprctl", "HyprDisplayService", available => {
      root.hyprctlAvailable = available;
      if (available)
        root.refresh();
    });
  }

  FileView {
    id: monitorsConfigFile
    path: root.monitorsPath
    blockLoading: true
    blockWrites: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }

  Process {
    id: writeApplyProc
    running: false
    command: []
    stderr: StdioCollector {
      id: writeApplyErr
      waitForEnd: true
    }
    // qmllint disable signal-handler-parameters
    onExited: code => {
      root.applying = false;
      if (code === 0) {
        root.applyFinished(true, "Applied");
        root.refresh();
      } else {
        root.lastError = writeApplyErr.text.trim() || "Failed to apply monitor config";
        root.applyFinished(false, root.lastError);
      }
    }
    // qmllint enable signal-handler-parameters
  }
}
