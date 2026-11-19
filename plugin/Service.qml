import QtQuick
import Quickshell
import Quickshell.Io

// Talks to the omarchy-amnezia CLI (which talks to the root helper).
// Everything coming back is JSON produced by our own scripts; it is still
// treated as untrusted text by the UI (PlainText everywhere).
Item {
  id: root
  visible: false

  property var settings: ({})
  property bool panelOpen: false

  readonly property string cli: "/usr/local/bin/omarchy-amnezia"

  // False until the CLI answers with valid JSON: a missing binary never runs
  // the output handler at all, so "installed" must be earned, not assumed.
  property bool installed: false
  property bool loaded: false
  property string active: ""
  property int handshake: -1
  property real rx: 0
  property real tx: 0
  property string endpoint: ""
  property string autostart: ""
  property var configs: []
  property var candidates: []

  property bool busy: false
  property string busyAction: ""   // "up:<name>", "down", "import", "diagnose:<name>", ...
  property string lastError: ""
  property string notice: ""
  property var diagnosis: null     // last diagnose result
  property bool diagnosing: false

  readonly property bool connected: active !== ""
  readonly property string lastUsed: configs.length > 0 ? (_last !== "" ? _last : configs[0].name) : ""
  property string _last: ""

  // Polling: fast while the panel is open, slower while connected (traffic
  // counters), slow when idle. Each poll is one short bash + sudo + awg call.
  readonly property int pollMs: panelOpen ? 2000 : (connected ? 10000 : 30000)

  function clip(s, n) { s = String(s === undefined || s === null ? "" : s); return s.length > n ? s.slice(0, n) : s }

  function parse(text) {
    try { return JSON.parse(String(text || "").trim() || "{}") } catch (e) { return { ok: false, error: "unexpected output" } }
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }
  function refreshLists() {
    if (!listProc.running) listProc.running = true
    if (!candProc.running) candProc.running = true
  }

  function run(args, action) {
    if (busy) return
    busy = true
    busyAction = action
    lastError = ""
    notice = ""
    actionProc.command = [cli].concat(args)
    actionProc.running = true
  }

  function connect(name) { if (name) run(["up", name], "up:" + name) }
  function disconnect() { run(["down"], "down") }
  function toggle() {
    if (connected) disconnect()
    else if (lastUsed !== "") connect(lastUsed)
    else lastError = "Import a config first"
  }
  function importFile(path, name) {
    path = String(path || "").trim()
    if (path.indexOf("~/") === 0) path = Quickshell.env("HOME") + path.slice(1)
    if (path === "") return
    run(name ? ["import", path, name] : ["import", path], "import")
  }
  function remove(name) { run(["remove", name], "remove:" + name) }
  function setJunk(name, on) { run(["obfuscate", name, on ? "on" : "off"], "obfuscate:" + name) }
  function setAutostart(name) { run(["autostart", name || "off"], "autostart") }
  function diagnose(name) {
    if (diagProc.running) return
    diagnosis = null
    diagnosing = true
    lastError = ""
    diagProc.command = [cli, "diagnose", name]
    diagProc.running = true
  }

  Timer {
    interval: root.pollMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  onPanelOpenChanged: if (panelOpen) { refresh(); refreshLists() }

  Process {
    id: statusProc
    command: [root.cli, "status"]
    // A binary that cannot start exits non-zero without ever producing output.
    onExited: function(exitCode) { if (exitCode !== 0 && !root.loaded) root.installed = false }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // No output at all means the CLI itself could not start.
        if (String(text || "").trim() === "") {
          root.installed = false
          root.active = ""
          return
        }
        var j = root.parse(text)
        if (j.ok === false) {
          root.installed = String(j.error || "").indexOf("not installed") < 0 && String(j.error || "").indexOf("sudo rule") < 0
          if (!root.installed) root.lastError = root.clip(j.error, 200)
          root.active = ""
          return
        }
        root.installed = true
        root.loaded = true
        root.active = root.clip(j.active, 15)
        root.handshake = Number(j.handshake) || -1
        root.rx = Number(j.rx) || 0
        root.tx = Number(j.tx) || 0
        root.endpoint = root.clip(j.endpoint, 64)
        root.autostart = root.clip(j.autostart, 15)
      }
    }
  }

  Process {
    id: listProc
    command: [root.cli, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var j = root.parse(text)
        if (!(j instanceof Array)) return
        var out = []
        for (var i = 0; i < j.length && i < 64; i++) {
          out.push({ name: root.clip(j[i].name, 15), endpoint: root.clip(j[i].endpoint, 64),
                     junk: j[i].junk === true, awg: j[i].awg === true })
        }
        root.configs = out
      }
    }
  }

  Process {
    id: candProc
    command: [root.cli, "candidates"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var j = root.parse(text)
        if (!(j instanceof Array)) return
        var out = []
        for (var i = 0; i < j.length && i < 32; i++) out.push({ path: root.clip(j[i].path, 512), name: root.clip(j[i].name, 15) })
        root.candidates = out
      }
    }
  }

  Process {
    id: lastProc
    command: ["sh", "-c", "cat \"${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-amnezia/last\" 2>/dev/null"]
    running: true
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._last = root.clip(String(text).trim(), 15) }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {
      id: actionOut
      waitForEnd: true
      onStreamFinished: {
        var j = root.parse(text)
        if (j.ok === false) root.lastError = root.clip(j.error, 300)
        else if (root.busyAction.indexOf("up:") === 0) root._last = root.busyAction.slice(3)
        else if (root.busyAction === "import") root.notice = "Imported " + root.clip(j.name, 15)
        root.busy = false
        root.busyAction = ""
        root.refresh()
        root.refreshLists()
        lastProc.running = true
      }
    }
  }

  Process {
    id: diagProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var j = root.parse(text)
        root.diagnosing = false
        if (j.ok === false) { root.lastError = root.clip(j.error, 300); return }
        root.diagnosis = {
          name: root.clip(j.name, 15),
          handshake: Number(j.handshake),
          loss: Number(j.loss),
          ping: j.ping === true,
          https: j.https === true,
          rx: Number(j.rx) || 0,
          tx: Number(j.tx) || 0
        }
      }
    }
  }
}
