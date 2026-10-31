.pragma library

// Face Unlock attempt policy. Pure functions over a plain state object so the
// lock service stays small and the rules can be unit tested under node
// (tests/test_policy.js). Times are milliseconds (Date.now()).
//
// The camera only turns on in response to keyboard or pointer activity on the
// lock screen, never on a timer. Every scan that does not unlock counts as an
// attempt, and attempts back off so a cat on the keyboard (or a bag leaning on
// it) cannot keep the camera running:
//
//   - nothing in the first `graceMs` after locking, so the keypress that
//     locked the screen does not immediately unlock it again
//   - one scan at a time, each bounded by the scan watchdog
//   - after a failed scan, wait backoffMs[n] before the next automatic scan
//   - after `maxAttempts` failures, face unlock pauses for `pauseMs`;
//     the password always works

var DEFAULTS = {
  enabled: true,
  showBarIcon: true,
  graceMs: 2500,
  backoffMs: [2000, 5000, 15000, 30000],
  maxAttempts: 5,
  pauseMs: 10 * 60 * 1000,
  scanTimeoutMs: 9000,
  successHoldMs: 520
}

function clampInt(value, min, max, fallback) {
  var n = Number(value)
  if (!isFinite(n)) return fallback
  n = Math.round(n)
  return Math.max(min, Math.min(max, n))
}

// Settings come from a user-editable JSON file. Anything malformed falls back
// to the defaults; every value is bounded so a typo cannot produce a camera
// that never rests (e.g. a zero backoff) or a scan that never ends.
function normalizeSettings(raw) {
  var s = raw && typeof raw === "object" ? raw : {}
  var out = {
    enabled: typeof s.enabled === "boolean" ? s.enabled : DEFAULTS.enabled,
    showBarIcon: typeof s.showBarIcon === "boolean" ? s.showBarIcon : DEFAULTS.showBarIcon,
    graceMs: clampInt(s.graceSeconds * 1000, 1000, 30000, DEFAULTS.graceMs),
    maxAttempts: clampInt(s.maxAttempts, 1, 10, DEFAULTS.maxAttempts),
    pauseMs: clampInt(s.pauseMinutes * 60000, 60000, 24 * 3600000, DEFAULTS.pauseMs),
    scanTimeoutMs: DEFAULTS.scanTimeoutMs,
    successHoldMs: DEFAULTS.successHoldMs,
    backoffMs: DEFAULTS.backoffMs.slice()
  }
  if (Array.isArray(s.backoffSeconds) && s.backoffSeconds.length > 0) {
    var list = []
    for (var i = 0; i < s.backoffSeconds.length && i < 10; i++)
      list.push(clampInt(s.backoffSeconds[i] * 1000, 1000, 3600000, 5000))
    out.backoffMs = list
  }
  return out
}

function freshState(now) {
  return {
    lockedAt: now,
    attempts: 0,
    nextAllowedAt: now,
    pausedUntil: 0,
    scanning: false,
    scanStartedAt: 0
  }
}

function backoffFor(settings, attempts) {
  var list = settings.backoffMs
  if (!list || list.length === 0) return DEFAULTS.backoffMs[0]
  return list[Math.min(Math.max(attempts - 1, 0), list.length - 1)]
}

// Why a scan may not start right now. "" means it may.
// `manual` is a deliberate click on the face glyph: it skips the backoff wait
// but never the grace period, the pause, or the one-scan-at-a-time rule.
function blockReason(state, settings, now, manual) {
  if (!settings.enabled) return "disabled"
  if (state.scanning) return "scanning"
  if (now < state.lockedAt + settings.graceMs) return "grace"
  if (state.pausedUntil > now) return "paused"
  if (!manual && now < state.nextAllowedAt) return "cooldown"
  return ""
}

function beginScan(state, now) {
  var next = copy(state)
  // A pause that has run out starts a fresh round of attempts.
  if (next.pausedUntil > 0 && next.pausedUntil <= now) {
    next.pausedUntil = 0
    next.attempts = 0
  }
  next.scanning = true
  next.scanStartedAt = now
  return next
}

function scanFailed(state, settings, now) {
  var next = copy(state)
  next.scanning = false
  next.attempts += 1
  if (next.attempts >= settings.maxAttempts) {
    next.pausedUntil = now + settings.pauseMs
    next.nextAllowedAt = next.pausedUntil
  } else {
    next.nextAllowedAt = now + backoffFor(settings, next.attempts)
  }
  return next
}

// A scan that ended without a verdict of our own making (lock torn down,
// face unlock switched off mid-scan) is not held against the user.
function scanCancelled(state) {
  var next = copy(state)
  next.scanning = false
  return next
}

function attemptsLeft(state, settings) {
  return Math.max(0, settings.maxAttempts - state.attempts)
}

function copy(state) {
  var out = {}
  for (var k in state) out[k] = state[k]
  return out
}
