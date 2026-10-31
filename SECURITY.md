# Security

Face Unlock sits in an authentication path, so its design keeps the attack
surface small and the password path untouched.

## Threat model

- **Spoofing.** RGB webcams can be fooled by photos or screens. Howdy Next's
  detection settings help, but they are no substitute for an IR camera. Treat
  Face Unlock as a convenience. Do not use it where someone with a photo of
  you and physical access is a concern.
- **Password path.** The plugin never edits `/etc/pam.d/omarchy-lock-password`.
  Face runs in a separate `PamContext` against `/etc/pam.d/omarchy-lock-face`.
- **Lockouts.** The face stack runs `pam_faillock.so preauth`, so face cannot
  unlock an account locked by failed passwords. Face misses are not recorded
  as failures.
- **Camera use.** Scans only start from user input on the secure lock surface
  and are rate limited (see `FacePolicy.js` and `tests/test_policy.js`). A
  watchdog aborts any scan that outlives Howdy's own timeout.
- **Settings file.** `~/.config/omarchy-face-unlock/settings.json` is
  user-writable by design. It can only switch face unlock off or tune the
  rate limits within clamped bounds. It cannot enable face unlock without
  the root-owned PAM file.
- **Bar widget.** The widget runs in the shared shell scene. It has no access
  to the lock service or PAM, and changes settings only through the CLI.
- **Face data.** Models live in Howdy's root-owned directory. Howdy Next
  prepares root-controlled runtime copies through its setuid
  `howdy-auth-helper`. This plugin never reads or transmits them.
- **sudo.** Optional and off by default. When enabled, one line
  (`auth sufficient pam_howdy.so`) is inserted above the first `auth` line of
  `/etc/pam.d/sudo`. A backup is kept at `/etc/pam.d/sudo.face-unlock.bak`,
  and `face-unlock uninstall` removes the line again.

## Recovery

If the lock screen ever misbehaves, switch to a TTY
(<kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>F3</kbd>), log in, and run:

```sh
omarchy plugin disable phi0x.face-unlock   # stock lock screen returns
```

## Reporting

Please report vulnerabilities privately through GitHub's
"Report a vulnerability" (Security tab) rather than in a public issue.
