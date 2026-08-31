import QtQuick
import qs.Ui
import "Catalog.js" as Catalog

// The pill. Deliberately quiet: an icon, and optionally how many listings the
// catalog holds. Everything interesting happens in the browser it opens.
BarWidget {
  id: root
  moduleName: "io.github.labrat-0.omasift"

  readonly property string pluginId: "io.github.labrat-0.omasift"
  property var service: null

  readonly property bool showCount: root.setting("showCount", true) === true
  readonly property int refreshHours: Math.max(1, Number(root.setting("refreshHours", 24)) || 24)

  readonly property var summary: root.service ? root.service.summary : null
  readonly property bool ready: root.service !== null && root.service.loaded

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
    if (root.service) root.service.refreshHours = root.refreshHours
  }

  function openBrowser() {
    // Prefer the in-process call; fall back to IPC if the host predates it.
    if (root.bar && root.bar.shell && typeof root.bar.shell.toggle === "function")
      root.bar.shell.toggle(root.pluginId, "{}")
    else if (root.bar)
      root.bar.run("omarchy-shell shell toggle " + root.pluginId + " '{}'")
  }

  // BarIconButton hides its label by design, so the count rides along in the
  // button text rather than as a second element.
  function buttonText() {
    if (!root.showCount || !root.ready || !root.service.count) return "󰏖"
    // Not starLabel: rounding 1995 listings to "2k" contradicts the exact
    // figure the browser header shows two clicks later.
    return "󰏖 " + root.service.count
  }

  function tooltip() {
    if (!root.service) return "OmaSift — starting"
    if (root.service.refreshing) return "OmaSift — refreshing the catalog"
    if (!root.service.loaded) return "OmaSift — loading"
    if (root.service.lastError) return "OmaSift — " + root.service.lastError
    var s = root.summary
    if (!s || !s.total) return "OmaSift — no catalog yet"
    return s.total + " plugins · " + s.verified + " verified · "
      + s.stale + " moved since review · " + s.unreviewed + " never reviewed"
  }

  onServiceChanged: root.pushSettings()
  onRefreshHoursChanged: root.pushSettings()
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
    text: root.buttonText()
    active: root.service !== null && root.service.refreshing
    tooltipText: root.tooltip()
    onPressed: function (b) {
      if (b === Qt.MiddleButton) { if (root.service) root.service.refresh() }
      else root.openBrowser()
    }
  }
}
