# The installed tdeinit_displayconfig is the control; SHIM preloads a
# patched KRandrSimpleAPI::applyHotplugRules over the installed libtderandr.
# `driver` and `shim` fetch two small packages into out/ (no root, nothing
# installed). TDELIBS is the clone whose libtderandr.cpp is under test.
TDELIBS ?= ../../tdelibs
OUT      = out
GEN      = $(OUT)/gen
INCS     = -I$(GEN) -I$(TDELIBS)/tderandr -I$(TDELIBS)/tdecore -I$(TDELIBS)/tdeui \
           -I$(TDELIBS)/dcop -I$(TDELIBS)/tdeio/tdeio -I$(OUT)/root/usr/include/tqt3

.PHONY: test driver clean

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

# The one function, cut out of the source under test.
$(OUT)/shim.cpp: $(TDELIBS)/tderandr/libtderandr.cpp
		mkdir -p $(OUT)
		{ echo '#include "libtderandr.h"'; \
		  sed -n '/^void KRandrSimpleAPI::applyHotplugRules/,/^}/p' $<; } > $@

$(GEN)/tdemacros.h: $(TDELIBS)/tdecore/tdemacros.h.cmake
		mkdir -p $(GEN)
		sed -e 's/^#cmakedefine __TDE_HAVE_GCC_VISIBILITY.*/#define __TDE_HAVE_GCC_VISIBILITY 1/' \
		    -e 's/#cmakedefine/#undef/' -e 's/@[A-Z_]*@//g' $< > $@

$(OUT)/shim.so: $(OUT)/shim.cpp $(GEN)/tdemacros.h $(OUT)/root/usr/include/tqt3/tqstring.h
		$(CXX) -Os -fPIC -shared -o $@ $(OUT)/shim.cpp $(INCS) -DTQT_THREAD_SUPPORT \
		    /opt/trinity/lib/libtderandr.so.0

test: driver $(OUT)/shim.so
		timeout 120 ./harness.sh stock
		SHIM=$(CURDIR)/$(OUT)/shim.so timeout 120 ./harness.sh patched

clean:
		rm -rf $(OUT)
