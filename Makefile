# This project's product is patches and notes, so there is nothing to
# compile and no BUILD_DIR. The targets are the settled shared ones plus
# `upstream`, which fetches the TDE trees the patches are written against.

GITEA  = https://mirror.git.trinitydesktop.org/gitea/TDE
CLONES = tdebase tdepowersave tdelibs

.PHONY: help upstream style style-source style-tool style-docs hooks

help:
	@echo 'upstream  clone or fetch the TDE trees named in CLONES'
	@echo "style     run the shared gate over this project's own files"
	@echo 'hooks     install tool/hooks/ into .git/hooks'

# Clone what is missing, fetch what is present. Never checks anything out
# and never resets: a clone may hold work in progress, and this target has
# no business discarding it.
upstream:
	@for r in $(CLONES); do \
		if [ -d "$$r/.git" ]; then \
			echo "fetch  $$r"; git -C "$$r" fetch --all --tags --prune; \
		else \
			echo "clone  $$r"; git clone "$(GITEA)/$$r.git" "$$r"; \
		fi; \
	done

style: style-tool style-source style-docs

# The style gate's own suite, run ahead of the gate's verdict. A checker
# that has stopped inspecting anything passes exactly as loudly as one
# that works, so its pass is worth reading only once its suite has.
# tool/test_style_gate.py arrives beside tool/style_gate.py and was
# carried here unrun until 2026-11-12, on the holder's word.
style-tool:
	python3 tool/test_style_gate.py

style-source:
	python3 tool/style_gate.py check

# project.md is authoritative, so it is held to the tree: a heading that
# appears twice means whichever one you find, the other is the one with
# the answer. Added 2026-10-07, when it reported one such pair; that
# was answered in project.md on 2026-11-12 rather than silenced here.
style-docs:
	python3 tool/style_gate.py docs

# Ask git where the hooks live: in a linked worktree or a submodule
# checkout .git is a file, and .git/hooks/ does not exist.
hooks:
	@if ! command -v git >/dev/null 2>&1; then \
		echo "hooks: git is not installed, so there is nowhere to install to." >&2; \
		exit 1; \
	fi; \
	dir=$$(git rev-parse --git-common-dir 2>/dev/null); \
	if [ -z "$$dir" ]; then \
		echo "hooks: not a git repository, so there is nowhere to install to." >&2; \
		exit 1; \
	fi; \
	set -e; \
	mkdir -p "$$dir/hooks"; \
	for h in tool/hooks/*; do \
		install -m 0755 "$$h" "$$dir/hooks/$$(basename $$h)"; \
		echo "hooks: $$(basename $$h) installed from tool/hooks/ into $$dir/hooks/"; \
	done
