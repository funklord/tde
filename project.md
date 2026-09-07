# tde

Repairing the ageing Trinity Desktop software this workstation runs, one
package at a time. The first target is **TDEPowersave** and the screen
locking it drives.

The product of this project is **patches to upstream TDE**, plus this file.
It builds nothing of its own.

## Scope and layout

    project.md          this file -- authoritative over the code
    code-style.md       copied from the global source
    Makefile            upstream / style / hooks; there is nothing to compile
    tool/               the shared style gate and git hooks
    tdebase/            upstream clone, not tracked here
    tdepowersave/       upstream clone, not tracked here

The two clones are fetched with `make upstream` and are ignored by git.
They are separate upstream repositories, not one -- verified by their root
commits (`be4fc77c` for tdepowersave, `4aed2c82` for tdebase) and their
distinct remotes under `https://mirror.git.trinitydesktop.org/gitea/TDE/`. TDE
splits its modules the way KDE 3 did, so there is no monorepo to work in.

### Use `mirror.git.trinitydesktop.org`, not `scm.`

Despite the names, **`mirror.git` is the live instance and `scm.` lags.**
Upstream's own README names `mirror.git` as the collaboration tool, and it
is the only one that works. Measured 2026-09-06:

    heads served      tdebase   tdepowersave
    scm.                   29              5
    mirror.git.            34              5

The five tdebase branches `scm.` was missing were the five newest pull
requests -- and `master` and `r14.1.x` were behind on it as well, by eleven
non-translation commits including the konsole `Screen` class rename. So a
clone from `scm.` is not merely short of topic branches; its mainline is
stale, and findings taken against it are findings against the wrong tree.
Both bugs below were re-verified against `mirror.git` after this was found.

The API is at `mirror.git.trinitydesktop.org/gitea/api/v1`. Its pull
endpoints work there and 404 on `scm.`, which is what made the difference
visible.

## How we work with upstream

**Reuse. Patch rather than fork, and fork only where the change is
fundamental or so opinionated that upstream would reasonably refuse it.**
Set by the copyright holder 2026-09-06.

**Develop on `master`, backport to `r14.1.x`.** Also set 2026-09-06, and it
applies per repository since there are two.

The branch layout is the same trap in both repos and is worth stating
because getting it wrong makes a divergence look like new work:

- The `r14.1.6` tag we run is an ancestor of **`r14.1.x`**, the stable line.
- It is **not** an ancestor of `master`, the development line.
- They diverged long ago -- tdepowersave at `609098f`, 2023-04-16.

So `git log r14.1.6..origin/master` lists the divergence, not upstream
progress. Ask `r14.1.6..origin/r14.1.x` for that. This was got wrong once
here, and the wrong reading said "45 new commits" when the true answer for
tdepowersave is zero.

## Hosting: there is nothing on GitHub to fork

**TDE has no presence on GitHub.** Measured 2026-09-06 -- `api.github.com/orgs/`
returns 404 for `TDE`, `trinitydesktop`, `TrinityDesktopEnvironment` and
`trinity-desktop`, and a repository search finds no upstream mirror:

    search "tdebase"        1 hit    OpenMandrivaAssociation/trinity-tdebase
    search "tdepowersave"   1 hit    OpenMandrivaAssociation/trinity-tdepowersave
    search "tdelibs"        4 hits   distro packaging and one 2016 personal fork

The OpenMandriva repositories are RPM packaging -- a `.spec`, an rpmlintrc
and four PAM files, no upstream source and no shared history. Forking one
would advertise a link to a packaging repository, not to TDE.

So a GitHub fork **cannot** express the relationship, because GitHub's fork
metadata only exists between two repositories on GitHub. Three things do
express it, and they are not exclusive:

- **Fork on TDE's own Gitea**, `mirror.git.trinitydesktop.org`. This is the
  real one: it is where the fork button, the pull requests and the reviewers
  are, and it is what upstream's README asks for. A patch we intend to land
  goes here regardless of what else we do.
- **Push a mirror to a personal GitHub account.** `git push --mirror` into an
  empty repository carries the entire upstream history, so `git log`, blame
  and "N commits ahead" all read correctly and the ancestry is obvious to
  anyone who looks. GitHub will not print the word "fork" above it, and no
  arrangement short of upstream being on GitHub will.
- **Keep the patches here as a series**, which is what this project already
  is. The link is then stated rather than inferred, and nothing has to be
  mirrored at all.

Undecided, and it is the copyright holder's call. Nothing here depends on
it: patches are written against the clones either way.

## The machine these measurements come from

Dell Latitude 5430, Intel Alder Lake-UP3 Iris Xe, internal panel `eDP-1`,
USB-C DisplayPort outputs `DP-1` and `DP-2`. Debian 13, TDE
`4:14.1.6-0debian13.0.0+0` from `mirror.ppa.trinitydesktop.org`, 112
packages, prefix `/opt/trinity`. Measured 2026-09-06.

## Confirmed findings

Each carries the command that produced it, so it can be re-taken.

### 1. kdesktop_lock cannot create its control socket -- FIXED

**Fixed 2026-09-06** on `fix/lock-fifo-per-user` (master) and
`fix/lock-fifo-per-user-r141x` (stable, built and tested). Not yet
submitted upstream. The diagnosis below stands as the record of the fault.

The FIFOs now come from `TDEGlobal::dirs()->saveLocation("socket")`, the
per-user per-host socket resource tdelibs creates mode 0700, and both are
created 0600. `mknod` failures are reported with their errno, `EEXIST` is
treated as the success it is, and the process-wide `umask(0)` is restored.

**A shared directory was the wrong home regardless of permissions**, and
this is why the fix moves the path rather than loosening the mode. The
inbound FIFO accepts commands that dismiss the unlock dialog and display
arbitrary text (`processInputPipeCommand`, cases `C`, `T`, `E`/`W`/`I`/`K`),
and the outbound one carries the PIN the user has typed
(`lockprocess.cpp:2818`). Making the shared directory world-writable so
each user could create their own nodes would let any local user pre-create
another user's control socket, drive their lock screen and read their PIN.
That is a worse fault than the one being repaired.

