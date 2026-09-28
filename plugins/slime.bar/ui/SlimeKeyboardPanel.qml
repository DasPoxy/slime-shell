import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Slime Shell: a copy of Omarchy's KeyboardPanel (qs.Ui) that, on the slime
// bar, drips its card out of the bar as a blob of ooze instead of fading in a
// flat card. The slime is drawn by the bar's shader running in this window,
// fed the bar's own clock and uniforms so it lines up with the bar beneath,
// and clipped to below the bar so the bar's widgets stay visible. The card is
// fully slime like the command centre; panel content is inked by the bar. Off the slime bar it behaves exactly like the
// original.
//
// Upstream notes follow.
//
// Layer-shell popup attached to a bar widget icon, designed for
// click-driven AND keyboard-driven panels (e.g. SUPER+CTRL+W summon).
//
// Built on PanelWindow with a brief WlrKeyboardFocus.Exclusive prime followed
// by OnDemand rather than PopupWindow (xdg-popup). The prime acquires focus
// both when the surface maps and when it reopens while still mapped for its
// fade-out. xdg-popups don't get that — they only receive keys after a
// click/hover routes focus through their parent surface — so keyboard-summoned
// popups fell flat without it.
//
// Exclusive would also grant map-time focus, but it makes Hyprland route
// *every* pointer event to the exclusive surface no matter which output
// the cursor is over, which leaves clicks on any other monitor unable to
// reach the dismissal surfaces below.
//
// API is a subset of Common.PopupCard: anchorItem, owner, bar, open,
// padding, margin, contentWidth/Height, centerOnBar, default contentItem.
// Missing on purpose (for now): triggerMode ("hover"), containsMouse.
//
// Positioning: full-screen layer-shell with the card placed inside at
// `cardOrigin`. We use the bar window's height/width for the perpendicular
// axis (away-from-bar) because mapToItem on the anchor returns
// bar-content-relative coords with internal layout offsets baked in
// (e.g. ~13px from the bar's vertical centering of its widget row). The
// parallel axis (along-the-bar) uses the anchor's content x/y since the
// bar spans full screen on that axis.
//
// Outside-click dismissal: an overlay MouseArea catches clicks, with the
// QsWindow.mask subtracting the bar strip so clicks on the bar still
// reach the bar widgets (activePopout coordinator hands off to another
// popup if the user clicks a different bar icon).
PanelWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int margin: Style.gapsOut
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
  property bool centerOnBar: false
  property bool open: false
  property int gap: Style.gapsOut  // distance between bar edge and panel
  property bool popoutSwitching: false
  property bool popoutSwitchClosing: false
  property bool focusPrimed: false

  // Item that should take keyboard focus once the panel maps. Typically a
  // PanelKeyCatcher inside the panel content. Layer-shell grants focus to the
  // surface during the Exclusive prime, but Qt still needs an active-focus
  // target inside the surface for Keys.onPressed handlers to fire. Schedule
  // the focus through Qt.callLater so it runs after the surface is fully
  // mapped and child items have completed layout.
  property Item focusTarget: null

  default property alias contentItem: contentHolder.children

  readonly property var coordinatorKey: owner || root

  // ---- Slime ----
  readonly property bool slime: !!bar && bar.slimeSkin === true
  // 0 closed, 1 fully dripped open.
  property real dripProgress: 0
  NumberAnimation on dripProgress { id: dripAnim; running: false }
  function animateDrip(opening) {
    dripAnim.stop()
    dripAnim.to = opening ? 1 : 0
    dripAnim.duration = opening ? 650 : 380
    dripAnim.easing.type = opening ? Easing.OutQuad : Easing.InQuad
    dripAnim.start()
  }
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property string barPos: bar ? bar.position : "top"

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  function beginFocusPrime() {
    if (open && backingWindowVisible) focusPrimeTimer.restart()
  }

  // --- screen + lifetime ---------------------------------------------------

  screen: anchorWindow ? anchorWindow.screen : null
  visible: open || card.opacity > 0 || popoutSwitching || (slime && dripProgress > 0)
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: "omarchy-keyboard-panel"
  WlrLayershell.layer: WlrLayer.Overlay
  // Keyboard focus follows `open` (NOT `visible`). The window remains
  // mapped during the fade-out so the opacity animation has something to
  // animate, but keyboard/click ownership must release the moment the
  // logical close fires — otherwise the user is locked out for 140ms.
  //
  // Prime with Exclusive on every open, then settle on OnDemand. Hyprland
  // focuses OnDemand when a surface first maps, but not when an already-mapped
  // fade-out surface changes from None back to OnDemand. Exclusive also takes
  // focus when the previously focused application has constrained the pointer.
  // The brief prime covers both cases; OnDemand then releases compositor-wide
  // pointer hit-testing so clicks can reach the dismissal windows below.
  WlrLayershell.keyboardFocus: open
    ? (focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
    : WlrKeyboardFocus.None

  onBackingWindowVisibleChanged: beginFocusPrime()

  // Full-screen layer-shell. The visible card is positioned inside via
  // `cardOrigin`. The `mask` below makes the bar area click-through (so
  // the user can click another bar icon while the panel is open and the
  // activePopout coordinator swaps to that popup); everywhere else, the
  // overlay catches the click and dismisses via the MouseArea below.
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // Clickable region is the whole screen. Clicks in the bar strip are
  // forwarded to registered bar buttons so switching between panel icons
  // works in one click even when the overlay surface is above the bar.
  readonly property real _barStripSize: {
    if (!bar) return 0
    var actual = (root.barPos === "top" || root.barPos === "bottom") ? root.barH : root.barW
    return Math.max(bar.barSize, actual) + root.gap
  }
  mask: Region {
    width: root.screenW
    height: root.screenH
  }

  // Track every layout change between the bar's contentItem and the
  // anchor item. `transform` updates whenever any item in that chain
  // moves/resizes, which is what makes the position binding below
  // actually reactive — mapToItem on its own is a one-shot.
  TransformWatcher {
    id: anchorWatcher
    a: anchorWindow ? anchorWindow.contentItem : null
    b: anchorItem
  }

  // Anchor item's position within the bar's content surface. For a
  // full-width top bar, the content x maps directly to screen x; the y
  // returned here has the bar's internal padding baked in (e.g. ~13px
  // from vertical centering of the widget row), which is why `cardOrigin`
  // below uses `barH` for the perpendicular axis instead of this y.
  readonly property point anchorScreenPos: {
    anchorWatcher.transform  // reactive dependency
    if (!anchorItem || !anchorWindow) return Qt.point(0, 0)
    return anchorItem.mapToItem(anchorWindow.contentItem, 0, 0)
  }
  readonly property real anchorW: anchorItem ? anchorItem.width : 0
  readonly property real anchorH: anchorItem ? anchorItem.height : 0
  readonly property real screenW: screen ? screen.width : 0
  readonly property real screenH: screen ? screen.height : 0
  readonly property real availableCardWidth: screenW > 0
    ? Math.max(120, screenW - ((barPos === "left" || barPos === "right") ? barW + gap + margin : margin * 2))
    : 0
  readonly property real availableCardHeight: screenH > 0
    ? Math.max(120, screenH - ((barPos === "top" || barPos === "bottom") ? barH + gap + margin : margin * 2))
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

  // Desired top-left of the card in screen coordinates. For the
  // perpendicular axis (away-from-bar) we anchor to the bar window's edge
  // directly — not the anchor item's y/x — because mapToItem(barContent)
  // returns coordinates in the bar's content space, which can be offset
  // from the bar surface's screen-anchored corner by internal layout
  // (centering wrappers, padding). The bar's surface IS aligned to its
  // anchored screen edge, so using `barW`/`barH` gives the right edge
  // regardless of how the bar's internal widgets are positioned. For the
  // parallel axis (along the bar) the anchor item's reported position is
  // still consistent with the bar content origin, so it's accurate for
  // centering the card under the icon.
  readonly property real barW: slime ? bar.barSize : (anchorWindow ? anchorWindow.width : screenW)
  readonly property real barH: slime ? bar.barSize : (anchorWindow ? anchorWindow.height : 0)
  // Floating: the panel sits in the middle of the screen as a free-standing
  // blob that swells open, instead of dripping out of the bar (used when a
  // panel is summoned by keybind rather than clicked on the bar).
  property bool floating: false

  readonly property point cardOrigin: {
    if (floating) return Qt.point(Math.round(screenW / 2 - contentWidth / 2), Math.round(screenH * 0.42 - contentHeight / 2))
    if (!anchorItem || !bar) return Qt.point(margin, margin)
    var x = 0, y = 0
    if (centerOnBar && (barPos === "top" || barPos === "bottom")) {
      x = screenW / 2 - contentWidth / 2
      y = barPos === "bottom" ? screenH - barH - contentHeight - gap : barH + gap
    } else if (centerOnBar) {
      x = barPos === "left" ? barW + gap : screenW - barW - contentWidth - gap
      y = screenH / 2 - contentHeight / 2
    } else if (barPos === "bottom") {
      x = anchorScreenPos.x + anchorW / 2 - contentWidth / 2
      y = screenH - barH - contentHeight - gap
    } else if (barPos === "left") {
      x = barW + gap
      y = anchorScreenPos.y + anchorH / 2 - contentHeight / 2
    } else if (barPos === "right") {
      x = screenW - barW - contentWidth - gap
      y = anchorScreenPos.y + anchorH / 2 - contentHeight / 2
    } else { // "top" (default)
      x = anchorScreenPos.x + anchorW / 2 - contentWidth / 2
      y = barH + gap
    }
    x = Math.max(margin, Math.min(x, screenW - contentWidth - margin))
    y = Math.max(margin, Math.min(y, screenH - contentHeight - margin))
    return Qt.point(Math.round(x), Math.round(y))
  }


  // --- popout coordination (same-bar single-popout model) -----------------

  // Coordinate on `open`, not `visible`. `visible` lags into the fade-out
  // animation, which made ownership transfer to a sibling popup race.
  onOpenChanged: {
    if (slime) animateDrip(open)
    if (open) {
      focusPrimed = false
      beginFocusPrime()
      if (focusTarget) Qt.callLater(function() {
        if (root.open && root.focusTarget) root.focusTarget.forceActiveFocus()
      })
    } else {
      focusPrimeTimer.stop()
      focusPrimed = false
    }
    if (!bar) return
    if (open) {
      popoutSwitchClosing = false
      popoutSwitching = bar.activePopout && bar.activePopout !== coordinatorKey
      bar.requestPopout(coordinatorKey)
      if (popoutSwitching) popoutSwitchTimer.restart()
    } else {
      popoutSwitchClosing = !!(owner && owner.popoutSwitchClosing)
      popoutSwitching = false
      if (bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
      if (popoutSwitchClosing) closeSwitchTimer.restart()
    }
  }

  Timer {
    id: focusPrimeTimer
    // Leave enough time for multiple Qt/Wayland commit cycles after the
    // backing window becomes visible while keeping the compositor-wide
    // Exclusive phase imperceptibly short. This interval is covered by the
    // immediate hide/re-summon acceptance case.
    interval: 75
    onTriggered: if (root.open) root.focusPrimed = true
  }

  Timer {
    id: popoutSwitchTimer
    interval: 150
    onTriggered: root.popoutSwitching = false
  }

  Timer {
    id: closeSwitchTimer
    interval: 1
    onTriggered: root.popoutSwitchClosing = false
  }

  // --- outside-click dismissal --------------------------------------------

  // Catches clicks anywhere in the clickable region (i.e. everywhere on
  // screen except the bar strip, which is masked out). The card has its
  // own MouseArea below so clicks on it don't bubble up here. Disabled
  // during the fade-out so the dying overlay doesn't swallow clicks that
  // were meant for the apps behind it.
  MouseArea {
    id: dismissArea
    anchors.fill: parent
    enabled: root.open
    acceptedButtons: Qt.AllButtons
    hoverEnabled: true
    property bool hoveringBar: false
    cursorShape: hoveringBar ? Qt.PointingHandCursor : Qt.ArrowCursor

    function inBarRegion(px, py) {
      if (root.barPos === "bottom") return py >= root.screenH - root._barStripSize
      if (root.barPos === "left") return px <= root._barStripSize
      if (root.barPos === "right") return px >= root.screenW - root._barStripSize
      return py <= root._barStripSize
    }

    function barPoint(px, py) {
      // the bar's window is thicker than the bar when skinned, so offset by
      // the window's real size
      var winH = root.anchorWindow ? root.anchorWindow.height : root.barH
      var winW = root.anchorWindow ? root.anchorWindow.width : root.barW
      if (root.barPos === "bottom") return Qt.point(px, py - (root.screenH - winH))
      if (root.barPos === "right") return Qt.point(px - (root.screenW - winW), py)
      return Qt.point(px, py)
    }

    function pressTargetAt(px, py) {
      if (!root.anchorWindow || !root.anchorWindow.contentItem || !root.bar || !root.bar.clickTargets) return null
      var p = barPoint(px, py)
      var targets = root.bar.clickTargets
      for (var i = targets.length - 1; i >= 0; i--) {
        var target = targets[i]
        if (!target || !target.triggerPress || target.visible === false || target.opacity === 0 || !target.mapToItem) continue
        if (root.bar.targetBelongsToWindow && !root.bar.targetBelongsToWindow(target, root.anchorWindow)) continue
        var pos = root.anchorWindow.itemPosition(target)
        if (p.x >= pos.x && p.x <= pos.x + target.width && p.y >= pos.y && p.y <= pos.y + target.height) return target
      }
      return null
    }

    function forwardBarClick(px, py, button) {
      if (button !== Qt.LeftButton && button !== Qt.RightButton && button !== Qt.MiddleButton) return false
      var target = pressTargetAt(px, py)
      if (!target) return false
      target.triggerPress(button)
      return true
    }

    onPositionChanged: function(mouse) { hoveringBar = inBarRegion(mouse.x, mouse.y) }
    onExited: hoveringBar = false
    onClicked: function(mouse) {
      // While Exclusive is priming, Hyprland may route a click from another
      // output here with translated coordinates. Never interpret that as a
      // click on this output's bar.
      if (root.focusPrimed && inBarRegion(mouse.x, mouse.y) && forwardBarClick(mouse.x, mouse.y, mouse.button)) return
      root.close()
    }
  }

  // The panel surface only spans the anchor's screen, and the compositor
  // hit-tests pointer input per output, so `dismissArea` above can never see
  // a click on another monitor. Give every other output a transparent twin
  // whose only job is to catch that click. They exist only while the panel is
  // logically open (not during the fade-out, matching `dismissArea.enabled`).
  //
  // Keyboard focus is None: these must catch the pointer without taking focus
  // from the panel when the cursor merely crosses onto their output.
  Variants {
    model: root.open ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        required property var modelData

        screen: modelData
        // Compare by output name: the anchor screen must be known before any
        // twin maps, or a twin would cover the panel's own output.
        visible: root.open && !!root.screen && modelData.name !== root.screen.name
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "omarchy-keyboard-panel-dismiss"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
          onPressed: root.close()
        }
      }
    }
  }

  // --- slime ---------------------------------------------------------------

  ShaderEffect {
    id: slimeShader
    visible: root.slime && root.dripProgress > 0
    anchors.fill: parent
    fragmentShader: Qt.resolvedUrl("../shaders/slime.frag.qsb")
    // every shader uniform set explicitly: unset ones are not guaranteed to be 0
    property vector2d origin: Qt.vector2d(0, 0)          // full-screen window
    property real orient: root.slime && !root.floating ? root.bar.orientId : 0
    property vector2d screenSize: Qt.vector2d(root.screenW, root.screenH)
    // the card in bar space: start and length along the bar, and how far it
    // reaches out from the bar's edge
    readonly property real along: orient >= 1.5 ? card.y : card.x
    readonly property real alongLen: orient >= 1.5 ? card.height : card.width
    readonly property real reach: orient < 0.5 ? card.y + card.height
      : orient < 1.5 ? root.screenH - card.y
      : orient < 2.5 ? card.x + card.width
      : root.screenW - card.x
    property real blobMode: root.floating ? 1 : 0

    readonly property var bulbs: root.anchorWindow && root.anchorWindow.bulbRects ? root.anchorWindow.bulbRects : []
    readonly property vector4d noBulb: Qt.vector4d(0, 0, 0, 0)

    property real time: root.slime ? root.bar.animTime : 0
    property real barHeight: root.slime ? root.bar.barSize : 0
    property real openProgress: root.dripProgress
    property real dripAmount: root.slime ? root.bar.dripLevel : 1
    property real shadingStyle: root.slime ? root.bar.shadingStyle : 3
    property vector2d resolution: Qt.vector2d(width, height)
    // The blob hangs from the bar's edge down to the card's bottom.
    // floating: the card's own rect, swelling from 40% as it opens
    readonly property real swell: 0.4 + 0.6 * Math.min(1, openProgress / 0.8)
    property vector4d panelRect: root.floating
      ? Qt.vector4d(card.x + card.width * (1 - swell) / 2, card.y + card.height * (1 - swell) / 2, card.width * swell, card.height * swell)
      : Qt.vector4d(along, 0, alongLen, reach - barHeight)
    property color slimeColor: root.slime ? root.bar.slimeColor : "black"
    property color slimeColor2: root.slime ? root.bar.slimeColor2 : "black"
    property color paperColor: root.slime ? root.bar.paperColor : "white"
    // Only draw below the bar and around this panel; the bar paints the rest.
    property real clipTop: root.floating ? -100000 : barHeight - 2
    property vector4d cullRect: root.floating
      ? Qt.vector4d(card.x - 60, card.x + card.width + 60, card.y + card.height + 160, 1)
      : Qt.vector4d(along - 60, along + alongLen + 60, reach + 160, 1)
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
    property vector4d dropShape: Qt.vector4d(0, 0, 0, 0)
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

  // --- card ----------------------------------------------------------------

  BorderSurface {
    id: card
    x: root.cardOrigin.x
    y: root.cardOrigin.y
    width: root.contentWidth
    height: root.contentHeight
    // On slime the ooze is the card; the surface itself goes clear.
    color: root.slime ? "transparent" : Color.popups.background
    borderSpec: root.slime ? Border.none() : root.borderSpec
    padding: root.padding
    radius: Style.cornerRadius
    opacity: root.slime
      ? Math.max(0, (root.dripProgress - 0.75) / 0.25)
      : (root.open || root.popoutSwitching ? 1.0 : 0)

    Behavior on opacity {
      enabled: !root.slime && !root.popoutSwitching && !root.popoutSwitchClosing
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    // Swallow clicks on the card so they don't bubble to the dismissal
    // MouseArea behind us.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
    }

    // bits adrift in the ooze behind the content (the "bar debris" setting)
    SlimePanelDebris {
      anchors.fill: parent
      bar: root.bar
      active: root.open && root.slime
    }

    Item {
      id: contentHolder
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      opacity: root.popoutSwitching ? (root.open ? 1.0 : 0) : 1.0

      Behavior on opacity {
        enabled: root.popoutSwitching
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
    }
  }
}
