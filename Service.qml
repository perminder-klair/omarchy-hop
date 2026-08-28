import QtQuick
import Quickshell
import Quickshell.Io

// Headless half of Hop: owns the machine list and opens sessions.
//
// The store is a plain JSON file managed by bin/hop, not by this file.
// Keeping every write behind the CLI means the panel, a keybinding and a
// terminal all mutate the same thing the same way, and the shell process
// never has to be the authority on what a valid entry looks like.
//
// Nothing here holds a password. `hop connect` hands ssh a real tty in
// the user's own terminal, so authentication happens where it always did.
Item {
  id: root

  // Injected by omarchy-shell's service loader.
  property var shell: null
  property var manifest: null

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")
  readonly property string ctl: pluginDir + "bin/hop"
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/hop"
  readonly property string storePath: configDir + "/hosts.json"

  // ---- live state, read by BarWidget.qml and Panel.qml -------------------

  // [{id, name, host, user, port, identity, init, forwardAgent}]
  property var hosts: []
  property string lastError: ""
  property string lastConnected: ""

  readonly property int count: hosts.length

  // The CLI already caps the list and validates every field, so this is the
  // second of two identical limits rather than the only one: a list arriving
  // over stdout still cannot make the panel build an unbounded number of rows.
  readonly property int maxHosts: 256

  function hostById(id) {
    for (var i = 0; i < hosts.length; i++)
      if (String(hosts[i].id) === String(id)) return hosts[i]
    return null
  }

  // ---- reading -----------------------------------------------------------

  function refresh() {
    if (listProc.running) return
    listProc.command = [root.ctl, "list"]
    listProc.running = true
  }

  // ---- writing -----------------------------------------------------------
  //
  // add() and save() take the same field object the panel form produces, so
  // the form does not need to know which flags the CLI spells how.

  function _flagsFor(fields) {
    var argv = []
    if (fields.name !== undefined) argv.push("--name", String(fields.name))
    if (fields.host !== undefined) argv.push("--host", String(fields.host))
    if (fields.user !== undefined) argv.push("--user", String(fields.user))
    if (fields.port !== undefined) argv.push("--port", String(Number(fields.port) || 22))
    if (fields.identity !== undefined) argv.push("--identity", String(fields.identity))
    if (fields.path !== undefined) argv.push("--path", String(fields.path))
    if (fields.init !== undefined) argv.push("--init", String(fields.init))
    if (fields.forwardAgent !== undefined) argv.push(fields.forwardAgent ? "--agent" : "--no-agent")
    return argv
  }

  function add(fields) {
    root.lastError = ""
    writeProc.command = [root.ctl, "add"].concat(_flagsFor(fields))
    writeProc.running = true
  }

  function save(id, fields) {
    if (!id) return add(fields)
    root.lastError = ""
    writeProc.command = [root.ctl, "set", String(id)].concat(_flagsFor(fields))
    writeProc.running = true
  }

  function remove(id) {
    root.lastError = ""
    writeProc.command = [root.ctl, "rm", String(id)]
    writeProc.running = true
  }

  // ---- connecting --------------------------------------------------------

  function connect(id) {
    var entry = root.hostById(id)
    if (!entry) return false
    root.lastError = ""
    root.lastConnected = String(entry.name || entry.host)
    connectProc.command = [root.ctl, "connect", String(id)]
    connectProc.running = true
    return true
  }

  // Files opens the same machine over SFTP. Deliberately a separate process
  // from connect(): gvfs holds its own connection and its own auth prompt, so
  // browsing does not depend on a terminal session being up, or vice versa.
  function browse(id) {
    var entry = root.hostById(id)
    if (!entry) return false
    root.lastError = ""
    filesProc.command = [root.ctl, "files", String(id)]
    filesProc.running = true
    return true
  }

  Process {
    id: listProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var list = JSON.parse(text)
          if (!Array.isArray(list)) list = []
          root.hosts = list.length > root.maxHosts ? list.slice(0, root.maxHosts) : list
        } catch (e) {
          root.hosts = []
          root.lastError = "Could not read " + root.storePath
        }
      }
    }
  }

  Process {
    id: writeProc
    running: false
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var line = String(text).trim()
        if (line !== "") root.lastError = line.replace(/^hop: /, "")
      }
    }
    onExited: root.refresh()
  }

  Process {
    id: connectProc
    running: false
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var line = String(text).trim()
        if (line !== "") root.lastError = line.replace(/^hop: /, "")
      }
    }
  }

  Process {
    id: filesProc
    running: false
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var line = String(text).trim()
        if (line !== "") root.lastError = line.replace(/^hop: /, "")
      }
    }
  }

  // Poll the short-lived CLI rather than opening or watching the predictable
  // store path in this long-lived shell process. The CLI's reader uses a
  // nonblocking, no-follow open, validates the held descriptor, caps both the
  // file and output sizes, and returns only parsed JSON whose host count is
  // capped and whose every field has been type-, length- and range-checked.
  Timer {
    interval: 10000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Lets a machine be opened straight from a keybinding:
  //   omarchy-shell hop connect "Prod web"
  IpcHandler {
    target: "hop"

    // Resolved by the CLI rather than against root.hosts: a keybinding can
    // fire seconds after a machine was added elsewhere, and the snapshot in
    // this process is only as fresh as the last poll.
    function connect(name: string): string {
      connectProc.command = [root.ctl, "connect", name]
      connectProc.running = true
      return "connecting to " + name
    }

    function files(name: string): string {
      filesProc.command = [root.ctl, "files", name]
      filesProc.running = true
      return "browsing " + name
    }

    function list(): string {
      var out = []
      for (var i = 0; i < root.hosts.length; i++) out.push(String(root.hosts[i].name || root.hosts[i].host))
      return out.join("\n")
    }

    function refresh(): void { root.refresh() }
  }
}