**Nothing in tdebase reads these FIFOs**, and no binary on this machine
other than `kdesktop_lock` mentions them -- it is an extension point for
external interactive-logon modules with no in-tree client. A privileged
helper running as root still reaches them; a module running as another user
no longer can, which is the intended loss.

`test/lock-fifo/` proves it against the unpatched build as a control: both
start from a directory proven empty, the unpatched case reaches the same
code and fails there, the patched case creates both FIFOs and prints no
warning. Two earlier versions of that test proved nothing -- one ran the
system binary because `kdesktop` resolves the helper with
`TDEStandardDirs::findExe()` regardless of `PATH`, and one measured FIFOs
left by a previous run. Both are recorded in its README.

#### The fault as found



`/tmp/tdesocket-global` is created at boot by tdm as `root:root 0755`. The
lock helper runs as the user and cannot write into it:

    $ touch /tmp/tdesocket-global/probe-$$
    touch: cannot touch '...': Permission denied            exit=1
    $ touch /tmp/tdesocket-nabbe/probe-$$                    # positive control
    (succeeds)

83 failures in one session (`grep -c kdesktoplockcontrol ~/.xsession-errors`),
each printing that interactive logon modules may not work. That socket is
the channel the unlock dialog's plugin modules use.

The code is wrong independently of the permissions, and is unchanged on
both `r14.1.x` and `master`:

    kdesktop/lock/lockprocess.h:43    #define FIFO_DIR "/tmp/tdesocket-global"
    kdesktop/lock/lockprocess.cpp:3007        mkdir(FIFO_DIR,0644);
    kdesktop/lock/lockprocess.cpp:3008        mknod(fifo_file, ...);

`mkdir` with `0644` makes a directory with no execute bit, which is
unusable even when it wins the race; `mknod`'s return is never read, so the
failure is noticed only indirectly at line 3025. The directory is shared
with root-owned `tsak` and `tdm` (`tsak/main.cpp:47`,
`tdm/kfrontend/kgreeter.cpp:108`), which is why it exists as root before
the user's helper gets there.

**No branch in tdebase fixes this** -- swept every remote branch.

### 2. tdm registers the user's session as a greeter -- FIXED

**Fixed 2026-09-06** on `fix/tdm-session-class` (master) and
`fix/tdm-session-class-r141x` (stable). Compiles clean; **not runtime
tested**, because verifying it requires a fresh login through tdm and this
machine's session cannot be restarted. Not yet submitted upstream.

The misplaced value is dropped from the authentication path and
`XDG_SESSION_CLASS=user` is set immediately before `pam_open_session()`,
in the block whose existing comment already reads "the greeter is gone by
now". The result of `pam_putenv()` is read rather than discarded, as the
original line discarded it.

**The mechanism is no longer an inference.** It was recorded here as
unverified; systemd's own source settles it, in
`src/login/logind-session.h`:

    /* Which session classes have a lock screen concept? */
    #define SESSION_CLASS_CAN_LOCK(class) \
            (IN_SET((class), SESSION_USER, SESSION_USER_EARLY))

`SESSION_GREETER` is excluded there and in `SESSION_CLASS_CAN_STOP_ON_IDLE`,
and those two are the entire difference -- `CAN_IDLE`, `CAN_DISPLAY`,
`CAN_TAKE_DEVICE` and `CAN_CHANGE_TYPE` all admit a greeter already. So the
fix restores lockability and stop-on-idle and changes nothing else. The
`CanLock` property is `SD_BUS_VTABLE_PROPERTY_CONST`, which is why nothing
can correct this at runtime.

**Structural evidence that the line was simply misplaced:** the tdm backend
has exactly one `pam_start()`, one `pam_open_session()` and one
`pam_close_session()`. The greeter has no PAM session of its own, so the
only session that value ever reached was the user's. It also cannot have
worked as intended, because pam_systemd acts in the session phase rather
than the authentication phase.

**A build that proved nothing, kept as a warning.** The first build of this
fix produced a `tdm` binary containing no `XDG_SESSION_CLASS` string at
all, because `WITH_PAM` defaults off and the whole `#ifdef USE_PAM` block
was skipped -- the change was never compiled. `make` exited 0 throughout.
Rebuilt with `-DWITH_PAM=ON`, the object carries `XDG_SESSION_CLASS=user`
and the binary carries zero occurrences of `=greeter`, against the system
binary which carries it. Check the artifact, not the exit status.

#### The fault as found



    $ loginctl show-session c1
    Service=tdm-trinity  Type=x11  Class=greeter  LockedHint=no
    $ busctl introspect org.freedesktop.login1 /org/freedesktop/login1/session/c1
    .CanLock    property b  false  const

`XDG_SESSION_CLASS` appears **exactly once in the whole tdebase tree**:

    tdm/backend/client.c:399    pam_putenv( pamh, "XDG_SESSION_CLASS=greeter" );

It is set inside `doPAMAuth()`, which is called at `:567` and `:795` to
authenticate **the user**, and the same `pamh` reaches `pam_open_session()`
at `:1436` with nothing resetting it. So pam_systemd registers the
logged-in session as a login greeter.

`CanLock` is a `const` property, fixed at session creation, so nothing can
correct this at runtime. **Any locking built on logind is blocked until
this is fixed** -- `loginctl lock-session`, the `Lock`/`Unlock` signals and
`SetLockedHint` all hang off that session.

Present identically on `r14.1.x` and `master`.

*Not verified:* that logind gates `CanLock` on `class == user`. The
observation is measured; the mechanism is read from behaviour, not from
systemd's source.

### 3. tdepowersave's lock layer is 2006-vintage, and upstream has not moved

`screen::lockScreen()` calls DCOP `kdesktop KScreensaverIface lock`, falling
back to `xscreensaver-command -lock`, `gnome-screensaver-command --lock`,
then `xlock`. Supporting hacks: `forceDPMSOff()` shells out to
`xset dpms force off`, and `fakeShiftKeyEvent()` fakes keycode 62 through
XTest `timeToFakeKeyAfterLock` ms after locking, purely to raise the unlock
dialog.

    src/screen.cpp:473  DCOP lock        :715  xset dpms force off
    src/screen.cpp:745  XTestFakeKeyEvent(dpy, 62, ...)

