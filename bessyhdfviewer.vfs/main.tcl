
  package require starkit
  starkit::startup
  set libdir [file join [file dirname [info script]] lib]
  lappend auto_path $libdir $libdir/tklib $libdir/tcllib
  package require app-bessyhdfviewer

