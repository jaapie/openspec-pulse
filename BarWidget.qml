import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The bar badge: neutral when nothing is stale, the stale count in the theme's
// attention colour (Commons.Color.urgent) when something is, and a warning
// glyph when the CLI or any repo or change reports an error.
Panel {
  id: root
  moduleName: "io.github.jaapie.openspec-pulse"
  ipcTarget: "io.github.jaapie.openspec-pulse"

  // The bar sizes and centres a widget from its root's implicit size.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property int staleCount: service ? service.staleCount : 0
  readonly property bool hasError: service ? service.hasError : false
  readonly property bool waiting: !service || (service.report === null && service.cliError === "")

  // Nerd Font glyphs: a task list, and a warning sign for errors.
  readonly property string listGlyph: ""
  readonly property string errorGlyph: ""

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // The command override is a bar widget setting; the service runs the CLI.
  function shareSettings() { if (service) service.settings = root.settings }
  onSettingsChanged: shareSettings()
  onServiceChanged: shareSettings()

  // Which page of the list is showing. Reopening starts at page 1.
  property int page: 0
  // The open change as { repo, name }, or null for the list.
  property var chosen: null

  onOpenedChanged: if (opened) {
    page = 0
    chosen = null
    if (service) {
      service.clearToggleError()
      service.refresh()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.hasError ? root.errorGlyph : root.listGlyph
    labelText: root.staleCount > 0 && !vertical ? Commons.I18n.formatNumber(root.staleCount) : ""
    // Grow by the label's own width (plus the button's 4px gap), not a fixed second slot.
    slotSize: Style.bar.iconSlot + (labelText !== "" ? Math.ceil(labelMetrics.advanceWidth) + Style.space(4) : 0)
    active: root.staleCount > 0 || root.hasError
    tooltipText: root.hasError ? strings.t("bar.error")
               : root.waiting ? strings.t("bar.loading")
               : root.staleCount > 0 ? strings.tn("bar.stale", root.staleCount).arg(Commons.I18n.formatNumber(root.staleCount))
               : strings.t("bar.nothingStale")
    onPressed: function(buttonCode) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(460))
    // Panel.qml is a fixed 640px and pages rather than scrolls; the screen
    // height is the only other limit.
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    // Panel.qml by URL: a type named Panel would clash with qs.Ui's Panel.
    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: contentLoader.implicitHeight
      onCloseRequested: root.close()
      Loader {
        id: contentLoader
        anchors.fill: parent
        source: Qt.resolvedUrl("Panel.qml")
        onLoaded: {
          item.service = Qt.binding(function() { return root.service })
          item.page = Qt.binding(function() { return root.page })
          item.pageRequested.connect(function(p) { root.page = p })
          item.chosen = Qt.binding(function() { return root.chosen })
          item.changeChosen.connect(function(c) { root.chosen = { repo: c.repo, name: c.name } })
          item.backRequested.connect(function() { root.chosen = null })
          item.closeRequested.connect(function() { root.close() })
        }
      }
    }
  }

  TextMetrics {
    id: labelMetrics
    font.family: button.fontFamily
    font.pixelSize: button.fontSize
    text: button.labelText
  }
}
