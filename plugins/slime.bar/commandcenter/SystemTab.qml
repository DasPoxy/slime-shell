import QtQuick
import QtQuick.Shapes
import Quickshell.Io
import Quickshell.Widgets

// System: CPU / memory / GPU with short history graphs, disks, load and the
// top processes. Meters are adventurers marching on a dungeon (AdventureMeter)
// and each card sits on a faint landscape backdrop. Samples come from sysinfo.sh every 1.5 s while this tab is
// showing.
Item {
  id: sys

  property var cc: null
  property var sample: null
  property var prev: null
  property real cpu: 0
  property var cpuHistory: []
  property var memHistory: []
  readonly property int historyLength: 40

  implicitHeight: column.implicitHeight

  function push(list, value) {
    var out = list.slice(-(historyLength - 1))
    out.push(value)
    return out
  }

  Process {
    id: probe
    command: ["bash", Qt.resolvedUrl("sysinfo.sh").toString().replace("file://", "")]
    stdout: StdioCollector {
      onStreamFinished: {
        var s
        try { s = JSON.parse(text) } catch (e) { return }
        if (sys.prev) {
          var total = s.cpuTotal - sys.prev.cpuTotal
          sys.cpu = total > 0 ? (s.cpuBusy - sys.prev.cpuBusy) / total : 0
          sys.cpuHistory = sys.push(sys.cpuHistory, sys.cpu)
        }
        sys.memHistory = sys.push(sys.memHistory, s.memTotal > 0 ? s.memUsed / s.memTotal : 0)
        sys.prev = s
        sys.sample = s
      }
    }
  }
  Timer { interval: 1500; repeat: true; running: true; triggeredOnStart: true; onTriggered: probe.running = true }

  component Graph: Canvas {
    id: graph
    property var values: []
    property color ink: sys.cc.ink
    height: 44
    onValuesChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var n = sys.historyLength
      if (values.length < 2) return
      var step = width / (n - 1)
      var x0 = width - (values.length - 1) * step
      ctx.beginPath()
      ctx.moveTo(x0, height)
      for (var i = 0; i < values.length; i++) ctx.lineTo(x0 + i * step, height - values[i] * (height - 2))
      ctx.lineTo(width, height)
      ctx.closePath()
      ctx.fillStyle = Qt.rgba(ink.r, ink.g, ink.b, 0.18)
      ctx.fill()
      ctx.beginPath()
      for (var j = 0; j < values.length; j++) {
        var y = height - values[j] * (height - 2)
        if (j === 0) ctx.moveTo(x0, y); else ctx.lineTo(x0 + j * step, y)
      }
      ctx.strokeStyle = ink
      ctx.lineWidth = 2
      ctx.stroke()
    }
  }

  component Card: ClippingRectangle {
    id: card
    default property alias content: inner.data
    width: (sys.width - 12) / 2
    height: inner.implicitHeight + 24
    radius: 16
    color: sys.cc.wash

    // adventure backdrop: distant mountains, a castle, rolling hills and pines,
    // all faint so the numbers stay readable
    Shape {
      id: scenery
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      readonly property real w: width
      readonly property real h: height
      readonly property color ink: sys.cc.ink
      ShapePath {   // sun
        fillColor: Qt.rgba(1, 1, 1, 0.35)
        strokeColor: "transparent"
        PathAngleArc { centerX: scenery.w - 34; centerY: 22; radiusX: 13; radiusY: 13; startAngle: 0; sweepAngle: 360 }
      }
      ShapePath {   // far mountains
        fillColor: Qt.rgba(scenery.ink.r, scenery.ink.g, scenery.ink.b, 0.06)
        strokeColor: "transparent"
        PathSvg {
          path: {
            var w = scenery.w, h = scenery.h
            return "M 0 " + (h * 0.62) + " L " + (w * 0.14) + " " + (h * 0.4) + " L " + (w * 0.26) + " " + (h * 0.56)
              + " L " + (w * 0.42) + " " + (h * 0.3) + " L " + (w * 0.58) + " " + (h * 0.54) + " L " + (w * 0.72) + " " + (h * 0.38)
              + " L " + w + " " + (h * 0.6) + " L " + w + " " + h + " L 0 " + h + " Z"
          }
        }
      }
      ShapePath {   // castle on the far ridge
        fillColor: Qt.rgba(scenery.ink.r, scenery.ink.g, scenery.ink.b, 0.09)
        strokeColor: "transparent"
        PathSvg {
          path: {
            var x = scenery.w * 0.66, y = scenery.h * 0.46
            return "M " + x + " " + y + " L " + x + " " + (y - 14) + " L " + (x + 3) + " " + (y - 14) + " L " + (x + 3) + " " + (y - 11)
              + " L " + (x + 6) + " " + (y - 11) + " L " + (x + 6) + " " + (y - 20) + " L " + (x + 10) + " " + (y - 26)
              + " L " + (x + 14) + " " + (y - 20) + " L " + (x + 14) + " " + (y - 11) + " L " + (x + 17) + " " + (y - 11)
              + " L " + (x + 17) + " " + (y - 14) + " L " + (x + 20) + " " + (y - 14) + " L " + (x + 20) + " " + y + " Z"
          }
        }
      }
      ShapePath {   // near hills
        fillColor: Qt.rgba(scenery.ink.r, scenery.ink.g, scenery.ink.b, 0.08)
        strokeColor: "transparent"
        PathSvg {
          path: {
            var w = scenery.w, h = scenery.h
            return "M 0 " + (h * 0.8) + " Q " + (w * 0.2) + " " + (h * 0.62) + " " + (w * 0.42) + " " + (h * 0.78)
              + " Q " + (w * 0.7) + " " + (h * 0.94) + " " + w + " " + (h * 0.7) + " L " + w + " " + h + " L 0 " + h + " Z"
          }
        }
      }
      ShapePath {   // pines
        fillColor: Qt.rgba(scenery.ink.r, scenery.ink.g, scenery.ink.b, 0.1)
        strokeColor: "transparent"
        PathSvg {
          path: {
            var w = scenery.w, h = scenery.h, d = ""
            var trees = [[0.06, 0.8, 16], [0.11, 0.78, 12], [0.84, 0.8, 18], [0.9, 0.76, 13], [0.95, 0.79, 15]]
            for (var i = 0; i < trees.length; i++) {
              var x = trees[i][0] * w, y = trees[i][1] * h, s = trees[i][2]
              d += "M " + (x - s * 0.4) + " " + y + " L " + x + " " + (y - s) + " L " + (x + s * 0.4) + " " + y + " Z "
            }
            return d
          }
        }
      }
    }

    Column {
      id: inner
      x: 12; y: 12
      width: parent.width - 24
      spacing: 6
    }
  }


  Column {
    id: column
    width: parent.width
    spacing: 12

    Flow {
      width: parent.width
      spacing: 12

      Card {
        Row {
          spacing: 8
          Text { text: ""; color: sys.cc.ink; font.family: sys.cc.font; font.pixelSize: 16 }
          Text { text: "CPU"; color: sys.cc.ink; font.family: sys.cc.displayFont; font.weight: sys.cc.displayWeight; font.pixelSize: 14 }
        }
        Text {
          text: Math.round(sys.cpu * 100) + "%" + (sys.sample && sys.sample.cpuTemp ? "   " + sys.sample.cpuTemp + "°C" : "")
          color: sys.cc.ink; font.family: sys.cc.displayFont; font.weight: sys.cc.displayWeight; font.pixelSize: 26
        }
        Graph { width: parent.width; values: sys.cpuHistory }
        Text {
          text: sys.sample ? "load " + sys.sample.load : ""
          color: sys.cc.ink; font.family: sys.cc.font; font.pixelSize: 11; opacity: 0.7
        }
      }

      Card {
        Row {
          spacing: 8
          Text { text: "\uf1c0"; color: sys.cc.ink; font.family: sys.cc.font; font.pixelSize: 16 }
          Text { text: "MEMORY"; color: sys.cc.ink; font.family: sys.cc.displayFont; font.weight: sys.cc.displayWeight; font.pixelSize: 14 }
        }
        Text {
          text: sys.sample ? sys.cc.formatBytes(sys.sample.memUsed) + " / " + sys.cc.formatBytes(sys.sample.memTotal) : "…"
          color: sys.cc.ink; font.family: sys.cc.displayFont; font.weight: sys.cc.displayWeight; font.pixelSize: 20
        }
        Graph { width: parent.width; values: sys.memHistory }
        Text {
          text: sys.sample && sys.sample.swapTotal > 0
            ? "swap " + sys.cc.formatBytes(sys.sample.swapUsed) + " / " + sys.cc.formatBytes(sys.sample.swapTotal) : ""
          color: sys.cc.ink; font.family: sys.cc.font; font.pixelSize: 11; opacity: 0.7
        }
      }

      Card {
        visible: !!sys.sample && !!sys.sample.gpu
        Row {
          spacing: 8
          Text { text: ""; color: sys.cc.ink; font.family: sys.cc.font; font.pixelSize: 16 }
          Text {
            text: sys.sample && sys.sample.gpu ? sys.sample.gpu.name.replace(/^NVIDIA (GeForce )?/, "") : ""
            color: sys.cc.ink; font.family: sys.cc.displayFont; font.weight: sys.cc.displayWeight; font.pixelSize: 14
          }
        }
        AdventureMeter {
          cc: sys.cc
          hero: "knight"
          label: "Utilisation"
          value: sys.sample && sys.sample.gpu ? sys.sample.gpu.util + "%   " + sys.sample.gpu.temp + "°C" : ""
          fraction: sys.sample && sys.sample.gpu ? sys.sample.gpu.util / 100 : 0
        }
        AdventureMeter {
          cc: sys.cc
          hero: "wizard"
          label: "VRAM"
          value: sys.sample && sys.sample.gpu ? sys.cc.formatBytes(sys.sample.gpu.memUsed * 1048576) + " / " + sys.cc.formatBytes(sys.sample.gpu.memTotal * 1048576) : ""
          fraction: sys.sample && sys.sample.gpu ? sys.sample.gpu.memUsed / sys.sample.gpu.memTotal : 0
        }
      }

      Card {
        Row {
          spacing: 8
          Text { text: ""; color: sys.cc.ink; font.family: sys.cc.font; font.pixelSize: 16 }
          Text { text: "DISKS"; color: sys.cc.ink; font.family: sys.cc.displayFont; font.weight: sys.cc.displayWeight; font.pixelSize: 14 }
        }
        Repeater {
          // / and /home on one filesystem report identical numbers; show it once.
          model: {
            var seen = {}, out = []
            var disks = sys.sample ? sys.sample.disks : []
            for (var i = 0; i < disks.length; i++) {
              var key = disks[i].size + ":" + disks[i].used
              if (seen[key]) continue
              seen[key] = true
              out.push(disks[i])
            }
            return out
          }
          AdventureMeter {
            required property var modelData
            cc: sys.cc
            hero: "rogue"
            label: modelData.mount
            value: sys.cc.formatBytes(modelData.used) + " / " + sys.cc.formatBytes(modelData.size)
            fraction: modelData.used / modelData.size
          }
        }
      }
    }

    CcHeading { cc: sys.cc; text: "TOP PROCESSES" }
    Repeater {
      model: sys.sample ? sys.sample.procs : []
      Row {
        required property var modelData
        width: column.width
        Text {
          width: parent.width - 180
          text: modelData.name
          elide: Text.ElideRight
          color: sys.cc.ink; font.family: sys.cc.font; font.pixelSize: 12; font.bold: true
        }
        Text {
          width: 80
          horizontalAlignment: Text.AlignRight
          text: modelData.cpu.toFixed(1) + "%"
          color: sys.cc.ink; font.family: sys.cc.font; font.pixelSize: 12
        }
        Text {
          width: 100
          horizontalAlignment: Text.AlignRight
          text: sys.cc.formatBytes(modelData.mem)
          color: sys.cc.ink; font.family: sys.cc.font; font.pixelSize: 12; opacity: 0.8
        }
      }
    }
  }
}
