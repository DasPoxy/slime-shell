import QtQuick

// Debris for the background of a slime panel (widget popups, the command
// centre): a few bits drifting in the ooze behind the content, faint enough
// that text stays readable, and now and then one of the bar's easter-egg
// adventurers trapped in there too, flailing as it drifts. Follows the bar's
// "bar debris" setting (and, like the bar, shows nothing on plain). Re-rolled
// each time the panel opens (`active` going true), so every peek differs.
Item {
  id: root

  required property var bar
  property bool active: true
  property real bitOpacity: 0.45
  property real captiveChance: 0.16
  property real burst: 0          // 0..1: everything flies apart and fades

  readonly property bool enabled_: !!bar && bar.slimeSkin === true && bar.barDebris === true && bar.material !== "plain"
  visible: enabled_ && active

  property var bits: []
  property string captiveKind: ""
  property real seed: 0

  function reroll() {
    if (!enabled_ || width <= 0 || height <= 0) return
    var kinds = bar.material === "sinew" ? ["eye", "tooth", "sword", "eye", "axe", "skull"]
      : bar.material === "bone" ? ["bone", "skull", "tooth", "sword", "axe", "eye"]
      : ["eye", "bubble", "frog", "bone", "hat", "bubble", "mug", "tooth", "potion", "sword", "axe"]
    var own = ["eye", "bone", "tooth", "bubble"]
    // about one bit per 30k px², kept to a handful
    var n = Math.max(3, Math.min(9, Math.round(width * height / 30000)))
    var out = []
    for (var i = 0; i < n; i++) {
      var kind = kinds[Math.floor(Math.random() * kinds.length)]
      var size = 10 + Math.round(Math.random() * 8)
      if (own.indexOf(kind) === -1) size = Math.round(size * 1.35)
      out.push({ kind: kind, x: 0.06 + Math.random() * 0.88, y: 0.08 + Math.random() * 0.84, s: size, sp: 0.15 + Math.random() * 0.35 })
    }
    bits = out
    var eggs = ["gnome", "goblin", "skeleton", "knight", "wizard", "priest"]
    captiveKind = Math.random() < captiveChance ? eggs[Math.floor(Math.random() * eggs.length)] : ""
    seed = Math.random() * 100
  }
  onActiveChanged: if (active) reroll()
  onEnabled_Changed: if (enabled_) reroll()
  Component.onCompleted: Qt.callLater(reroll)

  SlimeDebris {
    anchors.fill: parent
    bar: root.bar
    bits: root.bits
    bitOpacity: root.bitOpacity
    burst: root.burst
    // big bits in a big panel; a small bead keeps them to its thickness
    room: Math.min(Math.min(width, height) - 4, 44)
  }

  // a trapped adventurer, wandering slowly around the panel
  SlimeCaptive {
    visible: root.captiveKind !== ""
    readonly property real t: root.bar ? root.bar.animTime * 0.07 + root.seed : 0
    size: 26
    x: (root.width - width) * (0.5 + 0.42 * Math.sin(t * 1.3)) + 30 * root.burst
    y: (root.height - height) * (0.5 + 0.4 * Math.sin(t * 0.9 + 1.7)) + 40 * root.burst * root.burst
    rotation: 200 * root.burst
    opacity: 0.6 * (1 - root.burst)
    kind: root.captiveKind || "gnome"
    time: root.bar ? root.bar.animTime : 0
    ink: root.bar ? root.bar.slimeInk : "black"
    paper: root.bar ? root.bar.paperColor : "white"
    goo: root.bar ? root.bar.slimeColor : "green"
    pal: root.bar && root.bar.palette ? root.bar.palette : ({})
  }
}
