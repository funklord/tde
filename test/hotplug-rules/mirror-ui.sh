#!/bin/bash
# mirror-ui.sh LABEL -- drive the Displays module (tdecmshell displayconfig)
# on the private dummy-driver Xorg, primary DUMMY0 1024x768 and DUMMY1
# 800x600 beside it, and print where DUMMY1 ends up after Apply.
#
#   STAGE=out/stage        use the module build-kcm.sh built, else installed
#   KSHIM=<file.so>        preload into tdecmshell, e.g. a fixed libtderandr
#   START_MIRROR=1         start with DUMMY1 at +0+0, mirrored outside TDE
#   CLICK_MIRROR=1         click the "Mirror the primary monitor" box
#
# Same namespaces as harness.sh: private /tmp, no system bus, no /dev/dri.
# There is no window manager, so the clicks are at measured positions; the
# confirm dialog is accepted and the result read after its 15 s revert
# timer. Fixed steps, two bounded waits; everything dies with the namespace.
set -u
LABEL=${1:-ui}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$HERE/out
if [ -z "${HOTPLUG_IN_NS:-}" ]; then
	mkdir -p "$OUT/empty"
	exec unshare -r -m --pid --fork --kill-child --mount-proc bash -c "
		mount -t tmpfs tmpfs /tmp &&
		mount --bind /dev/null /run/dbus/system_bus_socket &&
		mount --bind '$OUT/empty' /dev/dri &&
		exec unshare --user --map-user=$(id -u) --map-group=$(id -g) \
			env -u XDG_SESSION_ID -u DISPLAY HOTPLUG_IN_NS=1 \
			LIBSEAT_BACKEND=noop bash '$0' '$LABEL'"
fi
DRV=$OUT/root/usr/lib/xorg/modules
[ -e "$DRV/drivers/dummy_drv.so" ] || { echo "run 'make driver' first" >&2; exit 1; }
R=$OUT/ui/$LABEL
# Start every program from inside the fresh run directory: TDE treats any
# output from xrandr as failure, and a shell whose directory was just
# replaced prints a getcwd error into it.
rm -rf "$R"; mkdir -p "$R/home"; cd "$R/home"
/usr/lib/xorg/Xorg :8 -config "$HERE/xorg-dummy.conf" -modulepath "$DRV,/usr/lib/xorg/modules" \
	-logfile "$R/xorg.log" -nolisten tcp -noreset -novtswitch -sharevts > "$R/xorg.out" 2>&1 &
n=0
while [ $n -lt 20 ]; do
	DISPLAY=:8 xdpyinfo >/dev/null 2>&1 && break
	n=$((n + 1)); sleep 0.5
done
export DISPLAY=:8 HOME=$R/home TDEHOME=$R/tdehome PATH=/opt/trinity/bin:$PATH
[ -n "${STAGE:-}" ] && export TDEDIRS=$STAGE:/opt/trinity
xrandr --newmode 800x600t 40.00 800 840 968 1056 600 601 605 628 +hsync +vsync
xrandr --addmode DUMMY1 800x600t
xrandr --output DUMMY1 --mode 800x600t --right-of DUMMY0
[ -n "${START_MIRROR:-}" ] && xrandr --output DUMMY1 --pos 0x0
dcopserver --nofork --nosid > "$R/dcop.log" 2>&1 &
sleep 2
# Without kded: its low-disk warning would cover the module.
tdeinit --no-kded > "$R/tdeinit.log" 2>&1
sleep 4
env ${KSHIM:+LD_PRELOAD=$KSHIM} tdecmshell displayconfig > "$R/kcm.log" 2>&1 &
sleep 10
K=$(pgrep -n tdecmshell)
grep -o '/[^ ]*kcm_displayconfig\.so' /proc/$K/maps | sort -u | sed 's/^/  module: /'
snap() { import -window root "$R/$1.png" 2>/dev/null; }
xdotool key alt+e; sleep 1                              # enable display control
xdotool key alt+l; sleep 2                              # Resolution and Layout
echo "  start:  $(xrandr | grep -E '^DUMMY1 connected' | sed 's/ (.*//')"
xdotool mousemove 860 352 click 1; sleep 1; xdotool key Down Return; sleep 1
snap 1-monitor2
[ -n "${CLICK_MIRROR:-}" ] && { xdotool mousemove 53 534 click 1; sleep 2; snap 2-clicked; }
xdotool key alt+a; sleep 4                              # Apply
D=$(xdotool search --onlyvisible --name 'Confirm Display Settings' 2>/dev/null | head -1)
[ -n "$D" ] && xdotool mousemove --window "$D" 102 135 click 1  # Accept Configuration
sleep 17
snap 3-result
echo "  result: $(xrandr | grep -E '^Screen|^DUMMY[01] connected' | sed 's/ (.*//; s/ [0-9]*mm x [0-9]*mm//; s/, maximum.*//; s/minimum.*current/current/' | tr '\n' ';')"
