import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Optional bar icon. It never touches PAM or the lock service: it reads the
// same settings file the lock service watches, and every change goes through
// the `face-unlock` CLI so there is a single writer.
BarWidget {
  id: root
  moduleName: "phi0x.face-unlock"

  readonly property string home: Quickshell.env("HOME")
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
  readonly property string settingsPath: configHome + "/omarchy-face-unlock/settings.json"
  readonly property string cliPath: decodeURIComponent(String(Qt.resolvedUrl("bin/face-unlock")).replace(/^file:\/\//, ""))

  property var settings: ({ enabled: true, showBarIcon: true })
  property bool pamConfigured: false
  property bool popupOpen: false
  property bool busy: false

  readonly property bool enabled: settings.enabled !== false
  readonly property bool showIcon: settings.showBarIcon !== false
  readonly property string cameraName: {
    var p = String(settings.camera || "")
    if (!p) return "Not chosen"
    var n = p.split("/").pop().replace(/^usb-/, "").replace(/-video-index\d+$/, "").replace(/_/g, " ")
    return n || p
  }
  readonly property string statusText: !pamConfigured ? "Not set up yet"
    : (enabled ? "On · unlocks when you wake the lock screen" : "Off · password only")

  function close() { popupOpen = false }

  function run(args) {
    runner.command = [cliPath].concat(args)
    busy = true
    runner.running = true
  }

  // Interactive flows (setup, faces) need sudo, so they open in Omarchy's
  // floating terminal rather than running hidden.
  function openTerminal(sub) {
    popupOpen = false
    terminal.command = ["omarchy-launch-floating-terminal-with-presentation", "'" + cliPath + "' " + sub]
    terminal.running = true
  }

  visible: showIcon
  implicitWidth: showIcon ? glyph.width + Style.space(14) : 0
  implicitHeight: barSize

  FaceGlyph {
    id: glyph
    anchors.centerIn: parent
    width: Math.round(Style.font.body * 1.45)
    height: width
    mode: root.pamConfigured && root.enabled ? "idle" : "resting"
    color: root.bar ? root.bar.barForeground : Commons.Color.foreground
    opacity: root.pamConfigured && root.enabled ? 1.0 : 0.45
    onClicked: root.popupOpen = !root.popupOpen
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.MiddleButton && root.pamConfigured) root.run(["toggle"])
      else root.popupOpen = !root.popupOpen
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, "Face Unlock · " + root.statusText)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(330))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      width: parent.width
      spacing: Style.space(10)

      Row {
        spacing: Style.space(12)
        width: parent.width

        FaceGlyph {
          width: Style.space(46)
          height: width
          mode: root.pamConfigured && root.enabled ? "idle" : "resting"
          color: root.bar ? root.bar.foreground : Commons.Color.foreground
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Style.space(58)
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            text: "Face Unlock"
            color: root.bar ? root.bar.foreground : Commons.Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.statusText
            color: Commons.Util.alpha(root.bar ? root.bar.foreground : Commons.Color.foreground, 0.7)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      PanelSeparator { width: parent.width }

      Toggle {
        width: parent.width
        visible: root.pamConfigured
        label: "Use on the lock screen"
        description: "Your password always works too"
        checked: root.enabled
        foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
        onClicked: if (!root.busy) root.run([root.enabled ? "disable" : "enable"])
      }

      Button {
        width: parent.width
        leftAlign: true
        bordered: true
        iconText: root.pamConfigured ? "󰀉" : "󰐕"
        text: root.pamConfigured ? "Manage faces…" : "Set up Face Unlock…"
        foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
        onClicked: root.openTerminal(root.pamConfigured ? "faces" : "setup")
      }

      Button {
        width: parent.width
        leftAlign: true
        bordered: true
        visible: root.pamConfigured
        iconText: "󰄀"
        text: "Camera: " + root.cameraName
        tooltipText: "Choose which camera looks for you"
        foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
        onClicked: root.openTerminal("camera")
      }

      Button {
        width: parent.width
        leftAlign: true
        bordered: true
        visible: root.pamConfigured
        iconText: "󰒓"
        text: "Settings & setup wizard…"
        foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
        onClicked: root.openTerminal("")
      }

      Button {
        width: parent.width
        leftAlign: true
        iconText: "󰈈"
        text: "Hide this bar icon"
        tooltipText: "Bring it back from the Face Unlock app or `face-unlock bar show`"
        foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
        onClicked: { root.popupOpen = false; root.run(["bar", "hide"]) }
      }
    }
  }

  Process {
    id: runner
    onExited: root.busy = false
  }

  Process { id: terminal }

  FileView {
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      try { root.settings = JSON.parse(text()) || {} } catch (e) { root.settings = {} }
    }
    onLoadFailed: root.settings = ({})
    onFileChanged: reload()
  }

  FileView {
    path: "/etc/pam.d/omarchy-lock-face"
    watchChanges: true
    printErrors: false
    onLoaded: root.pamConfigured = true
    onLoadFailed: root.pamConfigured = false
    onFileChanged: reload()
  }
}
