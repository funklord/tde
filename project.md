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

A TQt3 control-centre module and tray for netcfgd were written during this
work and live in **netcfgd's** tree, at `adapter/netcfgd-tde/`, packaged as
`netcfgd-trinity`. They are recorded there rather than here because they
are netcfgd's software; the pointer is here because a reader of this file
would otherwise not know a TDE front end exists. `doc/tde-integration.md`
in that tree carries why it is a second front end rather than the Qt one
repackaged.

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

#### The fault as found: a socket directory the user cannot write



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

#### The fault as found: a user session registered as a greeter



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
lid-close response when it says yes. `ignoreLidCloseWhenDocked` defaults
to true, matching logind's own `HandleLidSwitchDocked=ignore` -- the
default tdepowersave's block inhibitor currently prevents the system from
ever reaching.

**As first written it guarded only the action branch**, on the reasoning
that a lock was a separate concern the way logind separates
`HandleLidSwitch` from session locking. That was wrong for a single
setting whose whole promise is that a docked session stays usable: a
machine with no configured lid-close action -- the common case, where
closing the lid just locks -- still locked on every lid close while
docked. Fixed in `+lidfix3`, recorded below.

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

#### The guard skipped the lock and DPMS-off paths -- FIXED (+lidfix3)

**Fixed 2026-09-17**, and confirmed by the copyright holder closing the
lid docked: it no longer locks. On `feat/lid-docked` (master) and
`feat/lid-docked-r141x`, with `feat/lid-panel-off` rebased onto each so
both feature branches carry it; built as `tdepowersave-trinity +lidfix3`
and installed.

`handleLidEvent()` checked `ignoreLidCloseWhenDocked && externalDisplayConnected()`
only inside the branch that handles a configured action, so the lock and
`forceDpmsOffOnLidClose` in the other branch ran regardless. The wiring
was the proof: a lock is exactly the exit the guard did not reach. The fix
hoists the guard above both branches, so docked-and-ignore means no lock,
no DPMS-off and no action.

**The single flag then became two, on the copyright holder's design
call.** `ignoreLidCloseWhenDocked` coupled the lock and the action, which
tdepowersave keeps separate everywhere else, and had no UI. It is replaced
by `lockOnLidCloseWhenDocked` and `performLidActionWhenDocked`, both
defaulting off (so the behaviour above is the default), each a checkbox in
the configure dialog -- the lock one in Lock Screen, the action one in
Button Events beside "Lid close Button:". The model is two plain toggles
rather than a mirror of logind's docked/external-power/normal triplet: the
holder noted logind is a systemd interface tdepowersave must outlive, and
this is the only machine here with systemd. `+lidfix4`.

**And the checkboxes were invisible until a second bug was found -- see
finding 9.** The dialog hid every lid option on this hardware because TDE
reports the form factor as Desktop. `+lidfix5` gates them on the lid
switch instead; `+lidfix6` moved the action checkbox to Button Events.
`+lidfix7` then made lock-on-lid a three-state combo (do not lock /
unless docked / even when docked) rather than two checkboxes that could
express a nonsense fourth state, and moved the lid button to the foot of
the Button Events list beside its action checkbox.


Runtime only for the confirmation: the `kdDebug` trace that would show the
branch taken is stripped by `-DNDEBUG`, established by a positive control
(the old build lacks its own old trace string too), so `strings` cannot
see the change either way. What was verified mechanically is that the
edited `tdepowersave.cpp` was the file compiled into the shipped object;
that the docked session no longer locks is the copyright holder's
observation, which is the only instrument that reaches it.

#### The fault as found: a standing block on handle-lid-switch



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

### 7. `tdelfeditor -e` strips GNU_RELRO from every TDE binary

Found while packaging a TQt3 front end for netcfgd, where lintian reported
`hardening-no-relro` on a binary whose link line demonstrably carried
`-Wl,-z,relro`.

TDE's cmake macros run two commands on every binary and library after the
link, at four call sites in `TDEMacros.cmake` (the `COMMENT` lines are
1443, 1453, 1694 and 1705):

    tdelfeditor -m <target> ${ELF_EMBEDDING_METADATA}   # write SCM metadata
    tdelfeditor -e <target>                             # remove resource

Isolated on a copy of one linked binary, one command at a time:

    before      GNU_RELRO present
    after -m    GNU_RELRO present
    after -e    GNU_RELRO gone

So `-e` rewrites the ELF without carrying the segment across. Reproduced
from the other end as well: running the build's own link command by hand,
out of `CMakeFiles/<target>.dir/link.txt`, produces a binary with the
segment, and the build's own output of that same command does not.

It is not specific to anything built here. Stock binaries have none
either, while a non-TDE binary built on the same machine by the same
toolchain keeps its segment -- which is the control that makes this
TDE's tool rather than the compiler or the flags:

    /opt/trinity/bin/tdepowersave   none
    /opt/trinity/bin/tdesu          none
    /usr/bin/netcfgd-gui            GNU_RELRO

Every Trinity binary on a Debian system is therefore missing a hardening
measure the distribution applies by default, and **no packaging can put it
back**: the flag is honoured at link time and destroyed afterwards. Passing
it is still right, so that a fixed `tdelfeditor` takes effect for free.

