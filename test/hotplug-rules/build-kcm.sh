#!/bin/bash
# build-kcm.sh TDEBASE TDELIBS -- build kcm_displayconfig from a tdebase
# clone as checked out, against the installed TDE libraries and headers
# taken from the tdelibs clone, into out/stage/lib/trinity, with a .la that
# makes TDE's loader prefer it when out/stage leads TDEDIRS. The DCOP
# skeleton is written by hand (displayconfig_skel.cpp): the module's k_dcop
# section is empty and dcopidl is not installed here. A fixed file list,
# no loops that spawn.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
S=$(cd "$1" && pwd)/kcontrol/displayconfig
L=$(cd "$2" && pwd)
OUT=$HERE/out
R=$OUT/root
K=$OUT/kcm
ST=$OUT/stage/lib/trinity
mkdir -p "$K/gen" "$ST"
cd "$K"

# Generated tdelibs headers this module reaches, reduced to what it needs.
sed -e 's/^#cmakedefine __TDE_HAVE_GCC_VISIBILITY.*/#define __TDE_HAVE_GCC_VISIBILITY 1/' \
    -e 's/^#cmakedefine __TDE_HAVE_TDEHWLIB.*/#define __TDE_HAVE_TDEHWLIB 1/' \
    -e 's/#cmakedefine/#undef/' -e 's/@[A-Z_]*@//g' "$L/tdecore/tdemacros.h.cmake" > gen/tdemacros.h
sed -e 's/#cmakedefine/#undef/' "$L/tdeio/kssl/ksslconfig.h.cmake" > gen/ksslconfig.h
printf '#define WITH_XRANDR 1\n#define WITH_TDEHWLIB 1\n' > gen/config.h
ln -sfn "$L/tderandr" gen/libtderandr

"$R/usr/bin/tquic" "$S/displayconfigbase.ui" -o displayconfigbase.h
"$R/usr/bin/tquic" -impl displayconfigbase.h "$S/displayconfigbase.ui" -o displayconfigbase.cpp
"$R/usr/bin/tqmoc" "$S/monitorworkspace.h" -o monitorworkspace.moc
"$R/usr/bin/tqmoc" "$S/displayconfig.h" -o displayconfig.moc
"$R/usr/bin/tqmoc" displayconfigbase.h -o displayconfigbase.moc.cpp

INC="-I$K -I$K/gen -I$S -I$L -I$L/tdecore -I$L/tdecore/tdehw -I$L/tdeui -I$L/tdeio
	-I$L/tdeio/tdeio -I$L/tdeio/tdefile -I$L/dcop -I$L/tdeutils -I$L/tdefx -I$L/tderandr
	-I$R/usr/include/tqt3 -DTQT_THREAD_SUPPORT -DHAVE_CONFIG_H -DWITH_XRANDR
	-DWITH_TDEHWLIB -DKDE_CONFDIR=\"/etc/trinity\""
for f in "$S/displayconfig.cpp" "$S/monitorworkspace.cpp" displayconfigbase.cpp \
	displayconfigbase.moc.cpp "$HERE/displayconfig_skel.cpp"; do
	g++ -c -fPIC -Os -Wall -Wno-unused-parameter $INC "$f" -o "$(basename "${f%.cpp}").o"
done

T=/opt/trinity/lib
g++ -shared -o "$ST/kcm_displayconfig.so" displayconfig.o monitorworkspace.o \
	displayconfigbase.o displayconfigbase.moc.o displayconfig_skel.o \
	$T/libtdeio.so.14 $T/libtdeutils.so.1 $T/libtderandr.so.0 $T/libtdehw.so.14 \
	$T/libtdeui.so.14 $T/libtdecore.so.14 $T/libDCOP.so.14 \
	$(ls /usr/lib/*/libtqt-mt.so.3 | head -1) -lXrandr -lX11
# TDE's loader reads the .la first and takes the directory from libdir.
sed "s|^libdir=.*|libdir='$ST'|" $T/trinity/kcm_displayconfig.la > "$ST/kcm_displayconfig.la"
echo "built $ST/kcm_displayconfig.so from $(git -C "$S" rev-parse --abbrev-ref HEAD)"
