import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.jeremylongshore.wait-state"

  property var service: null

  function resolveService() {
    if (root.service || !root.bar || !root.bar.shell) return
    if (typeof root.bar.shell.serviceFor !== "function") return
    var candidate = root.bar.shell.serviceFor(root.moduleName)
    if (candidate) {
      root.service = candidate
      root.injectPanel()
    }
  }

  Timer {
    interval: 500
    running: root.service === null
    repeat: true
    triggeredOnStart: true
    onTriggered: root.resolveService()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = root.service
  }

  onServiceChanged: injectPanel()
  onBarChanged: { root.resolveService(); root.injectPanel() }
  onSettingsChanged: root.injectPanel()

  function refresh() {
    if (root.service && typeof root.service.sample === "function") root.service.sample()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing:
    panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

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

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: panelLoader.item ? panelLoader.item.label : "PSI …"
    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    active: panelLoader.item ? panelLoader.item.isAlert === true : false
    tooltipText: panelLoader.item ? panelLoader.item.tooltip : "Wait State is starting"

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