**`master`'s `screen.cpp` differs from `r14.1.6`'s by two lines** -- one
`#include` rename and one comment. Every line above is current upstream.

### 4. The lid inhibitor defeats logind's docked handling -- FIXED

**Fixed 2026-09-06** on `feat/lid-docked` (master) and
`feat/lid-docked-r141x` (stable, built and tested). Not submitted upstream.

`screen::externalDisplayConnected()` asks RandR whether any connector other
than the built-in panel is connected, and `handleLidEvent()` skips the
lid-close **action** when it says yes. Only the action is suppressed;
locking keeps its own setting, which is how logind splits the two. The new
`ignoreLidCloseWhenDocked` defaults to true, matching logind's own
`HandleLidSwitchDocked=ignore` -- the default tdepowersave's block
inhibitor currently prevents the system from ever reaching.

It calls `XRRGetScreenResourcesCurrent` rather than
`XRRGetScreenResources` deliberately: the latter forces a DDC probe of
every connector, which is slow and is the last kind of traffic to generate
from a lid event, particularly on a machine with a display fault under
investigation.

The panel is identified by name -- `eDP`, `LVDS`, `DSI` -- which is the
convention every driver follows and the same test other desktops use.

`test/docked-detect/` links **the object the real build produced** rather
than reimplementing the query, so the test cannot drift from the code:

    :0   eDP-1 connected, laptop panel only     ->  false
    :9   Xvfb, sole output named "screen"       ->  true

The two disagree, which is what makes the result mean anything. What it
does not cover is stated in its README: Xvfb's output stands in for *a name
that is not a panel*, so the RandR query and the name matching are
exercised and a real hotplug, a real DisplayPort connector and the lid
event itself are not.

#### The fault as found



    $ systemd-inhibit --list
    TDEPowersave ... handle-lid-switch ... block

A `block` inhibitor, so logind's default `HandleLidSwitchDocked=ignore`
never applies -- and tdepowersave has no concept of "docked". Closing the
lid with an external display attached runs the full lid-close action.

### 5. tdepowersave has no RandR awareness at all

`grep -rn -i 'randr\|XRR\|RRScreenChange' src/` returns nothing. A display
hotplug reaches it only as TDE hardware-device events; on a `Backlight`
event it queues `checkBrightness()` behind a 50 ms `singleShot`
(`src/hardware.cpp:198`, `:328`).

### 6. X BadWindow noise around every lock attempt

566 in one session, opcodes 20 `GetProperty` (459), 19 `DeleteProperty`
(101), 2 `ChangeWindowAttributes` (78), 3 `GetWindowAttributes` (6), in
bursts coinciding with the lock warnings. Cause not established.

## Open: the USB-C display hang -- NOT fixed

Reported by the copyright holder: an occasional hang when a USB-C display
is connected or disconnected **while the lid is closed**; a visible screen
appears to mitigate it. **Still not reproduced, and no mechanism is
established.** What follows is a lead and an instrument, not a repair.

### The forensic source is unreadable, and this was measured late

The kernel log cannot be read by this user. `dmesg` answers
`Operation not permitted`, and the account is in neither `adm` nor
`systemd-journal`, so `journalctl` shows only its own session's entries --
3542 of them this boot, all `pppd`, `dhcpcd`, `wpa_supplicant` and systemd
user units.

**Several searches were run against that log before this was noticed**, and
each reported no i915 faults, no GPU hangs and no DRM errors. Every one of
those results was vacuous: an empty result from a log that cannot contain
kernel messages says nothing whatever. The check that would have caught it
costs one command and asks what the log actually holds before reading its
silence.

Granting access is a root action and is the copyright holder's:

    sudo usermod -aG adm,systemd-journal <user>      # takes effect on next login

Until then, a hang leaves no trail that can be read here.

### A lead, in the right code path, and deliberately not acted on

`kdesktop_lock` has an unbounded self-rescheduling loop in exactly the path
a display hotplug takes. `LockProcess::doDesktopResizeFinish()`
(`kdesktop/lock/lockprocess.cpp:1075`) is driven by the resize timer whose
own comment reads *"should allow display switching operations to finish"*.
It does:

    while (mDialogControlLock == true) { usleep(100000); }
    mDialogControlLock = true;
    if (closeCurrentWindow()) {
            TQTimer::singleShot( 0, this, TQ_SLOT(doDesktopResizeFinish()) );
            mDialogControlLock = false;
            return;
    }

`closeCurrentWindow()` returns true for as long as `mDialogs` is non-empty,
and a dialog leaves that list only after its `exec()` returns. So a dialog
that does not close re-schedules this at **0 ms, with no iteration cap and
no timeout**: a permanent busy loop while the screen is mid-resize.

That is a real defect whether or not it is this hang. It is **not** being
patched, and the reason is the rule rather than caution: an explanation
this comfortable, arriving in exactly the right subsystem, is what stops
anybody looking further. Non-reproduction is what "intermittent" means, so
a speculative fix followed by a quiet week would prove nothing and would
retire the investigation.

There are also nine unbounded `while (mDialogControlLock == true)` spins in
that file, none with a timeout. Four are in the FIFO command handler, which
has no consumer on this system and therefore never runs.

### The fault predates TDE, which refutes the lead above

Reported by the copyright holder 2026-09-06: the hang was seen under KDE
Plasma **before the switch to TDE**, and was **much more frequent then**.
TDE became the display manager on 2026-07-28. So the fault existed on a
system that was not running any TDE code, and the resize loop recorded
below is **refuted as its cause** rather than merely demoted -- it can only
exist in kdesktop_lock, which Plasma never runs. It stays written down as a
real defect in its own right and is not this.

That moves the search below both desktops: the i915 driver, the
DisplayPort alt-mode path, the USB-C controller, or firmware.

### The frequency drop has two candidate causes, minutes apart

The hang became much less frequent after 2026-07-28. Two things happened
that morning:

    07:56:09   linux-image-6.12.96 installed, replacing 6.12.90
    08:00:51   display-manager.service -> tdm.service