Not reported upstream. It belongs to tdelibs and its cmake modules rather
than to tdebase, so it is a different tracker from findings 1 to 6.

### 8. No display arrangement persistence or hotplug policy

Not a regression and not one of our patches -- a standing TDE gap, surfaced
2026-09-17 by the first reboot in eleven days. Recorded because it is what
the copyright holder actually wants fixed and because two hours went into
learning its shape.

Three symptoms, one absence:

- **The arrangement resets on every cold boot.** There is no `tderandrrc`
  and nothing in `.xsession` or Autostart runs `xrandr`, so at login the
  `modesetting` driver's default stands: both outputs enabled, side by
  side, the built-in panel primary at the origin. Whatever arrangement the
  previous session had was runtime-only state a reboot discards.
- **Kicker and the lock/login prompt then sit on the internal panel**
  (`XineramaScreen=0`, the output at the origin), so with the lid shut they
  are on a dark screen. `+lidfix3` removes the docked case of this by not
  locking at all; the panel-primary placement remains for anything else.
- **Nothing re-applies an arrangement on a RandR change.** A mirror set by
  hand did not survive a lid-close: with both outputs at one origin the
  driver collapsed them to a single CRTC and kept the *internal*, dropping
  the external, so the desktop rendered scaled onto the shut panel and its
  menus were unreachable. Observed once, with a `--scale-from` mirror;
  not proven for a plain same-resolution mirror, but any mirror shares the
  one-origin property the driver mishandled.

The unifying fact is that TDE R14.1 has no component that owns display
policy across events -- the "display switcher daemon" that newer desktops
run. `tderandrtray` reacts to change events but applies no chosen policy;
hand-`xrandr` cannot stand in, because the event that breaks it is the same
event that would need to re-apply it.

**Whose decision, and the options, because this is a feature rather than a
fix.** A daemon that on each RandR change picks a policy -- docked: external
primary, internal mirrored or off; undocked: internal only -- is the thing
wanted, and the copyright holder said earlier this is plausibly
tdepowersave's job since nothing else holds it. That is a real piece of
design, not a setting, and it is not started here without being asked for.
`autorandr` exists and does exactly this generically, at the cost of a
per-machine dependency and of not being TDE's own. Left open for a
deliberate decision.

**The policy the holder wants, specified 2026-10-02.** The earlier text
left the policy open; it is now decided, and it is a **mirror, not an
extension**:

- **External connected:** the framebuffer is the external's native
  resolution, the external is primary and shows all of it, and the internal
  panel mirrors the **top-left crop** of it at the internal's own native
  mode. Both outputs share the origin; the larger framebuffer is what makes
  the internal a crop rather than a scaled copy. So it is a true mirror at
  the *external's* resolution, with the smaller laptop panel cropped -- not
  a common-resolution mirror (which would letterbox or soften the external)
  and not side-by-side extend.
- **External disconnected:** fall back to the laptop's native resolution.

The live recovery that realises the connected half, runtime-only and left
behind by nothing, is the shape an implementation reproduces:

    xrandr --output <ext> --mode <ext-native> --pos 0x0 --primary \
           --output <int> --mode <int-native> --pos 0x0

**Recorded as the holder's preference, not as "what other desktops do."**
The holder stated mirror is the common default; measured against the live
ones it is the other way -- GNOME, Plasma, macOS and Windows default a
docked laptop to extend and offer mirror as a toggle. That does not change
the decision, which is the holder's to make for TDE; it is noted so a future
implementer does not "correct" the policy to extend believing that is the
saner default. The policy to build is mirror-crop as above.

This sharpens the open feature rather than closing it: the daemon that owns
display policy across RandR events now has a concrete rule to apply on
connect and on disconnect. What remains unbuildable-here is unchanged --
the switching only exercises on a real connect/disconnect and across a
reboot with the external present, which is the wall finding 8 opens with.

**What was NOT done, deliberately:** no `autorandr` install, no
`/etc/trinity/tdm/Xsetup` edit, no persisted `xrandr` -- those fix one
machine, and the instruction was to fix TDE. The live `xrandr` used while
diagnosing is runtime-only and leaves nothing behind.

### 9. TDE reports this laptop as a desktop, hiding the lid settings

Found while making the docked policy configurable: the two new checkboxes,
and the pre-existing "Lock screen on lid close", were absent from the
configure dialog on this machine. Not a build problem -- they were
compiled in and rendered fine in a standalone preview of the dialog. The
`ConfigureDialog` subclass hides all three whenever `hwinfo->isLaptop()`
is false, and it is false here.

Measured, not inferred. `isLaptop()` is TDE's hardware layer reporting
`TDERootSystemDevice::formFactor()`, and a probe linked against `tdehw`
returns **`formFactor=1` (Desktop)** on a Dell Latitude 5430 whose DMI
chassis type is **10 (Notebook)** -- so the layer does not map that
chassis type to Laptop. The same probe finds **one `ACPILidSwitch`
device**, so the lid is plainly there; TDE just does not call the machine
a laptop.

