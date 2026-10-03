import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Slime Shell: a copy of Omarchy's PopupCard (qs.Ui). On the slime bar the
// popup grows upward to meet the bar and sideways/down to leave room for the
// rim and drips, and the bar's shader draws the card as a blob of ooze
// dripping out of the bar (fed the popup's position as `origin` so it lines
// up with the bar beneath). The card is fully slime; content is inked by
// the bar. Off the slime bar it behaves exactly like the
// original.
PopupWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int margin: Style.gapsOut
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property color borderColor: Color.popups.border
  property var borderSpec: Border.localOrSurfaceSpec("popups", "border", borderColor, Color.popups.border, Math.max(1, Style.space(2)))
  property bool open: false
  property bool centerOnBar: false
  // "click" — uses HyprlandFocusGrab so clicking outside dismisses the popup.
  // "hover" — passive overlay; the owning widget controls open via hover.
  property string triggerMode: "click"
  // nothing on it takes the pointer (a caption dripping over windows)
  property bool clickThrough: false
  // stays mapped while closed (drawing nothing): the compositor restacks
  // windows as a popup unmaps, flashing the bar's drips over its neighbours
  property bool keepMapped: false
  readonly property bool drawsNothing: keepMapped && !open && !(slime && dripProgress > 0)
  // a lyric drip instead of the card shape (see the shader's lyricDrop):
  // x on, y sunk (px), z falling / bursting 0..1, w the bead's height
  property vector4d dropShape: Qt.vector4d(0, 0, 0, 0)
  // where the debris floats (card coordinates; empty = the whole card), and
  // how far it has burst apart (a lyric drip letting go)
  property rect debrisRect: Qt.rect(0, 0, 0, 0)
  property real debrisBurst: 0

  readonly property var coordinatorKey: owner || root

  // ---- Slime ----
  readonly property bool slime: !!bar && bar.slimeSkin === true
  readonly property int sidePad: slime ? 24 : 0      // rim + drips either side
  readonly property int dripPad: slime ? 110 : 0     // drips hanging below
  // Distance from the bar's bottom edge down to the card.
  readonly property int neck: slime ? root.margin + 4 : 0
  property real dripProgress: 0
  property point slimeOrigin: Qt.point(0, 0)      // popup's top-left, screen coords
  readonly property string edge: bar ? bar.position : "top"
  readonly property bool sideBar: edge === "left" || edge === "right"
  // where the card sits inside the popup: the neck toward the bar, drip room
  // away from it, rim room along it
  readonly property real cardX: !slime ? 0 : edge === "left" ? neck : edge === "right" ? dripPad : sidePad
  readonly property real cardY: !slime ? 0 : edge === "top" ? neck : edge === "bottom" ? dripPad : sidePad
  NumberAnimation on dripProgress { id: dripAnim; running: false }
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property var popupScreen: anchorWindow ? anchorWindow.screen : null
  readonly property bool containsMouse: cardHover.hovered
  readonly property real screenW: popupScreen ? popupScreen.width : 0
  readonly property real screenH: popupScreen ? popupScreen.height : 0
  // the bar's thickness (the skinned bar's window is far bigger than the bar
  // itself: it holds the drips and the command centre)
  readonly property real barW: slime ? bar.barSize : (anchorWindow ? anchorWindow.width : 0)
  readonly property real barH: slime ? bar.barSize : (anchorWindow ? anchorWindow.height : 0)
  readonly property real availableCardWidth: screenW > 0
    ? Math.max(120, screenW - ((bar && (bar.position === "left" || bar.position === "right")) ? barW : 0) - root.margin * 2)
    : 0
  readonly property real availableCardHeight: screenH > 0
    ? Math.max(120, screenH - ((bar && (bar.position === "top" || bar.position === "bottom")) ? barH : 0) - root.margin * 2)
    : 0
  readonly property real verticalContentInset: padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)

  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    var maxWidth = root.availableCardWidth > 0 ? root.availableCardWidth : desired
    if (cap !== undefined && Number(cap) > 0) maxWidth = Math.min(maxWidth, Number(cap))
    return Math.round(Math.min(desired, maxWidth))
  }

  function fittedContentHeight(implicitHeight, cap) {
    var desired = Math.max(root.verticalContentInset, (Number(implicitHeight) || 0) + root.verticalContentInset)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    if (cap !== undefined && Number(cap) > 0) maxHeight = Math.min(maxHeight, Number(cap))
    return Math.round(Math.min(desired, maxHeight))
  }

  function cappedContentHeight(height) {
    var desired = Math.max(root.padding * 2, Number(height) || root.padding * 2)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    return Math.round(Math.min(desired, maxHeight))
  }

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  // (not "contentItem": a window has one of its own)
  default property alias contents: contentHolder.children

  visible: keepMapped || open || card.opacity > 0 || (slime && dripProgress > 0)
  color: "transparent"
  implicitWidth: slime && sideBar ? contentWidth + neck + dripPad : contentWidth + sidePad * 2
  implicitHeight: slime && sideBar ? contentHeight + sidePad * 2 : contentHeight + neck + dripPad

  // Only the card (and the neck above it) takes input; the drip room is
  // click-through.
  mask: clickThrough ? noInput : slime ? slimeMask : null
  property Region noInput: Region {}
  property Region slimeMask: Region {
    x: root.edge === "left" ? 0 : root.cardX
    y: root.edge === "top" ? 0 : root.cardY
    width: root.contentWidth + (root.sideBar ? root.neck : 0)
    height: root.contentHeight + (root.sideBar ? 0 : root.neck)
  }

  Component.onDestruction: if (open && bar && triggerMode === "hover" && "hoverPeeks" in bar) bar.hoverPeeks = Math.max(0, bar.hoverPeeks - 1)
  onOpenChanged: {
    if (slime) {
      dripAnim.stop()
      dripAnim.to = open ? 1 : 0
      dripAnim.duration = open ? 600 : 360
      dripAnim.easing.type = open ? Easing.OutQuad : Easing.InQuad
      dripAnim.start()
    }
    // a hover card is a passing peek: it mustn't close the command centre or
    // another widget's panel
    if (bar && triggerMode === "hover" && "hoverPeeks" in bar) {
      bar.hoverPeeks = Math.max(0, bar.hoverPeeks + (open ? 1 : -1))
      return
    }
    if (!bar || triggerMode === "hover") return
    if (open) bar.requestPopout(coordinatorKey)
    else if (bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
  }

  // Outside-click dismissal via Hyprland's focus grab. While `active`, input
  // is routed only to the listed windows; clicking anywhere else clears the
  // grab and we close the popup. Skipped for hover-mode popups so the cursor
  // can move freely between the trigger and the popup.
  HyprlandFocusGrab {
    active: root.open && root.triggerMode === "click"
    windows: root.anchorWindow ? [root, root.anchorWindow] : [root]
    onCleared: root.close()
  }

  anchor {
    id: popupAnchor
    window: anchorItem ? anchorItem.QsWindow.window : null
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1

    onAnchoring: {
      if (!root.anchorItem || !root.bar) return

      var target = root.anchorItem
      var popupWidth = root.implicitWidth
      var popupHeight = root.implicitHeight
      var localX = target.width / 2 - popupWidth / 2
      var localY = target.height + root.margin

      if (root.bar.position === "bottom") {
        localY = -popupHeight - root.margin
      } else if (root.bar.position === "left") {
        localX = target.width + root.margin
        localY = target.height / 2 - popupHeight / 2
      } else if (root.bar.position === "right") {
        localX = -popupWidth - root.margin
        localY = target.height / 2 - popupHeight / 2
      }

      var window = target.QsWindow.window
      if (!window) return

      if (root.centerOnBar) {
        var cx = 0;
        var cy = 0;
        if (root.bar.position === "top" || root.bar.position === "bottom") {
          // measured from the bar itself, not its window (the skinned bar's
          // window reaches far past the bar)
          cx = window.width / 2 - popupWidth / 2
          cy = root.bar.position === "bottom" ? window.height - root.barH - popupHeight - root.margin : root.barH + root.margin
          cx = Math.max(root.margin, Math.min(cx, window.width - popupWidth - root.margin))
        } else {
          cx = root.bar.position === "left" ? root.barW + root.margin : window.width - root.barW - popupWidth - root.margin
          cy = window.height / 2 - popupHeight / 2
          cy = Math.max(root.margin, Math.min(cy, window.height - popupHeight - root.margin))
        }

        popupAnchor.rect.x = Math.round(cx)
        popupAnchor.rect.y = Math.round(cy)
        return
      }

      var point = window.contentItem.mapFromItem(target, localX, localY)

      if (root.slime) {
        // flush against the bar on whichever edge it's on, slid along it
        var bs = root.bar.barSize
        if (root.edge === "top") point.y = bs - 2
        else if (root.edge === "bottom") point.y = window.height - bs + 2 - popupHeight
        else if (root.edge === "left") point.x = bs - 2
        else point.x = window.width - bs + 2 - popupWidth
        if (root.sideBar)
          point.y = Math.max(root.margin - root.sidePad, Math.min(point.y, window.height - popupHeight - root.margin + root.sidePad))
        else
          point.x = Math.max(root.margin - root.sidePad, Math.min(point.x, window.width - popupWidth - root.margin + root.sidePad))
        point.x = Math.round(point.x)
        point.y = Math.round(point.y)
        var so = window.screenOrigin ? window.screenOrigin : Qt.vector2d(0, 0)
        root.slimeOrigin = Qt.point(point.x + so.x, point.y + so.y)
        popupAnchor.rect.x = point.x
        popupAnchor.rect.y = point.y
        return
      }

      if (root.bar.position === "top" || root.bar.position === "bottom") {
        point.x = Math.max(root.margin, Math.min(point.x, window.width - popupWidth - root.margin))
      } else {
        point.y = Math.max(root.margin, Math.min(point.y, window.height - popupHeight - root.margin))
      }

      popupAnchor.rect.x = Math.round(point.x)
      popupAnchor.rect.y = Math.round(point.y)
    }
  }

  ShaderEffect {
    id: slimeShader
    visible: root.slime && root.dripProgress > 0
    anchors.fill: parent
    fragmentShader: Qt.resolvedUrl("../shaders/slime.frag.qsb")
    // every shader uniform set explicitly: unset ones are not guaranteed to be 0
    // (every pixel culled while it's only being kept mapped)
    property vector4d cullRect: root.drawsNothing ? Qt.vector4d(0, -1, -1, 1) : Qt.vector4d(0, 0, 0, 0)
    property real blobMode: 0

    readonly property var bulbs: root.anchorWindow && root.anchorWindow.bulbRects ? root.anchorWindow.bulbRects : []
    readonly property vector4d noBulb: Qt.vector4d(0, 0, 0, 0)

    property vector2d origin: Qt.vector2d(root.slimeOrigin.x, root.slimeOrigin.y)
    property real orient: root.slime ? root.bar.orientId : 0
    readonly property var scr: root.anchorWindow && root.anchorWindow.screen ? root.anchorWindow.screen : null
    property vector2d screenSize: scr ? Qt.vector2d(scr.width, scr.height) : Qt.vector2d(0, 0)
    // the card in bar space (see SlimeKeyboardPanel)
    readonly property real cx: origin.x + root.cardX
    readonly property real cy: origin.y + root.cardY
    readonly property real along: root.sideBar ? cy : cx
    readonly property real alongLen: root.sideBar ? root.contentHeight : root.contentWidth
    readonly property real reach: root.edge === "top" ? cy + root.contentHeight
      : root.edge === "bottom" ? screenSize.y - cy
      : root.edge === "left" ? cx + root.contentWidth
      : screenSize.x - cx
    property real time: root.slime ? root.bar.animTime : 0
    property real barHeight: root.slime ? root.bar.barSize : 0
    property real openProgress: root.dripProgress
    property real dripAmount: root.slime ? root.bar.dripLevel : 1
    property real shadingStyle: root.slime ? root.bar.shadingStyle : 3
    property vector2d resolution: Qt.vector2d(width, height)
    // In bar coordinates: the blob hangs from the bar's edge to the card's bottom.
    property vector4d panelRect: Qt.vector4d(along, 0, alongLen, reach - barHeight)
    property color slimeColor: root.slime ? root.bar.slimeColor : "black"
    property color slimeColor2: root.slime ? root.bar.slimeColor2 : "black"
    property color paperColor: root.slime ? root.bar.paperColor : "white"
    property real clipTop: barHeight - 2
    property real poolDepth: 0     // fully slime, like the command centre
    // the bar's physical shape, so this window's drips line up with it
    property real barShape: root.slime ? root.bar.barShapeId : 0
    property real material: root.slime ? root.bar.materialId : 0
    property vector4d dripStyle: root.slime ? root.bar.dripStyleVec : Qt.vector4d(1, 1, 0, 1)
    property vector4d dripExtra: root.slime ? root.bar.dripExtraVec : Qt.vector4d(0, 0, 0, 0)
    property vector4d cava0: root.bar ? root.bar.cava0 : Qt.vector4d(0, 0, 0, 0)
    property vector4d cava1: root.bar ? root.bar.cava1 : Qt.vector4d(0, 0, 0, 0)
    property vector4d cava2: root.bar ? root.bar.cava2 : Qt.vector4d(0, 0, 0, 0)
    property vector4d cava3: root.bar ? root.bar.cava3 : Qt.vector4d(0, 0, 0, 0)
    property vector4d cavaOpts: root.bar ? root.bar.cavaOpts : Qt.vector4d(0, 0, 0, 0)
    property vector4d dockBracket: root.bar ? root.bar.dockBracketVec : Qt.vector4d(0, 0, 0, 0)
    property vector4d dropShape: root.dropShape
    property vector4d eggDrip: Qt.vector4d(0, 0, 0, 0)
    property vector4d group0: root.slime && root.bar.sharedGroupRects[0] ? root.bar.sharedGroupRects[0] : noBulb
    property vector4d group1: root.slime && root.bar.sharedGroupRects[1] ? root.bar.sharedGroupRects[1] : noBulb
    property vector4d group2: root.slime && root.bar.sharedGroupRects[2] ? root.bar.sharedGroupRects[2] : noBulb
    property vector4d bulb0: bulbs[0] || noBulb
    property vector4d bulb1: bulbs[1] || noBulb
    property vector4d bulb2: bulbs[2] || noBulb
    property vector4d bulb3: bulbs[3] || noBulb
    property vector4d bulb4: bulbs[4] || noBulb
    property vector4d bulb5: bulbs[5] || noBulb
    property vector4d bulb6: bulbs[6] || noBulb
    property vector4d bulb7: bulbs[7] || noBulb
    property vector4d bulb8: bulbs[8] || noBulb
    property vector4d bulb9: bulbs[9] || noBulb
    property vector4d bulb10: bulbs[10] || noBulb
    property vector4d bulb11: bulbs[11] || noBulb
    property vector4d bulb12: bulbs[12] || noBulb
    property vector4d bulb13: bulbs[13] || noBulb
    property vector4d bulb14: bulbs[14] || noBulb
    property vector4d bulb15: bulbs[15] || noBulb
    property vector4d bulb16: bulbs[16] || noBulb
    property vector4d bulb17: bulbs[17] || noBulb
    property vector4d bulb18: bulbs[18] || noBulb
    property vector4d bulb19: bulbs[19] || noBulb
    property vector4d bulb20: bulbs[20] || noBulb
    property vector4d bulb21: bulbs[21] || noBulb
    property vector4d bulb22: bulbs[22] || noBulb
    property vector4d bulb23: bulbs[23] || noBulb
  }

  BorderSurface {
    id: card
    x: root.cardX
    y: root.cardY
    width: root.contentWidth
    height: root.contentHeight
    // On slime the ooze is the card; the surface itself goes clear.
    color: root.slime ? "transparent" : Color.popups.background
    borderSpec: root.slime ? Border.none() : root.borderSpec
    padding: root.padding
    radius: Style.cornerRadius
    opacity: root.slime ? Math.max(0, (root.dripProgress - 0.75) / 0.25) : (root.open ? 1.0 : 0)

    Behavior on opacity {
      enabled: !root.slime
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    // bits adrift in the ooze behind the content (the "bar debris" setting)
    SlimePanelDebris {
      readonly property bool own: root.debrisRect.width > 0
      x: own ? root.debrisRect.x : 0
      y: own ? root.debrisRect.y : 0
      width: own ? root.debrisRect.width : parent.width
      height: own ? root.debrisRect.height : parent.height
      bar: root.bar
      active: root.open && root.slime
      burst: root.debrisBurst
      // a small bead holds a couple of bits, not a panel's worth
      bitOpacity: own ? 0.55 : 0.45
    }

    Item {
      id: contentHolder
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
    }

    HoverHandler {
      id: cardHover
    }
  }
}
