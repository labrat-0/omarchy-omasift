import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Catalog.js" as Catalog

// Fullscreen, keyboard-first browser over the marketplace catalog. Shares the
// [menu] theme tokens with clipboard and emojis, so a theme that styles those
// styles this too.
Item {
  id: root

  // Injected by the shell's panel loader.
  property var shell: null
  property var manifest: null
  property var service: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false

  property string trustFilter: ""
  property string categoryFilter: ""
  property string sortMode: "stars"
  property string flash: ""

  property var results: []

  readonly property var trustCycle: ["", "verified", "stale", "unreviewed"]
  readonly property var sortCycle: ["stars", "relevance", "updated", "added", "name"]
  property var categoryCycle: [""]

  readonly property var current:
    root.selectedIndex >= 0 && root.selectedIndex < root.results.length
      ? root.results[root.selectedIndex] : null

  // ------------------------------------------------------------ theme tokens

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color borderColor: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", borderColor, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily

  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int contentSpacing: Style.spacing.md
  // One line per result. The description lives in the detail pane, so the
  // list stays scannable instead of becoming a wall of prose.
  readonly property int rowHeight: Math.max(Style.space(26), Style.font.body + Style.spacing.rowPaddingX)
  readonly property int detailWidth: Style.space(300)

  function trustColor(p) {
    if (!p) return root.foreground
    if (p.trust === "verified") return Color.accent
    if (p.trust === "unreviewed") return Color.urgent
    return root.foreground
  }

  // A dim run of "tab filter · copy · esc" reads as prose. Boxing the key
  // makes it look pressable, and pairing it with the value it changes shows
  // what pressing it does without a legend.
  // A dim run of "tab filter · copy · esc" reads as prose. Boxing the key
  // makes it look pressable, and pairing it with the value it changes shows
  // what pressing it does without a legend.
  //
  // An Item wrapping a Row, rather than a Row directly: a MouseArea that
  // fills a Row is sized by the Row and sizes it back, and the whole footer
  // collapses to nothing.
  component KeyHint: Item {
    id: hint
    property string cap: ""
    property string label: ""
    property bool engaged: false
    // Set for the interactive chips; the plain reminders leave it null.
    property var onActivate: null
    readonly property bool hovered: hitArea.containsMouse && hint.onActivate !== null

    implicitWidth: inner.implicitWidth
    implicitHeight: inner.implicitHeight

    Row {
      id: inner
      anchors.verticalCenter: parent.verticalCenter
      spacing: Math.max(2, Style.spacing.controlGap / 2)

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        radius: Math.max(2, root.cornerRadius / 2)
        implicitWidth: capText.implicitWidth + Style.space(9)
        implicitHeight: capText.implicitHeight + Style.space(3)
        color: Util.alpha(Color.accent, hint.hovered ? 0.42 : (hint.engaged ? 0.30 : 0.14))
        border.width: 1
        border.color: Util.alpha(Color.accent, hint.hovered || hint.engaged ? 0.75 : 0.40)

        Text {
          id: capText
          anchors.centerIn: parent
          text: hint.cap
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: hint.label
        color: hint.engaged || hint.hovered ? root.foreground : Util.alpha(root.foreground, 0.62)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // The whole chip is the target, not just the cap. Right-click steps back.
    MouseArea {
      id: hitArea
      anchors.fill: parent
      hoverEnabled: hint.onActivate !== null
      acceptedButtons: hint.onActivate !== null ? (Qt.LeftButton | Qt.RightButton) : Qt.NoButton
      cursorShape: hint.onActivate !== null ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: function (mouse) {
        if (hint.onActivate) hint.onActivate(mouse.button === Qt.RightButton ? -1 : 1)
      }
    }
  }

  // ---------------------------------------------------------------- lifecycle

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.flash = ""
    root.refreshCategories()
    root.rebuild()
    // Without this the view keeps the scroll offset from the last summon and
    // opens showing row four with the selection off-screen above it.
    listView.positionViewAtBeginning()
    if (root.service && root.service.isStale() && !root.service.refreshing) root.service.refresh()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.flash = ""
  }

  function toggle(arg) {
    if (root.opened) root.close()
    else root.open(arg && String(arg).length ? arg : "{}")
  }

  function ping(arg) { return "ok" }

  // ------------------------------------------------------------------- model

  function refreshCategories() {
    if (!root.service) return
    var cats = root.service.categories()
    var out = [""]
    for (var i = 0; i < cats.length; i++) out.push(cats[i].name)
    root.categoryCycle = out
  }

  function rebuild() {
    if (!root.service || !root.service.loaded) { root.results = []; return }
    root.results = root.service.search(root.filterText, {
      trust: root.trustFilter,
      category: root.categoryFilter
    }, root.sortMode)
    if (root.selectedIndex >= root.results.length)
      root.selectedIndex = Math.max(0, root.results.length - 1)
  }

  function setFilter(text) {
    root.filterText = text
    root.selectedIndex = 0
    root.flash = ""
    root.rebuild()
    listView.positionViewAtBeginning()
  }

  function cycle(list, value, step) {
    var i = list.indexOf(value)
    if (i === -1) i = 0
    var n = (i + step + list.length) % list.length
    return list[n]
  }

  function cycleTrust(step) {
    root.trustFilter = root.cycle(root.trustCycle, root.trustFilter, step)
    root.selectedIndex = 0
    root.rebuild()
    listView.positionViewAtBeginning()
  }

  function cycleSort(step) {
    root.sortMode = root.cycle(root.sortCycle, root.sortMode, step)
    root.selectedIndex = 0
    root.rebuild()
    listView.positionViewAtBeginning()
  }

  function cycleCategory(step) {
    root.categoryFilter = root.cycle(root.categoryCycle, root.categoryFilter, step)
    root.selectedIndex = 0
    root.rebuild()
    listView.positionViewAtBeginning()
  }

  function select(delta) {
    if (root.results.length === 0) return
    root.selectedIndex = Math.max(0, Math.min(root.results.length - 1, root.selectedIndex + delta))
    listView.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (root.results.length === 0) return
    root.selectedIndex = Math.max(0, Math.min(root.results.length - 1, index))
    listView.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  // ----------------------------------------------------------------- actions

  // Deliberately copy rather than run. Installing is `omarchy plugin add`'s
  // job: it warns, shows the source, and lands the plugin disabled for review.
  // A browser that shelled out to it would be asking you to trust two things
  // at once, and would put this plugin in the capability-review bucket it
  // exists to warn you about.
  function copyInstall() {
    var p = root.current
    if (!p) return
    if (!p.install) {
      root.flash = p.note ? p.note : "No install command — this listing needs manual setup."
      return
    }
    // execArgv, not a composed shell string: every value here came out of a
    // downloaded catalog, and argv means it stays literal rather than being
    // re-tokenized by a shell.
    Util.execArgv(["wl-copy", "--", p.install])
    root.flash = "Copied: " + p.install
  }

  function copyRepo() {
    var p = root.current
    if (!p || !p.repo) return
    Util.execArgv(["wl-copy", "--", p.repo])
    root.flash = "Copied: " + p.repo
  }

  function openRepo() {
    var p = root.current
    if (!p || !p.repo) return
    // The fetcher already drops anything that is not https, but this is the
    // call that reaches a desktop handler, so it checks for itself rather than
    // trusting a file written by something else.
    if (String(p.repo).indexOf("https://") !== 0) {
      root.flash = "Not a web address, refusing to open it"
      return
    }
    Util.execArgv(["xdg-open", p.repo])
    root.flash = "Opened " + Catalog.repoLabel(p.repo)
  }

  onServiceChanged: { root.refreshCategories(); root.rebuild() }

  Connections {
    target: root.service
    function onCatalogChanged() {
      root.refreshCategories()
      root.rebuild()
    }
  }

  // -------------------------------------------------------------------- view

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omasift"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: root.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: card
      width: Math.min(Style.space(860), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(520), panel.height - Style.gapsOut * 2)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.close()
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            root.cycleTrust(event.modifiers & Qt.ShiftModifier ? -1 : 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Backtab) {
            root.cycleTrust(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            // Left/Right were free, and every letter belongs to the search
            // box — so the filters use the keys you cannot type instead of
            // modifier chords.
            root.cycleCategory(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.cycleCategory(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_F2) {
            root.cycleSort(1)
            event.accepted = true
          } else if (event.key === Qt.Key_F5) {
            if (root.service) { root.service.refresh(); root.flash = "Refreshing…" }
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1); event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1); event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-8); event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(8); event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectAbsolute(0); event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectAbsolute(root.results.length - 1); event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (event.modifiers & Qt.AltModifier) root.openRepo()
            else if (event.modifiers & Qt.ShiftModifier) root.copyRepo()
            else root.copyInstall()
            event.accepted = true
          } else if (event.text && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        Column {
          // BorderSurface exposes its padded region as content insets; filling
          // the raw parent instead puts the header count and the footer keys
          // under the border, where they get clipped.
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset
          spacing: root.contentSpacing

          // ------------------------------------------------------- header
          // One line: what you typed, and how much of the catalog survived it.
          Item {
            id: header
            width: parent.width
            height: Math.max(searchText.implicitHeight, countText.implicitHeight)

            Text {
              id: searchText
              anchors.left: parent.left
              anchors.right: countText.left
              anchors.rightMargin: Style.spacing.controlGap
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: "󰍉  " + (root.filterText.length ? root.filterText : "search the marketplace")
              color: root.filterText.length ? root.foreground : Util.alpha(root.foreground, 0.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
            }

            Text {
              id: countText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: {
                if (!root.service) return ""
                if (root.service.refreshing) return "refreshing"
                if (!root.service.loaded) return "loading"
                var n = root.service.summary.total
                if (!n) return "no catalog — ctrl+r"
                return root.results.length === n
                  ? String(n) : (root.results.length + " of " + n)
              }
              // The only place the catalog size is shown now that the bar
              // pill is icon-only, so it reads a shade stronger than a hint.
              color: Util.alpha(root.foreground, 0.66)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Util.alpha(root.borderColor, 0.28)
          }

          // -------------------------------------------------- list + detail
          Item {
            width: parent.width
            height: parent.height - parent.spacing * 4
                    - header.height - 2 - footer.height

            ListView {
              id: listView
              width: parent.width - root.detailWidth - root.contentSpacing
              height: parent.height
              clip: true
              model: root.results
              currentIndex: root.selectedIndex
              boundsBehavior: Flickable.StopAtBounds

              delegate: Rectangle {
                required property var modelData
                required property int index

                width: ListView.view.width
                height: root.rowHeight
                radius: root.cornerRadius
                color: index === root.selectedIndex ? root.selectedBackground : "transparent"

                readonly property bool sel: index === root.selectedIndex
                readonly property color fg: sel ? root.selectedText : root.foreground

                MouseArea {
                  anchors.fill: parent
                  onClicked: root.selectAbsolute(index)
                  onDoubleClicked: { root.selectAbsolute(index); root.copyInstall() }
                }

                Text {
                  anchors.left: parent.left
                  anchors.right: badges.left
                  anchors.rightMargin: Style.spacing.controlGap
                  anchors.leftMargin: Style.spacing.rowPaddingX
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                  text: modelData.name
                  color: parent.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Row {
                  id: badges
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.rowPaddingX
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.controlGap

                  Text {
                    visible: root.service !== null && root.service.isInstalled(modelData.id)
                    text: "installed"
                    color: Util.alpha(parent.parent.fg, 0.5)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    visible: modelData.stars > 0
                    text: "\u2605" + Catalog.starLabel(modelData.stars)
                    color: Util.alpha(parent.parent.fg, 0.5)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    text: Catalog.trustShort(modelData)
                    color: parent.parent.sel ? root.selectedText : root.trustColor(modelData)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            // ------------------------------------------------------ detail
            Rectangle {
              width: root.detailWidth
              height: parent.height
              anchors.right: parent.right
              radius: root.cornerRadius
              color: Util.alpha(root.borderColor, 0.10)

              Column {
                anchors.fill: parent
                anchors.margins: Style.spacing.panelPadding
                spacing: Style.spacing.labelGap
                visible: root.current !== null

                Text {
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: root.current ? root.current.name : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }

                Text {
                  width: parent.width
                  elide: Text.ElideRight
                  text: root.current ? root.current.id : ""
                  color: Util.alpha(root.foreground, 0.6)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: root.current ? root.current.desc : ""
                  color: Util.alpha(root.foreground, 0.85)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Rectangle {
                  width: parent.width; height: 1
                  color: Util.alpha(root.borderColor, 0.28)
                }

                Text {
                  width: parent.width
                  text: root.current ? Catalog.trustLabel(root.current) : ""
                  color: root.trustColor(root.current)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Text {
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: root.current ? Catalog.trustNote(root.current) : ""
                  color: Util.alpha(root.foreground, 0.75)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Rectangle {
                  width: parent.width; height: 1
                  color: Util.alpha(root.borderColor, 0.28)
                }

                Text {
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: {
                    var p = root.current
                    if (!p) return ""
                    var bits = []
                    if (p.author) bits.push("by " + p.author)
                    if (p.version) bits.push("v" + p.version)
                    if (p.kind) bits.push(p.kind)
                    if (p.cat) bits.push(p.cat)
                    if (p.license) bits.push(p.license)
                    if (p.stars) bits.push("★ " + Catalog.starLabel(p.stars))
                    if (p.updated) bits.push("updated " + Catalog.ageLabel(p.updated, Date.now()))
                    if (p.status === "Manual setup") bits.push("manual setup")
                    return bits.join("  ·  ")
                  }
                  color: Util.alpha(root.foreground, 0.7)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  width: parent.width
                  elide: Text.ElideRight
                  text: root.current ? Catalog.repoLabel(root.current.repo) : ""
                  color: Util.alpha(root.foreground, 0.7)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  width: parent.width
                  wrapMode: Text.WrapAnywhere
                  text: root.current && root.current.install ? root.current.install : ""
                  color: Util.alpha(root.foreground, 0.9)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                anchors.centerIn: parent
                visible: root.current === null
                width: parent.width - Style.spacing.panelPadding * 2
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: root.service && root.service.loaded
                  ? "Nothing matches that." : "Loading the catalog…"
                color: Util.alpha(root.foreground, 0.55)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Util.alpha(root.borderColor, 0.28)
          }

          // -------------------------------------------------------- footer
          // Each filter sits next to the key that cycles it, and lights up
          // when it is holding something back.
          Item {
            id: footer
            width: parent.width
            height: Math.max(leftHints.implicitHeight, rightHints.implicitHeight)

            Row {
              id: leftHints
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.md
              visible: root.flash.length === 0

              KeyHint {
                cap: "tab"
                engaged: root.trustFilter !== ""
                onActivate: function (step) { root.cycleTrust(step) }
                label: root.trustFilter === ""
                  ? "any review state"
                  : Catalog.trustShort({ trust: root.trustFilter })
              }
              KeyHint {
                cap: "\u2190\u2192"
                engaged: root.categoryFilter !== ""
                onActivate: function (step) { root.cycleCategory(step) }
                label: root.categoryFilter === "" ? "all categories" : root.categoryFilter
              }
              KeyHint {
                cap: "f2"
                engaged: root.sortMode !== "stars"
                onActivate: function (step) { root.cycleSort(step) }
                label: root.sortMode
              }
            }

            Text {
              anchors.left: parent.left
              anchors.right: rightHints.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              visible: root.flash.length > 0
              elide: Text.ElideRight
              text: root.flash
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              id: rightHints
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.md

              KeyHint { cap: "\u21b5"; label: "copy install" }
              KeyHint {
                cap: "f5"
                label: "refresh"
                onActivate: function (step) {
                  if (root.service) { root.service.refresh(); root.flash = "Refreshing\u2026" }
                }
              }
              KeyHint { cap: "esc"; label: "close" }
            }
          }
        }
      }
    }
  }
}
