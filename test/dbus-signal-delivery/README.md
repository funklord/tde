# Does PR 779's inhibit-leak guard actually fire?

`ScreenSaverDBusWatcher` builds a `TQT_DBusProxy` on `org.freedesktop.DBus`
and relies on `NameOwnerChanged` to release the inhibit cookies of a client
that died without calling `UnInhibit`. If that signal never arrives, a
crashed client inhibits the screensaver **forever**.

`dbus-1-tqt`'s own documentation describes only client-side filtering and
says nothing about registering a bus match rule, and the library carries the
string `destination='` -- which would restrict delivery to signals addressed
to the connection, and `NameOwnerChanged` is a broadcast with no
destination. That reasoning predicted the guard could not fire.

**It was wrong.** This probe builds the proxy exactly as the watcher does
and counts what arrives, against a `dbus-monitor` control over the same
window. Measured 2026-09-06:

    probe          8 NameOwnerChanged received
    dbus-monitor  10 over the same window

Four client connect/disconnect pairs give eight events, and the probe caught
all eight; the control's extra two are its own and the probe's connections.
The guard fires.

The probe needs no X server and claims no bus name. It stops itself after
six seconds.

    make test
