# Patch series

Off-machine backup of the feature branches that otherwise live only in the
local upstream clones. Those clones are gitignored here, and their only
remote is TDE's own Gitea, which we cannot push feature branches to -- so
until a fork exists on `mirror.git.trinitydesktop.org`, these patches are
the only copy of the code that leaves this machine. Committing them here
means a push of this repository preserves the work.

They are a **snapshot**, exported with `git format-patch`. When a branch
changes, re-export it rather than editing the patches by hand.

## What is here

    tdepowersave/feat-lid-panel-off-r141x/   the stable series (r14.1.x)
    tdepowersave/feat-lid-panel-off/         the master twin

    tdebase/fix-lock-fifo-per-user{,-r141x}/     the lock control FIFOs
    tdebase/fix-tdm-session-class{,-r141x}/      the greeter/user session class
    tdebase/fix-lock-resize-retry{,-r141x}/      the locker resize loop bound
    tdebase/fix-directory-mime-default{,-r141x}/ folders open in the file manager

Each tdebase branch is a single commit, exported for both the master and
the r14.1.x line. As with tdepowersave, the r141x side is the one built and
installed here.

Both are the same twelve commits -- the docked lid policy, the form-factor
(`hasLid`) fix, the lock-mode combo, the per-scheme netcfgd profile, the
inhibit toggle, the panel-off mechanism, and the display-off split with its
backlight-only checkbox. The **r141x series is the authoritative one**: it
is what was built into the installed `+lidfix` packages and tested on the
live desktop. The master twin was produced by cherry-pick and is
content-identical (`git range-diff` agrees) but is **not build-verified**,
because master does not build on this machine.

The panel-off branch is stacked on the docked branch, so this series
already contains every commit of `feat/lid-docked`; there is no separate
export for it.

## Re-exporting

    cd <tdepowersave clone>
    git format-patch -12 --zero-commit --no-signature \
        -o <this>/tdepowersave/feat-lid-panel-off-r141x feat/lid-panel-off-r141x

## Applying

    cd <a fresh r14.1.6 tdepowersave clone>
    git checkout -b feat/lid-panel-off-r141x r14.1.6
    git am <this>/tdepowersave/feat-lid-panel-off-r141x/*.patch

## Before these go upstream

Each commit needs a `Signed-off-by:` (TDE carries the DCO); that line is the
author's to add and is not in the patches. See `../pr-descriptions.md`.
