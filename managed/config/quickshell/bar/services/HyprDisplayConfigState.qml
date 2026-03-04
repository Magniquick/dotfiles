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

  readonly property bool hasPending: Object.keys(pending).length > 0

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

  function clearPending() {
    pending = ({});
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
    HyprDisplayService.writeAndApply(buildApplyMap());
  }

  function confirm() {
    waitingConfirm = false;
    clearPending();
    snapshotBeforeApply = ({});
    confirmTimer.stop();
  }

  function revert() {
    waitingConfirm = false;
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
      confirmTimer.restart();
    }
  }

  Timer {
    id: confirmTimer
    interval: root.confirmSeconds * 1000
    repeat: false
    onTriggered: root.revert()
  }

  Component.onCompleted: rebuildOutputs()
}
