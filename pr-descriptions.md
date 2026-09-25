# Pull request descriptions

Ready to paste into `mirror.git.trinitydesktop.org`. One per branch pair.

**Before submitting**, add your own `Signed-off-by:` -- TDE carries the DCO
and that line is a statement about provenance that only its author can
make:

    git commit --amend -s          # on each branch, master and r14.1.x

Each fix is developed on `master` and backported to `r14.1.x`; the
diffstats match, which is what says the backport changed nothing. Whether
upstream wants both branches or only `master` is theirs to say.

---

## PR 1 -- tdebase: `fix/lock-fifo-per-user`

**Title:** `kdesktop: put the lock control FIFOs in the per-user socket directory`

kdesktop_lock creates two control FIFOs and, on a normal desktop, has
never been able to create either of them.

They are placed in `/tmp/tdesocket-global`, which tdm creates as root
before anyone logs in, so `mknod()` fails with `EACCES` on every lock
attempt for an ordinary user. On the machine this was found on it produced
**83 identical warnings in a single session**:

    [kdesktop_lock] Warning: unable to create control socket
    '/tmp/tdesocket-global/kdesktoplockcontrol-0'.
    Interactive logon modules may not function properly.

Neither `mknod()` nor `mkdir()` had its return value read, so the failure
surfaced only through that message and reads as a warning about an
optional feature rather than a feature that has never once worked.

The directory creation could not have helped even without the ownership
problem: `mkdir(FIFO_DIR, 0644)` asks for a directory with no execute bit,
which cannot be entered to create anything inside it.

### Why the path moves rather than the permissions loosening

These FIFOs are privileged. The inbound one accepts commands that dismiss
the unlock dialog and display arbitrary text (`processInputPipeCommand`,
cases `C`, `T`, `E`/`W`/`I`/`K`); the outbound one carries the PIN the user
has typed. Making the shared directory writable so each user could create
their own nodes would let any local user pre-create another user's control
socket, drive their lock screen and read their PIN -- a worse fault than
the one being fixed.

`TDEGlobal::dirs()->saveLocation("socket")` is per-user and per-host and
tdelibs creates it mode 0700, which is what these need. Both FIFOs are
created 0600 rather than the inbound one being world-readable. A
privileged helper running as root reaches them exactly as before; a module
running as another user no longer can.

Also: a failing `mknod()` is reported with its `errno`, an existing FIFO is
treated as the success it is, and the process-wide `umask(0)` is dropped
rather than restored -- this runs in a worker thread, so it affected every
file the rest of the process created, and it was never needed, since a
umask only clears bits and the `chmod` sets the mode outright.

### Testing

Built and run against the unpatched binary as a control, on a nested X
display. Both cases start from a directory verified empty:

    unpatched   0 FIFOs created, warning printed
    patched     2 FIFOs created (prw------- 0600), no warning

Installed on a live TDE 14.1.6 desktop: the FIFOs now appear on locking,
and the warning that fired 83 times per session fires not at all.

---

## PR 2 -- tdebase: `fix/tdm-session-class`

**Title:** `tdm: classify the user's session as a user session, not a greeter`

tdm registers every logged-in session with logind as class `greeter`.

`XDG_SESSION_CLASS=greeter` is put into the PAM environment by
`doPAMAuth()`, which authenticates the person logging in, and the same PAM
handle is carried through to `pam_open_session()` with nothing resetting it
in between. There is exactly one `pam_start()` and one `pam_open_session()`
in the backend and the greeter has no PAM session of its own, so the only
session that value ever reached was the user's.

The cost is that such a session is not lockable. systemd gates this on the
class directly, in `src/login/logind-session.h`:

    /* Which session classes have a lock screen concept? */
    #define SESSION_CLASS_CAN_LOCK(class) \
            (IN_SET((class), SESSION_USER, SESSION_USER_EARLY))

