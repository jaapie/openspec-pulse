import QtQuick
import qs.Commons
import qs.Ui

// Plain text that, when elided or cut to its maximum lines, shows the whole of
// it in Omarchy's panel tooltip on hover. Text comes from tasks.md and the
// CLI, so it stays plain text in both places.
Text {
  id: root

  textFormat: Text.PlainText
  elide: Text.ElideRight

  readonly property real tipMaxWidth: Style.space(380)
  // Where the pointer came in, so the tip opens there rather than centred over
  // a row-wide item.
  property real pointerX: 0

  HoverHandler {
    id: hover
    onHoveredChanged: if (hovered) root.pointerX = point.position.x
  }

  // Measured, not bound to the tooltip's own implicit width: with word wrap,
  // that binding loops and the tip lands somewhere different each time.
  TextMetrics {
    id: fullText
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    text: root.text
  }

  PanelToolTip {
    id: tip
    visible: hover.hovered && root.truncated
    text: root.text
    width: Math.min(Math.ceil(fullText.advanceWidth) + Style.spacing.controlPaddingX * 2 + Style.space(4), root.tipMaxWidth)
    x: Math.max(0, Math.min(root.pointerX - Style.space(12), root.width - width))
    y: root.height + Style.space(4)
  }
}
