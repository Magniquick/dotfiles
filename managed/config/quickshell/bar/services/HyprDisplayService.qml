pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import "../../common" as Common

Item {
  id: root
  visible: false

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
    for (const raw of lines) {
      const line = raw.trim();
      if (!line || line.startsWith("#"))
        continue;
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

  function refresh() {
    if (!root.isHyprlandSession || !root.hyprctlAvailable)
      return;
    root.loading = true;
    liveMonitorsProc.running = true;
    loadConfigProc.running = true;
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
        lines.push("monitor = " + name + ", disable");
        continue;
      }
      const mode = o.mode || "preferred";
      const pos = (o.x || 0) + "x" + (o.y || 0);
      const scale = isFinite(o.scale) ? o.scale : 1.0;
      let line = "monitor = " + name + ", " + mode + ", " + pos + ", " + scale;
      if ((o.transform || 0) !== 0)
        line += ", transform, " + Math.round(o.transform);
      if ((o.vrr || 0) > 0)
        line += ", vrr, " + Math.round(o.vrr);
      if ((o.mirror || "") !== "")
        line += ", mirror, " + o.mirror;
      if ((o.bitdepth || 8) !== 8)
        line += ", bitdepth, " + Math.round(o.bitdepth);
      if ((o.cm || "auto") !== "auto")
        line += ", cm, " + o.cm;
      if ((o.sdrbrightness || 1.0) !== 1.0)
        line += ", sdrbrightness, " + Number(o.sdrbrightness).toFixed(2);
      if ((o.sdrsaturation || 1.0) !== 1.0)
        line += ", sdrsaturation, " + Number(o.sdrsaturation).toFixed(2);
      lines.push(line);
    }
    return lines.join("\n");
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
    const esc = finalText.replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\$/g, "\\$").replace(/`/g, "\\`");
    writeApplyProc.command = ["sh", "-lc", "mkdir -p \"$HOME/.config/hypr/hyprland\" && printf \"%s\" \"" + esc + "\" > \"$HOME/.config/hypr/hyprland/monitors.conf\" && hyprctl reload"];
    writeApplyProc.running = true;
  }

  Component.onCompleted: {
    Common.DependencyCheck.require("hyprctl", "HyprDisplayService", available => {
      root.hyprctlAvailable = available;
      if (available)
        root.refresh();
    });
  }

  Process {
    id: liveMonitorsProc
    running: false
    command: ["hyprctl", "-j", "monitors", "all"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          const data = JSON.parse(text || "[]");
          root.liveOutputs = root._buildFromLive(data);
          root.dataChanged();
        } catch (e) {
          root.lastError = "Failed to parse hyprctl monitor data";
        }
      }
    }
    onExited: code => {
      if (code !== 0)
        root.lastError = "hyprctl monitors failed";
      root.loading = false;
    }
  }

  Process {
    id: loadConfigProc
    running: false
    command: ["sh", "-lc", "mkdir -p \"$HOME/.config/hypr/hyprland\" && touch \"$HOME/.config/hypr/hyprland/monitors.conf\" && cat \"$HOME/.config/hypr/hyprland/monitors.conf\""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const split = root._splitManaged(text || "");
        root.preservedPrefix = split.prefix;
        root.preservedSuffix = split.suffix;
        root.parsedConfigOutputs = root._parseManaged(split.managed);
        root.dataChanged();
      }
    }
    onExited: code => {
      if (code !== 0)
        root.lastError = "Failed to read monitors.conf";
    }
  }

  Process {
    id: writeApplyProc
    running: false
    command: []
    stderr: StdioCollector {
      id: writeApplyErr
      waitForEnd: true
    }
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
  }
}
