# Does the docked check actually discriminate?

`screen::externalDisplayConnected()` decides whether the lid-close action
runs. This links **the object the real build produced** rather than
reimplementing the RandR query, so a second copy of the logic cannot drift
from the first.

    make test BUILD=../../build/tps-dock

## Result, 2026-09-06

    :0   eDP-1 connected, laptop panel only     ->  false
    :9   Xvfb, sole output named "screen"       ->  true

The two cases disagree, which is what makes the result mean anything. A
probe that answered the same both ways would have established nothing.

The line

    DCOPRef::call():  no DCOP client or client not attached error

is expected. The `screen` constructor asks kdesktop about the screensaver
over DCOP, and this probe attaches no DCOP client. It does not affect the
RandR query under test.

## What it does not test

Xvfb's `screen` output is not an external display; it stands in for *an
output whose name is not that of a built-in panel*, which is the branch
under test. So this exercises the RandR query and the name matching
against real code, and does **not** exercise a real hotplug, a real
DisplayPort connector, or the lid event that calls it.

Testing the whole path needs a physical external display and a lid to
close.
