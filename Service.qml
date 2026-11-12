import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Runs the openspec-pulse CLI and holds its report. All judgement (stale, sort,
// once-a-day digest) lives in the CLI; this only runs it and keeps the result.
Item {
  id: root

  property var shell: null
  property var manifest: null
  // Bar widget settings, handed over by BarWidget.qml. `command` overrides the CLI path.
  property var settings: ({})

  readonly property int refreshIntervalMs: 5 * 60 * 1000
  readonly property int maxOutputBytes: 4 * 1024 * 1024
  readonly property string home: Quickshell.env("HOME") || ""

  // mise's shims first, so Ruby 4.0 and openspec come from mise, not Arch's
  // /usr/bin/ruby. /usr/share/omarchy/bin is where `omarchy` and the
  // notification command live.
  readonly property var cliEnvironment: ({
    "PATH": [home + "/.local/share/mise/shims", home + "/.local/bin",
             "/usr/share/omarchy/bin", "/usr/bin", "/bin"].join(":")
  })

  readonly property string bundledCli: localPath(Qt.resolvedUrl("bin/openspec-pulse"))
  readonly property string commandOverride: String((settings && settings.command) || "").trim()
  property string cliOnPath: ""
  readonly property string cli: commandOverride !== "" ? commandOverride : (cliOnPath !== "" ? cliOnPath : bundledCli)

  // The latest good report, kept while a refresh runs or after one fails.
  property var report: null
  // Why the latest refresh failed: CLI missing, non-zero exit or invalid JSON.
  // Never cleared to look like "nothing to report".
  property string cliError: ""
  property string notifyError: ""
  // Why the last `nudges on|off` failed; the switch keeps showing the report's value.
  property string nudgesError: ""
  readonly property bool nudgesBusy: nudgesProc.running
  // Set once `nudges on|off` succeeds, so the switch moves at once instead of
  // after the next full report (about 4 s). Cleared once a report agrees.
  property var nudgesSaved: null
  property bool nudgesRequested: true
  readonly property bool nudges: nudgesSaved !== null ? nudgesSaved : (report ? report.nudges === true : true)
  property bool loading: false
  property bool resolved: false

  readonly property int staleCount: report && report.summary ? report.summary.stale : 0
  readonly property int reportErrors: report && report.summary ? report.summary.errors : 0
  readonly property bool hasError: cliError !== "" || reportErrors > 0

  function localPath(url) {
    var s = String(url)
    if (s.indexOf("file://") === 0) s = decodeURIComponent(s.substring(7))
    return s
  }

  // Runs the CLI through sh so a missing file is exit 127, not a silent no-op.
  function cliCommand(args) {
    return ["sh", "-c", "exec \"$0\" \"$@\"", root.cli].concat(args)
  }

  function refresh() {
    if (!root.resolved || statusProc.running) return
    statusProc.out = ""
    statusProc.err = ""
    root.loading = true
    statusProc.command = cliCommand(["status", "--json"])
    statusProc.running = true
  }

  function sendDigest() {
    if (!root.resolved || notifyProc.running) return
    notifyProc.err = ""
    notifyProc.command = cliCommand(["notify"])
    notifyProc.running = true
  }

  // Opening a change in the default agent, from the list's icon or the change
  // view's button. /opsx:apply goes first so Claude Code expands it, then the
  // preamble as its arguments: omarchy-agent starts Claude in auto mode and
  // sends the prompt at once, so it asks the agent to check before acting.
  readonly property string agentPreamble: "Opened from the openspec-pulse panel to pick this change up again. You can read and check things, but don't apply any change (edits, commits, or commands that change a system) until you've told me what you're going to do and I've confirmed."

  function agentPrompt(change) { return "/opsx:apply " + change.name + " " + agentPreamble }

  // omarchy-agent's terminal opens in the folder it is run from, so cd first.
  // Util.execArgv gives it the login session's PATH; each argument stays data.
  function openAgent(change) {
    if (!change || !change.repo_path) return
    Util.execArgv(["sh", "-c", 'cd "$1" && exec omarchy-agent --prompt "$2"', "sh", change.repo_path, agentPrompt(change)])
  }

  // A failed toggle is a one-off, so its message goes when the panel reopens.
  // CLI and repo errors need no clearing: every refresh works them out again.
  function clearToggleError() { root.nudgesError = "" }

  // The daily digest on or off. Only the notification: the badge is unaffected.
  function setNudges(on) {
    if (!root.resolved || nudgesProc.running) return
    nudgesProc.err = ""
    root.nudgesRequested = on
    nudgesProc.command = cliCommand(["nudges", on ? "on" : "off"])
    nudgesProc.running = true
  }

  function failure(exitCode, err, out) {
    if (exitCode === 127)
      return "Could not find openspec-pulse at " + root.cli + ". Install it on PATH, or set the command setting to its full path. It needs Ruby 4.0, git and openspec."
    var detail = String(err || out || "").trim()
    return "openspec-pulse failed (exit " + exitCode + ")" + (detail ? ": " + detail.substring(0, 1000) : "")
  }

  function applyStatus(text) {
    var parsed = null
    try { parsed = JSON.parse(text) } catch (e) { parsed = null }
    if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.changes) || !parsed.summary) {
      root.cliError = "openspec-pulse printed something that isn't a status report: " + String(text).trim().substring(0, 200)
      return
    }
    root.report = parsed
    root.cliError = ""
    // A report started before the switch was flipped still has the old value;
    // keep the saved one until a report agrees with it.
    if (root.nudgesSaved !== null && parsed.nudges === root.nudgesSaved) root.nudgesSaved = null
  }

  function append(proc, key, data) {
    if (proc[key].length + data.length > root.maxOutputBytes) {
      proc.overflow = true
      proc.signal(9)
      return
    }
    proc[key] += data
  }

  // Find openspec-pulse on PATH once; fall back to the copy in this plugin.
  Process {
    id: whichProc
    running: true
    command: ["sh", "-c", "command -v openspec-pulse || true"]
    environment: root.cliEnvironment
    stdout: StdioCollector {
      id: whichOut
      onStreamFinished: root.cliOnPath = String(whichOut.text || "").trim()
    }
    onExited: {
      root.resolved = true
      root.refresh()
      root.sendDigest()
    }
  }

  Process {
    id: statusProc
    property string out: ""
    property string err: ""
    property bool overflow: false
    running: false
    environment: root.cliEnvironment
    stdout: SplitParser { splitMarker: ""; onRead: function(data) { root.append(statusProc, "out", data) } }
    stderr: SplitParser { splitMarker: ""; onRead: function(data) { root.append(statusProc, "err", data) } }
    onExited: function(exitCode) {
      root.loading = false
      if (statusProc.overflow) {
        statusProc.overflow = false
        root.cliError = "openspec-pulse printed more than " + (root.maxOutputBytes / 1048576) + " MB; ignoring it."
      } else if (exitCode === 0) {
        root.applyStatus(statusProc.out)
      } else {
        root.cliError = root.failure(exitCode, statusProc.err, statusProc.out)
      }
    }
  }

  Process {
    id: notifyProc
    property string out: ""
    property string err: ""
    property bool overflow: false
    running: false
    environment: root.cliEnvironment
    stderr: SplitParser { splitMarker: ""; onRead: function(data) { root.append(notifyProc, "err", data) } }
    onExited: function(exitCode) {
      notifyProc.overflow = false
      root.notifyError = exitCode === 0 ? "" : root.failure(exitCode, notifyProc.err, "")
    }
  }

  Process {
    id: nudgesProc
    property string out: ""
    property string err: ""
    property bool overflow: false
    running: false
    environment: root.cliEnvironment
    stderr: SplitParser { splitMarker: ""; onRead: function(data) { root.append(nudgesProc, "err", data) } }
    onExited: function(exitCode) {
      nudgesProc.overflow = false
      root.nudgesError = exitCode === 0 ? "" : root.failure(exitCode, nudgesProc.err, "")
      root.nudgesSaved = exitCode === 0 ? root.nudgesRequested : null
      root.refresh()
    }
  }

  // The CLI decides whether a digest is due; calling it every tick is cheap.
  Timer {
    interval: root.refreshIntervalMs
    repeat: true
    running: root.resolved
    onTriggered: {
      root.refresh()
      root.sendDigest()
    }
  }

  // For checking the service by hand: `omarchy-shell io.github.jaapie.openspec-pulse.service state`.
  ShellIpc {
    target: "io.github.jaapie.openspec-pulse.service"
    function refresh(): string { root.refresh(); return "ok" }
    function state(): string {
      return JSON.stringify({
        cli: root.cli, loading: root.loading, cliError: root.cliError, notifyError: root.notifyError,
        stale: root.staleCount, errors: root.reportErrors,
        changes: root.report ? root.report.changes.length : null
      })
    }
  }
}
