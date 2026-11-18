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
with both. The primary branch leaves these rows as stock.

    case                                 want    stock    matcher  bounds   both
    one rule that holds                  docked  docked   docked   docked   docked
    one rule that does not hold          none    none     none     none     none
    docked {D0 C, D1 C}, D1 unplugged    none    docked   none     docked   none
    laptop {D0 C} vs docked 3 conditions laptop  docked   laptop   docked   laptop
    laptop/docked pair, unplugged        laptop  laptop   laptop   laptop   laptop
    20-screen profile, 16 outputs        docked  crashed  crashed  docked   docked
    laptop/docked pair, plugged          docked  docked   docked   docked   docked
    docked {D0 C, D1 C}, plugged         docked  docked   docked   docked   docked

Which output libtderandr calls primary (`primary_probe`, both outputs
active), stock against `fix/randr-primary-output` and against all three
fixes together:

    RandR primary    stock    primary  all three
    DUMMY0           DUMMY1   DUMMY0   DUMMY0
    DUMMY1           DUMMY0   DUMMY1   DUMMY1

The same unpatched file built as a shim also crashes on the
20-screen profile, so the shim reproduces stock rather than masking it.
The patches are `patch/tdelibs/fix-hotplug-rule-all-conditions`,
`patch/tdelibs/fix-display-profile-output-bounds` and
`patch/tdelibs/fix-randr-primary-output`.

## The Displays module's mirror option (`make mirror-ui`)

`build-kcm.sh` builds `kcm_displayconfig` from the tdebase clone into
`out/stage`, and `mirror-ui.sh` drives it under `tdecmshell` on the same
private server. It enables display control, picks monitor 2, optionally
clicks the mirror box, applies, accepts, and reads `xrandr` after the
15-second revert timer. There is no window manager, so the clicks are at
measured positions, and the screenshots in `out/ui/` show what was
clicked. The shim is preloaded, so TDELIBS should carry the
primary-output fix.

Result, 2026-11-18, module from `feat/displayconfig-mirror`, primary
DUMMY0 1024x768:

    case                                   module   screen     DUMMY0      DUMMY1
    already mirrored, Apply unchanged      stock    1024x1360  +0+592      +0+0
    side by side, tick the box             patched  1024x768   +0+0        +0+0
    already mirrored, Apply unchanged      patched  1024x768   +0+0        +0+0
    already mirrored, untick the box       patched  1824x768   +0+0        +1024+0

The patch is `patch/tdebase/feat-displayconfig-mirror`.
