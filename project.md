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

### 1. kdesktop_lock cannot create its control socket

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

### 2. tdm registers the user's session as a greeter

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

### 4. The lid inhibitor defeats logind's docked handling

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

## Open: the USB-C display hang

Reported by the copyright holder: an occasional hang when a USB-C display
is connected or disconnected **while the lid is closed**; having a visible
screen appears to mitigate it. Culprit unknown.

**Not reproduced, and no mechanism is claimed.** Finding 5 is a candidate
-- a hotplug device storm queueing brightness re-enumerations while DPMS
has been forced off and a lock attempt is in flight -- and "a visible
screen mitigates it" fits, because an open lid means neither
`forceDPMSOff()` nor a lock attempt. It fits several other stories equally
well. Non-reproduction is what "intermittent" means, so an absence of
symptoms during testing settles nothing.

Next step is instrumentation, not reasoning: timestamped RandR events,
tdehw device events, lid state, DPMS state and lock attempts, size-capped.

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
