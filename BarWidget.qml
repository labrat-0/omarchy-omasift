import QtQuick
import qs.Ui

// The pill. Deliberately quiet: an icon and nothing else. Everything worth
// reading — the count, the review-state breakdown — is in the browser it
// opens, where there is room to read it.
BarWidget {
  id: root
  moduleName: "io.github.labrat-0.omasift"

  readonly property string pluginId: "io.github.labrat-0.omasift"
  property var service: null

  readonly property int refreshHours: Math.max(1, Number(root.setting("refreshHours", 24)) || 24)
  readonly property string palette: String(root.setting("palette", "lab"))

  readonly property var summary: root.service ? root.service.summary : null

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // `_services` is populated asynchronously after widget construction, so the
  // first lookup usually misses. Poll until it lands, then stop.
  function findService() {
    if (root.service) return
    if (root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function")
      root.service = root.bar.shell.serviceFor(root.pluginId)
  }

  function pushSettings() {
    if (!root.service) return
    root.service.refreshHours = root.refreshHours
    root.service.palette = root.palette
  }

  function openBrowser() {
    // Prefer the in-process call; fall back to IPC if the host predates it.
    if (root.bar && root.bar.shell && typeof root.bar.shell.toggle === "function")
      root.bar.shell.toggle(root.pluginId, "{}")
    else if (root.bar)
      root.bar.run("omarchy-shell shell toggle " + root.pluginId + " '{}'")
  }

  // Status only. How many listings there are, and how they break down, is
  // something you read in the browser — not a number parked in the bar.
  function tooltip() {
    if (!root.service) return "OmaSift — starting"
    if (root.service.refreshing) return "OmaSift — refreshing the catalog"
    if (!root.service.loaded) return "OmaSift — loading"
    if (root.service.lastError) return "OmaSift — " + root.service.lastError
    if (!root.summary || !root.summary.total) return "OmaSift — no catalog yet"
    return "Search the plugin marketplace"
  }

  onServiceChanged: root.pushSettings()
  onRefreshHoursChanged: root.pushSettings()
  onPaletteChanged: root.pushSettings()
  Component.onCompleted: root.findService()

  Timer {
    interval: 400
    repeat: true
    running: root.service === null
    onTriggered: root.findService()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰏖"
    active: root.service !== null && root.service.refreshing
    tooltipText: root.tooltip()
    onPressed: function (b) {
      if (b === Qt.MiddleButton) { if (root.service) root.service.refresh() }
      else root.openBrowser()
    }
  }
}
