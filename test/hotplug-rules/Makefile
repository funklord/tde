# The installed tdeinit_displayconfig is the control; SHIM preloads
# libtderandr.cpp and lowlevel_randr.c from TDELIBS, as checked out, over
# the installed libtderandr, so `make test` tests whichever branch is out.
# `driver` and the shim fetch small packages into out/ (no root, nothing
# installed).
TDELIBS ?= ../../tdelibs
OUT      = out
GEN      = $(OUT)/gen
INCS     = -I$(GEN) -I$(TDELIBS)/tderandr -I$(TDELIBS)/tdecore -I$(TDELIBS)/tdeui \
           -I$(TDELIBS)/dcop -I$(TDELIBS)/tdeio/tdeio -I$(OUT)/root/usr/include/tqt3

.PHONY: test driver kcm mirror-ui clean FORCE

$(OUT)/root/usr/lib/xorg/modules/drivers/dummy_drv.so:
		mkdir -p $(OUT)/deb
		cd $(OUT)/deb && apt-get download xserver-xorg-video-dummy
		dpkg-deb -x $(OUT)/deb/xserver-xorg-video-dummy_*.deb $(OUT)/root

driver: $(OUT)/root/usr/lib/xorg/modules/drivers/dummy_drv.so

$(OUT)/root/usr/include/tqt3/tqstring.h:
		mkdir -p $(OUT)/deb
		cd $(OUT)/deb && apt-get download libtqt3-headers libtqt3-mt-dev
		dpkg-deb -x $(OUT)/deb/libtqt3-headers_*.deb $(OUT)/root
		dpkg-deb -x $(OUT)/deb/libtqt3-mt-dev_*.deb $(OUT)/root

$(GEN)/tdemacros.h: $(TDELIBS)/tdecore/tdemacros.h.cmake
		mkdir -p $(GEN)
		sed -e 's/^#cmakedefine __TDE_HAVE_GCC_VISIBILITY.*/#define __TDE_HAVE_GCC_VISIBILITY 1/' \
		    -e 's/#cmakedefine/#undef/' -e 's/@[A-Z_]*@//g' $< > $@

$(OUT)/lowlevel_randr.o: $(TDELIBS)/tderandr/lowlevel_randr.c $(GEN)/tdemacros.h
		$(CC) -Os -fPIC -c -o $@ $< -I$(GEN) -I$(TDELIBS)/tderandr -I$(TDELIBS)/tdecore

# Rebuilt every time: which branch the clone has out decides what is
# tested, and a switch can leave the file older than the shim.
$(OUT)/shim.so: $(OUT)/lowlevel_randr.o $(GEN)/tdemacros.h $(OUT)/root/usr/include/tqt3/tqstring.h FORCE
		$(CXX) -Os -fPIC -shared -o $@ $(TDELIBS)/tderandr/libtderandr.cpp \
		    $(OUT)/lowlevel_randr.o $(INCS) -DTQT_THREAD_SUPPORT -DWITH_XRANDR \
		    /opt/trinity/lib/libtderandr.so.0 -lXrandr -lX11

primary_probe: primary_probe.cpp $(GEN)/tdemacros.h $(OUT)/root/usr/include/tqt3/tqstring.h
		$(CXX) -Os -o $@ $< $(INCS) -I$(TDELIBS) -DTQT_THREAD_SUPPORT \
		    /opt/trinity/lib/libtderandr.so.0 /opt/trinity/lib/libtdecore.so.14 \
		    $(firstword $(wildcard /usr/lib/*/libtqt-mt.so.3))

test: driver $(OUT)/shim.so primary_probe
		@echo "TDELIBS $(TDELIBS): $$(git -C $(TDELIBS) rev-parse --abbrev-ref HEAD)"
		timeout 120 ./harness.sh stock
		SHIM=$(CURDIR)/$(OUT)/shim.so timeout 120 ./harness.sh patched

# The Displays module from TDEBASE as checked out; mirror-ui runs the four
# cases in README.md with the shim preloaded, so TDELIBS should carry the
# primary-output fix or the installed library reads the primary inverted.
TDEBASE ?= ../../tdebase

$(OUT)/root/usr/bin/tquic:
		mkdir -p $(OUT)/deb
		cd $(OUT)/deb && apt-get download tqt3-dev-tools
		dpkg-deb -x $(OUT)/deb/tqt3-dev-tools_*.deb $(OUT)/root

kcm: $(OUT)/root/usr/bin/tquic $(OUT)/root/usr/include/tqt3/tqstring.h FORCE
		./build-kcm.sh $(TDEBASE) $(TDELIBS)

mirror-ui: driver kcm $(OUT)/shim.so
		@echo "TDEBASE $(TDEBASE): $$(git -C $(TDEBASE) rev-parse --abbrev-ref HEAD)"
		KSHIM=$(CURDIR)/$(OUT)/shim.so START_MIRROR=1 timeout 120 ./mirror-ui.sh stock-keep
		STAGE=$(CURDIR)/$(OUT)/stage KSHIM=$(CURDIR)/$(OUT)/shim.so CLICK_MIRROR=1 timeout 120 ./mirror-ui.sh tick
		STAGE=$(CURDIR)/$(OUT)/stage KSHIM=$(CURDIR)/$(OUT)/shim.so START_MIRROR=1 timeout 120 ./mirror-ui.sh keep
		STAGE=$(CURDIR)/$(OUT)/stage KSHIM=$(CURDIR)/$(OUT)/shim.so START_MIRROR=1 CLICK_MIRROR=1 timeout 120 ./mirror-ui.sh untick

clean:
		rm -f primary_probe
		rm -rf $(OUT)

FORCE:
