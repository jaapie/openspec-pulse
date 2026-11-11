import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One change's tasks (layout B's separate task view). A fixed header, then the
// groups in file order, scrolling inside the fixed-height panel. Task text and
// titles come from tasks.md, so they are plain text.
Item {
  id: root

  property var change: null
  signal back()
  // Something was opened outside the panel; BarWidget closes the panel.
  signal launched()
  signal agentRequested(var change)

  readonly property var groups: change && change.groups ? change.groups : []
  readonly property color textColor: Commons.Color.popups.text
  readonly property color mutedColor: Commons.Color.muted
  readonly property color attentionColor: Commons.Color.urgent
  readonly property color accentColor: Commons.Color.accent

  // Which groups have their done tasks showing, by index. Reset per change.
  property var shownDone: ({})
  // Whether the purpose shows in full. Reset per change, like shownDone.
  property bool purposeExpanded: false
  onChangeChanged: {
    shownDone = ({})
    purposeExpanded = false
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function count(key, n) { return strings.tn(key, n).arg(Commons.I18n.formatNumber(n)) }

  function touchedText() {
    if (!change || !change.last_touched) return ""
    var when = new Date(change.last_touched)
    var locale = Qt.locale(Commons.I18n.formatLocale)
    var format = when.getFullYear() === new Date().getFullYear() ? "dd MMM" : "dd MMM yyyy"
    var key = change.touched_source === "git" ? "change.lastCommit" : "change.lastEdited"
    return strings.t(key).arg(when.toLocaleDateString(locale, format))
  }

  function toggleDone(index) {
    var next = ({})
    for (var k in shownDone) next[k] = shownDone[k]
    next[index] = !next[index]
    shownDone = next
  }

  // The service launches the agent, so the list's icon and this button share it.
  function openAgent() { root.agentRequested(root.change) }

  function openTasksFile() {
    Util.execArgv(["omarchy-launch-editor", change.path + "/tasks.md"])
    root.launched()
  }

  function doneTasks(group) { return group.tasks.filter(function(t) { return t.done }) }
  function openTasks(group) { return group.tasks.filter(function(t) { return !t.done }) }

  // ------------------------------------------------------------- header
  Column {
    id: header
    width: parent.width
    spacing: Style.space(8)

    Button {
      text: strings.t("change.back")
      foreground: root.textColor
      onClicked: root.back()
    }

    Column {
      width: parent.width
      spacing: Style.space(3)
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.change ? root.change.name : ""
        color: root.textColor
        wrapMode: Text.Wrap
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        font.bold: true
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.change ? [root.change.repo, root.touchedText()].filter(function(s) { return s }).join(" · ") : ""
        color: root.mutedColor
        elide: Text.ElideRight
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    Item {
      width: parent.width
      height: progressLabel.implicitHeight
      Rectangle {
        anchors.left: parent.left
        anchors.right: progressLabel.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(4)
        radius: height / 2
        color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.12)
        Rectangle {
          width: root.change && root.change.total > 0 ? parent.width * root.change.done / root.change.total : 0
          height: parent.height
          radius: parent.radius
          color: root.change && root.change.stale ? root.attentionColor : root.accentColor
        }
      }
      Text {
        id: progressLabel
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: root.change && root.change.total !== null
              ? root.change.done + "/" + root.change.total
                + (root.change.ready > 0 ? " · " + root.count("panel.ready", root.change.ready) : "")
              : ""
        color: root.mutedColor
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    PanelSeparator { foreground: root.textColor }
  }

  // ------------------------------------------------------------- groups
  Flickable {
    id: flick
    anchors.top: header.bottom
    anchors.topMargin: Style.space(10)
    anchors.bottom: actions.top
    anchors.bottomMargin: Style.space(10)
    width: parent.width
    contentWidth: width
    contentHeight: groupsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: groupsColumn
      width: flick.width - Style.space(8)
      spacing: Style.space(12)

      // What the change is for, from the Why section of its proposal.md:
      // three lines, then "more". Hidden when the CLI found no purpose.
      Column {
        visible: !!(root.change && root.change.purpose)
        width: groupsColumn.width
        spacing: Style.space(4)

        PanelSectionHeader {
          foreground: root.textColor
          text: strings.t("change.purpose")
        }
        Text {
          id: purposeText
          width: parent.width
          textFormat: Text.PlainText
          text: root.change && root.change.purpose ? root.change.purpose : ""
          color: root.textColor
          wrapMode: Text.Wrap
          // maximumLineCount has no "unlimited" to bind back to, so a large number.
          maximumLineCount: root.purposeExpanded ? 10000 : 3
          elide: Text.ElideRight
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          visible: purposeText.truncated || root.purposeExpanded
          textFormat: Text.PlainText
          text: strings.t(root.purposeExpanded ? "change.less" : "change.more")
          color: root.accentColor
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.purposeExpanded = !root.purposeExpanded
          }
        }
      }

      // Separates the purpose from the task groups; without a purpose the
      // groups start at the top as before.
      PanelSectionHeader {
        visible: !!(root.change && root.change.purpose)
        foreground: root.textColor
        text: strings.t("change.tasks")
      }

      Text {
        visible: root.change && !root.change.tasks_file
        textFormat: Text.PlainText
        text: strings.t("change.noTasksFile")
        color: root.mutedColor
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Repeater {
        model: root.groups
        delegate: Column {
          id: groupEntry
          required property var modelData
          required property int index
          readonly property bool finished: modelData.total > 0 && modelData.done === modelData.total
          readonly property bool showingDone: !!root.shownDone[index]
          width: groupsColumn.width
          spacing: Style.space(4)

          // Title and done/total. A finished group is just this line.
          Item {
            width: parent.width
            height: titleText.implicitHeight
            opacity: groupEntry.finished || groupEntry.modelData.total === 0 ? 0.6 : 1
            TruncatedText {
              id: titleText
              width: parent.width - countText.implicitWidth - Style.space(8)
              textFormat: Text.PlainText
              text: groupEntry.modelData.title || strings.t("change.untitled")
              color: root.textColor
              elide: Text.ElideRight
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              id: countText
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: groupEntry.modelData.done + "/" + groupEntry.modelData.total
              color: root.mutedColor
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }

          // Tasks not done: id and text, cut to two lines.
          Repeater {
            model: groupEntry.finished ? [] : root.openTasks(groupEntry.modelData)
            delegate: Row {
              required property var modelData
              x: Style.space(8) + modelData.indent * Style.space(12)
              width: groupEntry.width - x
              spacing: Style.space(6)
              Text {
                id: openId
                width: Style.space(34)
                textFormat: Text.PlainText
                text: modelData.id || "○"
                color: root.mutedColor
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
              TruncatedText {
                width: parent.width - openId.width - parent.spacing
                textFormat: Text.PlainText
                text: modelData.text
                color: root.textColor
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          // Done tasks folded behind "N done (show)".
          Text {
            visible: !groupEntry.finished && groupEntry.modelData.done > 0
            x: Style.space(8)
            textFormat: Text.PlainText
            text: strings.t(groupEntry.showingDone ? "change.hideDone" : "change.showDone")
                    .arg(Commons.I18n.formatNumber(groupEntry.modelData.done))
            color: root.accentColor
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleDone(groupEntry.index)
            }
          }

          Repeater {
            model: groupEntry.showingDone && !groupEntry.finished ? root.doneTasks(groupEntry.modelData) : []
            delegate: Row {
              required property var modelData
              x: Style.space(8) + modelData.indent * Style.space(12)
              width: groupEntry.width - x
              spacing: Style.space(6)
              opacity: 0.55
              Text {
                id: doneId
                width: Style.space(34)
                textFormat: Text.PlainText
                text: modelData.id || "✓"
                color: root.mutedColor
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
              TruncatedText {
                width: parent.width - doneId.width - parent.spacing
                textFormat: Text.PlainText
                text: modelData.text
                color: root.textColor
                font.strikeout: true
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }
      }
    }
  }

  // Open actions, pinned to the bottom like the list's pager.
  Row {
    id: actions
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.space(8)

    Button {
      text: strings.t("change.openAgent")
      foreground: root.textColor
      enabled: !!(root.change && root.change.repo_path)
      opacity: enabled ? 1 : 0.35
      onClicked: root.openAgent()
    }
    Button {
      text: strings.t("change.openTasks")
      foreground: root.textColor
      enabled: !!(root.change && root.change.tasks_file)
      opacity: enabled ? 1 : 0.35
      onClicked: root.openTasksFile()
    }
  }
}
