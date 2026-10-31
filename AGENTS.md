# Agent guide

Face Unlock is a public Omarchy shell plugin (`phi0x.face-unlock`, repo
`phi0x/omarchy-face-unlock`). It replaces the lock screen through Omarchy's
clone mechanism and adds a Howdy Next face flow.

## Rules that matter

- **Never modify the password flow.** Upstream password, fingerprint,
  session-lock, stranded-lock and blanking logic in `Service.qml` stay as
  upstream has them. Face code lives in marked `Face Unlock` blocks. Follow
  `docs/UPSTREAM.md` when Omarchy updates the lock.
- **Camera only on user input.** Scans start from `LockView` input signals
  (`wakeRequested`, `faceRequested`), never from timers. All gating goes
  through `FacePolicy.js`. Add a test in `tests/test_policy.js` for any
  policy change.
- **The bar widget never touches PAM or the lock service.** It reads
  `settings.json` and runs the CLI.
- **The CLI is the only writer of `settings.json`.** Keep writes atomic
  (temp file + `mv`).
- **PAM edits:** only `/etc/pam.d/omarchy-lock-face` (owned by us) and the
  optional single sudo line. Never touch `omarchy-lock-password`, never
  use `pam_faillock` authfail in the face stack, never write passwordless
  sudo rules.
- **Don't lock the session during development.** Use
  `face-unlock demo` / `omarchy-shell lock preview`. Real lock tests are for
  the user to do.

## Checks

```sh
node tests/test_policy.js
bash tests/test_camera_names.sh
bash -n bin/face-unlock
omarchy plugin validate .
omarchy restart shell && omarchy-shell lock status   # passwordPam must be true
face-unlock demo
```

## Public repo hygiene

Treat everything tracked as public. Do not commit screenshots containing
desktop content, camera snapshots, face models, real device serials or
personal paths. `preview.png` must show only the lock screen.
