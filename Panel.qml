import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.jeremylongshore.wait-state"
  ipcTarget: "io.github.jeremylongshore.wait-state"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property var service: null
  property int revision: 0
  property double nowMs: Date.now()

  readonly property var snapshot: {
    root.revision
    return root.service ? root.service.snapshot : Model.emptySnapshot(0)
  }
  readonly property var history: {
    root.revision
    return root.service ? root.service.history : []
  }
  readonly property string selectedResource: {
    root.revision
    return root.service ? root.service.selectedResource : "cpu"
  }
  readonly property string barResource: {
    root.revision
    return root.service ? root.service.barResource : "Worst"
  }
  readonly property string historyWindow: {
    root.revision
    return root.service ? root.service.historyWindow : "1 hour"
  }
  readonly property int warningPercent: {
    root.revision
    return root.service ? root.service.warningPercent : 5
  }
  readonly property int criticalPercent: {
    root.revision
    return root.service ? root.service.criticalPercent : 20
  }
  readonly property string lastError: {
    root.revision
    return root.service ? String(root.service.lastError || "") : "service unavailable"
  }
  readonly property bool sampling: {
    root.revision
    return root.service ? root.service.sampling === true : false
  }

  readonly property string currentName: Model.selectedResource(snapshot, barResource)
  readonly property real currentValue: currentName && snapshot.resources[currentName]
    ? snapshot.resources[currentName].some.avg10 : 0
  readonly property string currentSeverity:
    Model.severity(currentValue, warningPercent, criticalPercent)
  readonly property string label: Model.pillText(snapshot, barResource)
  readonly property string tooltip:
    Model.tooltipText(snapshot, barResource, warningPercent, criticalPercent, nowMs, lastError)
  readonly property bool isAlert: currentSeverity !== "normal"
  readonly property var chartSeries:
    Model.historySeries(history, selectedResource, historyWindow, nowMs, 48)
  readonly property var chartStats: Model.seriesStats(chartSeries)

  function levelColor(level) {
    if (level === "critical") return Qt.hsla(0.0, 0.68, 0.58, 1.0)
    if (level === "warning") return Qt.hsla(0.11, 0.72, 0.58, 1.0)
    return root.bar ? root.bar.foreground : Color.foreground
  }

  function resourceValue(name, field, window) {
    if (!root.snapshot.resources[name] || !root.snapshot.resources[name].available) return 0
    return root.snapshot.resources[name][field][window]
  }

  function choose(name) {
    if (root.service && typeof root.service.chooseResource === "function")
      root.service.chooseResource(name)
  }

  function moveSelection(delta) {
    var resources = ["cpu", "memory", "io"]
    var index = resources.indexOf(root.selectedResource)
    if (index < 0) index = 0
    index = (index + (delta < 0 ? -1 : 1) + resources.length) % resources.length
    root.choose(resources[index])
  }

  function refresh() {
    if (root.service && typeof root.service.sample === "function") root.service.sample()
  }

  function open() {
    root.controller.show()
    root.refresh()
  }

  function openFromHotkey() {
    root.controller.show()
    root.refresh()
  }

  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.openFromHotkey() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onPressureChanged() { root.revision++ }
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void {
      if (root.hostWidget && typeof root.hostWidget.broadcast === "function")
        root.hostWidget.broadcast("refresh")
      else root.refresh()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveSelection(dy) }
      onTextKey: function(key) {
        if (key === "r") root.refresh()
        else if (key === "1") root.choose("cpu")
        else if (key === "2") root.choose("memory")
        else if (key === "3") root.choose("io")
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: parent.width
          spacing: Style.space(10)

          Column {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(16)
            spacing: Style.space(3)

            Text {
              text: "WAIT STATE"
              textFormat: Text.PlainText
              width: parent.width
              elide: Text.ElideRight
              color: root.levelColor(root.currentSeverity)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              font.letterSpacing: 1
            }

            Text {
              text: root.snapshot.valid
                ? Model.resourceLabel(root.currentName) + " is the current bottleneck · "
                  + Model.formatPercent(root.currentValue) + " stalled over 10 seconds"
                : "Linux pressure data is unavailable"
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              text: root.snapshot.valid
                ? "Sampled " + Model.ageText(root.snapshot.capturedAt, root.nowMs)
                  + (root.sampling ? " · refreshing" : "")
                  + (root.service && root.service.inputTruncated
                      ? " · input truncated at safety limit" : "")
                : root.lastError
              textFormat: Text.PlainText
              width: parent.width
              elide: Text.ElideRight
              color: root.bar ? Qt.darker(root.bar.foreground, 1.4) : Color.muted
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          PanelSeparator { foreground: root.bar ? root.bar.foreground : Color.foreground }

          PanelSectionHeader {
            text: "WHERE WORK IS WAITING"
            leftPadding: Style.space(16)
            foreground: root.bar ? root.bar.foreground : Color.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }

          Repeater {
            model: ["cpu", "memory", "io"]

            Rectangle {
              required property var modelData
              readonly property string resourceName: String(modelData)
              readonly property bool available:
                root.snapshot.resources[resourceName]
                  && root.snapshot.resources[resourceName].available
              readonly property real value:
                available ? root.snapshot.resources[resourceName].some.avg10 : 0
              readonly property string level:
                Model.severity(value, root.warningPercent, root.criticalPercent)
              readonly property color stateColor: level === "critical"
                ? Qt.hsla(0.0, 0.68, 0.58, 1.0)
                : level === "warning"
                  ? Qt.hsla(0.11, 0.72, 0.58, 1.0)
                  : (root.bar ? root.bar.foreground : Color.foreground)
              width: contentColumn.width - Style.space(24)
              height: resourceColumn.implicitHeight + Style.space(18)
              anchors.horizontalCenter: parent.horizontalCenter
              radius: Style.cornerRadius
              color: resourceName === root.selectedResource
                ? Qt.rgba(stateColor.r, stateColor.g, stateColor.b, 0.14)
                : Qt.rgba(0, 0, 0, 0)
              border.width: resourceName === root.selectedResource ? 1 : 0
              border.color: stateColor

              Column {
                id: resourceColumn
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Row {
                  width: parent.width
                  spacing: Style.space(10)

                  Text {
                    text: Model.resourceLabel(resourceName)
                    textFormat: Text.PlainText
                    width: Style.space(54)
                    elide: Text.ElideRight
                    color: stateColor
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }

                  Text {
                    text: available ? Model.formatPercent(value) : "unavailable"
                    textFormat: Text.PlainText
                    width: Style.space(76)
                    elide: Text.ElideRight
                    color: root.bar ? root.bar.foreground : Color.foreground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }

                  Text {
                    text: available
                      ? "1m " + Model.formatPercent(root.resourceValue(resourceName, "some", "avg60"))
                        + " · 5m " + Model.formatPercent(root.resourceValue(resourceName, "some", "avg300"))
                        + (resourceName === "cpu" ? "" : " · full "
                          + Model.formatPercent(root.resourceValue(resourceName, "full", "avg10")))
                      : "No readable /proc/pressure source"
                    textFormat: Text.PlainText
                    width: parent.width - Style.space(150)
                    elide: Text.ElideRight
                    color: root.bar ? Qt.darker(root.bar.foreground, 1.35) : Color.muted
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                Text {
                  text: Model.diagnosis(resourceName, root.snapshot,
                    root.warningPercent, root.criticalPercent)
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  color: root.bar ? Qt.darker(root.bar.foreground, 1.2) : Color.muted
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.choose(parent.resourceName)
              }
            }
          }

          PanelSeparator { foreground: root.bar ? root.bar.foreground : Color.foreground }

          PanelSectionHeader {
            text: Model.resourceLabel(root.selectedResource) + " HISTORY · "
              + root.historyWindow.toUpperCase()
            leftPadding: Style.space(16)
            foreground: root.bar ? root.bar.foreground : Color.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }

          Column {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(16)
            spacing: Style.space(6)

            Row {
              width: parent.width
              spacing: Style.space(16)
              Text {
                text: "now " + Model.formatPercent(root.chartStats.current)
                textFormat: Text.PlainText
                width: Style.space(95)
                elide: Text.ElideRight
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                text: "avg " + Model.formatPercent(root.chartStats.average)
                textFormat: Text.PlainText
                width: Style.space(95)
                elide: Text.ElideRight
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                text: "peak " + Model.formatPercent(root.chartStats.peak)
                textFormat: Text.PlainText
                width: Style.space(105)
                elide: Text.ElideRight
                color: root.levelColor(Model.severity(root.chartStats.peak,
                  root.warningPercent, root.criticalPercent))
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                text: root.chartStats.samples + " samples"
                textFormat: Text.PlainText
                width: parent.width - Style.space(343)
                elide: Text.ElideRight
                color: root.bar ? Qt.darker(root.bar.foreground, 1.4) : Color.muted
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Item {
              width: parent.width
              height: Style.space(72)

              Text {
                visible: root.chartSeries.length === 0
                anchors.centerIn: parent
                text: "History fills while the shell runs"
                textFormat: Text.PlainText
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                color: root.bar ? Qt.darker(root.bar.foreground, 1.45) : Color.muted
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              Row {
                anchors.fill: parent
                spacing: 2

                Repeater {
                  model: root.chartSeries

                  Item {
                    required property var modelData
                    width: Math.max(2, (parent.width - Math.max(0,
                      root.chartSeries.length - 1) * 2) / Math.max(1, root.chartSeries.length))
                    height: parent.height

                    Rectangle {
                      anchors.bottom: parent.bottom
                      width: parent.width
                      height: Math.max(1, parent.height * Math.min(1,
                        modelData.value / Math.max(root.criticalPercent, root.chartStats.peak, 1)))
                      radius: Math.min(width / 2, Style.space(2))
                      color: Model.severity(modelData.value, root.warningPercent,
                        root.criticalPercent) === "critical"
                        ? Qt.hsla(0.0, 0.68, 0.58, 1.0)
                        : Model.severity(modelData.value, root.warningPercent,
                            root.criticalPercent) === "warning"
                          ? Qt.hsla(0.11, 0.72, 0.58, 1.0)
                          : (root.bar ? root.bar.foreground : Color.foreground)
                      opacity: 0.82
                    }
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.bar ? root.bar.foreground : Color.foreground }

          Column {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(16)
            spacing: Style.space(3)

            Text {
              text: "HOW TO READ THIS"
              textFormat: Text.PlainText
              width: parent.width
              elide: Text.ElideRight
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Text {
              text: "Some is the share of time at least one task was stalled. Full means all active work was stalled together. CPU full is undefined system-wide, so CPU comparisons use some. PSI identifies the constrained resource, not the responsible process."
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              color: root.bar ? Qt.darker(root.bar.foreground, 1.3) : Color.muted
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            Text {
              text: "1/2/3 select · j/k move · r refresh · middle-click pill refreshes"
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              color: root.bar ? Qt.darker(root.bar.foreground, 1.45) : Color.muted
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Item { width: 1; height: Style.space(4) }
        }
      }
    }
  }
}
