# Point LIBKONQ at the directory holding the libkonq.so.4 under test; the
# installed one is the control. Each run ends its own processes; see
# harness.sh for the two X files left to remove by name.
LIBKONQ ?= /opt/trinity/lib

.PHONY: test clean

xds_source: xds_source.c
		$(CC) -Os -Wall -Wextra -o $@ xds_source.c -lX11

test: xds_source
		timeout 120 ./harness.sh $(LIBKONQ) run

clean:
		rm -f xds_source
		rm -rf out
