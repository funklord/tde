#!/bin/bash
# End-to-end probe for TDE PR 779 + PR 47, on a NESTED display only.
#
# Termination: every process started here is recorded in PIDS and killed by
# the EXIT trap; the script itself has no loops that spawn, and its only
# wait loop is bounded by a counter. The caller wraps it in `timeout`.
set -u

DISP=:9
[ "$DISP" = ":0" ] && { echo "refusing to touch the live display"; exit 9; }

ROOT=/home/nabbe/src/tde
STAGE_TB=$ROOT/stage/tdebase
STAGE_TP=$ROOT/stage/tdepowersave
LOG=$ROOT/scratch

PIDS=""
cleanup() {
	echo "--- cleanup ---"
	for p in $PIDS; do
		if kill -0 "$p" 2>/dev/null; then
			kill "$p" 2>/dev/null
		fi
	done
	sleep 2
	for p in $PIDS; do
		if kill -0 "$p" 2>/dev/null; then
			echo "  force-killing $p"
			kill -9 "$p" 2>/dev/null
		fi
	done
	# A PID list is not enough on its own. dcopserver daemonises unless
	# --nofork is given, so the recorded pid is the parent that exits and
	# the real daemon is reparented to init, surviving the trap. That
	# happened once here. Sweep by the private TDEHOME as well, which no
	# other session on this machine can match, so the live desktop's own
	# dcopservers are never candidates.
	leaked=$(pgrep -u "$(id -u)" -f "$TDEHOME" 2>/dev/null | grep -v "^$$\$")
	for p in $leaked; do
		echo "  sweeping leaked $p"
		kill -9 "$p" 2>/dev/null
	done
}
trap cleanup EXIT INT TERM

# Private TDE home so nothing reads or writes ~/.trinity
export TDEHOME=$LOG/tdehome
rm -rf "$TDEHOME"
mkdir -p "$TDEHOME"

export TDEDIR=/opt/trinity
export TDEDIRS=$STAGE_TB:$STAGE_TP:/opt/trinity
export PATH=$STAGE_TB/bin:$STAGE_TP/bin:/opt/trinity/bin:$PATH
export LD_LIBRARY_PATH=$STAGE_TB/lib:$STAGE_TP/lib:/opt/trinity/lib
export XDG_DATA_DIRS=$STAGE_TB/share:$STAGE_TP/share:/usr/share

echo "=== 1. nested X server on $DISP ==="
Xvfb $DISP -screen 0 1024x768x24 > "$LOG/xvfb.log" 2>&1 &
PIDS="$PIDS $!"
n=0
while [ $n -lt 20 ]; do
	DISPLAY=$DISP xdpyinfo >/dev/null 2>&1 && break
	n=$((n + 1))
	sleep 1
done
[ $n -ge 20 ] && { echo "X did not come up"; exit 1; }
export DISPLAY=$DISP
echo "  X up after ${n}s"

echo "=== 2. private DCOP server ==="
dcopserver --nofork --nosid > "$LOG/dcop.log" 2>&1 &
PIDS="$PIDS $!"
sleep 3
dcop >/dev/null 2>&1 && echo "  dcop responding" || echo "  dcop NOT responding"

echo "=== 3. kdesktop (patched, from stage) ==="
"$STAGE_TB/bin/kdesktop" > "$LOG/kdesktop.log" 2>&1 &
PIDS="$PIDS $!"
sleep 6
dcop | grep -q kdesktop && echo "  kdesktop registered on DCOP" \
                        || echo "  kdesktop NOT on DCOP"

echo "=== 4. does it own org.freedesktop.ScreenSaver? ==="
dbus-send --session --dest=org.freedesktop.DBus --print-reply=literal \
	/org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>/dev/null \
	| tr ',' '\n' | grep -i screensaver | sed 's/^/  /'

echo "=== 5. tdepowersave (patched, from stage) ==="
"$STAGE_TP/bin/tdepowersave" > "$LOG/tdepowersave.log" 2>&1 &
PIDS="$PIDS $!"
sleep 6
dcop | grep -q tdepowersave && echo "  tdepowersave registered on DCOP" \
                            || echo "  tdepowersave NOT on DCOP"

echo "=== 6. Inhibit over D-Bus ==="
dbus-send --session --print-reply --dest=org.freedesktop.ScreenSaver \
	/org/freedesktop/ScreenSaver org.freedesktop.ScreenSaver.Inhibit \
	string:"harness" string:"end-to-end probe" 2>&1 | sed 's/^/  /'

sleep 3
echo "=== 7. did the chain reach tdepowersave? ==="
grep -i -E 'inhibit' "$LOG/tdepowersave.log" | tail -5 | sed 's/^/  TPS: /'
grep -i -E 'inhibit' "$LOG/kdesktop.log" | tail -5 | sed 's/^/  KDE: /'

echo "=== done ==="
