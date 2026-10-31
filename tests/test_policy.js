// node tests/test_policy.js — exercises FacePolicy.js outside Quickshell.
"use strict"
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const src = fs.readFileSync(path.join(__dirname, "..", "FacePolicy.js"), "utf8")
  .replace(/^\.pragma library\s*$/m, "")
const P = new Function(src + "\nreturn { DEFAULTS, normalizeSettings, freshState, blockReason, beginScan, scanFailed, scanCancelled, attemptsLeft, backoffFor }")()

let passed = 0
function test(name, fn) { fn(); passed++; console.log("ok - " + name) }

const S = P.normalizeSettings(null)
const T0 = 1_000_000

test("defaults when settings are missing or malformed", () => {
  assert.deepStrictEqual(P.normalizeSettings("nope").maxAttempts, P.DEFAULTS.maxAttempts)
  assert.strictEqual(P.normalizeSettings({ enabled: "yes" }).enabled, true)
  assert.strictEqual(P.normalizeSettings({ enabled: false }).enabled, false)
})

test("values are clamped so the camera can never run unbounded", () => {
  const s = P.normalizeSettings({ graceSeconds: 0, maxAttempts: 999, pauseMinutes: 0, backoffSeconds: [0, -5, 1e9] })
  assert.strictEqual(s.graceMs, 1000)
  assert.strictEqual(s.maxAttempts, 10)
  assert.strictEqual(s.pauseMs, 60000)
  assert.deepStrictEqual(s.backoffMs, [1000, 1000, 3600000])
})

test("no scan during the grace period after locking", () => {
  const st = P.freshState(T0)
  assert.strictEqual(P.blockReason(st, S, T0 + 100, false), "grace")
  assert.strictEqual(P.blockReason(st, S, T0 + 100, true), "grace", "a click does not skip grace")
  assert.strictEqual(P.blockReason(st, S, T0 + S.graceMs, false), "")
})

test("only one scan at a time", () => {
  let st = P.beginScan(P.freshState(T0), T0 + S.graceMs)
  assert.strictEqual(P.blockReason(st, S, T0 + S.graceMs + 10, true), "scanning")
})

test("failures back off, a click skips the wait", () => {
  let now = T0 + S.graceMs
  let st = P.scanFailed(P.beginScan(P.freshState(T0), now), S, now)
  assert.strictEqual(st.attempts, 1)
  assert.strictEqual(P.blockReason(st, S, now + 100, false), "cooldown")
  assert.strictEqual(P.blockReason(st, S, now + 100, true), "")
  assert.strictEqual(P.blockReason(st, S, now + S.backoffMs[0], false), "")
})

test("backoff grows and holds at the last step", () => {
  assert.strictEqual(P.backoffFor(S, 1), S.backoffMs[0])
  assert.strictEqual(P.backoffFor(S, 2), S.backoffMs[1])
  assert.strictEqual(P.backoffFor(S, 99), S.backoffMs[S.backoffMs.length - 1])
})

test("a stuck key cannot keep the camera on: pause after max attempts", () => {
  let now = T0 + S.graceMs
  let st = P.freshState(T0)
  let scans = 0
  // Hammer activity every 100 ms for 10 minutes.
  for (let t = now; t < now + 10 * 60 * 1000; t += 100) {
    if (P.blockReason(st, S, t, false) === "") {
      st = P.scanFailed(P.beginScan(st, t), S, t + 4000)
      scans++
    }
  }
  assert.strictEqual(scans, S.maxAttempts)
  assert.strictEqual(P.blockReason(st, S, now + 60000, true), "paused", "clicks do not bypass the pause")
})

test("the pause expires into a fresh round", () => {
  let now = T0 + S.graceMs
  let st = P.freshState(T0)
  for (let i = 0; i < S.maxAttempts; i++) st = P.scanFailed(P.beginScan(st, now), S, now)
  const after = st.pausedUntil + 1
  assert.strictEqual(P.blockReason(st, S, after, false), "")
  st = P.beginScan(st, after)
  assert.strictEqual(st.attempts, 0)
  assert.strictEqual(st.pausedUntil, 0)
})

test("cancelled scans are not counted", () => {
  let st = P.scanCancelled(P.beginScan(P.freshState(T0), T0 + S.graceMs))
  assert.strictEqual(st.attempts, 0)
  assert.strictEqual(st.scanning, false)
})

test("disabled blocks everything", () => {
  const off = P.normalizeSettings({ enabled: false })
  assert.strictEqual(P.blockReason(P.freshState(0), off, 1e9, true), "disabled")
})

test("state updates never mutate their input", () => {
  const st = P.freshState(T0)
  const snapshot = JSON.stringify(st)
  P.scanFailed(P.beginScan(st, T0 + 5000), S, T0 + 6000)
  assert.strictEqual(JSON.stringify(st), snapshot)
})

console.log(`\n${passed} passed`)