That the checkbox was hidden all along is how the machine came to lock on
lid close with no visible setting for it: the daemon acts on lid events
regardless of the dialog, so the behaviour was reachable while its control
was not.

**Fixed in tdepowersave by asking the right question.** The dialog now
gates the lid options on whether a lid switch exists (`hasLid()`, recorded
from the ACPI lid device tdepowersave already connects to) rather than on
the form factor. `+lidfix5`. This restores the stock "Lock screen on lid
close" checkbox too, not only the new ones.

**The root cause is one layer down and is not fixed here.** The chassis-10
gap belongs to tdelibs' `TDERootSystemDevice::formFactor()`, and anything
else keying UI on `isLaptop()` inherits it. That is a separate tdelibs
report, not made yet, and it is a different tracker from tdebase and from
tdepowersave.

The process lesson is finding 4's, sharpened: the first "it is definitely
there" rested on a standalone render of the uic **base** dialog, which
does not run the subclass's `hide()`, so it could not see the very bug the
subclass introduced. The reboot that changed nothing was the tell that the
verified artifact was the wrong one. What settled it was measuring the
predicate -- `formFactor` and the lid-switch count -- on the real
hardware.

### 10. tdepowersave carries a netcfgd profile per power scheme

A feature rather than a fix, and the first cross-tool tie in this tree:
a power scheme can name a netcfgd profile to switch to when it activates,
so a battery scheme can trim the network. netcfgd owns what the profile
does; tdepowersave only names which profile goes with which scheme.

**Detection, not linking, which is the point.** Nothing here links
netcfgd. `TDEGlobal::dirs()->findExe("ncfg")` decides whether the feature
exists at all; `ncfg profile list` fills the combo and `ncfg profile set`
switches -- the same shell-out shape the panel-off code uses for xrandr.
The Networking page in the per-scheme toolbox is shown only when ncfg is
found and removed otherwise. The selection is stored by profile name, not
combo index, so it survives the list changing and an unknown name falls
back to not switching. Switching is silent (schemes flip on every
AC/battery change; a popup each time would be noise) and a failure is a
text line on the page, cleared on the next success. `ncfg profile set`
runs without a shell so a configured name cannot be interpreted.

**It is its own upstream pull request, not the lid's.** It shares the lid
branches locally, but it touches the scheme path and the netcfgd
relationship, not the lid, and the commit says to extract it before
submitting. It respects netcfgd's one-way rule: netcfgd needs no change,
its CLI already exposes profiles. Built into `+lidfix8`.

### 11. A tray toggle to temporarily inhibit power management

Asked for late: an easy way to tell tdepowersave to stop suspending,
dimming and locking for a while. It is a checkable tray item, "Do Not
Suspend or Lock the Screen", gating at the action points -- the inactivity
suspend and dim, and the lid-close branch -- rather than stopping timers,
so the paths that would act just return. Manual suspend/hibernate and the
power buttons still work (it inhibits the automatic responses, not the
machine), and a critical battery is left to act. Runtime only, so
"temporary" is until it is switched off or the session ends, which is the
semantics the word asks for. A passive popup confirms each toggle -- a
deliberate click, unlike the per-scheme switches that fire on every
AC/battery change and are silent. `+lidfix9`. Its own upstream PR, sharing
the lid branches only locally, like findings 10 and this one's siblings.

## Open: tdelauncher lost its socket once, cause unknown

2026-09-15, eight days into a session. Every attempt to LAUNCH something
-- a menu entry, a file association, `tdecmshell` -- reported "TDELauncher
cannot be reached by DCOP", while programs that fork directly were
unaffected, which made it look intermittent.

Measured rather than inferred:

    connect /tmp/tdesocket-nabbe/tdeinit__0   ECONNREFUSED
    connect /tmp/tdesocket-nabbe/tdeinit-:0   ECONNREFUSED
    dcop | grep -c tdelauncher                0

So the message was literally true. The odd half is that `tdelauncher` pid
1808 was still in the process table, running since the session began on
2026-09-06: the process lived and its door was gone. Both socket files had
been bound at **17:44:54.893229420**, the same nanosecond, by a tdeinit
that had since exited -- leaving dead sockets at the path every launch
consults.

**What bound them was never established.** No user process started
anywhere near 17:44 (`ps -eo pid,lstart` shows only kernel workers), and
`.xsession-errors` holds nothing from that minute. Two headless
`tdecmshell` runs earlier the same afternoon are a candidate that cannot
be fully excluded -- the second used the real `TDEHOME` where the first
used a throwaway one -- but they ran on a separate Xvfb display two hours
before, and the dead sockets are `:0`'s.

Repaired in place with `tdeinit --no-kded`, `--no-kded` because kded was
still registered and healthy and a second one would have been a new fault.
Both sockets answered afterwards and the launcher re-registered. It left
the two orphaned tdelaunchers from 09-06 and 09-07 in the table, inert.

**If it recurs, capture this before restarting anything** -- the socket's
mtime pins the event to whatever was happening at that moment, which is
the one thing missing here, the trail having been two hours cold:

    stat -c%y /tmp/tdesocket-nabbe/tdeinit__0
    dcop | grep -c tdelauncher

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

