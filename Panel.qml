import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The drop-down's content: the list of changes (layout B). It only lays out
// what the CLI decided; order, stale and kind all come from the report.
// Everything shown from the report is plain text (it comes from repos).
//
// The panel is a fixed height and never scrolls: each page holds as many rows
// as fit, and the pager sits pinned to the bottom so its buttons never move.
Item {
  id: root

  property var service: null
  // The page is kept by BarWidget, so reopening resets it and the change view
  // can come back to it.
  property int page: 0
  // The open change, as { repo, name } from BarWidget; null shows the list.
  // Looked up in each fresh report, so a refresh updates its tasks.
  property var chosen: null
  signal changeChosen(var change)
  signal pageRequested(int page)
  signal backRequested()
  signal closeRequested()

  readonly property var report: service ? service.report : null
  readonly property var changes: report ? report.changes : []
  readonly property var summary: report ? report.summary : null
  readonly property var repoErrors: report ? report.repos.filter(function(r) { return !!r.error }) : []
  readonly property var changeErrors: changes.filter(function(c) { return !!c.error })
  readonly property string cliError: service ? service.cliError : ""
  readonly property string nudgesError: service ? service.nudgesError : ""
  readonly property var current: {
    if (!chosen) return null
    for (var i = 0; i < changes.length; i++)
      if (changes[i].repo === chosen.repo && changes[i].name === chosen.name) return changes[i]
    return null
  }

  readonly property color textColor: Commons.Color.popups.text
  readonly property color mutedColor: Commons.Color.muted
  readonly property color attentionColor: Commons.Color.urgent
  readonly property color accentColor: Commons.Color.accent

  readonly property real panelHeight: Style.space(640)
  readonly property real sectionGap: Style.space(10)
  readonly property real rowGap: Style.space(4)
  readonly property real headingGap: Style.space(4)
  readonly property real laterHeadingPadding: Style.space(8)

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  implicitWidth: Style.space(420)
  implicitHeight: panelHeight

  function count(key, n) { return strings.tn(key, n).arg(Commons.I18n.formatNumber(n)) }

  function note(change) {
    if (change.error) return ""
    if (change.kind === "complete") return strings.t("panel.readyToArchive")
    if (change.kind === "not_started") return strings.t("panel.notStarted")
    return count("panel.days", change.days_quiet)
  }

  // The group a row belongs to, from what the CLI decided. Rows arrive already
  // ordered by group, so a heading goes wherever the group changes.
  function group(change) {
    if (!change) return ""
    if (change.error) return "errors"
    if (change.stale) return "stale"
    if (change.kind === "complete") return "archive"
    if (change.kind === "in_progress") return "progress"
    return "notStarted"
  }

  function openAgent(change) {
    if (root.service) root.service.openAgent(change)
    root.closeRequested()
  }

  function noteColor(change) {
    if (change.stale) return attentionColor
    if (change.kind === "complete") return accentColor
    return mutedColor
  }

  // ------------------------------------------------------------- paging
  //
  // Heights come from hidden probes built from the same components as the
  // real rows, so a page is filled with exactly what fits.
  readonly property real rowHeight: rowProbe.implicitHeight
  readonly property real firstHeadingHeight: firstHeadingProbe.implicitHeight + headingGap
  readonly property real laterHeadingHeight: laterHeadingProbe.implicitHeight + headingGap
  readonly property real listTop: top.implicitHeight + sectionGap
  readonly property real roomWithoutPager: panelHeight - listTop
  readonly property real roomWithPager: roomWithoutPager - pagerBar.implicitHeight - sectionGap

  function paginate(room) {
    var pages = [], current = [], used = 0
    for (var i = 0; i < changes.length; i++) {
      var change = changes[i]
      var first = current.length === 0
      var heading = first || group(change) !== group(current[current.length - 1])
      var need = (heading ? (first ? firstHeadingHeight : laterHeadingHeight) : 0) + rowHeight + rowGap
      if (!first && used + need > room) {
        pages.push(current)
        current = []
        used = 0
        need = firstHeadingHeight + rowHeight + rowGap
      }
      current.push(change)
      used += need
    }
    if (current.length > 0) pages.push(current)
    return pages.length > 0 ? pages : [[]]
  }

  // One page if everything fits without the pager; otherwise leave it room.
  readonly property var pages: {
    var single = paginate(roomWithoutPager)
    return single.length <= 1 ? single : paginate(roomWithPager)
  }
  readonly property int pageCount: pages.length
  readonly property int shownPage: Math.min(Math.max(page, 0), pageCount - 1)
  readonly property var pageChanges: pages[shownPage]

  // ------------------------------------------------------------- one row
  component ChangeRow: Item {
    id: row
    property var change: ({})
    width: root.width
    implicitHeight: rowColumn.implicitHeight + Style.space(18)  // 6 above, 12 below
    opacity: change.kind === "not_started" ? 0.5 : 1

    Rectangle {
      anchors.fill: parent
      radius: Style.space(4)
      color: rowMouse.containsMouse || agentMouse.containsMouse ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.06) : "transparent"
    }

    // Under the content, so the agent icon's own area takes its clicks.
    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.changeChosen(row.change)
    }

    Column {
      id: rowColumn
      x: Style.space(10)
      y: Style.space(6)
      width: parent.width - Style.space(20)
      spacing: Style.space(3)

      Item {
        width: parent.width
        height: nameText.implicitHeight
        TruncatedText {
          id: nameText
          width: parent.width - noteRow.implicitWidth - Style.space(8)
          textFormat: Text.PlainText
          text: row.change.name || ""
          color: root.textColor
          elide: Text.ElideRight
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }
        // "94 days | <agent icon>": the icon opens the change in the agent.
        Row {
          id: noteRow
          anchors.right: parent.right
          spacing: Style.space(6)
          Text {
            textFormat: Text.PlainText
            text: row.change.name ? root.note(row.change) : ""
            color: root.noteColor(row.change)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            visible: !row.change.error
            textFormat: Text.PlainText
            text: "|"
            color: root.mutedColor
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            id: agentIcon
            visible: !row.change.error
            textFormat: Text.PlainText
            text: "󰚩"
            color: agentMouse.containsMouse ? root.accentColor : root.mutedColor
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
            MouseArea {
              id: agentMouse
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openAgent(row.change)
            }
            PanelToolTip {
              visible: agentMouse.containsMouse
              text: strings.t("change.openAgent")
            }
          }
        }
      }

      Item {
        width: parent.width
        height: detailText.implicitHeight
        Text {
          id: detailText
          width: parent.width * 0.6
          textFormat: Text.PlainText
          text: row.change.repo || ""
          color: root.mutedColor
          elide: Text.ElideRight
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: row.change.total === null || row.change.total === undefined ? ""
                : row.change.done + "/" + row.change.total
                  + (row.change.ready > 0 ? " · " + root.count("panel.ready", row.change.ready) : "")
          color: root.mutedColor
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }

      // Progress bar.
      Rectangle {
        width: parent.width
        height: Style.space(3)
        radius: height / 2
        color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.12)
        Rectangle {
          width: row.change.total > 0 ? parent.width * row.change.done / row.change.total : 0
          height: parent.height
          radius: parent.radius
          color: row.change.stale ? root.attentionColor : root.accentColor
        }
      }
    }

  }

  // Probes for measuring; never shown.
  ChangeRow { id: rowProbe; visible: false; change: ({ name: "probe", repo: "probe", done: 1, total: 2, ready: 1, kind: "in_progress", days_quiet: 1 }) }
  PanelSectionHeader { id: firstHeadingProbe; visible: false; text: "Probe" }
  PanelSectionHeader { id: laterHeadingProbe; visible: false; text: "Probe"; topPadding: root.laterHeadingPadding }

  // ------------------------------------------------------------- layout
  Column {
    id: top
    visible: root.current === null
    width: parent.width
    spacing: root.sectionGap

    // Header row, as other Omarchy panels have it: icon, title, and totals
    // across every change (not just what is on screen), then a divider.
    PanelHero {
      width: parent.width
      foreground: root.textColor
      title: strings.t("panel.title")
      meta: root.summary
            ? [root.count("panel.changes", root.summary.changes),
               root.count("panel.stale", root.summary.stale),
               root.count("panel.archive", root.summary.complete)].join(" · ")
            : ""
      // The daily reminder switch. It shows the report's setting, so after a
      // failed change it still shows what is really set.
      trailingControl: Component {
        ToggleSwitch {
          id: nudgeSwitch
          visible: root.report !== null
          checked: root.service ? root.service.nudges : true
          busy: root.service ? root.service.nudgesBusy : false
          foreground: root.textColor
          onToggled: if (root.service) root.service.setNudges(!root.service.nudges)

          PanelToolTip {
            visible: nudgeSwitch.containsMouse
            text: strings.t(nudgeSwitch.checked ? "panel.nudgesOn" : "panel.nudgesOff")
          }
        }
      }
      iconComponent: Component {
        Text {
          textFormat: Text.PlainText
          text: ""
          color: root.textColor
          font.family: Style.font.family
          font.pixelSize: Style.font.display
        }
      }
    }

    PanelSeparator { foreground: root.textColor }

    // Errors first: a failure must never look like an empty list.
    Column {
      width: parent.width
      spacing: Style.space(4)
      visible: root.cliError !== "" || root.nudgesError !== "" || root.repoErrors.length > 0 || root.changeErrors.length > 0

      Text {
        visible: root.nudgesError !== ""
        width: parent.width
        textFormat: Text.PlainText
        text: root.nudgesError
        color: root.attentionColor
        wrapMode: Text.Wrap
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Text {
        visible: root.cliError !== ""
        width: parent.width
        textFormat: Text.PlainText
        text: root.cliError
        color: root.attentionColor
        wrapMode: Text.Wrap
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Repeater {
        model: root.repoErrors
        delegate: Text {
          required property var modelData
          width: parent.width
          textFormat: Text.PlainText
          text: modelData.name + ": " + modelData.error
          color: root.attentionColor
          wrapMode: Text.Wrap
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }
      Repeater {
        model: root.changeErrors
        delegate: Text {
          required property var modelData
          width: parent.width
          textFormat: Text.PlainText
          text: modelData.repo + " / " + modelData.name + ": " + modelData.error
          color: root.attentionColor
          wrapMode: Text.Wrap
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }
    }

    Text {
      visible: root.report === null && root.cliError === ""
      textFormat: Text.PlainText
      text: strings.t("bar.loading")
      color: root.mutedColor
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  Column {
    id: list
    visible: root.current === null
    y: root.listTop
    width: parent.width

    Repeater {
      model: root.pageChanges
      delegate: Column {
        id: entry
        required property var modelData
        required property int index
        readonly property bool heading: index === 0 || root.group(root.pageChanges[index - 1]) !== root.group(modelData)
        width: list.width

        PanelSectionHeader {
          visible: entry.heading
          topPadding: entry.index === 0 ? 0 : root.laterHeadingPadding
          foreground: root.textColor
          text: strings.t("panel.group." + root.group(entry.modelData))
        }
        Item { visible: entry.heading; width: 1; height: root.headingGap }
        ChangeRow { change: entry.modelData }
        Item { width: 1; height: root.rowGap }
      }
    }
  }

  // Pinned to the bottom so the buttons stay put from page to page.
  Item {
    id: pagerBar
    visible: root.current === null && root.pageCount > 1
    anchors.bottom: parent.bottom
    width: parent.width
    implicitHeight: Math.max(previousButton.implicitHeight, pageLabel.implicitHeight)
    height: implicitHeight

    Button {
      id: previousButton
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: strings.t("panel.previous")
      foreground: root.textColor
      enabled: root.shownPage > 0
      opacity: enabled ? 1 : 0.35
      onClicked: root.pageRequested(root.shownPage - 1)
    }
    Text {
      id: pageLabel
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: strings.t("panel.pageOf").arg(Commons.I18n.formatNumber(root.shownPage + 1)).arg(Commons.I18n.formatNumber(root.pageCount))
      color: root.mutedColor
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
    Button {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: strings.t("panel.next")
      foreground: root.textColor
      enabled: root.shownPage < root.pageCount - 1
      opacity: enabled ? 1 : 0.35
      onClicked: root.pageRequested(root.shownPage + 1)
    }
  }

  // The change view replaces the list; back returns to the same page.
  ChangeView {
    anchors.fill: parent
    visible: root.current !== null
    change: root.current
    onBack: root.backRequested()
    onLaunched: root.closeRequested()
    onAgentRequested: function(change) { root.openAgent(change) }
  }
}
