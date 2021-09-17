#!/bin/bash

hostmachine=$(uname -sm | tr ' ' '-')

if [ -z "$machine" ]; then 
	machine="$hostmachine"
fi
echo $machine

function download() {
	url="$1"
	target="$2"
	if [ -e "$target" ]; then return; fi
	curl "$url" -LJo "$target"
}

topdir="$(pwd)"
libdir="$topdir/bessyhdfviewer.vfs/lib"
rtdir="$topdir/Runtime"

mkdir -p dependencies
mkdir -p "$rtdir"

download https://github.com/BessyHDFViewer/HDFpp/releases/download/latest/HDFpp_$machine.tar.bz2 dependencies/HDFpp_$machine.tar.bz2
download https://github.com/auriocus/kbskit/releases/download/latest/kbskit_$machine.tar.bz2 dependencies/kbskit_$machine.tar.bz2

# in case of Windows, create an alias from the complex MINGW-name
if [[ "$machine" == *MINGW* ]]; then
	windows=yes
	smachine=Windows-x86_64
	( cd dependencies
		
	  cp HDFpp_$machine.tar.bz2 HDFpp_$smachine.tar.bz2
	  cp kbskit_$machine.tar.bz2 kbskit_$smachine.tar.bz2
	  )
fi


# HDFpp is prepared for BessyHDFViewer. Simply extract 
# into the libdir

tar xvf "$topdir/dependencies/HDFpp_$machine.tar.bz2" -C "$libdir"

# kbskit is a general package. Extract, then pick out the cherries that are needed

( cd dependencies
  tar xvf kbskit_$machine.tar.bz2 )

kbskitdir="$topdir/dependencies/kbskit_$machine"

cp "$kbskitdir/bin/kbsvq8.6"* "$rtdir"
cp -r "$kbskitdir/licenses/"* "$libdir/3rdparty"

if [ "$machine" == "$hostmachine" ]; then 
	cp "$kbskitdir/bin/sdx"* "$rtdir"
	
fi

