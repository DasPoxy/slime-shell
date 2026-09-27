import QtQuick

// Makes its parent a stop for the command centre's keyboard navigation:
// arrow keys can land on it (the highlight ring takes its shape) and
// Enter / Space fires `activate`. The shared controls (CcButton,
// CcGearButton, CcTile, section headers, sliders) are stops already; this is
// for one-off clickable spots.
Item {
  anchors.fill: parent
  readonly property bool ccFocusable: true
  signal activate()
  function ccActivate() { activate() }
}
