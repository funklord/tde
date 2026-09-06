#!/bin/bash
#
# Capture display, lid and power state around USB-C hotplug events, so that
# the next occurrence of the reported hang leaves a trail. It records a
# snapshot whenever anything changes, plus a periodic heartbeat, and every
# line is flushed as it is written -- the entry immediately before the gap
# is the evidence a hang leaves behind.
#
# TERMINATION. Three conditions, any of which stops it:
#   - the log reaches MAX_BYTES (default 8 MB)
#   - MAX_SECONDS have elapsed (default 24 hours)
#   - SIGINT or SIGTERM
# It spawns nothing that outlives a tick, loops a fixed number of times at
# a fixed interval, and appends to exactly one named file.
#
# It needs no root. It reads /proc, /sys and the X server it is pointed at,
# and writes only the log. It changes nothing.
#
#   tool/hotplug-log.sh [logfile]
#
set -u

LOG=${1:-$HOME/tde-hotplug.log}
INTERVAL=${INTERVAL:-5}
MAX_BYTES=${MAX_BYTES:-8388608}
MAX_SECONDS=${MAX_SECONDS:-86400}
HEARTBEAT=${HEARTBEAT:-600}

stamp() { date '+%Y-%m-%d %H:%M:%S'; }

snapshot() {
	local lid connectors dpms outputs locker
	lid=$(sed -n 's/^state: *//p' /proc/acpi/button/lid/*/state 2>/dev/null | head -1)
	connectors=$(for c in /sys/class/drm/card*-*/status; do
		[ -r "$c" ] || continue
		printf '%s=%s ' "$(basename "$(dirname "$c")")" "$(cat "$c")"
	done)
	dpms=$(timeout 5 xset q 2>/dev/null | grep -A1 'DPMS' | tail -1 | tr -s ' ' | sed 's/^ *//')
	outputs=$(timeout 5 xrandr --query 2>/dev/null | grep ' connected' | cut -d' ' -f1 | tr '\n' ',')
	# CPU discriminates between the two shapes a hang can take: a spin loop
	# burns a core, a block sits at zero. It is deliberately NOT keyed to one
	# desktop -- the fault has been seen under both TDE and Plasma, and more
	# often under Plasma, so anything TDE-specific would miss half the
	# evidence. Sample the X server, any locker that happens to be present,
	# and whatever is busiest.
	locker=$(pgrep -a -x 'kdesktop_lock|kscreenlocker_greet|xsecurelock|i3lock' \
		2>/dev/null | awk '{printf "%s ", $2}')
	xcpu=$(ps -C Xorg -o %cpu= 2>/dev/null | tr -d ' ' | paste -sd, -)
	top=$(ps -eo pcpu=,comm= --sort=-pcpu 2>/dev/null | head -1 | tr -s ' ' | sed 's/^ *//')
	echo "lid=$lid | $connectors| dpms=[$dpms] | xrandr=$outputs | locker=[${locker:-none}] xorg_cpu=${xcpu:-none} top=[$top]"
}

trap 'echo "$(stamp)  STOP  signalled" >> "$LOG"; exit 0' INT TERM

echo "$(stamp)  START interval=${INTERVAL}s max=${MAX_SECONDS}s cap=${MAX_BYTES}B display=${DISPLAY:-unset}" >> "$LOG"

prev=""
elapsed=0
since_beat=$HEARTBEAT
ticks=$(( MAX_SECONDS / INTERVAL ))
i=0

while [ $i -lt $ticks ]; do
	i=$(( i + 1 ))
	now=$(snapshot)

	if [ "$now" != "$prev" ]; then
		echo "$(stamp)  CHANGE $now" >> "$LOG"
		prev="$now"
		since_beat=0
	elif [ $since_beat -ge $HEARTBEAT ]; then
		echo "$(stamp)  ..     $now" >> "$LOG"
		since_beat=0
	fi

	size=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
	if [ "$size" -ge "$MAX_BYTES" ]; then
		echo "$(stamp)  STOP  size cap reached ($size bytes)" >> "$LOG"
		exit 0
	fi

	sleep "$INTERVAL"
	elapsed=$(( elapsed + INTERVAL ))
	since_beat=$(( since_beat + INTERVAL ))
done

echo "$(stamp)  STOP  time cap reached (${elapsed}s)" >> "$LOG"
