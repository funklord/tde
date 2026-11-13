# tde

Trinity (TDE) carries on the KDE 3 desktop. It is fast, it is stable, and
people who have used it for twenty years can still work in it without
relearning anything. It also carries code that was written before logind,
RandR hotplug and laptop docks were normal. That old code fails in quiet
ways on today's hardware, and none of them crash: the screen locks itself
while a laptop sits closed in its dock with two monitors in use; the lock
screen has no working control channel; the login manager registers your
session as a greeter, so the system refuses to let you lock it; a laptop
is reported as a desktop, so its lid settings are hidden; files copied
over SFTP arrive dated 1 January 1970. Each of these tends to be blamed on
the person's own configuration rather than on the desktop.

This project finds such faults on a machine in daily use, measures each
one down to the line responsible, and fixes it **as patches to upstream
TDE** rather than as a fork. Every fix is written for TDE's development
line (`master`) and backported to the stable line (`r14.1.x`) that
distributions ship. It follows TDE's own code style and commit
conventions, so it can be reviewed and merged as it stands. The aim is
that the fixes land upstream and reach every TDE user, rather than living
in one person's packages.

## What it changes, compared with stock TDE

- **Docked laptops stay usable.** tdepowersave holds a logind inhibitor
  on the lid switch, which defeats logind's own
  `HandleLidSwitchDocked=ignore`. As a result, closing the lid on a
  docked laptop locks it or suspends it. With the patches, tdepowersave
  asks RandR whether an external display is connected and then follows
  the docked policy. Whether a docked lid close locks the screen, and
  whether it carries out the lid action, are now separate settings.
- **The internal panel switches off on lid close**, and its arrangement is
  restored when the lid opens. Switching the display off is a setting
  of its own, separate from locking and from suspending. Stock TDE
  does not handle RandR at all.
- **Screen locking works under logind.** tdm now sets the session class
  to `user` when it opens the session, so logind reports `CanLock=yes`.
  The lock screen's control FIFOs, which could not be created in the
  shared socket directory, now live in the user's own `0700` directory.
  A shared world-writable directory would have let any local user drive
  another user's lock screen and read the PIN they type. The locker's
  resize loop is bounded.
- **Laptops are recognised as laptops.** tdelibs works out the form
  factor from the SMBIOS chassis type, using systemd-hostnamed's
  grouping. Without this, a laptop is shown as a desktop and its lid
  settings stay hidden.
- **Smaller repairs**: an autosuspend countdown that ignored the user
  coming back; a tray toggle that suspends power management for a
  while; folders opened from GTK programs that went to Cervisia instead
  of the file manager; SFTP copies dated 1970; and `tdelfeditor`
  stripping `GNU_RELRO` from every binary it edits, fixed in libr.

**Where each one stands.** Every fix is listed with its evidence and its
test status in `project.md`, under *Confirmed findings*. The stable-line
tdepowersave and tdebase fixes have been built and run on a laptop in
daily use. The master tdepowersave series has been built, linked and
started against TDE 14.2. The other newer series have been compiled
against 14.2 headers but not run. Nothing has been merged upstream yet.

**Where upstream already has work in progress**, this project reuses it
rather than competing with it: TDE's open pull requests #779 and #47 are
built, tested and reviewed in `project.md`, and the series here are
checked against them. The patches do not depend on any distribution's
packaging or carry changes specific to one.

## Using the patches

    make upstream          # clone tdebase, tdepowersave, tdelibs, libr
    cd tdepowersave
    git checkout -b lid origin/r14.1.x
    git am ../patch/tdepowersave/feat-lid-panel-off-r141x/*.patch

`patch/README.md` lists every series, how the stacked tdepowersave series
splits into its five upstream pull requests, and how to re-export a
branch. `pr-descriptions.md` holds the text each pull request will be
sent with. A bare `make` lists the targets; there is no software of this
project's own to build.

## Copyright

Copyright (C) 2026 Nabeel Sowan <nabeel@vibes.se>

The patches change upstream TDE code, which keeps its own authors'
copyright and licence terms.
