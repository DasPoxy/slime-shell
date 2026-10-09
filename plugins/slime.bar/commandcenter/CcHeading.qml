import QtQuick

// Small caps section label.
Text {
  textFormat: Text.PlainText
  id: heading
  required property var cc
  readonly property real fs: cc && cc.fontScale ? cc.fontScale : 1
  color: cc.ink
  font.family: cc.font
  font.pixelSize: Math.round(10 * heading.fs)
  font.bold: true
  font.letterSpacing: 0.6
  opacity: 0.7
}
