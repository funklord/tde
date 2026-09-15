#!/bin/bash
#
# Write the list of locally-built packages to install, for a source package
# whose binaries carry a version suffix.
#
# The point is the closure. A Debian source package's outputs pin each other
# by exact version, so installing a few of them makes apt remove every
# sibling that still pins the old one -- which it will do silently if asked
# the wrong way. Installing the locally-built version of every binary from
# that source that is ALREADY INSTALLED keeps versions in step and removes
# nothing.
#
# Runs once, reads only dpkg and the directory it is given, writes one file.
#
#   tool/make-install-list.sh <deb-dir> <suffix> [more-suffixes...]
#
set -u

[ $# -ge 2 ] || { echo "usage: $0 <deb-dir> <suffix>..." >&2; exit 2; }

dir=$1; shift
[ -d "$dir" ] || { echo "no such directory: $dir" >&2; exit 2; }

out=$dir/install-list.txt
: > "$out"
missing=""

for suffix in "$@"; do
	src=$(ls "$dir"/*"$suffix"*.deb 2>/dev/null | head -1)
	[ -n "$src" ] || { echo "no debs matching $suffix in $dir" >&2; continue; }

	# Which source package these came from, asked of a deb rather than guessed.
	srcname=$(dpkg-deb -f "$src" Source 2>/dev/null)
	[ -n "$srcname" ] || srcname=$(dpkg-deb -f "$src" Package)
	srcname=${srcname%% *}

	for p in $(apt-cache showsrc "$srcname" 2>/dev/null \
			| grep -a -m1 '^Binary:' | sed 's/^Binary: //' | tr ',' ' '); do
		dpkg-query -W -f='${Status}' "$p" 2>/dev/null \
			| grep -q 'ok installed' || continue
		# _all.deb as well as _amd64.deb: three of tdebase's are
		# Architecture: all, and a glob for one arch silently drops them.
		f=$(ls "$dir/$p"_*"$suffix"*_amd64.deb \
		       "$dir/$p"_*"$suffix"*_all.deb 2>/dev/null | head -1)
		if [ -n "$f" ]; then
			echo "./$(basename "$f")" >> "$out"
		else
			missing="$missing $p"
		fi
	done
done

echo "wrote $out with $(wc -l < "$out") package(s)"
[ -z "$missing" ] || { echo "INSTALLED BUT NOT BUILT:$missing" >&2; exit 1; }