### A defect found in it, before it was ever installed

`runXrandr()`'s return value was **ignored at all five call sites**. The
important one: if `xrandr` could not be run, `disableInternalPanel()`
carried on, found `enabledOutputCount()` still at 2 so the "did anything
survive" check passed, and set `m_panelDisabled = true` -- **recording the
panel as switched off when nothing had touched it.** The lid-open path
would then reconfigure a panel that had never been disabled.

All five are checked now, and each failure says how to recover by hand:

- the `--off` call returns without recording anything;
- the rollback and the restore log at error level with the exact
  `xrandr --output NAME --auto` needed, because those two are the paths
  that end with a display nobody can see;
- and success is no longer taken on trust: `internalPanelIsOff()` confirms
  the panel actually went dark, since xrandr exiting zero is not evidence
  that it did anything.

**A branch mix-up went with it.** The corrections were made while the
checkout sat on the r14.1.x branch, so for a while `master` carried the
uncorrected version and the stable branch the fixed one -- the reverse of
the workflow. Caught by the two diffstats disagreeing, 461 against 504,
which is exactly what that comparison is kept for. Master was rebuilt from
the corrected branch and both are 504 again.

### What is and is not tested

`test/docked-detect/` exercises every read-only helper against the real
build. Measured on the docked machine and on a nested server with no panel:

                                  real (docked)   nested (no panel)
    internalPanelOutput()         true (eDP-1)    false
    enabledOutputCount()          2               1
    internalPanelIsOff()          false           false

The nested case is the one worth having: **both refusal conditions hold at
once**, so the fail-closed behaviour is observed rather than asserted.

All three state-changing entry points are exercised on a nested server,
where they are guaranteed to refuse, and the refusal is checked by
observing that the enabled-output count did not move:

    disableInternalPanel()   false, outputs 1 -> 1
    restoreInternalPanel()   false
    healInternalPanel()      false, outputs still 1

What that does **not** reach is the acting path: record, switch off,
verify, and the rollback when verification fails. Those want a real lid and
a real external display. So what is established is that the code compiles,
that the detection it gates on is right in both directions, and that every
guard refuses when it should -- not that switching off and back on works.

**Trace logging cannot help here and it is worth knowing why.** The build
defines `NDEBUG`, which compiles `kdDebug()` away, so `--dbg-trace`
produces nothing whatever and an empty log says nothing about whether a
code path ran. Two runs were spent on that before the cause was found.
Calling the functions directly from a probe is the route that works.

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

## Splitting display-off from lock and suspend on lid close -- IMPLEMENTED

**Written 2026-09-22** on `feat/lid-panel-off-r141x`, built as `+lidfix10`.
The holder's framing, verbatim: display-off, lock and suspend are "3
disparate things", and on lid close the display should at least switch off
its light, and switch off driving the internal panel too where that saves
power and is not risky.

The tangle was real. Both the inhibit gate and the docked-ignore path
`return`ed early doing nothing, so under a shut lid the internal panel
stayed lit in exactly the two modes a user reaches for when stowing the
machine. Upstream's `forceDpmsOffOnLidClose` did blank the display, but
only in the undocked lock path, and via `xset dpms force off` -- which is
**global**, so it could never be used docked without blanking the external
too.

The restructure makes powering the internal panel off its own step, run
**first and unconditionally** on lid close (session active), before the
inhibit gate and independent of lock, suspend and the docked policy. A shut
lid is never being looked at, so this is the one lid-close response that is
always wanted. `powerSaveInternalDisplay()` picks the mechanism and records
what it did so the lid-open path undoes exactly that:

- **docked** (an external display is driving): `disableInternalPanel()` --
  the internal output goes off entirely, light and drive both, external
  untouched. Restored by the unconditional `restoreInternalPanel()`.
- **alone** (the internal panel is the only display): `forceDPMSOff()` --
  a power state, not a configuration change, so no zero-display moment, and
  it restores on the next input event. Global DPMS is safe here precisely
  because there is no external to blank. Lid-open resets the scheme to undo
  the forced xset state.
- **light-only** (`lidDisplayLightOnly=true`): dim the backlight to nothing
  and change no display configuration or power state at all. The saved
  level is restored on lid-open.

### The setting the holder asked for

`lidDisplayLightOnly`, a `[General]` config key, default false. Set, it
forces the gentle backlight-only mechanism in every case; unset, the fuller
kill (disable the output docked, DPMS off alone). Its reason is the holder's
own: "some setups don't seem to be able to handle changes or zero displays",
so the safe path is one that reconfigures nothing and only darkens the
backlight.

It is surfaced (`+lidfix12`) as a checkbox in the lid-close button
configuration, "On lid close, switch off only the backlight, not the
display", on the Button Events page directly under the docked lid-action
option, with a tooltip stating the compatibility purpose. It is a permanent
per-machine setting, not a situational one, so it lives with the permanent
lid configuration and applies to every lid close for whatever reason: checked
means a lid close only dims the backlight and never touches the display;
unchecked, the display itself is switched off, which is the default. It loads
and saves in the general group beside the lock-mode combo and the docked
action, and is hidden when `hwinfo->hasLid()` is false, exactly as those two
are. `forceDpmsOffOnLidClose`, the master, remains config-file-only.

