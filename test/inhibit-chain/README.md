# Does the PR 779 + PR 47 pair actually work end to end?

Runs the patched `kdesktop` and `tdepowersave` from `stage/` on a **nested**
X display (`:9`) under a private D-Bus session and a private `TDEHOME`.
Nothing touches display `:0`, the live session's DCOP, or `~/.trinity`.

    timeout 240 dbus-run-session -- ./harness.sh

Requires `make install` into `stage/` first, plus `Xvfb`.

## Result, 2026-09-06

    kdesktop registered on DCOP
    org.freedesktop.ScreenSaver claimed on the bus
    tdepowersave registered on DCOP
    Inhibit("harness", "end-to-end probe")  ->  uint32 1

    KDE: Inhibit: cookie(1), application(harness), reason(end-to-end probe)
    TPS: WARNING: Could not inhibit DPMS
    KDE: Removing inhibitor cookie(1) for disconnected D-Bus client(:1.2)

**The chain fires.** Read those three lines in order: kdesktop accepted the
D-Bus call, tdepowersave's slot ran, and the cookie was released when the
client vanished.

The tdepowersave line is a *warning*, and that is the evidence rather than a
problem. `screen::setDPMSInhibited()` returns false when the server has no
DPMS extension, so the warning appears **only if the whole D-Bus to DCOP to
slot chain reached it**. Its absence would mean a break.

The third line is the inhibit-leak guard firing in the real program:
`dbus-send` exits immediately after its call, and kdesktop released the
cookie on its own. `../dbus-signal-delivery/` establishes the same thing in
isolation; this is the production code path doing it.

## What this cannot test

**Neither Xvfb nor Xephyr provides the DPMS extension**, with or without
`+extension DPMS` -- both answer "Server does not have the DPMS Extension".
So the final X call, actually zeroing and restoring the DPMS timeouts,
cannot be observed on any nested server. Confirming that needs the real
display, and therefore a session that can be restarted.

## Why the cleanup is not just a PID list

`dcopserver` daemonises unless given `--nofork`, so the recorded `$!` is a
parent that exits while the real daemon is reparented to init -- it survived
the EXIT trap and had to be killed by hand. It is started with `--nofork`
now, and the trap additionally sweeps by the private `TDEHOME` path, which
no other session on this machine can match, so the live desktop's own
`dcopserver` processes can never be candidates.
