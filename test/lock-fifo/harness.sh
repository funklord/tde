#!/bin/bash
# Does kdesktop_lock actually create its control FIFOs?
#
# Runs the SAME scenario against the unpatched and the patched build and
# compares. The control is the point: "the FIFO exists" says nothing unless
# it has been watched not existing.
#
# Nested display only. Termination: every process started is recorded in
# PIDS and killed by the EXIT trap; the one wait loop is counter-bounded.
set -u

DISP=:9
[ "$DISP" = ":0" ] && { echo "refusing to touch the live display"; exit 9; }

ROOT=/home/nabbe/src/tde
LOG=$ROOT/scratch

# Script-scope, so the EXIT trap can reach them however the script ends.
PIDS=""
TDEHOME=""

cleanup() {
	for p in $PIDS; do kill "$p" 2>/dev/null; done
	sleep 2
	for p in $PIDS; do kill -9 "$p" 2>/dev/null; done
	# dcopserver daemonises without --nofork; sweep by the private TDEHOME,
	# a path no other session on this machine can match, so the live
	# desktop's own processes are never candidates.
	if [ -n "$TDEHOME" ]; then
		for p in $(pgrep -u "$(id -u)" -f "$TDEHOME" 2>/dev/null); do
			kill -9 "$p" 2>/dev/null
		done
	fi
	PIDS=""
}
trap cleanup EXIT INT TERM

run_case() {
	local label="$1" prefix="$2"

	export TDEHOME=$LOG/tdehome-$label
	rm -rf "$TDEHOME"; mkdir -p "$TDEHOME"
	export TDEDIR=/opt/trinity
	export TDEDIRS=$prefix:/opt/trinity
	export PATH=$prefix/bin:/opt/trinity/bin:$PATH
	export LD_LIBRARY_PATH=$prefix/lib:/opt/trinity/lib

	echo "=== case: $label ($prefix) ==="

	Xvfb $DISP -screen 0 1024x768x24 > "$LOG/xvfb-$label.log" 2>&1 &
	PIDS="$PIDS $!"
	local n=0
	while [ $n -lt 20 ]; do
		DISPLAY=$DISP xdpyinfo >/dev/null 2>&1 && break
		n=$((n + 1)); sleep 1
	done
	export DISPLAY=$DISP

	dcopserver --nofork --nosid > "$LOG/dcop-$label.log" 2>&1 &
	PIDS="$PIDS $!"
	sleep 3

	# Invoke the built binary DIRECTLY. Going through kdesktop is no good:
	# it resolves the helper with TDEStandardDirs::findExe(), which picked
	# /opt/trinity/bin/kdesktop_lock regardless of PATH, so both cases ran
	# the system build and the comparison proved nothing.
	# TDEHOME's socket-<host> entry is a SYMLINK into /tmp/tdesocket-<user>,
	# and it does not exist until tdelibs creates it. Resolving it before
	# the run gave a path that was not there, so the removal below deleted
	# nothing, the helper found FIFOs left by an earlier run, took the
	# EEXIST path and printed no warning. That reads exactly like success
	# and proves only that existing FIFOs are tolerated. Name the real
	# directory instead, so each case starts with none.
	local sockdir=/tmp/tdesocket-$(id -un)
	echo "  socket dir: $sockdir"
	rm -f "$sockdir/kdesktoplockcontrol-9" "$sockdir/kdesktoplockcontrol_out-9"
	rm -f /tmp/tdesocket-global/kdesktoplockcontrol-9
	# Count only display :9's pair. The live session's own -0 FIFOs live in
	# the same directory and must not be removed, but counting them made the
	# guard read "2 present" when the display under test was clean, which is
	# the opposite of what it is for.
	echo "  FIFOs for :9 present before the run: $(ls "$sockdir"/kdesktoplockcontrol*-9 2>/dev/null | wc -l)"

	timeout 15 "$prefix/bin/kdesktop_lock" --dontlock \
		> "$LOG/lock-$label.log" 2>&1 &
	local lockpid=$!
	PIDS="$PIDS $lockpid"
	sleep 8

	echo "  FIFOs in the per-user socket dir:"
	ls -l "$sockdir"/kdesktoplockcontrol*-9 2>/dev/null | sed 's/^/    /' \
		|| echo "    (none)"
	echo "  FIFOs in the shared global dir:"
	ls -l /tmp/tdesocket-global/kdesktoplockcontrol* 2>/dev/null | sed 's/^/    /' \
		|| echo "    (none)"
	# The helper prints its socket warning on the way out, so the log can
	# only be read after it has exited. Grepping it while still running
	# reported "nothing" for the failing case too, which made a real
	# failure look identical to a pass.
	# Wait for THIS process only. A bare `wait` waits for every child,
	# including Xvfb and dcopserver, which never exit -- the case then
	# hangs until the outer timeout.
	wait "$lockpid" 2>/dev/null
	echo "  what the helper said about its control socket:"
	if grep -i 'control socket\|socket directory' "$LOG/lock-$label.log"; then
		:
	else
		echo "    (no socket warning - it created them)"
	fi | sed 's/^/    /'

	cleanup
	sleep 2
}

run_case unpatched "$ROOT/stage/tdebase"
run_case patched   "$ROOT/stage/tdebase-lockfix"
echo "=== done ==="