**A false start recorded so the reasoning is not lost.** `+lidfix11` put
this in the tray menu as a runtime toggle, on a misreading of "add the menu
entry". The holder's correction was that this is a compatibility setting for
setups that break on display reconfiguration -- permanent, set once, and
therefore belonging in the lid-button configuration, not a menu toggle you
flip situationally. The tray commit was unpushed and was dropped rather than
carried, since the branch is meant to read as a clean change.

### Settings consolidated

`forceDpmsOffOnLidClose` becomes the single master enable for all of the
above, default on -- the name is now historical (it does more than DPMS) but
kept so existing configs and an existing `=false` opt-out still read, and
its code default is raised from false to true to match the shipped rc and
the holder's "by default" want. `switchOffPanelOnLidClose` (mine, never
released) is retired, folded into the master; the startup panel-heal now
gates on the master too. The two stray `forceDPMSOff()` calls inside the
docked-lock and undocked-lock branches are gone -- the panel is handled once,
at the top, which also removes the docked case where the global DPMS call
would have blanked the external.

### What is and is not tested

Built and installed as `+lidfix10`. **Verified end to end 2026-10-02 on the
real two-display setup** (external DP-1 3440x1440 + internal eDP-1), across
physical lid cycles, before this machine was retired:

- **Docked display-off (`disableInternalPanel()`).** Lid open, both outputs
  live; lid close -> `eDP-1`'s RandR output disabled (no active mode, not
  merely backlight-dark), `DP-1` stayed at 3440x1440, nothing locked
  (`isBlanked` false) or suspended. Open -> `eDP-1` active again.
- **The attribution was proven, not assumed.** At boot with the lid shut the
  kernel brings `eDP-1` up disabled, so a lid-close output-disable could in
  principle be the kernel rather than our code. The `lidDisplayLightOnly`
  run settles it: with that set, lid close left `eDP-1`'s output **active**
  and dropped the backlight to 0 -- so the kernel does not disable the output
  on a lid event, and the disable in the default run was ours.
- **Light-only restore.** Lid open after the light-only close -> backlight
  climbed from 0 back to full (96000), exercising `m_savedLidBrightnessLevel`.

The `lidDisplayLightOnly` key was written for the test and removed after;
the machine was left at defaults.

## Portability: the lid handling without systemd

**Traced 2026-09-25 from the source**, prompted by the holder asking whether
the lid work carries to Devuan and other systemd-free desktops -- the
project's own premise, since this is the only systemd machine and it is
going away. Read as a set of dependencies rather than a yes/no, because the
pieces differ.

**No init system in it at all -- the mechanisms.** Panel-off is `xrandr`,
DPMS is `xset`, backlight is a `/sys/class/backlight` write through the TDE
hardware library. All X11 and kernel. And the lid event itself is read
directly from the kernel ACPI lid switch as a tdehwlib event device
(`TDEEventDeviceType::ACPILidSwitch`, `hardware.cpp` around 798), emitted as
`lidclosetStatus`. Nothing consults a login manager to know the lid closed.

**A session/seat service is needed -- but not specifically systemd.**
`handleLidEvent` gates its actions on `currentSessionIsActive()`, so it will
not blank a session that is not the active one. That check runs through
`dbusInterface`, which speaks **both** `org.freedesktop.login1` **and**
`org.freedesktop.ConsoleKit` and uses whichever registers on D-Bus
(`onServiceRegistered`, `checkActiveSession` at `dbusInterface.cpp:374`):

- **systemd** -> logind. This machine, tested.
- **elogind** (Artix, Gentoo, many Devuan setups) -> the same `login1` path,
  including the lid-switch inhibitor at `dbusInterface.cpp:298`.
- **ConsoleKit2** (classic Devuan) -> the ConsoleKit branch. Works, and takes
  no inhibitor -- which it does not need, because without logind nothing else
  is claiming the lid switch to fight over.
- **none of the three** -> `checkActiveSession()` returns false, the session
  reads as inactive, and the lid actions do not fire. The one configuration
  where the feature silently does nothing.

**Two things are true and worth keeping straight.** None of the display-off
work added any systemd coupling: the split and the checkbox sit inside the
existing session gate and inherit its portability exactly; the session/seat
dependency is upstream's and predates all of it. And the ConsoleKit path,
while present in the source, is **not measured** -- there is no ConsoleKit on
this box -- so "works on Devuan" is built-for, not observed. By the code it
should, given ConsoleKit2 or elogind running and the session registered,
which is the normal case; a real Devuan/ConsoleKit2 test is what turns
*should* into *does*, and is the obvious thing to do first on that machine.

**One distro-level caveat, not a code matter.** On a systemd-free box, make
sure nothing else -- an `acpid` lid script, another power manager -- is also
handling the lid, the same as anywhere. And the backlight write needs the
session to own `/sys/class/backlight` (a udev/ACL grant or the `video`
group); logind arranges it on seats, ConsoleKit setups usually via a udev
rule. If that permission is missing the backlight will not move while
everything else does.

