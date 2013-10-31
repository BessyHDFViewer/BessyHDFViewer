#
# Tcl package index file
#
package ifneeded inotify 1.3 \
    [list load [file join $dir libinotify1.3_[expr {8*$::tcl_platform(pointerSize)}][info sharedlibextension]] inotify]
