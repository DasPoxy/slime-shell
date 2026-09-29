import QtQuick

// Click a slider's value readout to type the value instead. Put this beside
// the readout (same parent) with `target` the readout Text and `slider` the
// SlimePanelSlider: it lies over the readout, and a click turns it into a
// little input. Enter sets the slider — the number is read in the readout's
// units (`scale`: 100 for a 0..1 slider shown as %), and anything out of
// range or between steps snaps to the nearest value the slider allows. Esc
// or clicking away leaves it as it was.
// `fromDisplay` (optional) maps the typed number to a slider value itself
// (e.g. a slider over a list of sizes).
Item {
  id: edit

  required property Item target
  required property var slider
  property real scale: 1
  property var fromDisplay: null
  property color ink: target && target.color !== undefined ? target.color : "black"
  property bool editing: false
  // a stop for the command centre's keyboard highlight: Enter starts typing
  readonly property bool ccFocusable: true
  function ccActivate() { start() }

  // beside the readout, or inside it (when it's the readout's own child)
  x: target ? (target === parent ? 0 : target.x) - 4 : 0
  y: target ? (target === parent ? 0 : target.y) - 2 : 0
  width: target ? Math.max(target.width + 8, 44) : 0
  height: target ? target.height + 4 : 0
  z: 10

  function snap(v) {
    var s = slider
    v = Math.max(s.minimum, Math.min(s.maximum, v))
    if (s.integer) v = Math.round(v)
    else if (s.step > 0) v = s.minimum + Math.round((v - s.minimum) / s.step) * s.step
    return Math.max(s.minimum, Math.min(s.maximum, v))
  }
  function start() {
    if (!slider || slider.enabled === false) return
    var shown = String(target.text).replace(/[^0-9.,\-]/g, "").replace(",", ".")
    input.text = shown
    editing = true
    input.forceActiveFocus()
    input.selectAll()
  }
  function apply() {
    var n = parseFloat(String(input.text).replace(",", "."))
    editing = false
    if (isNaN(n)) return
    var v = snap(typeof fromDisplay === "function" ? fromDisplay(n) : n / scale)
    slider.liveValue = v
    slider.moved(v)
    slider.released(v)
  }

  MouseArea {
    anchors.fill: parent
    enabled: !edit.editing
    cursorShape: Qt.IBeamCursor
    onClicked: edit.start()
  }
  Rectangle {
    anchors.fill: parent
    visible: edit.editing
    radius: height / 2
    color: Qt.rgba(1, 1, 1, 0.96)      // (covers the readout underneath)
    border.color: edit.ink
    border.width: 1.2
    TextInput {
      id: input
      anchors.fill: parent
      anchors.leftMargin: 6; anchors.rightMargin: 6
      verticalAlignment: TextInput.AlignVCenter
      horizontalAlignment: TextInput.AlignHCenter
      color: edit.ink
      font: edit.target ? edit.target.font : Qt.font({})
      selectByMouse: true
      inputMethodHints: Qt.ImhFormattedNumbersOnly
      Keys.onReturnPressed: edit.apply()
      Keys.onEnterPressed: edit.apply()
      Keys.onEscapePressed: edit.editing = false
      onActiveFocusChanged: if (!activeFocus) edit.editing = false
    }
  }
}