## The autosuspend countdown ignores the user returning -- FIXED

**Fixed 2026-09-29** on `feat/lid-panel-off-r141x` (built and confirmed by
the holder 2026-09-30), the master twin carrying the same change. Reported
as: the machine suspends after the screen is woken by a mouse move, with a
countdown window that demands the Cancel button or it suspends anyway.

The inactivity monitor fires `inactivityTimeExpired` and then stops -- the
10-second check does not rearm after emitting. `do_autosuspendWarn` shows the
countdown, and from there nothing watches the X idle time, so moving the
mouse or pressing a key does not reach the countdown at all. The only way to
stop it was the Cancel button, which is precisely what someone is not
reaching for in the second after their screen lights up.

`autodimm` had already solved "the user is active again": a 1-second poll
(`startCheckForActivity` / `pollActivity`) that emits `UserIsActiveAgain`
when the idle time drops, used to re-brighten the display. That poll moved
**down into the shared `inactivity` base class**, so `autosuspend` -- until
now an empty subclass -- gets it for free; `autodimm` is unchanged in
behaviour, just relocated. `do_autosuspendWarn` now calls
`startCheckForActivity()` after showing the dialog, and `UserIsActiveAgain`
is wired to close the countdown. Because the dialog is `WDestructiveClose`,
closing it with time remaining emits `dialogClosed(true)`, which routes
through the existing `do_autosuspend(true)` cancel path -- stop, do not
suspend, restart monitoring -- exactly as the Cancel button does. The
`countdown` pointer is nulled there so a late activity poll cannot close a
dialog that has already gone.

Its own upstream PR, independent of the lid work it happens to share a
branch with; it wants extracting to a clean
`fix/autosuspend-cancel-on-activity` branch before submission.

## GTK applications opening a folder get Cervisia -- FIXED

**Fixed 2026-09-08** on `fix/directory-mime-default` (master) and
`fix/directory-mime-default-r141x` (stable). Verified end to end. Not
submitted upstream.

Anything outside TDE asking to open a folder -- `xdg-open`, `gio`, which is
what GTK programs use for "show in folder" -- got Cervisia, which then
reported that the folder is not a CVS folder.

**Nothing chose Cervisia.** With no default recorded for a type, the choice
falls to whatever sorts first in `mimeinfo.cache` among the desktop files
claiming it:

    inode/directory=tde-cervisia.desktop;tde-kfmclient_dir.desktop;

`cervisia` sorts before `kfmclient`. That is the entire mechanism. The
literal `%c` in the window title is the same leak from the other side: the
`Exec` line reads `cervisia -caption "%c" ...`, a TDE field code that the
non-TDE launcher passed through instead of expanding.

**The obvious fix is wrong.** Cervisia's `MimeType=inode/directory` looks
like a mistake for a CVS front-end, but Cervisia registers no service file
of its own -- checked -- so that line *is* how its KPart is registered, and
deleting it would take the CVS view out of Konqueror. Only three TDE
desktop files declare both a KPart service type and a MimeType, and the
other two, kaddressbook and kpovmodeler, are genuine applications claiming
types they really handle. Cervisia is the only one masquerading.

So the fix names the file manager rather than touching Cervisia: a
`tde-mimeapps.list` shipped by konqueror. The `tde-` prefix is what makes
it apply only when `XDG_CURRENT_DESKTOP` names TDE, leaving a machine
running another desktop alone. It installs into `applications/` rather than
`XDG_APPS_INSTALL_DIR`, which is `applications/tde` -- the specification
looks for the list beside the application directories, not inside them.

Verified by building into a staging prefix and putting it ahead in
`XDG_DATA_DIRS`, with a config home of its own so no user setting could
answer instead:

    with the staged tree     tde-kfmclient_dir.desktop
    without it               tde-cervisia.desktop

**On this machine**, the same result was reached immediately by adding one
line to `~/.config/mimeapps.list` under `[Default Applications]`; the
previous file is kept at `~/.config/mimeapps.list.before-tde-fix`. That is
a local override and is independent of the packaged fix.

## Deploying the fixes on this machine

Built as Debian packages rather than copied binaries, so the package
manager keeps track. Local versions carry a `+lockfix2` (tdebase) / `+lidfix3`
(tdepowersave) suffix, which sorts above the repository's `+0` -- so apt will not silently
undo them, and a genuine 14.1.7 from upstream will supersede them when it
appears.

Built from `scratch/pkg2/`, patched from the `r14.1.x` branches. Three
packages carry the fixes:

    tdepowersave-trinity   +lidfix9    the docked lid: configurable lock and
                                   action when docked, lid options shown by
                                   lid presence not form factor, panel switch
    kdesktop-trinity       +lockfix2   the control FIFO and the resize loop
    tdm-trinity            +lockfix2   the session class

### Installing those three would have removed nine

