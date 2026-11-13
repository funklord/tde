#!/bin/bash
# harness.sh LIBDIR LABEL -- open a scratch directory in konqueror on nested
# display :9, with libkonq taken from LIBDIR ahead of /opt/trinity/lib, and
# drop a file onto the view from xds_source.
#
# It re-executes itself inside an unprivileged PID namespace, mapped back to
# the calling user, so every process started here -- Xvfb, dcopserver,
# tdeinit's daemons, konqueror -- dies when it exits. The only thing the
# namespace cannot reach is Xvfb's /tmp/.X9-lock and socket, which hold a
# namespace-internal PID; remove them by name afterwards.
#
# XDS_NAME sets the proposed file name, XDS_ANSWER forces the source's
# reply (S, F or E). No loops except one bounded wait.
set -u
LIBDIR=$1; LABEL=$2
HERE=$(cd "$(dirname "$0")" && pwd)
if [ -z "${XDS_IN_NS:-}" ]; then
	exec unshare -r --pid --fork --kill-child --mount-proc \
		env XDS_IN_NS=1 unshare --user --map-user="$(id -u)" \
		--map-group="$(id -g)" bash "$0" "$@"
fi
[ "${DISPLAY:-}" = ":0" ] && unset DISPLAY
OUT=$HERE/out/$LABEL
rm -rf "$OUT"; mkdir -p "$OUT/tdehome" "$OUT/dropdir"
export TDEHOME=$OUT/tdehome PATH=/opt/trinity/bin:$PATH
export LD_LIBRARY_PATH=$LIBDIR:/opt/trinity/lib
Xvfb :9 -screen 0 1280x900x24 > "$OUT/xvfb.log" 2>&1 &
n=0
while [ $n -lt 20 ]; do
	DISPLAY=:9 xdpyinfo >/dev/null 2>&1 && break
	n=$((n + 1)); sleep 0.5
done
export DISPLAY=:9
dcopserver --nofork --nosid > "$OUT/dcop.log" 2>&1 &
sleep 2
tdeinit > "$OUT/tdeinit.log" 2>&1
sleep 3
konqueror "file://$OUT/dropdir" > "$OUT/konq.log" 2>&1 &
sleep 10
K=$(pgrep -n konqueror)
grep -o '/[^ ]*libkonq\.so[^ ]*' /proc/$K/maps | sort -u | sed 's/^/  loaded: /'
w=$(xdotool search --onlyvisible --class konqueror | head -1)
eval "$(xdotool getwindowgeometry --shell "$w")"
cx=$((X + WIDTH / 2)); cy=$((Y + HEIGHT / 2))
echo "=== $LABEL: dropping at $cx,$cy ==="
"$HERE/xds_source" $cx $cy "${XDS_NAME:-xds-test.txt}" 2>&1 | sed 's/^/  source: /'
sleep 3
import -window root "$OUT/after.png" 2>/dev/null
ls "$OUT/dropdir" | sed 's/^/  saved: /'
