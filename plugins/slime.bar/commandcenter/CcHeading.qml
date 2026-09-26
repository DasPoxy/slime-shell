import QtQuick

// Small caps section label.
Text {
  required property var cc
  color: cc.ink
  font.family: cc.font
  font.pixelSize: 10
  font.bold: true
  font.letterSpacing: 0.6
  opacity: 0.7
}
