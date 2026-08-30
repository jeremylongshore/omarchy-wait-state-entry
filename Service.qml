import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Background owner for PSI acquisition and bounded persistence. The reader
// touches exactly three kernel-owned files, caps each at 512 bytes, and emits
// a tiny line protocol. Model.js enforces a second total-size bound.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string moduleId: "io.github.jeremylongshore.wait-state"
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir:
    (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/wait-state"
  readonly property string statePath: stateDir + "/state.json"
  readonly property string configPath:
    (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/omarchy/shell.json"

  property string pollInterval: "5 seconds"
  property string barResource: "Worst"
  property string historyWindow: "1 hour"
  property int warningPercent: 5
  property int criticalPercent: 20

  property var snapshot: Model.emptySnapshot(0)
  property var history: []
  property string selectedResource: "cpu"
  property bool stateDirReady: false
  property bool stateLoaded: false
  property bool sampling: false
  property string lastError: ""
  property bool inputTruncated: false
  property double lastPersistAt: 0
  property double lastAttemptAt: 0

  signal pressureChanged()

  function readSettings() {
    var conf
    try { conf = JSON.parse(configFile.text() || "") } catch (e) { return }
    if (!conf || !conf.bar || !conf.bar.layout) return
    var zones = ["left", "center", "right"]
    for (var z = 0; z < zones.length; z++) {
      var entries = conf.bar.layout[zones[z]] || []
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        if (!entry || entry.id !== root.moduleId) continue
        root.pollInterval = ["2 seconds", "5 seconds", "10 seconds", "30 seconds"].indexOf(entry.pollInterval) >= 0
          ? entry.pollInterval : "5 seconds"
        root.barResource = ["Worst", "CPU", "Memory", "I/O"].indexOf(entry.barResource) >= 0
          ? entry.barResource : "Worst"
        root.historyWindow = ["15 minutes", "1 hour", "6 hours"].indexOf(entry.historyWindow) >= 0
          ? entry.historyWindow : "1 hour"
        var thresholds = Model.clampThresholds(entry.warningPercent, entry.criticalPercent)
        root.warningPercent = thresholds.warning
        root.criticalPercent = thresholds.critical
        root.pressureChanged()
        return
      }
    }
  }

  function sample() {
    if (!root.stateLoaded || root.sampling) return
    root.sampling = true
    root.lastAttemptAt = Date.now()
    pressureProc.running = true
  }

  function acceptSample(raw) {
    var parsed = Model.parseSnapshot(raw, Date.now())
    root.sampling = false
    if (!parsed.valid) {
      root.inputTruncated = parsed.truncated
      root.lastError = parsed.error
      root.pressureChanged()
      return
    }
    root.snapshot = parsed
    root.inputTruncated = parsed.truncated
    root.history = Model.addHistory(root.history, parsed)
    root.lastError = parsed.error
    root.pressureChanged()
    if (Date.now() - root.lastPersistAt >= 60000) root.persist()
  }

  function persist() {
    if (!root.stateDirReady || !root.stateLoaded) return
    root.lastPersistAt = Date.now()
    stateFile.setText(JSON.stringify({
      schemaVersion: 1,
      selected: root.selectedResource,
      history: root.history
    }))
    root.pressureChanged()
  }

  function loadState(raw) {
    var parsed = Model.parseState(raw)
    if (parsed.valid) {
      root.history = parsed.history
      root.selectedResource = parsed.selected
    }
    root.stateLoaded = true
    root.pressureChanged()
    root.sample()
  }

  function chooseResource(name) {
    if (Model.RESOURCES.indexOf(name) < 0) return
    root.selectedResource = name
    root.persist()
  }

  Process {
    id: pressureProc
    command: ["bash", "-c",
      "for r in cpu memory io; do "
      + "printf 'resource=%s\\n' \"$r\"; "
      + "if [ -r \"/proc/pressure/$r\" ]; then "
      + "head -c 512 -- \"/proc/pressure/$r\"; printf '\\n'; "
      + "else printf 'unavailable\\n'; fi; done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.acceptSample(text)
    }
    onExited: function(code) {
      if (code !== 0 && root.sampling) {
        root.sampling = false
        root.lastError = "pressure reader failed (exit " + code + ")"
        root.pressureChanged()
      }
    }
  }

  Process {
    id: stateDirProc
    command: ["install", "-d", "-m", "700", "--", root.stateDir]
    onExited: function(code) {
      root.stateDirReady = code === 0
      if (!root.stateDirReady) {
        root.stateLoaded = true
        root.lastError = "state directory unavailable"
        root.pressureChanged()
        root.sample()
      }
    }
  }

  FileView {
    id: stateFile
    path: root.stateDirReady ? root.statePath : ""
    atomicWrites: true
    printErrors: false
    onLoaded: {
      if (root.stateDirReady) root.loadState(text())
    }
    onLoadFailed: {
      if (root.stateDirReady) root.loadState("")
    }
  }

  FileView {
    id: configFile
    path: root.configPath
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.readSettings()
  }

  Timer {
    interval: Model.pollSeconds(root.pollInterval) * 1000
    running: true
    repeat: true
    onTriggered: root.sample()
  }

  Component.onCompleted: stateDirProc.running = true
  Component.onDestruction: {
    if (root.stateDirReady && root.stateLoaded) root.persist()
  }
}