**Four minutes apart, and either could account for it.** The desktop change
is the visible one and the kernel upgrade is at least as likely, so
attributing the improvement to the switch away from Plasma would be exactly
the comfortable explanation this file keeps warning about. Nothing measured
so far separates them.

Kernel history on this machine, from `dpkg.log`: 6.12.63 and 6.12.74
(2026-04-10, install), 6.12.90 (2026-06-15), 6.12.96 (2026-07-28).

### Two updates are available and neither has been applied

    BIOS      1.36.0, dated 2025-12-23   ->  1.40.0 offered via LVFS
    kernel    6.12.96                    ->  6.12.107 in the archive

`fwupdmgr get-history` reports **no history at all**, so firmware has never
been updated on this machine. USB-C DisplayPort alt-mode faults are
commonly firmware, and this is four BIOS releases behind.

Both are the copyright holder's to apply. **If the aim is to identify the
cause rather than only to stop the symptom, apply them one at a time with
enough time between to judge**, because doing both at once repeats the
2026-07-28 confound and will leave the same question unanswered.

### Xorg's logs are readable and hold nothing useful

`/var/log/Xorg.0.log` and `.old` are world-readable, which made them worth
trying. They record the initial modeset and then nothing about runtime
output changes -- the modesetting driver is silent about RandR
reconfiguration. Their only errors are input-device noise: touchpad jump
discards and "event processing lagging behind by 1036ms, your system is
too slow", which is a stall indicator worth remembering but is not a
display event.

So the kernel log remains the only source that would show a hotplug fault,
and it cannot be read here.

### An instrument hazard on this machine, found the hard way

**`grep` here is `ugrep`, and it silently skips files it decides are
binary.** `/var/log/Xorg.0.log.old` is "Non-ISO extended-ASCII text", so
every search over it returned nothing -- including a search for a string
visible in its own header. No error, no message, exit 1.

It was caught only because a file that documents `(EE)` and `(WW)` in its
own header reported zero of both. The counts previously taken from
`~/.xsession-errors` were re-measured with `-a` and are unaffected, that
file being plain ASCII: 83 lock-socket warnings, and BadWindow now 578
where it was 566, the session having run on since.

Pass `-a` when grepping any log on this machine, and treat an empty result
over a file whose encoding is unknown as unmeasured rather than clean.

### What would confirm or refute it

A spin loop and a blocked wait look identical from outside and differ in
one number: **CPU**. A spin burns a core; a block sits at zero.
`tool/hotplug-log.sh` samples `kdesktop_lock`'s CPU alongside lid state,
DRM connector status, DPMS state and RandR outputs, recording on change
with a periodic heartbeat, and flushing each line as it is written -- so
the entry immediately before the gap is what a hang leaves behind.

    tool/hotplug-log.sh [logfile]

It needs no root, changes nothing, and stops itself on any of three
conditions: an 8 MB size cap, a 24 hour time cap, or a signal.

If the next occurrence shows `kdesktop_lock` at high CPU, the loop above is
the answer and the fix is a bounded retry. If it shows zero, the fault is a
block and that loop is a red herring -- which is the outcome the entry
above is written to allow.

## Upstream work worth reusing before writing anything

**There is live upstream work on exactly this problem, and it is a
coordinated pair.** Both were opened 2026-08-23 against `master`, and both
report `mergeable=True`:

- **tdebase #779**, `feat/dbusscreensaver-refresh` -- "Add D-Bus ScreenSaver
  idle inhibition support". Updated 2026-09-01. Gives kdesktop an
  `org.freedesktop.ScreenSaver` interface.
- **tdepowersave #47**, `feat/idle-inhibition` (`b33256b`, +353) -- "Honor
  screen saver idle inhibition". Suppresses automatic DPMS, autodimming and
  inactivity autosuspend while an inhibitor is active, and resynchronises
  across kdesktop restarts.

One side publishes the inhibition interface, the other honours it. That is
the reported flakiness, being fixed upstream now. **Do not reimplement
this**; evaluate the pair, test it here, and report back through the PRs.

Note what it is and is not: `org.freedesktop.ScreenSaver` is the
**app-facing inhibit and query** interface. It is complementary to logind's
session `Lock`, not a substitute, and it does not touch either confirmed
bug below.

Also open, and relevant:

- **tdebase #531**, `feat/dbusscreensaver` -- the 2024 original of #779.
  `mergeable=False`; superseded. Kept here only so it is not mistaken for
  current work.
- **tdebase #653**, `feat/separate-tsak` (WIP) -- tsak is the other tenant
  of `/tmp/tdesocket-global`, so it touches finding 1's territory.
- **tdebase #16**, `feat/fix-suspend-code` (WIP) -- suspend/hibernate paths.

None of these has been evaluated for correctness yet.

## What the stable branch already offers

- **tdepowersave**: `r14.1.6..origin/r14.1.x` has **zero** non-translation
  commits. Nothing waiting.
- **tdebase**: real fixes since r14.1.6 -- konsole colon-separated CSI
  sub-parameters, kicker wheel scrolling, kcontrol builds against
  fontconfig-2.18, twin sizing. A rebuild from `r14.1.x` is worth something
  on its own.

## Building: master cannot be built on this machine

Measured 2026-09-06, and it shapes the whole workflow.

**Both repositories' `master` targets unreleased R14.2 tdelibs.** They
include headers that tdelibs 14.1.6 does not ship, so a build against the
installed desktop fails at the first compile:

    tdepowersave master   src/inactivity.h:24      tdeprocess.h
    tdebase master        kdesktop/lockeng.h:11    tdeprocess.h
                          kcontrol/.../bgrender.cpp    tdestandarddirs.h
                          kcontrol/.../bgsettings.cpp  tdesimpleconfig.h

    $ ls /opt/trinity/include/ | grep -E '^(k|tde)process\.h'
    kprocess.h
    $ dpkg -S /opt/trinity/include/tdeprocess.h
    (no package -- the header does not exist at 14.1.6)

The `k` to `tde` header rename is part of the divergence recorded above.
So the workflow has a wrinkle worth stating plainly: **develop on `master`,
where it cannot be compiled here, and test the `r14.1.x` backport.** That
inverts the usual arrangement, where you develop where you can run the
result. A patch is therefore never proven by the branch it is submitted on;
what is proven is the backport, and the two must be kept honest by
diffstat.

