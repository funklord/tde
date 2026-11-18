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

.PHONY: test driver clean FORCE

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

test: driver $(OUT)/shim.so
		@echo "TDELIBS $(TDELIBS): $$(git -C $(TDELIBS) rev-parse --abbrev-ref HEAD)"
		timeout 120 ./harness.sh stock
		SHIM=$(CURDIR)/$(OUT)/shim.so timeout 120 ./harness.sh patched

clean:
		rm -rf $(OUT)

FORCE:
