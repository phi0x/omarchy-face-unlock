# Keeping the lock fork in sync

`Service.qml` and `LockView.qml` are forks of Omarchy's
`shell/plugins/lock/` files. Every Face Unlock addition is marked with
`Face Unlock` comments, and everything else should match upstream.

Forked from: Omarchy **4.0.6** (`/usr/share/omarchy/shell/plugins/lock`).

## After an Omarchy update

```sh
up=/usr/share/omarchy/shell/plugins/lock
diff -u docs/upstream/Service.qml "$up/Service.qml"
diff -u docs/upstream/LockView.qml "$up/LockView.qml"
```

If upstream changed:

1. Copy the new upstream files over `docs/upstream/`.
2. Apply the same upstream diff to `Service.qml` / `LockView.qml`. The face
   blocks are self-contained, so conflicts should be rare.
3. Bump the "Forked from" version above, run the checks in `AGENTS.md`, and
   restart the shell to load the keepLoaded service.

Never ship a fork that lags behind an upstream security fix in the
password or session-lock logic.