### The recipe that works

    cmake -S tdepowersave -B build/<name> \
          -DCMAKE_INSTALL_PREFIX=<stage> -DCMAKE_BUILD_TYPE=RelWithDebInfo
    make -C build/<name> -j12

    cmake -S tdebase -B build/<name> -DBUILD_KDESKTOP=ON -DBUILD_LIBKONQ=ON \
          -DCMAKE_INSTALL_PREFIX=<stage> -DCMAKE_BUILD_TYPE=RelWithDebInfo

`BUILD_ALL` defaults off in tdebase, so components are named individually.
`BUILD_LIBKONQ=ON` is not optional: kdesktop includes
`/opt/trinity/share/cmake/libkonq.cmake`, only `tdelibs.cmake` is installed
there, and no `libkonq4-trinity-dev` package exists on this machine -- so
libkonq must be built from source beside it.

**Nothing is ever installed.** `CMAKE_INSTALL_PREFIX` points at `stage/`
precisely so that a stray `make install` cannot overwrite the running
desktop under `/opt/trinity`.

## Build results for #779 and #47

Both backport cleanly onto `r14.1.x` and both compile with **zero
warnings**. The backports are faithful: the diffstat against the stable
branch matches the diffstat of the original PR against its own base, which
is what says the transplant changed nothing.

    #47   1 commit  onto r14.1.x   353 insertions, 30 deletions   matches
    #779  3 commits onto r14.1.x  1439 insertions, 37 deletions   matches

Verified in the artifacts rather than from make's exit status:

    screen::setDPMSInhibited(bool)            in screen.cpp.o
    SaverEngine::notifyIdleInhibitionChanged()  in libtdeinit_kdesktop.so
    SaverEngine::setIdleInhibited(bool)         in libtdeinit_kdesktop.so
    ScreenSaverService::createInterface(...)    in libdbusscreensaverservice.a
    TDEDbusScreenSaver::configureService()      in libdbusscreensaverservice.a

Local branches: `pr47` and `pr779` are the PRs as submitted; `pr47-r141x`
and `pr779-r141x` are the buildable backports.

### What the pair actually does, and what it does not

Two transports, which the titles do not convey:

- Applications inhibit through **D-Bus**, `org.freedesktop.ScreenSaver`,
  which is #779's new interface in kdesktop.
- kdesktop then tells tdepowersave over **DCOP** -- #779 emits
  `idleInhibitionChanged(bool)` from `SaverEngine`, and #47 adds the
  matching slot.

So this is a modern *inhibition* path bolted onto the existing DCOP
plumbing. **It is not a move to modern locking, and it touches neither
confirmed bug above.**

### Review findings on #47

- **Sound logic.** `applyDPMSSettings()` returns early while inhibited, so
  scheme timeouts cannot overwrite the saved DPMS snapshot;
  `setSchemeSettings()` was rerouted through it; and
  `handleDCOPApplicationRemoved()` restores normal handling if kdesktop
  dies. The one `setDPMSTimeouts()` call that bypasses the guard is in
  `_quit()`, restoring defaults on exit, where unguarded is correct.
- **Indentation is wrong for the file it patches**, and this is worth
  reporting upstream:

        PR 47 added lines       5 tab-indented,  74 space-indented
        screen.cpp on master  448 tab-indented,  10 space-indented

  It also introduces `m_`-prefixed members into a file using bare names
  (`autoDimmDown`, `got_XScreensaver`). The prefix is arguably the author's
  to choose; the indentation is TDE's own convention in TDE's own file.

Neither has been run yet. Building is not behaving.

## Examination without a running X session

The copyright holder cannot restart X, so nothing below touches display
`:0`. Recorded 2026-09-06.

**Neither project ships any test suite.** No `add_test`, no
`enable_testing`, nothing under a test directory in either tree. So there
is nothing upstream to run against these PRs, and any test has to be built.

### The inhibit-leak guard in #779 fires -- tested, after a wrong prediction

An inhibit API's classic failure is a client that dies without calling
`UnInhibit`, leaving the screensaver suppressed for ever.
`ScreenSaverInterfaceImpl::handleDBusSignal()` guards it: on
`NameOwnerChanged` for a unique name that lost its owner, it calls
`removeInhibitorsForSender()`. The logic is right -- it filters for names
starting with `:`, a non-empty old owner and an empty new one.

The question was whether the signal ever arrives. `dbus-1-tqt`'s own
documentation describes only client-side filtering and never mentions a bus
match rule; the library carries the string `destination='`, and
`NameOwnerChanged` is a broadcast with no destination. **That reasoning
predicted the guard could not fire, and it was wrong.**

`test/dbus-signal-delivery/` builds a `TQT_DBusProxy` exactly as
`ScreenSaverDBusWatcher` does and counts what arrives, against a
`dbus-monitor` control over the same window:

    probe          8 NameOwnerChanged received
    dbus-monitor  10 over the same window

Four client connect/disconnect pairs are eight events and the probe caught
all eight; the control's extra two are its own connection and the probe's.
The library registers a broad enough match. `make -C test/dbus-signal-delivery test`
re-runs it, needs no X, and stops itself after six seconds.

The lesson is the one this file keeps relearning: a plausible mechanism read
out of strings and documentation is not a measurement, and the control is
what makes "received 0" mean anything.

### Both object paths are exposed, which is not cosmetic

Commit `086f0e25e` publishes the interface on `/ScreenSaver` as well as
`/org/freedesktop/ScreenSaver`. That matters -- Firefox and Chromium have
historically called the legacy path -- so this is the difference between the
feature working for real browsers and only in principle.

The declared interface is `GetActive`, `Lock`, `SetActive`, `Inhibit`,
`UnInhibit` and the `ActiveChanged` signal. `GetActiveTime` and
`SimulateUserActivity`, which some implementations carry, are absent. Not
yet established whether anything here needs them.

### Cookie handling reads correct

`Inhibit` never issues cookie zero and skips a value already live if the
counter wraps. `UnInhibit` clears the SaverEngine inhibition *before*
dropping the last cookie and keeps the cookie if the DCOP call fails, so
internal state cannot drift from the engine's. Not exercised yet.

