import QtQuick
import qs.Commons

// The colours and fonts a drip menu draws with (the CcButton / CcHeading
// family reads these): the slime's own while its skin is on, Omarchy's else.
//   SlimeLook { id: look; bar: root.bar; skin: root.slime }
// Each is a plain property, so a widget can set its own (ink: root.ink).
QtObject {
  property var bar: null
  // the slime's colours only while the slime skin is on (default: with a bar)
  property bool skin: !!bar
  property color ink: skin && bar ? bar.slimeInk : Color.foreground
  property color slime: skin && bar ? bar.slimeColor : Color.accent
  property color paper: bar ? bar.paperColor : "white"
  property string font: bar ? bar.fontFamily : Style.font.family
  property string displayFont: bar && bar.displayFontFamily ? bar.displayFontFamily : font
  property int displayWeight: bar ? bar.displayWeight : Font.Bold
  property real fontScale: 1
  property color wash: Qt.rgba(1, 1, 1, 0.45)
}
