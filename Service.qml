import QtQuick
import Quickshell
import Quickshell.Io
import "Catalog.js" as Catalog

// Owns the catalog: fetching it, holding the parsed result, and answering
// queries for both surfaces. The bar widget and the browser are views over
// this one instance, so a refresh in either is a refresh in both.
Item {
  id: root

  // Injected by the shell loader.
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property string pluginDir:
    manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
  // One helper, two modes: it fetches the catalog and it reads the cache back.
  // Where that cache lives is its business, not the shell's — it resolves the
  // path itself so the checks and the open happen in the same place.
  readonly property string helper: pluginDir ? pluginDir + "/bin/omasift-fetch" : ""

  // Seconds of grace before the guard starts escalating. The helper enforces
  // its own end-to-end deadline and a SIGALRM backstop, so these only have to
  // cover the process itself wedging past both.
  readonly property int fetchBudget: 120
  readonly property int readBudget: 15

  property var index: Catalog.emptyIndex()
  property bool loaded: false
  property bool refreshing: false
  property string lastError: ""
  property int refreshHours: 24
  // "lab" (the plugin's own look) or "shell" (follow the Omarchy theme).
  property string palette: "lab"

  readonly property var summary: Catalog.summarize(root.index.plugins)
  readonly property int count: root.index.count

  signal catalogChanged()

  // ------------------------------------------------------------------ query

  function search(query, filters, sort) {
    return Catalog.search(root.index.plugins, query, filters, sort)
  }

  function categories() { return Catalog.categories(root.index.plugins) }
  function kinds() { return Catalog.kinds(root.index.plugins) }

  // The registry already knows what is on disk, so "installed" costs a lookup
  // rather than a directory walk.
  function isInstalled(id) {
    if (!root.pluginRegistry || !root.pluginRegistry.installedPlugins) return false
    return root.pluginRegistry.installedPlugins[String(id)] !== undefined
  }

  function isEnabled(id) {
    if (!root.pluginRegistry || typeof root.pluginRegistry.isEnabled !== "function") return false
    return root.pluginRegistry.isEnabled(String(id)) === true
  }

  function ageHours() {
    if (!root.index.fetchedAt) return -1
    var t = Date.parse(root.index.fetchedAt)
    if (isNaN(t)) return -1
    return (Date.now() - t) / 3600000
  }

  function isStale() {
    var h = root.ageHours()
    return h < 0 || h >= root.refreshHours
  }

  // ---------------------------------------------------------------- loading

  function adopt(raw) {
    var next = Catalog.parseIndex(raw)
    // A failed parse on a catalog we already hold is a bad write, not an empty
    // marketplace. Keep what works and say so rather than blanking the UI.
    if (!next.ok && root.index.ok) {
      root.lastError = "catalog unreadable; keeping the previous copy"
      root.loaded = true
      return
    }
    root.index = next
    root.loaded = true
    if (next.ok) root.lastError = ""
    root.catalogChanged()
  }

  // Bounded on both sides: the helper caps what it writes to stderr, and this
  // caps what is kept from it, so neither can grow this string without limit.
  function noteError(text) {
    var t = String(text || "").slice(0, 2048).trim()
    if (t) root.lastError = t.split("\n").pop().slice(0, 240)
  }

  // Reading the cache goes through the helper rather than a FileView. The
  // helper opens it O_NOFOLLOW relative to a directory descriptor it verified
  // is ours, rejects anything that is not a regular file we own, caps the read,
  // and re-validates every field before printing it. A FileView opens a bare
  // pathname with no size bound and follows whatever symlink it finds there.
  function load() {
    if (readProc.running) return
    if (!root.helper) { root.lastError = "plugin directory unknown"; return }
    readProc.command = [root.helper, "--read"]
    readProc.running = true
    readGuard.ticks = 0
    readGuard.restart()
  }

  // --------------------------------------------------------------- refresh

  function refresh() {
    if (root.refreshing) return
    if (!root.helper) { root.lastError = "plugin directory unknown"; return }
    root.refreshing = true
    root.lastError = ""
    fetchProc.command = [root.helper, "--quiet"]
    fetchProc.running = true
    fetchGuard.ticks = 0
    fetchGuard.restart()
  }

  // -------------------------------------------------------- process lifetime

  // Deterministic escalation on a helper that will not finish: SIGTERM at the
  // budget so it can still unlink its staging file, SIGKILL five seconds later,
  // and only then stop waiting. Clearing `running` comes last rather than
  // first, so the exit is delivered to onExited and reaped instead of being
  // dropped while the process is still alive.
  //
  // The helper puts itself in its own process group and spawns nothing, so its
  // pid is the whole group. Returns true once the guard should stop.
  function escalate(proc, ticks, budget, label) {
    if (ticks === budget) {
      root.lastError = label + " timed out"
      proc.signal(15)
      return false
    }
    if (ticks === budget + 5) {
      proc.signal(9)
      return false
    }
    if (ticks >= budget + 10) {
      proc.running = false
      return true
    }
    return false
  }

  Process {
    id: readProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.adopt(String(this.text || ""))
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.noteError(this.text)
    }
    onExited: function (code) {
      readGuard.stop()
      readGuard.ticks = 0
      if (code === 0) return
      // Nothing cached yet, or the cache failed the helper's own checks. Either
      // way there is no index to show, so say so and go fetch one.
      root.loaded = true
      if (!root.refreshing) root.refresh()
    }
  }

  Timer {
    id: readGuard
    interval: 1000
    repeat: true
    property int ticks: 0
    onTriggered: {
      readGuard.ticks += 1
      if (root.escalate(readProc, readGuard.ticks, root.readBudget, "catalog read")) {
        readGuard.stop()
        readGuard.ticks = 0
      }
    }
  }

  Process {
    id: fetchProc
    running: false
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.noteError(this.text)
    }
    onExited: function (code, status) {
      fetchGuard.stop()
      fetchGuard.ticks = 0
      root.refreshing = false
      // A helper killed by a signal can still report exit code 0, so the exit
      // status gets a say as well as the code.
      if (code !== 0 || status !== 0) {
        if (!root.lastError) {
          root.lastError = status !== 0
            ? "refresh was killed before it finished"
            : "refresh failed (exit " + code + ")"
        }
        return
      }
      root.load()
    }
  }

  Timer {
    id: fetchGuard
    interval: 1000
    repeat: true
    property int ticks: 0
    onTriggered: {
      fetchGuard.ticks += 1
      if (root.escalate(fetchProc, fetchGuard.ticks, root.fetchBudget, "refresh")) {
        fetchGuard.stop()
        fetchGuard.ticks = 0
        root.refreshing = false
      }
    }
  }

  Component.onCompleted: root.load()

  // A shell reload, a disabled plugin, or a removed bar widget destroys this
  // item. Without this the helper would outlive whatever started it.
  Component.onDestruction: {
    fetchGuard.stop()
    readGuard.stop()
    if (fetchProc.running) { fetchProc.signal(15); fetchProc.running = false }
    if (readProc.running) { readProc.signal(15); readProc.running = false }
  }

  // Checked hourly rather than scheduled once, so a laptop that was asleep
  // through its window still refreshes shortly after it wakes. A fetch someone
  // ran by hand from a terminal is picked up on the same tick, which is what
  // replaced the FileView's inotify watch.
  Timer {
    interval: 3600000
    repeat: true
    running: true
    triggeredOnStart: false
    onTriggered: {
      if (!root.loaded) return
      if (root.isStale()) root.refresh()
      else root.load()
    }
  }
}
