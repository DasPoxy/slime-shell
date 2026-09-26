import QtQuick
import "../ui"

// The command centre's volume slider: SlimePanelSlider (the goo slider every
// Slime widget panel uses) with the command centre's `cc` wiring.
SlimePanelSlider {
  required property var cc
  bar: cc.bar
  step: 0.05
}
