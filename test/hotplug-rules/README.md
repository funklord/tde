# Hotplug rules: which display profile does TDE apply?

TDE saves display arrangements as profiles and picks one with *hotplug
rules*: "if these outputs are connected and those are not, apply this
profile". `tdeinit_displayconfig` evaluates them at login, `tderandrtray`
on every monitor change and tdm at its greeter, all through
`KRandrSimpleAPI::applyHotplugRules()` in tdelibs.

This test runs the installed `tdeinit_displayconfig` against a private
Xorg with the dummy video driver, whose outputs `DUMMY0`..`DUMMY15`
report a real connection state, and reads back which profile was
applied. `SHIM` preloads `libtderandr.cpp` and `lowlevel_randr.c`, built
from a tdelibs clone as checked out, over the installed library, so the
same binary is the control and the subject, and `make test` tests
whichever branch the clone has out.

    make test                 # stock, then patched from ../../tdelibs
    make test TDELIBS=/path   # another clone or worktree
    make clean

`make driver` fetches `xserver-xorg-video-dummy` into `out/`, and the shim
build fetches the TQt headers the same way; nothing is installed and no
root is needed. Each run is isolated: private `/tmp`, no system bus, no
`/dev/dri` (see `harness.sh` for why each matters). The program runs
with `--nocrashhandler`, so a crash is reported rather than waiting on
TDE's crash dialog.

## Result, 2026-11-18 (stock = TDE 14.2 preview, libtderandr pre343)

Columns are the shim built from `fix/hotplug-rule-all-conditions`
(matcher), `fix/display-profile-output-bounds` (bounds), and a worktree
with both.

    case                                 want    stock    matcher  bounds   both
    one rule that holds                  docked  docked   docked   docked   docked
    one rule that does not hold          none    none     none     none     none
    docked {D0 C, D1 C}, D1 unplugged    none    docked   none     docked   none
    laptop {D0 C} vs docked 3 conditions laptop  docked   laptop   docked   laptop
    laptop/docked pair, unplugged        laptop  laptop   laptop   laptop   laptop
    20-screen profile, 16 outputs        docked  crashed  crashed  docked   docked
    laptop/docked pair, plugged          docked  docked   docked   docked   docked
    docked {D0 C, D1 C}, plugged         docked  docked   docked   docked   docked

The same unpatched file built as a shim also crashes on the
20-screen profile, so the shim reproduces stock rather than masking it.
The patches are `patch/tdelibs/fix-hotplug-rule-all-conditions` and
`patch/tdelibs/fix-display-profile-output-bounds`.
