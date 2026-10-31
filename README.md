# Face Unlock for Omarchy

Face ID-style webcam unlock for the [Omarchy](https://omarchy.org) lock screen,
powered by [Howdy Next](https://codeberg.org/nathawat/howdy-next).

![Face Unlock on the Omarchy lock screen](preview.png)

Wake the lock screen with any key or a nudge of the mouse. The camera turns on,
finds your face, and you're back in, with a check mark on the way. If it
can't recognize you, your password works exactly as before.

## Features

- **Face ID-style lock screen.** An animated glyph above the stock password
  field: a scanning ring, a check mark on success, a head-shake when it doesn't
  match. It follows your Omarchy theme.
- **The camera only runs when you wake the screen.** Scans start on a key press,
  mouse movement or click on the lock screen, never on a timer or in the
  background.
- **Rate-limited.** Accidental input (a cat on the keyboard, a bag leaning on
  a key) can't keep the camera running:
  - no scan for 2.5 s after locking, so the key that locked the screen doesn't
    unlock it straight away
  - one scan at a time, each capped at a few seconds
  - an increasing wait between failed scans (2 s → 5 s → 15 s → 30 s)
  - after 5 misses, face unlock pauses for 10 minutes and the password is
    still there. Clicking the face skips the wait between attempts, but not
    the pause.
- **Setup wizard.** It installs the engine, picks your camera, enrolls your face
  and wires up the lock screen. You can re-run it any time.
- **Face management.** Add several looks (glasses, low light, headphones), list
  them, remove some or all.
- **Camera choice.** Pick any connected camera (an IR camera is best) and
  switch later.
- **Optional bar icon.** Toggle Face Unlock on and off, manage faces, change the
  camera, or hide the icon entirely. Everything is also in the app launcher
  ("Face Unlock") and on the command line.
- **Optional sudo support.** If you opt in, `sudo` can try your face before
  asking for your password.

## Security: read this first

Face recognition is a **convenience, not extra security**:

- Ordinary webcams (RGB) can be fooled by a good photo of you. IR cameras
  (Windows Hello-style) are much harder to fool. Use Face Unlock on machines
  where that tradeoff is acceptable to you.
- Your password always works. Face Unlock uses its own PAM service
  (`/etc/pam.d/omarchy-lock-face`) and never modifies the password stack
  (`omarchy-lock-password`).
- `pam_faillock` is checked before every face scan, so face can't get around a
  lockout caused by wrong passwords, and failed face scans don't count toward
  that lockout.
- Face models stay in Howdy's root-owned directory. This plugin never reads,
  copies or uploads them.

See [SECURITY.md](SECURITY.md) for details.

## Install

```sh
omarchy plugin add https://github.com/phi0x/omarchy-face-unlock.git
~/.config/omarchy/plugins/phi0x.face-unlock/bin/face-unlock setup
```

The wizard:

1. installs `howdy-next-git` from the AUR unattended (no yay prompts; use
   `face-unlock setup --review` to inspect the build files first) and
   downloads its recognition models
2. lets you choose a camera
3. enrolls your face, plus any extra looks you want
4. writes `/etc/pam.d/omarchy-lock-face` and, if you choose, adds face to sudo
5. turns on the Face Unlock lock screen, the bar icon and the app launcher entry

Then lock with <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>L</kbd>, wait a moment,
and press any key.

## Usage

```text
face-unlock                  home screen (also in the app launcher)
face-unlock setup [--review] setup wizard (safe to re-run)
face-unlock faces            manage faces: add, remove, remove all, test
face-unlock faces list|add [LABEL]|remove ID...|clear
face-unlock camera [list|set PATH]
face-unlock enable|disable|toggle
face-unlock bar show|hide
face-unlock status [--json]
face-unlock demo             preview the lock screen states (never unlocks)
face-unlock uninstall
```

Bar icon: left-click opens the panel, middle-click turns Face Unlock on or off.

### Settings

`~/.config/omarchy-face-unlock/settings.json` is written by the CLI and
watched live by the lock screen:

```json
{
  "enabled": true,
  "showBarIcon": true,
  "camera": "/dev/v4l/by-id/usb-…-video-index0",
  "graceSeconds": 2.5,
  "backoffSeconds": [2, 5, 15, 30],
  "maxAttempts": 5,
  "pauseMinutes": 10
}
```

Values are clamped to safe ranges. For example, a zero backoff becomes 1 s, and
`maxAttempts` is at most 10.

## How it works

Omarchy's lock screen is the first-party `omarchy.lock` shell service. This
plugin is a **clone** of it (`"omarchy": { "clonedFrom": "omarchy.lock" }`),
which is Omarchy's supported way to customize a built-in plugin. Enabling it
replaces the stock lock screen, and disabling it brings the stock one back.

The fork keeps upstream's password, fingerprint, multi-monitor and
crash-recovery logic as it is, and adds:

| File | Role |
| --- | --- |
| `Service.qml` | upstream lock service + a separate face `PamContext` |
| `LockView.qml` | upstream lock view + the glyph and caption above the field |
| `FaceGlyph.qml` | the animated Face ID-style glyph (also used in the bar) |
| `FacePolicy.js` | the pure attempt and rate-limit policy (unit tested) |
| `BarWidget.qml` | optional bar icon and panel; it never touches PAM |
| `bin/face-unlock` | wizard, face and camera management, settings |

## Uninstall

```sh
face-unlock uninstall                    # stock lock screen back, PAM files removed
omarchy plugin remove phi0x.face-unlock  # remove the plugin files
```

## Development

```sh
node tests/test_policy.js
bash -n bin/face-unlock
omarchy plugin validate .
face-unlock demo        # cycles the glyph states on the lock preview
```

The lock service is `keepLoaded`, so QML changes to it take effect after
`omarchy restart shell`. See [AGENTS.md](AGENTS.md) and
[docs/UPSTREAM.md](docs/UPSTREAM.md).

## Credits

- Lock screen code forked from [Omarchy](https://github.com/basecamp/omarchy)
  (MIT, © 37signals / Basecamp).
- Face recognition by [Howdy Next](https://codeberg.org/nathawat/howdy-next)
  (GPL-3.0-or-later), installed separately and not bundled here.

## License

MIT. See [LICENSE](LICENSE).