**apt answered the three-package form by proposing to remove nine other
packages**, konqueror and the `tde-trinity` metapackages among them. The
cause is that a Debian source package's binaries pin each other by exact
version, and five of tdebase's thirty-two installed outputs do:

    $ dpkg-query -W -f='${Depends}' konqueror-trinity
    ... kcontrol-trinity (= 4:14.1.6-0debian13.0.0+0+lockfix2) ...

A locally-built kcontrol therefore leaves the archive's konqueror with a
dependency nothing satisfies, and apt's answer to that is removal. The
count is re-derivable with

    for p in $(dpkg-query -W -f='${Package} ${Version}\n' \
                   | awk '/\+(lock|lid)fix2/{print $1}'); do
            dpkg-query -W -f='${Depends}' "$p" | grep -q '(= 4:14\.1\.6' \
                    && echo "$p"
    done

The answer is the closure: install the locally-built version of every
binary from that source **that is already installed**.
`tool/make-install-list.sh` computes it from dpkg and the built directory,
rather than from a list somebody keeps by hand:

    tool/make-install-list.sh scratch/pkg2 +lockfix2 +lidfix2
    cd scratch/pkg2 && sudo apt install $(cat install-list.txt)

It writes `install-list.txt` and **exits non-zero naming any package that
is installed but was not built**, which is the case that would otherwise
reintroduce the removals quietly. It matches `_all.deb` as well as
`_amd64.deb`: three of tdebase's outputs are `Architecture: all`, and a
glob for one architecture drops them without saying so.

So konqueror, konsole and kicker are rebuilt and replaced after all. That
is out of proportion to two bug fixes and it is not a choice -- it is what
keeping the versions in step costs.

### What is installed

Thirty-two packages, measured rather than remembered:

    dpkg-query -W -f='${Package} ${Version}\n' | grep -E '\+(lock|lid)fix'

31 at `+lockfix2` and `tdepowersave-trinity` at `+lidfix9`.

**The reboot is done -- 2026-09-17; what it showed is at the foot of
this section.** The baseline below was taken first so the run afterwards
would mean something. Measured 2026-09-15: installed 2026-09-07 15:43, machine last booted
2026-09-06 21:52 and up since. What was confirmed in production on the 6th
is fix set **1**, installed at 21:46 and booted into six minutes later. So
a reboot exercises, for the first time at boot, kdesktop_lock's resize
bound, a tdm binary that has never started a session, and tdepowersave
with the panel-off machinery compiled in.

`switchOffPanelOnLidClose` is unset in `~/.trinity/share/config/
tdepowersaverc`, so the compiled default of false applies and the acting
path stays untested -- `ignoreLidCloseWhenDocked` is likewise unset and
defaults true, so the docked behaviour is live. Turning the panel switch
on deserves its own reboot rather than riding along with this one.

#### The baseline, taken 2026-09-16 before the reboot

So that the run afterwards means something. Method: `tool/verify-fixes.sh`,
`loginctl show-session c1`, and `grep -ac` on the session log -- `-a`
because ugrep skips a file it decides is binary and this one is 14 MB of
eight days.

    verify-fixes.sh                pass=4 fail=0 unknown=0
    session c1                     Class=user CanLock=yes Type=x11
    control FIFOs                  2, both dated 09-06 21:58
    'unable to create control socket'  0 in this session's log
    BadWindow in .xsession-errors  1037, over 8 days and 14358672 bytes
    outputs connected              eDP-1 and DP-1

The running binaries are **fix set 1** -- installed 09-06 21:46, six
minutes before that boot -- while the disk holds set 2. That is what the
reboot changes.

**And the verifier cannot tell the two sets apart, which is the thing to
know before reading its output.** It checks the session class, the FIFOs
and a string in the tdepowersave binary, and all three are set 1's work;
it answered `pass=4` before the reboot and will answer `pass=4` after,
whatever set 2 does. A green run afterwards therefore says set 1 still
holds and says nothing about the resize bound.

**What does exercise set 2 is locking the screen and then changing the
display topology** -- plug or unplug the USB-C display with the screen
locked. That is the path `kdesktop_lock`'s resize retry bounds, and it is
also the USB-C hang's own reproduction, so the two tests are one act. DP-1
was connected when this baseline was taken, so the topology can be changed
in either direction.

#### After the reboot (2026-09-17)

Booted 17:06 into fix set 2 as it then stood (`+lockfix2`, `+lidfix2`);
tdepowersave went to `+lidfix3` later the same day, after the defect below
surfaced. A text console was confirmed first; graphical login came up and
nothing failed to start.

