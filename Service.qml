import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "FacePolicy.js" as FacePolicy

// Fork of Omarchy's omarchy.lock service (MIT, basecamp/omarchy) with an added
// Face Unlock flow. Everything outside the "Face Unlock" blocks is kept as
// close to upstream as possible so upstream fixes can be merged forward; see
// docs/UPSTREAM.md for the sync procedure.
Item {
  id: root

  property var shell: null
  property string omarchyPath: ""

  // ---- Face Unlock state ---------------------------------------------------
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
  readonly property string faceSettingsPath: configHome + "/omarchy-face-unlock/settings.json"
  property var faceSettings: FacePolicy.normalizeSettings(null)
  property var faceState: FacePolicy.freshState(Date.now())
  property bool facePamConfigured: false
  property string faceMode: "idle"
  property string faceCaption: ""
  property string faceDemoMode: ""
  property string faceHint: ""
  readonly property bool faceScanning: faceState.scanning
  readonly property bool faceAvailable: facePamConfigured && faceSettings.enabled

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  property bool lockRequested: false
  property bool pendingSessionLock: false
  property bool authenticatingPassword: false
  property bool fingerprintAuthenticating: false
  property bool passwordPamConfigured: false
  property bool fingerprintConfigured: false
  property bool previewVisible: false
  property string enteredPassword: ""
  property string pendingPassword: ""
  property string failureMessage: ""
  property int failedAttempts: 0
  property string backgroundPath: ""
  property int backgroundVersion: 0
  property string lastEvent: "init"
  property string lastEventAt: ""
  property bool strandedLock: false
  property bool strandedLockResolved: false

  readonly property bool locked: lockRequested || sessionLock.locked || sessionLock.secure

  // Decisions read the lock state afresh. A property binding that missed a change
  // notification once reported locked after an unlock, and a lock request before
  // suspend then took that for done and never locked the session.
  function currentlyLocked() {
    return lockRequested || sessionLock.locked || sessionLock.secure
  }
  readonly property bool authenticating: authenticatingPassword || fingerprintAuthenticating

  function realScreenCount() {
    var screens = Quickshell.screens || []
    var count = 0

    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
      if (screen && screen.name && screen.width > 0 && screen.height > 0) count += 1
    }

    return count
  }

  function hasRealScreen() {
    return realScreenCount() > 0
  }

  function queueSessionLock() {
    pendingSessionLock = true
    if (!sessionLockStabilizeTimer.running) logEvent("lock-pending: screen-stabilizing")
    sessionLockStabilizeTimer.restart()
    if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
  }

  function requestSessionLock() {
    if (!lockRequested || sessionLock.locked || sessionLock.secure) return
    if (sessionLockStabilizeTimer.running) return

    if (!hasRealScreen()) {
      if (!pendingSessionLock || lastEvent !== "lock-pending: no-real-screen") logEvent("lock-pending: no-real-screen")
      pendingSessionLock = true
      if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
      return
    }

    pendingSessionLock = false
    pendingSessionLockTimer.stop()
    sessionLock.locked = true
  }

  // ext-session-lock outlives its client, and a restart carries no lock over, so
  // a session locked this early may be an orphan behind Hyprland's failsafe. It
  // may also be another shell's live lock, which Hyprland would let this one
  // take over and then strand on exit, so the helper answers undetermined while
  // another locker runs. Outputs are often still absent here, so ask until the
  // answer means something.
  function checkStrandedLock() {
    if (strandedLockResolved || strandedLockCheckProc.running) return

    // A lock this shell took is nobody's orphan.
    if (currentlyLocked()) {
      strandedLockResolved = true
      return
    }

    strandedLockCheckProc.running = true
  }

  function recoverStrandedLock() {
    if (!strandedLock || currentlyLocked() || !passwordPamConfigured) return

    strandedLock = false
    logEvent("lock-stranded: recovering")
    beginLock()
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function refreshFingerprintStatus() {
    if (!fingerprintCheckProc.running) fingerprintCheckProc.running = true
  }

  function logEvent(event) {
    lastEvent = event
    lastEventAt = new Date().toISOString()
    console.log("omarchy lock " + lastEventAt + " " + event)
  }

  function resetAuthenticationState() {
    enteredPassword = ""
    pendingPassword = ""
    failureMessage = ""
    failedAttempts = 0
    authenticatingPassword = false
    fingerprintAuthenticating = false
    fingerprintRetryTimer.stop()
    if (passwordPam.active) passwordPam.abort()
    if (fingerprintPam.active) fingerprintPam.abort()
    resetFace()
  }

  // ---- Face Unlock ---------------------------------------------------------

  function resetFace() {
    faceState = FacePolicy.scanCancelled(FacePolicy.freshState(Date.now()))
    faceWatchdog.stop()
    faceSuccessTimer.stop()
    faceFailureTimer.stop()
    if (facePam.active) facePam.abort()
    faceMode = "idle"
    faceCaption = ""
  }

  // Called for genuine user input on the lock surface (key press, pointer
  // movement or click). `manual` is a click on the face glyph itself.
  function noteFaceActivity(manual) {
    if (!lockRequested || !sessionLock.secure || !faceAvailable) return
    if (faceMode === "success") return
    var now = Date.now()
    var reason = FacePolicy.blockReason(faceState, faceSettings, now, manual)
    if (reason === "") {
      startFaceScan(now)
    } else {
      refreshFaceCaption(now)
    }
  }

  function startFaceScan(now) {
    faceState = FacePolicy.beginScan(faceState, now)
    faceFailureTimer.stop()
    faceMode = "scanning"
    faceHint = ""
    faceCaption = "Looking for you…"
    runWake()
    if (!facePam.start()) {
      handleFaceFailure("Face Unlock unavailable")
      return
    }
    faceWatchdog.restart()
    logEvent("face-scan: start attempt=" + (faceState.attempts + 1))
  }

  function handleFaceSuccess() {
    faceWatchdog.stop()
    faceState = FacePolicy.scanCancelled(faceState)
    faceMode = "success"
    faceCaption = "Welcome back"
    logEvent("face-scan: success")
    // Let the check mark land before the surface goes away.
    faceSuccessTimer.restart()
  }

  function handleFaceFailure(message) {
    faceWatchdog.stop()
    if (!faceState.scanning) return
    faceState = FacePolicy.scanFailed(faceState, faceSettings, Date.now())
    faceMode = "failure"
    faceCaption = message || "Face not recognized"
    logEvent("face-scan: failed attempts=" + faceState.attempts)
    faceFailureTimer.restart()
    runWake()
  }

  function refreshFaceCaption(now) {
    if (faceMode === "scanning" || faceMode === "success" || faceMode === "failure") return
    var reason = FacePolicy.blockReason(faceState, faceSettings, now, false)
    if (reason === "paused") {
      faceMode = "resting"
      faceCaption = "Face Unlock paused · use your password"
    } else if (reason === "cooldown") {
      var secs = Math.max(1, Math.ceil((faceState.nextAllowedAt - now) / 1000))
      faceMode = "resting"
      faceCaption = "Try again in " + secs + "s · or click the face"
    } else if (reason === "grace") {
      faceMode = "resting"
      faceCaption = "Face Unlock"
    } else {
      faceMode = "idle"
      faceCaption = faceState.attempts > 0 ? "Press any key to try again" : "Press any key to look"
    }
  }

  function faceMessageFor(text) {
    var t = String(text || "").toLowerCase()
    if (t.indexOf("dark") !== -1) return "Too dark · add some light"
    if (t.indexOf("no face model") !== -1 || t.indexOf("no model") !== -1) return "No face enrolled · run setup"
    if (t.indexOf("camera") !== -1 || t.indexOf("device") !== -1) return "Camera unavailable"
    if (t.indexOf("lid") !== -1) return "Lid closed"
    if (t.indexOf("disabled") !== -1) return "Face Unlock is disabled"
    return ""
  }

  function beginLock() {
    if (!passwordPamConfigured) {
      logEvent("lock-denied: missing-pam")
      return false
    }

    resetAuthenticationState()
    faceState = FacePolicy.freshState(Date.now())
    refreshFaceCaption(Date.now())
    lockRequested = true
    armBlankTimer()
    logEvent("lock-requested")
    queueSessionLock()

    Qt.callLater(function() {
      root.refreshBackground()
      root.refreshFingerprintStatus()
    })

    return true
  }

  function finishUnlock() {
    if (!root.currentlyLocked()) return

    lockRequested = false
    pendingSessionLock = false
    sessionLockStabilizeTimer.stop()
    pendingSessionLockTimer.stop()
    resetAuthenticationState()
    idleBlankTimer.stop()
    sessionLock.locked = false
    logEvent("unlocked")
    runWake()
  }

  function armBlankTimer() {
    idleBlankTimer.armedAt = Date.now()
    idleBlankTimer.restart()
  }

  function runWake() {
    if (!wakeProcess.running) wakeProcess.running = true
    if (lockRequested) armBlankTimer()
  }

  function runBlank() {
    if (!blankProcess.running) blankProcess.running = true
  }

  function submitPassword(value) {
    var password = String(value || "")
    if (!lockRequested || authenticatingPassword || password.length === 0) return

    runWake()
    pendingPassword = password
    failureMessage = ""
    authenticatingPassword = true

    if (!passwordPam.start()) {
      handlePasswordFailure()
      return
    }

    Qt.callLater(respondToPasswordPrompt)
  }

  function respondToPasswordPrompt() {
    if (!authenticatingPassword || !passwordPam.active || !passwordPam.responseRequired) return
    passwordPam.respond(pendingPassword)
  }

  function handlePasswordFailure() {
    if (!lockRequested) return

    authenticatingPassword = false
    enteredPassword = ""
    pendingPassword = ""
    failedAttempts += 1
    failureMessage = "Authentication failed (" + failedAttempts + ")"
    runWake()
  }

  function startFingerprint() {
    if (!lockRequested || !sessionLock.secure || !fingerprintConfigured) return
    if (fingerprintPam.active || fingerprintAuthenticating) return

    fingerprintAuthenticating = true
    if (!fingerprintPam.start()) {
      fingerprintAuthenticating = false
    }
  }

  function handleFingerprintFinished(result) {
    fingerprintAuthenticating = false

    if (!lockRequested) return
    if (result === PamResult.Success) {
      finishUnlock()
    } else if (fingerprintConfigured) {
      fingerprintRetryTimer.restart()
    }
  }

  WlSessionLock {
    id: sessionLock

    locked: false

    onSecureStateChanged: {
      root.logEvent("secure=" + secure)
      if (secure) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.startFingerprint()
      }
    }

    onLockStateChanged: {
      root.logEvent("session-locked=" + locked)

      if (locked) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
      }

      if (!locked && root.lockRequested) {
        root.lockRequested = false
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.resetAuthenticationState()
        root.runWake()
      }
    }

    WlSessionLockSurface {
      id: lockSurface
      color: Commons.Color.background

      LockView {
        id: lockView
        anchors.fill: parent
        backgroundPath: root.backgroundPath
        backgroundVersion: root.backgroundVersion
        fingerprintConfigured: root.fingerprintConfigured
        authenticatingPassword: root.authenticatingPassword
        failureMessage: root.failureMessage
        failedAttempts: root.failedAttempts
        inputEnabled: root.lockRequested
        loadBackground: root.locked
        passwordText: root.enteredPassword
        faceAvailable: root.faceAvailable
        faceMode: root.faceMode
        faceCaption: root.faceCaption
        onPasswordTextEdited: function(password) { root.enteredPassword = password }
        onSubmitPassword: function(password) { root.submitPassword(password) }
        onClearFailureRequested: root.failureMessage = ""
        onWakeRequested: { root.runWake(); root.noteFaceActivity(false) }
        onFaceRequested: root.noteFaceActivity(true)
      }

    }
  }

  PanelWindow {
    id: previewWindow
    visible: root.previewVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-lock-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    LockView {
      anchors.fill: parent
      backgroundPath: root.backgroundPath
      backgroundVersion: root.backgroundVersion
      fingerprintConfigured: root.fingerprintConfigured
      authenticatingPassword: false
      failureMessage: ""
      failedAttempts: 0
      inputEnabled: false
      loadBackground: root.previewVisible
      passwordText: ""
      // The preview never authenticates. `face-unlock demo` cycles the
      // glyph through its states here so the look can be checked unlocked.
      faceAvailable: root.facePamConfigured || root.faceDemoMode !== ""
      faceMode: root.faceDemoMode !== "" ? root.faceDemoMode : "idle"
      faceCaption: ({ scanning: "Looking for you…", success: "Welcome back", failure: "Face not recognized",
                      resting: "Try again in 5s · or click the face", idle: "Press any key to look" })[root.faceDemoMode || "idle"]
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: { root.previewVisible = false; root.faceDemoMode = "" }
    }
  }

  PamContext {
    id: passwordPam
    config: "omarchy-lock-password"
    user: root.userName

    onResponseRequiredChanged: root.respondToPasswordPrompt()
    onPamMessage: root.respondToPasswordPrompt()

    onCompleted: function(result) {
      root.authenticatingPassword = false
      root.pendingPassword = ""

      if (!root.lockRequested) return
      if (result === PamResult.Success) root.finishUnlock()
      else root.handlePasswordFailure()
    }

    onError: function(error) {
      root.handlePasswordFailure()
    }
  }

  PamContext {
    id: fingerprintPam
    config: "omarchy-lock-fingerprint"
    user: root.userName

    onCompleted: function(result) {
      root.handleFingerprintFinished(result)
    }

    onError: function(error) {
      root.fingerprintAuthenticating = false
      if (root.lockRequested && root.fingerprintConfigured) fingerprintRetryTimer.restart()
    }
  }

  // ---- Face Unlock PAM -----------------------------------------------------
  // /etc/pam.d/omarchy-lock-face is written by `face-unlock setup`. It never
  // touches the password stack, and pam_faillock is consulted (preauth only)
  // so face cannot bypass a lockout earned by wrong passwords.
  PamContext {
    id: facePam
    config: "omarchy-lock-face"
    user: root.userName

    onPamMessage: {
      var friendly = root.faceMessageFor(facePam.message)
      if (friendly && root.faceState.scanning) {
        root.faceHint = friendly
        root.faceCaption = friendly
      }
      // pam_howdy never asks for input; anything that does is not ours to answer.
      if (facePam.responseRequired) facePam.abort()
    }

    onCompleted: function(result) {
      if (!root.lockRequested || !root.faceState.scanning) return
      if (result === PamResult.Success) root.handleFaceSuccess()
      else root.handleFaceFailure(root.faceHint)
    }

    onError: function(error) {
      if (root.faceState.scanning) root.handleFaceFailure("Face Unlock unavailable")
    }
  }

  // A scan that outlives Howdy's own timeout is aborted and counted.
  Timer {
    id: faceWatchdog
    interval: root.faceSettings.scanTimeoutMs
    repeat: false
    onTriggered: {
      if (facePam.active) facePam.abort()
      root.handleFaceFailure("Face not recognized")
    }
  }

  Timer {
    id: faceSuccessTimer
    interval: root.faceSettings.successHoldMs
    repeat: false
    onTriggered: if (root.lockRequested && root.faceMode === "success") root.finishUnlock()
  }

  // Hold the failure shake on screen briefly, then settle into the cooldown.
  Timer {
    id: faceFailureTimer
    interval: 1400
    repeat: false
    onTriggered: {
      if (root.faceMode !== "failure") return
      root.faceMode = "resting"
      root.refreshFaceCaption(Date.now())
    }
  }

  // Keeps the cooldown countdown honest while it is visible. Display only:
  // ticking never starts a scan.
  Timer {
    interval: 1000
    repeat: true
    running: root.lockRequested && root.faceAvailable && root.faceMode === "resting"
    onTriggered: root.refreshFaceCaption(Date.now())
  }

  FileView {
    path: "/etc/pam.d/omarchy-lock-face"
    watchChanges: true
    printErrors: false
    onLoaded: root.facePamConfigured = true
    onLoadFailed: root.facePamConfigured = false
    onFileChanged: reload()
  }

  FileView {
    id: faceSettingsFile
    path: root.faceSettingsPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      var parsed = null
      try { parsed = JSON.parse(text()) } catch (e) { parsed = null }
      root.faceSettings = FacePolicy.normalizeSettings(parsed)
    }
    onLoadFailed: root.faceSettings = FacePolicy.normalizeSettings(null)
    onFileChanged: reload()
  }

  onFaceAvailableChanged: {
    if (!faceAvailable && faceState.scanning) resetFace()
  }

  onFaceScanningChanged: {
    if (!lockRequested) return
    if (faceScanning) idleBlankTimer.stop()
    else armBlankTimer()
  }

  IpcHandler {
    target: "face-unlock"

    function status(): string {
      return JSON.stringify({
        pamConfigured: root.facePamConfigured,
        enabled: root.faceSettings.enabled,
        locked: root.currentlyLocked(),
        mode: root.faceMode,
        attempts: root.faceState.attempts,
        maxAttempts: root.faceSettings.maxAttempts
      })
    }

    // Preview-only: never runs PAM. mode = idle|scanning|success|failure|resting|off
    function demo(mode: string): string {
      var allowed = ["idle", "scanning", "success", "failure", "resting"]
      root.faceDemoMode = allowed.indexOf(mode) !== -1 ? mode : ""
      if (root.faceDemoMode !== "" && !root.previewVisible) {
        root.refreshBackground()
        root.previewVisible = true
      }
      return root.faceDemoMode || "off"
    }
  }

  Timer {
    id: fingerprintRetryTimer
    interval: 250
    repeat: false
    onTriggered: root.startFingerprint()
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = String(text || "").trim()
        if (next !== root.backgroundPath) {
          root.backgroundPath = next
          root.backgroundVersion += 1
        }
      }
    }
  }

  Process {
    id: fingerprintCheckProc
    command: ["bash", "-c", "if [[ -f /etc/pam.d/omarchy-lock-fingerprint ]] && command -v fprintd-list >/dev/null 2>&1 && fprintd-list \"$USER\" 2>/dev/null | grep -qi finger; then echo yes; else echo no; fi"]
    stdout: StdioCollector { id: fingerprintCheckStdout; waitForEnd: true }
    onExited: {
      root.fingerprintConfigured = String(fingerprintCheckStdout.text || "").trim() === "yes"
      if (root.lockRequested && root.fingerprintConfigured) root.startFingerprint()
      else if (!root.fingerprintConfigured && fingerprintPam.active) fingerprintPam.abort()
    }
  }

  Process {
    id: strandedLockCheckProc
    // $PPID is this shell: a crash re-execs in place, so its pid is the one to skip.
    command: ["bash", "-c", "omarchy-hyprland-session-lock-stranded \"$PPID\""]
    onExited: function(exitCode) {
      // No output to read the lock off yet.
      if (exitCode === 2) return

      root.strandedLockResolved = true

      // A lock taken while this was in flight is this shell's own.
      root.strandedLock = exitCode === 0 && !root.currentlyLocked()
      root.recoverStrandedLock()
    }
  }

  Process {
    id: wakeProcess
    command: ["bash", "-c", "omarchy-system-wake"]
  }

  Process {
    id: blankProcess
    command: ["bash", "-c", "omarchy-brightness-keyboard off; omarchy-brightness-display off"]
  }

  Timer {
    id: idleBlankTimer
    interval: 5000
    repeat: false
    property double armedAt: 0
    onTriggered: {
      // A countdown frozen by suspend fires right after resume, which would
      // blank the freshly woken unlock screen under the user. Wall-clock time
      // exposes the gap: take a fresh run-up instead of blanking.
      if (Date.now() - armedAt > interval + 2000) {
        root.armBlankTimer()
        return
      }
      // Only a password check in flight should hold the display up. The
      // fingerprint PAM stays armed for the whole lock, so gating on
      // `authenticating` here would keep the panel lit until unlock.
      if (root.lockRequested && !root.authenticatingPassword && !root.faceScanning) root.runBlank()
    }
  }

  Timer {
    id: sessionLockStabilizeTimer
    interval: 500
    repeat: false
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: pendingSessionLockTimer
    interval: 100
    repeat: true
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: strandedLockRetryTimer
    interval: 500
    repeat: true
    // Covers the compositor settling; screens coming back re-arm it.
    readonly property int budget: 20
    property int remaining: 20
    running: !root.strandedLockResolved && remaining > 0

    function rearm() {
      if (!root.strandedLockResolved) remaining = budget
    }

    onTriggered: {
      remaining -= 1
      root.checkStrandedLock()
    }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      root.requestSessionLock()

      // A monitor still coming up has no workspace, so cannot answer yet.
      strandedLockRetryTimer.rearm()
      root.checkStrandedLock()
    }
  }

  onAuthenticatingPasswordChanged: {
    if (!lockRequested) return
    if (authenticatingPassword) idleBlankTimer.stop()
    else armBlankTimer()
  }

  FileView {
    path: "/etc/pam.d/omarchy-lock-password"
    watchChanges: true
    printErrors: false
    onLoaded: root.passwordPamConfigured = true
    onLoadFailed: root.passwordPamConfigured = false
    onFileChanged: reload()
  }

  // No lock before PAM is known good. An answer from before then may be stale --
  // the failsafe can be cleared from a TTY -- so re-ask rather than act on it.
  onPasswordPamConfiguredChanged: {
    if (!passwordPamConfigured) return

    strandedLock = false
    strandedLockResolved = false
    strandedLockRetryTimer.rearm()
    checkStrandedLock()
  }

  Component.onCompleted: {
    refreshBackground()
    refreshFingerprintStatus()
    checkStrandedLock()
  }

  IpcHandler {
    target: "lock"

    function lock(): string {
      if (!root.passwordPamConfigured) return "missing-pam"
      if (!root.currentlyLocked() && !root.beginLock()) return "failed"
      return "ok"
    }

    function isLocked(): string {
      return root.currentlyLocked() ? "true" : "false"
    }

    function status(): string {
      return JSON.stringify({
        locked: root.currentlyLocked(),
        requested: root.lockRequested,
        pending: root.pendingSessionLock,
        sessionLocked: sessionLock.locked,
        secure: sessionLock.secure,
        realScreens: root.realScreenCount(),
        passwordPam: root.passwordPamConfigured,
        fingerprint: root.fingerprintConfigured,
        authenticating: root.authenticating,
        lastEvent: root.lastEvent,
        lastEventAt: root.lastEventAt
      })
    }

    function preview(): string {
      root.refreshBackground()
      root.refreshFingerprintStatus()
      root.previewVisible = true
      return "ok"
    }

    function hidePreview(): string {
      root.previewVisible = false
      root.faceDemoMode = ""
      return "ok"
    }
  }
}