### The pair works end to end -- measured on a nested display

`test/inhibit-chain/` runs the patched `kdesktop` and `tdepowersave` from
`stage/` on display `:9` under a private D-Bus session and a private
`TDEHOME`. Nothing touches `:0`, the live DCOP, or `~/.trinity`. Measured
2026-09-06:

    kdesktop registered on DCOP; org.freedesktop.ScreenSaver claimed
    tdepowersave registered on DCOP
    Inhibit("harness", "end-to-end probe")  ->  uint32 1

    KDE: Inhibit: cookie(1), application(harness), reason(end-to-end probe)
    TPS: WARNING: Could not inhibit DPMS
    KDE: Removing inhibitor cookie(1) for disconnected D-Bus client(:1.2)

Those three lines are the whole chain: kdesktop accepted the D-Bus call,
tdepowersave's slot ran, and the cookie was released when the client
vanished.

**The tdepowersave warning is the evidence, not a fault.**
`screen::setDPMSInhibited()` returns false when the server has no DPMS
extension, so that line appears only if the D-Bus to DCOP to slot chain
reached it. Its absence would mean a break. This is the probe-placement rule
paying off: the observable was chosen because it can only be produced by the
thing under test.

**The third line is the leak guard firing in the real program.**
`test/dbus-signal-delivery/` established in isolation that the signal
arrives; here the production code path released a dead client's cookie
unprompted. Two independent observations, one synthetic and one real.

### The ceiling: no nested server has DPMS

Neither Xvfb nor Xephyr provides the DPMS extension, with or without
`+extension DPMS` -- both answer "Server does not have the DPMS Extension".
So **the final X call, actually zeroing and restoring the DPMS timeouts,
cannot be observed on any nested display.** Everything up to that call is
confirmed; the call itself is not, and confirming it needs the real display
and therefore a session that can be restarted.

### An orphan escaped the trap, and why

The first harness run left `dcopserver --nosid` reparented to init. It
daemonises unless given `--nofork`, so the recorded `$!` was a parent that
exited while the real daemon outlived the EXIT trap. It was killed by hand
after being distinguished from the live session's two `dcopserver [tdeinit]`
processes by start time -- 32 seconds against three days.

Fixed by passing `--nofork` and by having the trap also sweep processes
matching the private `TDEHOME`, a path no other session on this machine can
produce. Recorded because a PID list reads like complete cleanup and is not
one whenever a child forks.

## Confirmed in production, 2026-09-06

All three are installed on this machine and verified on a real session,
which is a stronger claim than the staging tests that preceded them.

    session c1   before:  Class=greeter  CanLock=no
                 after:   Class=user     CanLock=yes

    /tmp/tdesocket-nabbe/kdesktoplockcontrol-0       prw------- created on lock
    /tmp/tdesocket-nabbe/kdesktoplockcontrol_out-0   prw-------

    "unable to create control socket": 83 per session before, 0 after

`tool/verify-fixes.sh` reports `pass=4 fail=0 unknown=0`. It reported
three failures against the same machine before the install, which is what
makes the pass worth reading.

Two ordering facts the verification depended on, worth keeping because both
would have produced a false negative:

- **The tdm fix cannot show in a session older than the install.** The class
  is fixed at session creation and `CanLock` is const, so the first run
  after installing still reported `Class=greeter`. It needed a reboot.
- **The lock helper is resident.** kdesktop pre-spawns
  `kdesktop_lock --internal` once and signals it to lock, so after an
  install the running helper is still the old binary --
  `/proc/<pid>/exe` pointed at a **deleted** inode. Locking before the
  reboot would have exercised the code being replaced.

**The docked-lid behaviour is still unconfirmed on real hardware.** It needs
an external display and a lid to close; `test/docked-detect/` reaches the
RandR query and the name matching and no further.

## Defects found in my own patches, and fixed

Reviewed 2026-09-06 after the fixes were already installed and working.
Four, in two of the three patches; the tdm one was clean.

**The FIFO patch kept a umask call it did not need.** The original set
`umask(0)` process-wide and never restored it; the first version of the fix
restored it, which is better and still wrong. `ControlPipeHandlerObject::run()`
is a worker thread, so for that window any file the rest of the process
created got whatever mode it asked for. It was never needed at all: a umask
can only clear bits, `0600` has none a sane one would clear, and the `chmod`
that follows sets the mode outright. Removed rather than repaired.

**It also chmod()ed a file it had failed to create.** Harmless, and sloppy
in a way that would confuse the next reader. Guarded.

**The docked patch put its `#include` at column 0** inside a tab-indented
`extern "C"` block -- the exact defect written up against upstream PR 47
two sections above, committed here in the same session. Reviewing one's own
patch by the standard applied to somebody else's is apparently not
automatic.

**And it called RandR with no error handler.** `externalDisplayConnected()`
runs *while the display is changing*, which is the one moment an output can
be removed between `XRRGetScreenResourcesCurrent` and `XRRGetOutputInfo`:
the resource list is a snapshot, and an id the server has since dropped is
an X error rather than a null return. It runs under the file's own
`badwindow_handler` now, as every other X call in that file does.

Both rebuilt with no warnings, and both tests re-run against the corrected
builds and still discriminate.

**A fifth was in the test rather than the patch.** `test/lock-fifo/`
counted every `kdesktoplockcontrol*` in the socket directory to prove the
display under test started clean -- including the live session's own `-0`
pair, which it must not remove. It reported "2 present" for a clean `:9`,
which is the opposite of what the guard is for. It counts `*-9` now.

## Submitting upstream

`pr-descriptions.md` holds the three pull request descriptions, ready to
paste. It is a separate file rather than a section here because it is an
outbound artifact meant to be copied verbatim into a web form, with a
different lifecycle from this record: once submitted it is history.

**Nothing has been submitted, and two things block it.** There are no
credentials for `mirror.git.trinitydesktop.org` on this machine -- no
`.netrc`, no credential helper, and a push dry-run fails asking for a
username. And TDE carries the DCO, so each commit needs a
`Signed-off-by:` -- a statement about provenance that belongs to its
author and to nobody else. `git commit --amend -s` on each of the six
branches.