`SESSION_GREETER` is excluded there and in `SESSION_CLASS_CAN_STOP_ON_IDLE`,
and those two are the whole difference -- `CAN_IDLE`, `CAN_DISPLAY`,
`CAN_TAKE_DEVICE` and `CAN_CHANGE_TYPE` all admit a greeter already. So
this restores lockability and stop-on-idle and changes nothing else.
`CanLock` is a const property fixed at session creation, so nothing can
correct it at runtime: `loginctl lock-session`, the `Lock` and `Unlock`
signals and `SetLockedHint` are all inert for the logged-in user.

Observed before the change, on TDE 14.1.6:

    Service=tdm-trinity  Type=x11  Class=greeter  CanLock=no

It cannot ever have worked as intended, either: pam_systemd acts in the
session phase rather than the authentication phase, so a class set before
`pam_authenticate()` has no effect until a session is opened, and the only
session opened here belongs to the user.

The value is set where the code already observes that the greeter has gone,
immediately before the session is opened, and `pam_putenv()`'s result is
read rather than discarded.

This changes what logind is told about the session. It does not change who
may authenticate and grants no new rights: a session classified as a user
session is what an ordinary login already is everywhere else.

### Testing

Compiled with `-DWITH_PAM=ON` and verified in the binary rather than the
build log -- the object carries `XDG_SESSION_CLASS=user` and zero
occurrences of `=greeter`. Installed on a live desktop; after the next
login:

    before:  Class=greeter  CanLock=no
    after:   Class=user     CanLock=yes

A reboot is required to observe it, the class being fixed at session
creation.

---

## PR 3 -- tdepowersave: `feat/lid-docked`

**Title:** `feature: skip the lid-close action while an external display is on`

Closing the lid of a docked machine suspends it, even though the session
remains perfectly usable on the external screen.

logind would not do this: its default is `HandleLidSwitchDocked=ignore`.
tdepowersave never reaches that default, because it takes a **block**
inhibitor on `handle-lid-switch` and so owns the event outright, and it has
no notion of being docked.

    $ systemd-inhibit --list
    TDEPowersave ... handle-lid-switch ... block

`screen::externalDisplayConnected()` asks RandR whether any connector other
than the built-in panel is connected, identifying the panel by name as
every driver spells it: `eDP`, `LVDS`, `DSI`.

It calls `XRRGetScreenResourcesCurrent` rather than
`XRRGetScreenResources` deliberately -- the latter forces a DDC probe of
every connector, which is slow and is the last kind of traffic to generate
from a lid event. The calls run under the file's own error handler, since
this is invoked while the display is changing, which is precisely when an
output can be removed between listing the resources and asking about one of
them.

Only the **action** is suppressed. Locking keeps its own setting, which is
how logind splits the two: closing the lid of a docked machine should not
power it down, but it may still be a reason to lock the screen.

`ignoreLidCloseWhenDocked` defaults to true, so the behaviour matches the
platform default the inhibitor currently overrides. Anyone who wants the
old unconditional action sets it to false.

### Testing

A probe linked against the built object rather than a reimplementation of
the query, so the test cannot drift from the code:

    laptop panel only (eDP-1 connected)        ->  false
    sole output not named like a panel         ->  true

The two disagree, which is what makes the result meaningful.

**Not tested on hardware**: this reaches the RandR query and the name
matching. A real hotplug, a real DisplayPort connector and the lid event
that calls it are not exercised, and want a physical external display.

---

## PR 4 -- tdepowersave: `feat/lid-panel-off`

**Title:** `feature: switch the internal display off on lid close, backlight only optional`

Closing the lid leaves the built-in panel lit, and turning it off is
tangled together with locking and suspending rather than being its own
decision. Two modes make it visible: with power management inhibited, or
with an external display connected, the lid-close handler returned early and
did nothing, so the internal panel -- which nobody can see under a shut lid
-- stayed on. Upstream's `forceDpmsOffOnLidClose` did blank it, but only in
the undocked lock path, and through `xset dpms force off`, which is global
and so cannot be used while docked without blanking the external display
too.

