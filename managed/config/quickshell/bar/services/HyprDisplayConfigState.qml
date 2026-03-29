pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import qs.bar

Item {
  id: root
  visible: false

  property var outputs: ({})
  property var pending: ({})
  property var snapshotBeforeApply: ({})
  property string applyError: ""
  property bool waitingConfirm: false
  property int confirmSeconds: 15
  property int confirmRemainingSeconds: 15

  readonly property bool hasPending: Object.keys(pending).length > 0
  readonly property var outputNames: {
    const names = Object.keys(outputs || {});
    names.sort((a, b) => {
      const oa = root.getOutput(a) || {};
      const ob = root.getOutput(b) || {};
      const aConnected = oa.description ? 1 : 0;
      const bConnected = ob.description ? 1 : 0;
      if (aConnected !== bConnected)
        return bConnected - aConnected;
      return (oa.x || 0) - (ob.x || 0) || (oa.y || 0) - (ob.y || 0) || a.localeCompare(b);
    });
    return names;
  }

  function refresh() {
    HyprDisplayService.refresh();
  }

  function rebuildOutputs() {
    const merged = JSON.parse(JSON.stringify(HyprDisplayService.liveOutputs || {}));
    const cfg = HyprDisplayService.parsedConfigOutputs || {};
    for (const name in cfg) {
      if (!merged[name])
        merged[name] = JSON.parse(JSON.stringify(cfg[name]));
      else
        Object.assign(merged[name], cfg[name]);
    }
    outputs = merged;
  }

  function getOutput(name) {
    const base = outputs[name];
    if (!base)
      return null;
    const out = JSON.parse(JSON.stringify(base));
    const p = pending[name];
    if (p)
      Object.assign(out, p);
    return out;
  }

  function setField(name, key, value) {
    const next = JSON.parse(JSON.stringify(pending));
    if (!next[name])
      next[name] = {};
    next[name][key] = value;
    pending = next;
  }

  function getPendingValue(name, key) {
    const entry = pending[name];
    if (!entry || !entry.hasOwnProperty(key))
      return undefined;
    return entry[key];
  }

  function clearPending() {
    pending = ({});
  }

  function outputLabel(name) {
    const output = getOutput(name);
    if (!output)
      return name;
    const parts = [];
    if (output.make)
      parts.push(output.make);
    if (output.model)
      parts.push(output.model);
    if (parts.length > 0)
      return name + " • " + parts.join(" ");
    if (output.description)
      return name + " • " + output.description;
    return name;
  }

  function parseMode(modeText) {
    const match = String(modeText || "").match(/(\d+)x(\d+)(?:@([\d.]+))?/);
    return {
      width: match ? parseInt(match[1]) : 1920,
      height: match ? parseInt(match[2]) : 1080,
      refresh: match && match[3] ? parseFloat(match[3]) : 0
    };
  }

  function modeLabel(modeText) {
    const parsed = parseMode(modeText);
    const refresh = parsed.refresh > 0 ? " @ " + Number(parsed.refresh).toFixed(0) + " Hz" : "";
    return parsed.width + " × " + parsed.height + refresh;
  }

  function outputLogicalSize(output) {
    const parsed = parseMode(output && output.mode ? output.mode : "preferred");
    let width = parsed.width;
    let height = parsed.height;
    const transform = output ? Number(output.transform || 0) : 0;
    if ([1, 3, 5, 7].indexOf(transform) >= 0) {
      const swap = width;
      width = height;
      height = swap;
    }
    const scale = output && isFinite(output.scale) && output.scale > 0 ? output.scale : 1.0;
    return {
      width: Math.max(1, width / scale),
      height: Math.max(1, height / scale)
    };
  }

  function boundsForNames(names) {
    let minX = Infinity;
    let minY = Infinity;
    let maxX = -Infinity;
    let maxY = -Infinity;
    for (const name of names || []) {
      const output = getOutput(name);
      if (!output || output.disabled)
        continue;
      const size = outputLogicalSize(output);
      minX = Math.min(minX, Number(output.x || 0));
      minY = Math.min(minY, Number(output.y || 0));
      maxX = Math.max(maxX, Number(output.x || 0) + size.width);
      maxY = Math.max(maxY, Number(output.y || 0) + size.height);
    }
    if (minX === Infinity) {
      return {
        minX: 0,
        minY: 0,
        width: 1920,
        height: 1080
      };
    }
    return {
      minX: minX,
      minY: minY,
      width: Math.max(1, maxX - minX),
      height: Math.max(1, maxY - minY)
    };
  }

  function setPosition(name, x, y) {
    setField(name, "x", Math.round(x));
    setField(name, "y", Math.round(y));
  }

  function transformLabel(value) {
    switch (Number(value || 0)) {
    case 1:
      return "90°";
    case 2:
      return "180°";
    case 3:
      return "270°";
    case 4:
      return "Flipped";
    case 5:
      return "Flipped 90°";
    case 6:
      return "Flipped 180°";
    case 7:
      return "Flipped 270°";
    default:
      return "Normal";
    }
  }

  function vrrLabel(value) {
    switch (Number(value || 0)) {
    case 1:
      return "On";
    case 2:
      return "Fullscreen Only";
    default:
      return "Off";
    }
  }

  function colorModeLabel(value) {
    switch (String(value || "auto")) {
    case "wide":
      return "Wide (BT2020)";
    case "dcip3":
      return "DCI-P3";
    case "dp3":
      return "Apple P3";
    case "adobe":
      return "Adobe RGB";
    case "edid":
      return "EDID";
    case "hdr":
      return "HDR";
    case "hdredid":
      return "HDR (EDID)";
    default:
      return "Auto (Wide)";
    }
  }

  function buildApplyMap() {
    const result = {};
    for (const name in outputs) {
      result[name] = getOutput(name);
    }
    return result;
  }

  function apply() {
    if (!hasPending || HyprDisplayService.applying)
      return;
    snapshotBeforeApply = JSON.parse(JSON.stringify(HyprDisplayService.parsedConfigOutputs || {}));
    applyError = "";
    confirmRemainingSeconds = confirmSeconds;
    HyprDisplayService.writeAndApply(buildApplyMap());
  }

  function confirm() {
    waitingConfirm = false;
    confirmRemainingSeconds = confirmSeconds;
    clearPending();
    snapshotBeforeApply = ({});
    confirmTimer.stop();
  }

  function revert() {
    waitingConfirm = false;
    confirmRemainingSeconds = confirmSeconds;
    confirmTimer.stop();
    HyprDisplayService.writeAndApply(snapshotBeforeApply || {});
    clearPending();
    snapshotBeforeApply = ({});
  }

  Connections {
    target: HyprDisplayService
    function onDataChanged() {
      root.rebuildOutputs();
    }
    function onApplyFinished(ok, message) {
      if (!ok) {
        root.applyError = message;
        return;
      }
      root.waitingConfirm = true;
      root.confirmRemainingSeconds = root.confirmSeconds;
      confirmTimer.restart();
    }
  }

  Timer {
    id: confirmTimer
    interval: 1000
    repeat: true
    onTriggered: {
      root.confirmRemainingSeconds = Math.max(0, root.confirmRemainingSeconds - 1);
      if (root.confirmRemainingSeconds <= 0) {
        stop();
        root.revert();
      }
    }
  }

  Component.onCompleted: rebuildOutputs()
}
