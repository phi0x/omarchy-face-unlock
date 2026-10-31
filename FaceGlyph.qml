import QtQuick

// Face ID-style glyph: four rounded viewfinder corners framing a minimal face.
//
//   idle      corners and face at rest, breathing gently
//   scanning  a ring of ticks sweeps around the frame while a scan line
//             passes over the face
//   success   the frame tightens, the ring fills, the face becomes a check
//   failure   a short head-shake, tinted with the error colour
//   resting   dimmed (cooldown / paused / disabled)
Item {
  id: root

  property string mode: "idle"          // idle | scanning | success | failure | resting
  property color color: "white"
  property color successColor: "#7ed492"
  property color errorColor: "#e06c75"

  // Animation drivers, all repaint the canvas.
  property real phase: 0                // 0..1, ring sweep + scan line
  property real ring: 0                 // ring visibility 0..1
  property real check: 0                // face -> checkmark morph 0..1
  property real tighten: 0              // frame contraction 0..1
  property real shakeX: 0
  property real breathe: 0
  property color tint: color

  signal clicked()

  implicitWidth: 112
  implicitHeight: 112
  opacity: mode === "resting" ? 0.42 : 1.0

  Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
  Behavior on tint { ColorAnimation { duration: 220 } }
  Behavior on ring { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

  onModeChanged: {
    if (mode !== "success") {
      successAnim.stop()
      check = 0
      tighten = 0
    }
    if (mode === "scanning") {
      check = 0
      tighten = 0
      tint = color
      ring = 1
    } else if (mode === "success") {
      tint = successColor
      ring = 1
      successAnim.restart()
    } else if (mode === "failure") {
      tint = errorColor
      ring = 0
      shakeAnim.restart()
    } else {
      ring = 0
      tint = color
    }
  }
  onColorChanged: if (mode !== "success" && mode !== "failure") tint = color

  onPhaseChanged: canvas.requestPaint()
  onRingChanged: canvas.requestPaint()
  onCheckChanged: canvas.requestPaint()
  onTightenChanged: canvas.requestPaint()
  onTintChanged: canvas.requestPaint()
  onBreatheChanged: canvas.requestPaint()

  NumberAnimation on phase {
    running: root.visible && (root.mode === "scanning" || root.ring > 0.01)
    from: 0; to: 1
    duration: 1400
    loops: Animation.Infinite
  }

  SequentialAnimation on breathe {
    running: root.visible && root.mode === "idle"
    loops: Animation.Infinite
    NumberAnimation { from: 0; to: 1; duration: 2200; easing.type: Easing.InOutSine }
    NumberAnimation { from: 1; to: 0; duration: 2200; easing.type: Easing.InOutSine }
  }

  ParallelAnimation {
    id: successAnim
    NumberAnimation { target: root; property: "tighten"; from: 0; to: 1; duration: 260; easing.type: Easing.OutBack }
    SequentialAnimation {
      PauseAnimation { duration: 90 }
      NumberAnimation { target: root; property: "check"; from: 0; to: 1; duration: 340; easing.type: Easing.OutCubic }
    }
  }

  SequentialAnimation {
    id: shakeAnim
    NumberAnimation { target: root; property: "shakeX"; to: -9; duration: 55; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "shakeX"; to: 8; duration: 80; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "shakeX"; to: -6; duration: 75; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "shakeX"; to: 4; duration: 70; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "shakeX"; to: 0; duration: 90; easing.type: Easing.OutQuad }
  }

  Canvas {
    id: canvas
    width: Math.min(root.width, root.height)
    height: width
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: root.shakeX
    antialiasing: true
    renderStrategy: Canvas.Cooperative

    function lerp(a, b, t) { return a + (b - a) * t }

    onPaint: {
      var ctx = getContext("2d")
      var s = width
      ctx.reset()
      ctx.clearRect(0, 0, s, s)
      ctx.lineCap = "round"
      ctx.lineJoin = "round"

      var c = root.tint
      function rgba(a) { return Qt.rgba(c.r, c.g, c.b, a * c.a) }

      // --- tick ring -------------------------------------------------------
      if (root.ring > 0.01) {
        var ticks = 48
        var rOuter = s * 0.495
        var rInner = s * 0.445
        ctx.lineWidth = Math.max(1.5, s * 0.016)
        var full = root.mode === "success"
        for (var i = 0; i < ticks; i++) {
          var t = i / ticks
          var a = t * Math.PI * 2 - Math.PI / 2
          // A bright head with a fading tail sweeping clockwise.
          var d = (t - root.phase + 1) % 1
          var lit = full ? 1 : Math.pow(1 - d, 3)
          var alpha = (0.14 + 0.86 * lit) * root.ring
          ctx.strokeStyle = rgba(alpha)
          ctx.beginPath()
          ctx.moveTo(s / 2 + Math.cos(a) * rInner, s / 2 + Math.sin(a) * rInner)
          ctx.lineTo(s / 2 + Math.cos(a) * rOuter, s / 2 + Math.sin(a) * rOuter)
          ctx.stroke()
        }
      }

      // --- viewfinder corners ---------------------------------------------
      var breath = root.mode === "idle" ? root.breathe * 0.012 : 0
      var inset = s * (lerp(0.2, 0.26, root.tighten) - breath)
      var x0 = inset, y0 = inset, x1 = s - inset, y1 = s - inset
      var arm = (x1 - x0) * 0.27
      var r = (x1 - x0) * 0.2
      ctx.lineWidth = Math.max(2, s * 0.042)
      ctx.strokeStyle = rgba(1)

      function corner(cx, cy, dx, dy) {
        // (cx, cy) is the frame corner; dx/dy point inwards.
        ctx.beginPath()
        ctx.moveTo(cx, cy + dy * arm)
        ctx.lineTo(cx, cy + dy * r)
        ctx.quadraticCurveTo(cx, cy, cx + dx * r, cy)
        ctx.lineTo(cx + dx * arm, cy)
        ctx.stroke()
      }
      corner(x0, y0, 1, 1)
      corner(x1, y0, -1, 1)
      corner(x0, y1, 1, -1)
      corner(x1, y1, -1, -1)

      // --- face ------------------------------------------------------------
      var w = x1 - x0
      var fx = function(u) { return x0 + w * u }
      var fy = function(v) { return y0 + w * v }
      var faceAlpha = 1 - Math.min(1, root.check * 1.6)
      ctx.lineWidth = Math.max(2, s * 0.036)

      if (faceAlpha > 0.01) {
        ctx.strokeStyle = rgba(faceAlpha)
        // eyes
        ctx.beginPath(); ctx.moveTo(fx(0.33), fy(0.33)); ctx.lineTo(fx(0.33), fy(0.43)); ctx.stroke()
        ctx.beginPath(); ctx.moveTo(fx(0.67), fy(0.33)); ctx.lineTo(fx(0.67), fy(0.43)); ctx.stroke()
        // nose
        ctx.beginPath()
        ctx.moveTo(fx(0.5), fy(0.34))
        ctx.lineTo(fx(0.5), fy(0.58))
        ctx.lineTo(fx(0.44), fy(0.58))
        ctx.stroke()
        // smile
        ctx.beginPath()
        ctx.moveTo(fx(0.32), fy(0.68))
        ctx.quadraticCurveTo(fx(0.5), fy(0.84), fx(0.68), fy(0.68))
        ctx.stroke()
      }

      // --- scan line -------------------------------------------------------
      if (root.mode === "scanning") {
        var sweep = (Math.sin(root.phase * Math.PI * 2) + 1) / 2
        var ly = lerp(y0 + w * 0.12, y1 - w * 0.12, sweep)
        var grad = ctx.createLinearGradient(x0, 0, x1, 0)
        grad.addColorStop(0, rgba(0))
        grad.addColorStop(0.5, rgba(0.85))
        grad.addColorStop(1, rgba(0))
        ctx.strokeStyle = grad
        ctx.lineWidth = Math.max(1.5, s * 0.02)
        ctx.beginPath()
        ctx.moveTo(x0 + w * 0.08, ly)
        ctx.lineTo(x1 - w * 0.08, ly)
        ctx.stroke()
      }

      // --- checkmark -------------------------------------------------------
      if (root.check > 0.01) {
        var p = Math.min(1, root.check)
        var ax = fx(0.27), ay = fy(0.53)
        var bx = fx(0.44), by = fy(0.70)
        var cx2 = fx(0.75), cy2 = fy(0.33)
        var l1 = Math.hypot(bx - ax, by - ay)
        var l2 = Math.hypot(cx2 - bx, cy2 - by)
        var len = (l1 + l2) * p
        ctx.strokeStyle = rgba(1)
        ctx.lineWidth = Math.max(2.5, s * 0.05)
        ctx.beginPath()
        ctx.moveTo(ax, ay)
        if (len <= l1) {
          ctx.lineTo(lerp(ax, bx, len / l1), lerp(ay, by, len / l1))
        } else {
          ctx.lineTo(bx, by)
          var t2 = (len - l1) / l2
          ctx.lineTo(lerp(bx, cx2, t2), lerp(by, cy2, t2))
        }
        ctx.stroke()
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  Component.onCompleted: canvas.requestPaint()
}
