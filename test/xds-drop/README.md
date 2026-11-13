# Does Konqueror accept an X Direct Save drop?

`xds_source` is a minimal XDND drag source that offers only
`XdndDirectSave0` (XDS protocol version 0). It proposes a file name,
drops at a given root position, and writes the file to whatever URL the
target puts back into the property. `harness.sh` opens a scratch
directory in Konqueror on nested display `:9`, with `libkonq` taken from
a chosen directory ahead of the installed one, and drops onto the view.

    make test LIBKONQ=<dir holding the libkonq.so.4 under test>
    make test                       # the installed libkonq, the control

The harness runs itself inside an unprivileged PID namespace, so
everything it starts dies with it. Afterwards remove `/tmp/.X9-lock` and
`/tmp/.X11-unix/X9` by name: they hold a PID from inside the namespace.

## Result, 2026-11-13 (tdebase master, TDE 14.2 installed)

    installed libkonq     drop accepted, text/uri-list asked for, no file
    patched libkonq       XdndDirectSave0 converted, source answers S,
                          file saved in the directory
    name "../escape.txt"  saved as dropdir/escape.txt, nothing above it
    source answers E      drop finishes, message queued, no file
    source answers F      falls through to the ordinary drop paths

The source sends two positions before dropping, as a moving pointer
would. Qt3's views ignore a move that reports the same point as the
enter, so with one position the first status is a refusal. That is not
a fault in the target.