Verified 2026-09-06, after the self-review corrections: every backport
still matches its master branch, which is what says the transplant changed
nothing.

    fix/lock-fifo-per-user    2 files, 58 insertions, 13 deletions   both
    fix/tdm-session-class     1 file,  13 insertions,  1 deletion    both
    feat/lid-docked           7 files, 101 insertions, 1 deletion    both

## The locker's resize loop -- FIXED

**Fixed 2026-09-07** on `fix/lock-resize-retry` (master) and
`fix/lock-resize-retry-r141x` (stable, built clean). Not submitted
upstream, and **not runtime tested** -- the trigger is a dialog that
declines to close, which has not been reproduced here.

`doDesktopResizeFinish()` re-armed itself at **zero milliseconds** for as
long as `closeCurrentWindow()` kept reporting true, with no cap.
`closeCurrentWindow()` reports true for as long as anything remains in
`mDialogs`, and a dialog leaves that list only once its `exec()` has
returned. So a dialog that will not close is a busy loop at whatever rate
the event loop turns: the resize never finishes and the process sits on a
core.

Now retries at 50 ms up to 40 attempts -- two seconds -- and on running out
finishes the resize anyway rather than never, putting `mClosingWindows` and
`mForceReject` back to rest so the next resize starts clean. Finishing with
a stale dialog on screen is the better of the two outcomes available at
that point.

The wait on `mDialogControlLock` in that same function is bounded too.
Every site that sets the flag clears it before returning, so the ceiling
should not be reachable; it is bounded because an unbounded spin inside a
screen locker is a hang with no escape for whoever is sitting in front of
it. Eight further such spins remain elsewhere in the file, four of them in
the FIFO command handler that has no consumer.

**Why this was done before the output-switching work**, rather than after:
a desktop resize while the screen is locked is exactly what a laptop does
when its lid closes onto an external display. Disabling an output on lid
close would turn this path from rare into certain, and it is the wrong
order to make a known-fragile path routine and then fix it.

## Switching off the internal panel on lid close -- IMPLEMENTED

**Written 2026-09-07** on `feat/lid-panel-off` (master) and
`feat/lid-panel-off-r141x` (stable, built clean). Branched from
`feat/lid-docked`, whose detection it reuses. Not submitted upstream, and
**the state-changing half is not tested** -- see below.

The three questions this design left open were answered by the copyright
holder delegating them, and decided as follows.

**RandR to read, `xrandr` to write.** Not either/or: reading mode, position
and primary flag through the API is exact, while parsing `xrandr --query`
is not; but writing through the API means reimplementing framebuffer-size
computation, whose failure mode is a corrupted screen rather than an error.
`runXrandr()` blocks deliberately, because the verification that follows is
meaningless against a process still running.

**Refuse when more than one internal panel is found.** A dual-panel laptop
has two and only one is behind the lid. Nothing visible here says which,
and refusing costs those users nothing they have today.

**A separate pull request from `feat/lid-docked`.** They share detection
and not risk: that one declines to act and fails safe, this one acts and
fails dangerous. A reviewer should be able to take the first without
judging the second.

### What is and is not tested

`test/docked-detect/` exercises every read-only helper against the real
build. Measured on the docked machine and on a nested server with no panel:

                                  real (docked)   nested (no panel)
    internalPanelOutput()         true (eDP-1)    false
    enabledOutputCount()          2               1
    internalPanelIsOff()          false           false

The nested case is the one worth having: **both refusal conditions hold at
once**, so the fail-closed behaviour is observed rather than asserted.

`disableInternalPanel()` and `restoreInternalPanel()` are **not exercised**.
They change the live display and want a real lid to close. What is
established is that the code compiles, that the detection it gates on is
correct in both directions, and that the guards refuse when they should.

### The design, as built

### The problem it solves

Closing the lid turns off the backlight. It does not disable the RandR
output, shrink the desktop or renumber the Xinerama heads. So a docked
machine with the lid shut keeps a 1920x1080 region of its desktop that is
physically invisible, and anything placed there is lost. Kicker is only the
visible symptom, being pinned to head 0; **any** window can land in that
region, which is why fixing kicker alone would be papering over one case of
many.

Nothing else on the system does this. There is no display-switcher daemon
in TDE, so it belongs in the thing that already owns the lid event.

### The risk is smaller than it first appears, and this is why

The obvious fear is a black screen with no way back. Working through it,
the dangerous case mostly is not one:

- **External unplugged while the lid is shut, internal already off.** No
  display -- and a closed laptop with no external is a machine showing
  nothing anyway. The user is not looking at the panel. It resolves the
  moment the lid opens.
- **So the whole safety burden falls on one path: re-enable on lid open.**
  That is a single trigger tdepowersave already handles, and it must fire
  unconditionally, ignoring any stored state, every time.

What remains genuinely dangerous is narrower:

- **A convertible reporting lid-closed in tablet mode**, where the internal
  panel is the display in use. The "another enabled output exists" guard
  covers this in practice, since such a machine rarely has an external
  attached in that pose -- but the lid switch is lying and no code here can
  tell.
- **tdepowersave dying while the output is off.** Nothing would restore it.
  Answered by a startup self-heal below.

### Invariants

1. **Never disable the last enabled output.** Decided by counting enabled
   outputs, not by "an external is connected" -- that closes the unplug
   race, where a check on connectedness passes just as the external goes.
2. **Verify afterwards that a CRTC is still active, and roll back if not.**
3. **Re-enable on lid open unconditionally**, whatever state is recorded.
4. **On startup, if the lid is open and an internal output is disabled,
   enable it.** This is the crash and restart path, and it costs one check.
5. **Fail closed.** If no output is recognised as internal, do nothing.

### Identifying the internal panel

The kernel names DRM connectors `<type>-<index>` from a fixed table, so
`eDP`, `LVDS` and `DSI` are the type rather than a guess, and
`/sys/class/drm/card*-*/enabled` gives the enabled count invariant 1 needs.
RandR output names mirror the DRM names for modesetting, intel and amdgpu.

They do not for the proprietary NVIDIA driver, which spells things
`DFP-0`. There the match simply finds nothing and rule 5 applies: no
internal output identified, no action. That is the correct failure.