`verify-fixes.sh` was not the instrument that mattered, for the reason
given above -- it reports on set 1's work, which held. What the reboot
actually surfaced was two things it could not see: the display arrangement
reset to the driver default (finding 8), and docked lid-close still locked
(finding 4's lock-path defect), which `+lidfix3` then fixed and the
copyright holder confirmed.

**The kdesktop resize bound (`+lockfix2`) is still unconfirmed at boot.**
It needs a lock followed by a display-topology change, and its give-up
warnings have not appeared in the session log this boot. It is the one
part of set 2 not yet exercised.

### The risk, and the way back

**tdm is the display manager.** If a broken one is installed there is no
graphical login at next boot. **Confirm a text console works before
rebooting** -- Ctrl+Alt+F2, log in there -- because that is the recovery
path, and finding out it does not work after the reboot is the bad order
to learn it in.

**kdesktop_lock guards the locked screen.** A broken one means a lock that
cannot be dismissed. Same recovery: a text console, then
`pkill kdesktop_lock`.

**The revert this section used to give does not work**, and a recovery
path that fails is read at the worst possible moment. It was

    sudo apt install --reinstall tdm-trinity kdesktop-trinity tdepowersave-trinity

on the reasoning that `--reinstall` names the archive version rather than
the locally-built one. It does not. Simulated against the machine as it
stands:

    Reinstallation of tdm-trinity is not possible, it cannot be downloaded.
    Reinstallation of kdesktop-trinity is not possible, it cannot be downloaded.
    Reinstallation of tdepowersave-trinity is not possible, it cannot be downloaded.

`--reinstall` fetches the version that is *installed*, and `+lockfix2` is
in no repository. It also named three packages, which is the same mistake
as installing three.

What does work names the archive version explicitly and downgrades the
whole set, deriving it from what is installed rather than from a list:

    list=$(dpkg-query -W -f='${Package}\t${Version}\n' \
               | awk '/\+(lock|lid)fix2/{sub(/\+(lock|lid)fix2$/,"",$2);
                                         print $1"="$2}')
    sudo apt install --allow-downgrades $list

Simulated with `apt-get -s`, which needs no privilege: **32 downgraded, 0
to remove.** The archive version is reachable -- `apt-cache policy
tdm-trinity` shows `4:14.1.6-0debian13.0.0+0` at priority 500 from
`mirror.ppa.trinitydesktop.org` -- so the way back does not depend on
anything in this tree surviving.

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

### Verification state, 2026-09-18

The tdepowersave work stands at `+lidfix14` (installed) and the tdebase
work at `+lockfix2`, installed. What is confirmed, and what is only built:

**Confirmed by running it:** the FIFO and session-class fixes, in
production since 2026-09-06; docked lid-close no longer locking
(`+lidfix3`); the lid settings being visible in the dialog
(`+lidfix5`) plus every dialog since -- the 3-state lock combo, the
reordered Button Events, the per-scheme Networking page -- by rendering
the actual generated dialog headlessly; and, on `+lidfix10`, the
display-off split's **alone** path in inhibit mode -- with the inhibit
toggle on, closing the lid on the single display now powers the panel off
(DPMS) where before inhibit skipped it and it stayed lit, and the machine
stays awake. Confirmed by the holder 2026-09-24. Two more confirmed by the
holder since: the `lidDisplayLightOnly` backlight-only checkbox
(`+lidfix12`/`+lidfix13`, once its Apply signal was wired), ticking it and
closing the lid dims the backlight without reconfiguring the display; and
the autosuspend countdown now cancelling when the mouse moves (`+lidfix14`,
confirmed 2026-09-30), where before it demanded the Cancel button; and
finally, on a two-display setup 2026-10-02, the **docked display-off** path
-- lid close disables the internal output while the external stays lit, with
no lock or suspend, the disable proven ours rather than the kernel's, and
the light-only backlight restore working (see *What is and is not tested*
under the display-off section for the method).

**Built and wired, not yet exercised live**, all single-display testable:
the inhibit toggle skipping the idle suspend/dim and the lid-close
(finding 11); the lock-on-lid combo mapping to behaviour on a non-docked
machine; the netcfgd profile firing on a scheme switch (finding 10) --
set a scheme's profile to `offline`, switch to it, and `ncfg profile get`
should read `offline` where it now reads `no profile chosen`.

**Needs an external display, so unverified:** anything under finding 8 (the
automatic mirror-crop policy, which is unbuilt). The docked display-off path
that was here is now verified -- see above.

`verify-fixes.sh` checks only the original three fixes; the combo,
`hasLid`, the netcfgd page and the inhibit toggle are verified as above,
not by that tool.

## Open questions

- Whether the tdepowersave **lock layer** is patched or replaced. Findings
  4 and 5 are defensible upstream fixes; swapping DCOP for logind is the
  opinionated change that may not be welcome upstream, and it is the one
  decision that could turn this from a patch set into a fork.
- Whether the greeter-class fix belongs in `doPAMAuth()` or in tdm's
  separation of greeter and user PAM handles. The one-line form is obvious;
  whether it is right has not been established.

## Corrected readings, kept so they are not repeated

- **A clean build failing on `tdeprocess.h` / `tdeApp` does not mean the
  TDE install changed.** It means the checkout is on a `master`-based
  branch. Upstream `master` modernised these names to the `tde*` spelling;
  the `r14.1.x` line this machine's R14.1.6 matches kept the `k*` spelling
  (`kprocess.h`, `kglobalaccel.h`, `kuniqueapplication.h`, `kapp`,
  `KUniqueApplication`). A `feat/*-r141x` branch builds cleanly here; its
  `feat/*` twin does not, and that is the branch giveaway, not an
  environment fault. Confirmed 2026-09-30 after an hour spent "adapting"
  the source before noticing the wrong branch was checked out.
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
