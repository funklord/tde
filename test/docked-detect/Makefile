# Links the object the real tdepowersave build produced, so this cannot
# drift from the code it tests. Point BUILD at that build directory.
BUILD ?= ../../build/tps-dock
SRC   ?= ../../tdepowersave/src
OBJ    = $(BUILD)/src/CMakeFiles/tdeinit_tdepowersave-shared.dir/screen.cpp.o
INC    = $(shell grep -o '\-I[^ ]*' $(BUILD)/src/CMakeFiles/tdeinit_tdepowersave-shared.dir/flags.make | sort -u)
LIBS   = $(shell pkg-config --libs tqt-mt xrandr xext xtst xscrnsaver) \
         -L/opt/trinity/lib -ltdecore -ltdeui -lDCOP -lX11

.PHONY: test clean

probe: probe.cpp $(OBJ)
		$(CXX) -o $@ probe.cpp -DHAVE_CONFIG_H -I$(SRC) $(INC) $(OBJ) $(LIBS)

# Two cases that must disagree. A run where both answer the same has
# established nothing, whichever answer it is.
test: probe
		@echo "case 1: real display, laptop panel only (expect false)"
		@DISPLAY=:0 ./probe || true
		@echo "case 2: nested server, output not named like a panel (expect true)"
		@Xvfb :9 -screen 0 1024x768x24 >/dev/null 2>&1 & \
		 x=$$!; sleep 3; DISPLAY=:9 ./probe || true; kill $$x 2>/dev/null

clean:
		rm -f probe cc.log
