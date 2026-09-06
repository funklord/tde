# Does kdesktop_lock create its control FIFOs?

Runs the **unpatched** and the **patched** `kdesktop_lock` through the same
scenario on nested display `:9` and compares. Nothing touches `:0`.

    timeout 200 dbus-run-session -- ./harness.sh

Needs both builds installed into `stage/`, plus `Xvfb`.

## Result, 2026-09-06

                        FIFOs before   FIFOs after   warning printed
    unpatched                      0             0   unable to create
                                                     '/tmp/tdesocket-global/
                                                      kdesktoplockcontrol-9'
    patched                        0             2   none

    prw------- kdesktoplockcontrol-9
    prw------- kdesktoplockcontrol_out-9

Both cases start from a directory proven empty, and the unpatched case
reaches the same code and fails there. That is what makes the patched
result mean something.

## Two ways this test was wrong first, kept so they are not repeated

**It ran the wrong binary.** Driving the lock through `kdesktop` looked
right and proved nothing: `kdesktop` resolves the helper with
`TDEStandardDirs::findExe()`, which returned `/opt/trinity/bin/kdesktop_lock`
whatever `PATH` said. Both cases ran the system build and printed identical
output. It invokes `$prefix/bin/kdesktop_lock` directly now.

**It read the log too early, then measured a stale artifact.** The helper
prints its socket warning on the way out, so a grep taken while it still ran
reported "nothing" for the failing case as well -- a real failure looking
exactly like a pass. And `$TDEHOME/socket-<host>` is a *symlink* into
`/tmp/tdesocket-<user>` that does not exist until tdelibs creates it, so
resolving it before the run gave a path that was not there, the cleanup
deleted nothing, and the helper found FIFOs left by a previous run. It took
the `EEXIST` path and printed no warning, which reads as success and proves
only that existing FIFOs are tolerated.

The harness now names the real directory and prints a **before** count, so a
case that did not start clean is visible in its own output.