### Mechanism, and the open question in it

Shelling out to `xrandr` is the cheap route and matches what the lid path
already does for `xset`. It also recomputes the framebuffer size, which
doing this through the RandR API would mean reimplementing.

Against it: restoring must put back the exact previous mode, position and
primary flag, so the configuration has to be recorded before disabling
rather than restored with `--auto` and hoped over.

**Whether that is acceptable in a power manager is the holder's call.**
It is a second process spawned from a hardware event, and it is the kind
of thing upstream may object to.

### Ordering, which is not arbitrary

Disable the output **before** locking, not after. The locker then draws
once on the final geometry instead of resizing underneath itself.
`fix/lock-resize-retry` bounds that path now, but bounded is not the same
as unnecessary, and the cheaper arrangement is to not provoke it.

### Configuration

Opt-in, defaulting **off**. Not because the feature is wrong, but because
its worst outcome is an invisible screen on somebody else's laptop, and a
default that can do that will be judged by its worst day rather than its
average one. `ignoreLidCloseWhenDocked` was defaulted on for the opposite
reason: its worst outcome is a machine that stays awake.

### What it deliberately does not do

- **Notice the external disappearing while the lid is shut.** That needs
  RandR event handling, which tdepowersave has none of, and by the argument
  above it does not need to: lid-open restores.
- **Handle multiple internal panels.** Dual-screen laptops have two eDPs
  and only one is behind the lid. Not distinguishable here; rule 5 could be
  tightened to refuse when more than one internal output is found.
- **Run under XWayland.** Outputs there are virtual and disabling them is
  meaningless. Upstream has a live `feat/run-in-xwayland` branch, so this
  will need an answer eventually, not now.

### Open questions for the holder

- `xrandr` subprocess, or the RandR API with the framebuffer arithmetic
  that implies?
- Refuse when more than one internal output is found, or act on the first?
- Is this one PR with `feat/lid-docked`, or a separate one? They share the
  detection code but not the risk profile: one declines to act, this one
  acts.

## Deploying the fixes on this machine

Built as Debian packages rather than copied binaries, so installing and
reverting are each one apt command and the package manager keeps track.
Local versions carry a `+lockfix1` / `+lidfix1` suffix, which sorts above
the repository's `+0` -- so apt will not silently undo them, and a genuine
14.1.7 from upstream will supersede them when it appears.

Built from `scratch/pkg/`, patched from the `r14.1.x` branches.

    tdepowersave-trinity_...+lidfix1_amd64.deb     the docked-lid feature
    kdesktop-trinity_...+lockfix1_amd64.deb        the control FIFO fix
    tdm-trinity_...+lockfix1_amd64.deb             the session class fix

Only those three binary packages are installed. The tdebase source builds
around thirty-five, and replacing konqueror, konsole and kicker to fix two
bugs would be out of all proportion to the change.

### The risk, and the way back

**tdm is the display manager.** If a broken one is installed there is no
graphical login at next boot. **Confirm a text console works before
rebooting** -- Ctrl+Alt+F2, log in there -- because that is the recovery
path, and finding out it does not work after the reboot is the bad order
to learn it in.

**kdesktop_lock guards the locked screen.** A broken one means a lock that
cannot be dismissed. Same recovery: a text console, then
`pkill kdesktop_lock`.

Reverting any of them is one command per package:

    sudo apt install --reinstall tdm-trinity kdesktop-trinity tdepowersave-trinity

That pulls the stock `4:14.1.6-0debian13.0.0+0` back from the TDE
repository, because `--reinstall` names the archive version rather than
the locally-built one.

### Verifying afterwards

`tool/verify-fixes.sh` reads logind, the socket directory and the session
log, changes nothing, and runs once. Run it after a reboot, and again after
locking the screen once.

**It was run against the unpatched system first and reported three
failures**, which is what makes a later pass worth anything: `Class=greeter`,
`CanLock=no`, and a `tdepowersave` binary with no `ignoreLidCloseWhenDocked`
in it. A check never seen to fail is not evidence.

It picks the session from `XDG_SESSION_ID`, falling back to the row with a
real seat. The first version scanned for the user's sessions and took the
first, which is the systemd user manager -- `Class=manager`, `CanLock=no`
whatever tdm does, and indistinguishable from the bug being tested for.

## Open questions

- Whether the tdepowersave **lock layer** is patched or replaced. Findings
  4 and 5 are defensible upstream fixes; swapping DCOP for logind is the
  opinionated change that may not be welcome upstream, and it is the one
  decision that could turn this from a patch set into a fork.
- Whether the greeter-class fix belongs in `doPAMAuth()` or in tdm's
  separation of greeter and user PAM handles. The one-line form is obvious;
  whether it is right has not been established.

## Corrected readings, kept so they are not repeated

- **A resident `kdesktop_lock --internal <pid>` sitting in `sigsuspend` is
  not hung.** It was first read here as a stuck locker. `kdesktop/lock/main.cpp:392-455`
  shows `--internal` is the pre-spawned helper: it signals kdesktop it is
  ready, then waits on `sigsuspend` for SIGUSR1. That is its idle state.
- **`git log r14.1.6..origin/master` is not "what is new".** See *How we
  work with upstream* above.
- **`ps ... | grep -E 'git|curl|apt'` matches `-caption`.** An orphan sweep
  here reported kmix and kcontrol as candidates for that reason alone.
- **A host called `scm.` was assumed canonical over one called `mirror.`,
  on the strength of the names and one matching HEAD.** Both wrong: the
  mirror is the live instance. One matching HEAD on one repository is not
  evidence that two hosts agree -- tdepowersave matched and tdebase did
  not, and the check that would have separated them, comparing the ref
  lists, cost one command. Upstream's README named the right host all
  along and was read past.

## Standing constraints

- **Nothing on the running desktop is changed without asking.** No config
  edits, no `loginctl lock-session`, no lock test: with the locker in its
  current state, a lock that cannot be dismissed locks the user out of the
  machine this work happens on.
- The upstream clones are never reset or checked out by any target here.
  `make upstream` clones what is missing and fetches what is present.
