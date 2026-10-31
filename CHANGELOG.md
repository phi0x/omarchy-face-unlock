# Changelog

## 0.1.0 — unreleased

- Face ID-style lock screen: animated glyph with scanning, success, failure
  and resting states, themed by Omarchy.
- Face scans triggered only by input on the lock screen, with a grace period,
  backoff, scan watchdog and a pause after repeated misses.
- `face-unlock` CLI: setup wizard, face management (add/list/remove/clear/test),
  camera selection, on/off, bar icon visibility, status, demo, uninstall.
- Optional bar icon with toggle, face management and camera shortcuts.
- App launcher entry; optional sudo integration.
- Lock service forked from Omarchy 4.0.6.
