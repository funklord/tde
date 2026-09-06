# This project's product is patches and notes, so there is nothing to
# compile and no BUILD_DIR. The targets are the settled shared ones plus
# `upstream`, which fetches the TDE trees the patches are written against.

GITEA  = https://mirror.git.trinitydesktop.org/gitea/TDE
CLONES = tdebase tdepowersave

.PHONY: help upstream style hooks

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

style:
	python3 tool/style_gate.py check

hooks:
	@for h in tool/hooks/*; do \
		install -m 755 "$$h" ".git/hooks/$$(basename $$h)" && \
		echo "installed $$(basename $$h)"; \
	done
