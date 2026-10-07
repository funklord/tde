# This project's product is patches and notes, so there is nothing to
# compile and no BUILD_DIR. The targets are the settled shared ones plus
# `upstream`, which fetches the TDE trees the patches are written against.

GITEA  = https://mirror.git.trinitydesktop.org/gitea/TDE
CLONES = tdebase tdepowersave

.PHONY: help upstream style style-source style-docs hooks

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

style: style-source style-docs

style-source:
	python3 tool/style_gate.py check

# project.md is authoritative, so it is held to the tree: a heading that
# appears twice means whichever one you find, the other is the one with
# the answer. Added 2026-10-07; it reports one finding today, which is
# the first open question in project.md and is deliberately left for
# this tree to answer rather than silenced here.
style-docs:
	python3 tool/style_gate.py docs

hooks:
	@for h in tool/hooks/*; do \
		install -m 755 "$$h" ".git/hooks/$$(basename $$h)" && \
		echo "installed $$(basename $$h)"; \
	done
