# Hotplug rules: which display profile does TDE apply?

TDE saves display arrangements as profiles and picks one with *hotplug
rules*: "if these outputs are connected and those are not, apply this
profile". `tdeinit_displayconfig` evaluates them at login, `tderandrtray`
on every monitor change and tdm at its greeter, all through
`KRandrSimpleAPI::applyHotplugRules()` in tdelibs.

This test runs the installed `tdeinit_displayconfig` against a private
Xorg with the dummy video driver, whose outputs `DUMMY0`..`DUMMY15`
report a real connection state, and reads back which profile was
applied. `SHIM` preloads a patched `applyHotplugRules()` built from a
tdelibs clone over the installed library, so the same binary is the
control and the subject.

    make test                 # stock, then patched from ../../tdelibs
    make test TDELIBS=/path   # another clone
    make clean

`make driver` fetches `xserver-xorg-video-dummy` into `out/`, and the shim
build fetches the TQt headers the same way; nothing is installed and no
root is needed. Each run is isolated: private `/tmp`, no system bus, no
`/dev/dri` (see `harness.sh` for why each matters).

## Result, 2026-11-18 (stock = TDE 14.2 preview, libtderandr pre343)

    case                                  stock    patched   want
    one rule that holds                   docked   docked    docked
    one rule that does not hold           none     none      none
    docked {D0 C, D1 C}, D1 unplugged     docked   none      none
    laptop {D0 C} vs docked 3 conditions  docked   laptop    laptop
    laptop/docked pair, unplugged         laptop   laptop    laptop
    laptop/docked pair, plugged           docked   docked    docked
    docked {D0 C, D1 C}, plugged          docked   docked    docked

The patch is `patch/tdelibs/fix-hotplug-rule-all-conditions`.
