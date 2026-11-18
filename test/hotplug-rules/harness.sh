#!/bin/bash
# harness.sh LABEL -- run TDE's hotplug rules (the installed
# tdeinit_displayconfig, with $SHIM preloaded if set) against a private Xorg
# on :8 driven by the dummy video driver, and print which profile each rule
# set applied. DUMMY0 starts connected and DUMMY1 disconnected; enabling a
# dummy output marks it connected and nothing marks it disconnected again.
#
# It re-executes itself in user, mount and PID namespaces, mapped back to
# the calling user, where /tmp is a private tmpfs, the system bus socket is
# /dev/null and /dev/dri is empty. Without the last two, Xorg's libseat
# takes logind control of the caller's own session (it did, 2026-11-18)
# and probes the live GPU. Every process dies when this script exits, and
# the private /tmp takes the X lock and the TDE sockets with it.
#
# Eight fixed cases; the only loops are one bounded wait and a fixed seq.
set -u
LABEL=${1:-stock}
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
R=$OUT/$LABEL
rm -rf "$R"; mkdir -p "$R/home"
/usr/lib/xorg/Xorg :8 -config "$HERE/xorg-dummy.conf" -modulepath "$DRV,/usr/lib/xorg/modules" \
	-logfile "$R/xorg.log" -nolisten tcp -noreset -novtswitch -sharevts > "$R/xorg.out" 2>&1 &
n=0
while [ $n -lt 20 ]; do
	DISPLAY=:8 xdpyinfo >/dev/null 2>&1 && break
	n=$((n + 1)); sleep 0.5
done
export DISPLAY=:8 HOME=$R/home TDEHOME=$R/tdehome PATH=/opt/trinity/bin:$PATH
C=$TDEHOME/share/config
mkdir -p "$C/displayconfig"
# Profiles differ only in DUMMY0's mode, which is what the cases read back.
profile() {
	printf '[SCREEN 0]\nScreenUniqueName=DUMMY0\nScreenConnected=true\nIsPrimary=true\nIsExtended=true\nAbsXPos=0\nAbsYPos=0\nCurrentXPixelCount=%s\nCurrentYPixelCount=%s\nRefreshRates=60\nCurrentRefreshRate=0\nGammaRed=1\nGammaGreen=1\nGammaBlue=1\n\n[SCREEN 1]\nScreenUniqueName=DUMMY1\nIsPrimary=false\nIsExtended=false\n' "$2" "$3" > "$C/displayconfig/$1"
}
CASE=0
profile docked 800 600
profile laptop 640 480
# A docked profile saved with more outputs than this server's 16.
{ cat "$C/displayconfig/docked"; for k in $(seq 2 19); do
	printf '\n[SCREEN %d]\nScreenUniqueName=DUMMY%d\nIsPrimary=false\nIsExtended=false\n' $k $k
done; } > "$C/displayconfig/docked-20"
mode() { xrandr | sed -n 's/^DUMMY0 connected primary \([0-9x]*\)+.*/\1/p'; }
named() { case $1 in 800x600) echo docked;; 640x480) echo laptop;; 1024x768) echo none;; *) echo "?$1";; esac; }
# rules NAME EXPECTED (outputs states profile)... -- TDE names outputs
# ":0:<name>" whatever the display; states 1 = connected, 2 = disconnected.
rules() {
	local name=$1 want=$2 i=0; shift 2
	xrandr --output DUMMY0 --mode 1024x768
	printf '[General]\nEnableDisplayControl=true\n' > "$C/displayglobals"
	while [ $# -ge 3 ]; do
		printf '\n[Hotplug-Rule%d]\nOutputs=%s\nStates=%s\nProfile=%s\n' $i "$1" "$2" "$3" >> "$C/displayglobals"
		i=$((i + 1)); shift 3
	done
	CASE=$((CASE + 1))
	# --nocrashhandler: a crash would otherwise wait on TDE's crash dialog.
	env ${SHIM:+LD_PRELOAD=$SHIM} tdeinit_displayconfig --nocrashhandler > "$R/case-$CASE.log" 2>&1
	rc=$?
	got=$(named "$(mode)")
	[ $rc -ge 128 ] && got=crashed
	printf '  %-34s applied %-7s %s\n' "$name" "$got" "$([ "$got" = "$want" ] && echo ok || echo "WRONG, want $want")"
}
echo "== $LABEL${SHIM:+ (preloading $SHIM)}: DUMMY1 disconnected"
rules "one rule that holds"          docked  :0:DUMMY0 1 docked
rules "one rule that does not hold"  none    :0:DUMMY1 1 docked
rules "docked {D0 C, D1 C}"          none    :0:DUMMY0,:0:DUMMY1 1,1 docked
rules "laptop {D0 C}, docked 3 conds" laptop  :0:DUMMY0 1 laptop :0:DUMMY0,:0:DUMMY1,:0:DUMMY2 1,1,2 docked
rules "laptop/docked pair, unplugged" laptop :0:DUMMY0,:0:DUMMY1 1,2 laptop :0:DUMMY0,:0:DUMMY1 1,1 docked
rules "20-screen profile, 16 outputs" docked  :0:DUMMY0 1 docked-20
xrandr --newmode 800x600t 40.00 800 840 968 1056 600 601 605 628 +hsync +vsync
xrandr --addmode DUMMY1 800x600t
xrandr --output DUMMY1 --mode 800x600t --right-of DUMMY0
echo "== $LABEL: DUMMY1 plugged in"
rules "laptop/docked pair, plugged"  docked  :0:DUMMY0,:0:DUMMY1 1,2 laptop :0:DUMMY0,:0:DUMMY1 1,1 docked
rules "docked {D0 C, D1 C}"          docked  :0:DUMMY0,:0:DUMMY1 1,1 docked
