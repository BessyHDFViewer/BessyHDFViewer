
  package require starkit
  starkit::startup
  set libdir [file join [file dirname [info script]] lib]
  lappend auto_path $libdir $libdir/tklib0.7 $libdir/tcllib1.20
  package require app-bessyhdfviewer

