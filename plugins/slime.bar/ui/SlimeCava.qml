import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io

// An audio visualizer made of ooze: `bars` goo columns that rise and fall with
// the music (from cava), each topped with a round blob, the tallest shedding a
// bubble. Cava only runs while `active` is true, so a hidden or paused
// visualizer costs nothing.
Item {
  id: viz

  property bool active: true
  property int bars: 12
  property color fill: "black"
  property color outline: "transparent"
  property real outlineWidth: 0
  property real gap: 2
  property bool fromTop: false            // hang down instead of rising up
  property var levels: []                 // 0..1 per bar, smoothed

  readonly property string configPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/slime-shell-cava-" + bars + ".conf"
  readonly property bool silent: levels.every(function(v) { return v < 0.02 })
  property bool configReady: false
  readonly property bool wanted: active && visible && configReady

  // cava config: raw ascii levels 0..100, ';' between bars, one frame per line
  FileView {
    id: config
    path: viz.configPath
    printErrors: false
    Component.onCompleted: setText(
      "[general]\nbars = " + viz.bars + "\nframerate = 30\nautosens = 1\n" +
      "[output]\nmethod = raw\nchannels = mono\nmono_option = average\nraw_target = /dev/stdout\ndata_format = ascii\n" +
      "ascii_max_range = 100\nbar_delimiter = 59\nframe_delimiter = 10\n" +
      "[smoothing]\nnoise_reduction = 60\n")
    onSaved: viz.configReady = true
    onSaveFailed: viz.configReady = true
  }

  Process {
    id: cava
    running: false
    command: ["cava", "-p", viz.configPath]
    stdout: SplitParser {
      onRead: data => {
        var parts = data.split(";")
        var out = []
        for (var i = 0; i < viz.bars; i++) {
          var v = Math.min(1, (parseInt(parts[i], 10) || 0) / 100)
          var prev = viz.levels[i] || 0
          out.push(v > prev ? v : prev * 0.7 + v * 0.3)   // quick rise, gooey fall
        }
        viz.levels = out
      }
    }
    onRunningChanged: if (!running) viz.levels = []
  }
  // Drive the process imperatively: an exit would break a `running` binding.
  onWantedChanged: cava.running = wanted
  Timer {   // bring cava back if it dies while wanted
    interval: 2000
    repeat: true
    running: viz.wanted && !cava.running
    onTriggered: cava.running = true
  }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: viz.fill
      strokeColor: viz.outline
      strokeWidth: viz.outlineWidth
      joinStyle: ShapePath.RoundJoin
      PathSvg {
        path: {
          var n = viz.bars, w = viz.width, h = viz.height
          var slot = w / n, bw = Math.max(1.5, slot - viz.gap), r = bw / 2
          var d = ""
          for (var i = 0; i < n; i++) {
            var v = Math.max(0.06, viz.levels[i] || 0)
            var len = Math.max(bw, v * h)
            var x = i * slot + (slot - bw) / 2
            if (viz.fromTop) {
              // hanging drip: flat top, rounded bulb at the bottom
              d += "M " + x + " 0 L " + (x + bw) + " 0 L " + (x + bw) + " " + (len - r)
                + " A " + r + " " + r + " 0 0 1 " + x + " " + (len - r) + " Z "
            } else {
              // rising goo: flat base, blob on top
              d += "M " + x + " " + h + " L " + x + " " + (h - len + r)
                + " A " + r + " " + r + " 0 0 1 " + (x + bw) + " " + (h - len + r)
                + " L " + (x + bw) + " " + h + " Z "
            }
          }
          return d
        }
      }
    }
  }

  // a bubble popping off the loudest bar
  Rectangle {
    readonly property int peak: {
      var best = -1, bv = 0.45
      for (var i = 0; i < viz.levels.length; i++) if (viz.levels[i] > bv) { bv = viz.levels[i]; best = i }
      return best
    }
    visible: peak >= 0 && !viz.fromTop
    width: Math.max(3, viz.width / viz.bars * 0.5)
    height: width
    radius: width / 2
    x: (peak + 0.5) * viz.width / viz.bars - width / 2
    y: viz.height - (viz.levels[peak] || 0) * viz.height - height - 2
    color: "transparent"
    border.color: viz.fill
    border.width: 1
  }
}
