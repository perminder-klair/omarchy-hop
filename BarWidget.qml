import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The bar half of Omassh: one icon that opens the machine list.
//
// There is no connection state to show — a session lives in a terminal
// window the user can see, not in this process — so the icon only reflects
// whether there is anything saved to connect to.
BarWidget {
  id: root
  moduleName: "co.klair.omassh"

  readonly property var service: bar?.shell?.serviceFor("co.klair.omassh")
  readonly property int hostCount: service ? service.count : 0
  readonly property bool showCount: setting("showCount", false)

  // A server stack rather than a terminal glyph: the bar already carries
  // terminal-shaped icons, and this widget is about machines, not shells.
  readonly property string glyph: "󰒋"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---- panel plumbing, same shape the bar expects from any widget --------

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = root.service
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onServiceChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // BarIconButton, not WidgetButton: WidgetButton derives hasVisualContent
  // from its text, so an icon-only widget would collapse to zero width.
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showCount && root.hostCount > 0 ? root.glyph + "  " + root.hostCount : root.glyph
    tooltipText: root.hostCount === 0
      ? "No SSH machines saved yet"
      : (root.hostCount === 1 ? "1 SSH machine" : root.hostCount + " SSH machines")

    readonly property color baseForeground: root.bar ? root.bar.barForeground : Color.foreground
    foreground: root.hostCount > 0 ? baseForeground : Qt.darker(baseForeground, 2.0)

    onPressed: root.togglePanel()

    Behavior on foreground {
      ColorAnimation { duration: 160 }
    }
  }
}
