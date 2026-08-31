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

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir:
    (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/omasift"
  readonly property string catalogPath: stateDir + "/catalog.json"
  readonly property string pluginDir:
    manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
  readonly property string fetchScript: pluginDir ? pluginDir + "/bin/omasift-fetch" : ""

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

  FileView {
    id: catalogFile
    path: root.catalogPath
    watchChanges: true
    atomicWrites: false          // only the helper writes this file
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.adopt(text())
    onLoadFailed: {
      // First run: nothing fetched yet. Say so, then go get it.
      root.adopt("")
      if (!root.refreshing) root.refresh()
    }
  }

  // --------------------------------------------------------------- refresh

  function refresh() {
    if (root.refreshing) return
    if (!root.fetchScript) { root.lastError = "plugin directory unknown"; return }
    root.refreshing = true
    root.lastError = ""
    fetchProc.command = [root.fetchScript, "--quiet"]
    fetchProc.running = true
    fetchGuard.restart()
  }

  Process {
    id: fetchProc
    running: false
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(this.text || "").trim()
        if (t) root.lastError = t.split("\n").pop()
      }
    }
    onExited: function (code) {
      fetchGuard.stop()
      root.refreshing = false
      if (code !== 0) {
        if (!root.lastError) root.lastError = "refresh failed (exit " + code + ")"
        return
      }
      // The watcher usually catches the new file on its own; reload anyway so
      // a missed inotify event cannot leave a stale view behind a successful
      // fetch.
      catalogFile.reload()
    }
  }

  // The helper sets its own socket timeout. This only covers the helper
  // process itself wedging, which that timeout cannot speak for.
  Timer {
    id: fetchGuard
    interval: 90000
    repeat: false
    onTriggered: {
      if (fetchProc.running) {
        fetchProc.running = false
        root.lastError = "refresh timed out"
      }
    }
  }

  // Checked hourly rather than scheduled once, so a laptop that was asleep
  // through its window still refreshes shortly after it wakes.
  Timer {
    interval: 3600000
    repeat: true
    running: true
    triggeredOnStart: false
    onTriggered: if (root.loaded && root.isStale()) root.refresh()
  }
}
