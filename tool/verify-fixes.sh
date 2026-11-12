#!/bin/bash
#
# Check whether each fix is actually in effect on the running system.
# Read-only: queries logind, the socket directory and the session log, and
# changes nothing. Runs once and exits; there is no loop.
#
# Run it after a reboot, and after locking the screen once.
#
set -u

pass=0
fail=0
unknown=0

ok()      { echo "  PASS  $*"; pass=$((pass + 1)); }
bad()     { echo "  FAIL  $*"; fail=$((fail + 1)); }
dunno()   { echo "  ????  $*"; unknown=$((unknown + 1)); }

echo "=== 1. tdm: is the session classified as a user session? ==="
# $XDG_SESSION_ID names this shell's own session. Falling back to a scan,
# take the one with a real seat: the other row for this user is the systemd
# user manager (Class=manager, SEAT "-"), which is never the graphical
# session and reports CanLock=no whatever tdm does.
sid=${XDG_SESSION_ID:-}
if [ -z "$sid" ]; then
	sid=$(loginctl list-sessions --no-legend 2>/dev/null \
		| awk -v u="$(id -un)" '$3 == u && $4 != "-" {print $1; exit}')
fi
if [ -z "$sid" ]; then
	dunno "no session found for $USER"
else
	class=$(loginctl show-session "$sid" -p Class --value 2>/dev/null)
	canlock=$(loginctl show-session "$sid" -p CanLock --value 2>/dev/null)
	echo "        session $sid: Class=$class CanLock=$canlock"
	[ "$class" = "user" ] && ok "Class is user" || bad "Class is $class, expected user"
	# elogind (Devuan, measured 255.17) has no CanLock property at all, so
	# an empty answer is the login manager's silence, not the fault.
	if [ -z "$canlock" ]; then
		dunno "this login manager exposes no CanLock; Class is the check"
	else
		[ "$canlock" = "yes" ] && ok "CanLock is yes" || bad "CanLock is $canlock, expected yes"
	fi
fi

echo "=== 2. kdesktop_lock: are the control FIFOs created? ==="
sock=/tmp/tdesocket-$(id -un)
found=$(ls "$sock"/kdesktoplockcontrol* 2>/dev/null | wc -l)
if [ "$found" -gt 0 ]; then
	ls -l "$sock"/kdesktoplockcontrol* | sed 's/^/        /'
	ok "$found FIFO(s) in $sock"
else
	dunno "none in $sock yet -- lock the screen once, then re-run"
fi
# grep -c prints 0 itself when nothing matches, so no fallback: one
# would print a second 0. Empty means the log is not there to read.
stale=$(grep -a -c 'unable to create control socket' ~/.xsession-errors 2>/dev/null)
stale=${stale:-"no log"}
echo "        'unable to create control socket' in this session's log: $stale"
echo "        (a count from before the new binary was installed is expected;"
echo "         what matters is that it stops rising after a lock)"

echo "=== 3. tdepowersave: is the docked setting present? ==="
# The series named this ignoreLidCloseWhenDocked until +lidfix4 split it
# into lockOnLidCloseWhenDocked and performLidActionWhenDocked; checking
# the old name failed against every build since.
if grep -a -q 'lockOnLidCloseWhenDocked' /opt/trinity/bin/tdepowersave \
	/opt/trinity/lib/libtdeinit_tdepowersave.so 2>/dev/null; then
	ok "the installed binary knows lockOnLidCloseWhenDocked"
else
	bad "installed tdepowersave has no lockOnLidCloseWhenDocked"
fi
echo "        connected outputs right now:"
xrandr --query 2>/dev/null | grep ' connected' | awk '{print "          " $1}'

echo
echo "pass=$pass fail=$fail unknown=$unknown"
[ "$fail" -eq 0 ]