Powering the internal panel off becomes its own step, run first and
unconditionally on lid close while the session is active, before the inhibit
gate and independent of lock, suspend and the docked policy.
`powerSaveInternalDisplay()` picks the mechanism and records what it did so
the lid-open path undoes exactly that:

- **docked** (an external display is driving): the internal output is
  disabled entirely, light and drive both, and the external is left
  untouched. `disableInternalPanel()` refuses if that would leave nothing
  displaying, and lid-open restores it.
- **alone** (the internal panel is the only display): DPMS off -- a power
  state rather than a configuration change, so no transient zero-display
  state, and it restores on the next input event. Global DPMS is safe here
  precisely because there is no external display for it to blank.
- **backlight only**: the backlight is dimmed to nothing and no display
  configuration or power state is touched at all.

### The compatibility option

`lidDisplayLightOnly`, a checkbox in the lid-close button configuration
("On lid close, switch off only the backlight, not the display"), selects
that third mechanism. It exists for desktops and software that break when
the display configuration changes, or that cannot survive a transient
zero-display state: ticked, a lid close only dims the backlight and never
touches the display; unticked, the display itself is switched off, which is
the default. It is shown only when the machine has a lid, exactly as the
lock-mode combo and the docked-action option are.

`forceDpmsOffOnLidClose` becomes the single master enable for all of this,
default on. Its name is now historical -- it once forced only DPMS -- and is
kept so existing configurations and an existing `=false` opt-out still read.

### What it deliberately does not do

- **Run under XWayland**, where outputs are virtual and disabling them is
  meaningless.
- **Handle multiple internal panels.** A dual-panel laptop has two eDPs and
  only one is behind the lid; the panel-off helper refuses rather than guess.

### Testing

Built as a Debian package and installed on a live TDE 14.1.6 desktop, with
the built binary confirmed to match the branch (the new config key present,
the retired one absent). On the single internal display this machine has:

    inhibit + lid close     internal panel goes dark (DPMS), machine awake
    backlight-only + lid     backlight dims, display left configured

Both observed on the running desktop; the checkbox renders and enables Apply
like its siblings.

**Not tested on hardware**: the docked path -- `disableInternalPanel()` on
lid close, external display staying lit -- reaches the RandR output disable
and wants a real second display, as does the restore across a docked lid
cycle.

### Note on the branch

This branch sits on `feat/lid-docked` (PR 3) and reuses its docked
detection and RandR helpers, so it should be reviewed after it. The four
commits here -- the panel-off mechanism, the display-off split, the
backlight-only checkbox and its signal fix -- are the whole of this PR. The
underlying `feat/lid-docked` has itself grown since PR 3 was written (the
docked policy is now configurable as two independent settings rather than
one `ignoreLidCloseWhenDocked` flag, plus the form-factor/`hasLid` fix and
the lock-mode combo); PR 3's description wants refreshing before that branch
goes up, and other independent features on it -- the inhibit toggle, the
per-scheme netcfgd profile -- deserve their own PRs rather than riding this
stack.

---

## A review comment for PR 47, same file

Worth raising on `feat/idle-inhibition` while in `screen.cpp`. It adds
**74 space-indented lines to a file carrying 448 tab-indented ones**:

    PR 47 added lines       5 tab-indented,  74 space-indented
    screen.cpp on master  448 tab-indented,   10 space-indented

The logic reads sound -- `applyDPMSSettings()` returns early while
inhibited so scheme timeouts cannot overwrite the saved DPMS snapshot,
`setSchemeSettings()` is rerouted through it, and
`handleDCOPApplicationRemoved()` restores normal handling if kdesktop dies.
The one `setDPMSTimeouts()` call that bypasses the guard is in `_quit()`,
restoring defaults on exit, where unguarded is correct.
