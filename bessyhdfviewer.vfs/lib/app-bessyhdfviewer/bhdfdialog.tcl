snit::widget BHDFFilePicker {
	hulltype ttk::frame
	component fname_entry
	component pickbutton
	option -variable -default {}
	option -command -default {}
	delegate option * except -textvariable to fname_entry

	constructor {args} {
		install fname_entry using ttk::entry $win.entry
		install pickbutton using ttk::button $win.button \
			-command [mymethod Pick] -image [BessyHDFViewer::IconGet pickhdf] -text Pick!
		$self configurelist $args
		$fname_entry configure -textvariable $options(-variable)
		grid $fname_entry $pickbutton -sticky nsew
		grid columnconfigure $win $fname_entry -weight 1
		$self configurelist $args
	}

	method Pick {} {
		set $options(-variable) [lindex $BessyHDFViewer::HDFFiles 0]
		$self see_end
		set cmd $options(-command)
		if {$cmd ne {}} {
			uplevel #0 $cmd
		}
	}
	
	method see_end {} {
		after idle [mymethod see_end_after]
	}
	
	method see_end_after {} {
		$fname_entry icursor end
		$fname_entry xview end
	}

	method state {args} {
		$pickbutton state {*}$args
		$fname_entry state {*}$args
	}
}

snit::widget GeneralFilePicker {
	hulltype ttk::frame
	component fname_entry
	component pickbutton
	option -variable -default {}
	option -command -default {}	
	option -mode -default open

	# options for the dialog
	option -message -default {}
	option -filetypes -default {}
	option -defaultextension -default {}
	option -multiple -default {}
	option -typevariable -default {}
	option -title -default {}
	
	# -mode determines the purpose of the entry
	#    open
	#    save
	#    dir
	delegate option * except -textvariable to fname_entry

	constructor {args} {
		$self configurelist $args
		
		install fname_entry using ttk::entry $win.entry
		set btext [dict get {open Open! save Save! dir Folder!} $options(-mode)]
		set icon [dict get {open document-open save document-save-as dir document-open-folder} $options(-mode)]
		install pickbutton using ttk::button $win.button -style Toolbutton \
			-command [mymethod Pick] -image [BessyHDFViewer::IconGet $icon] -text $btext
		$self configurelist $args
		$fname_entry configure -textvariable $options(-variable)
		grid $fname_entry $pickbutton -sticky nsew
		grid columnconfigure $win $fname_entry -weight 1
	}

	method Pick {} {
		upvar #0 $options(-variable) linkedvar

		if {[info exists linkedvar]} {
			set initial $linkedvar
		} else {
			set initial {}
		}

		switch $options(-mode) {
			open {
				set cmd [list tk_getOpenFile -initialfile $initial]
			}
			save {
				set cmd [list tk_getSaveFile -initialfile $initial]
			}
			dir {
				set cmd [list tk_chooseDirectory -initialdir $initial]
			}	
			default {
				return -code error "Unknown file dialog >$mode<"
			}
		}

		set cmdopts {}
		# transfer the standard dialog options
		foreach opt {-message -filetypes -defaultextension -multiple -typevariable -title} {
			if {$options($opt) ne {}} {
				dict set cmdopts $opt $options($opt)
			}
		}

		set result [{*}$cmd {*}$cmdopts]
		if {$result ne {}} {
			set linkedvar $result
			$self see_end
			set cmd $options(-command)
			if {$cmd ne {}} {
				uplevel #0 $cmd
			}
		}
	}
	
	method see_end {} {
		after idle [mymethod see_end_after]
	}
	
	method see_end_after {} {
		$fname_entry icursor end
		$fname_entry xview end
	}

	method state {args} {
		$pickbutton state {*}$args
		$fname_entry state {*}$args
	}
}



snit::widget BHDFDialog {
	hulltype toplevel

	variable diodes
	variable axes
	variable input
	variable widgets
	variable lbl
	variable conditions {}
	variable links {}
	variable id 0
	
	variable answers


	component formfr
	option -title -default {Select}
	option -hdfs

	# supported entry types:
	# channel
	# double
	# integer
	# bool
	# string
	# file
	# hdf
	# formula
	# separator
	#
	constructor {args} {
		$self configurelist $args
		
		# retrieve possible axes for channels
		set hdfs $options(-hdfs)
		
		set title "$options(-title) [file tail [lindex $hdfs 0]]"
		if {[llength $hdfs] > 1} { append title "..." }
		wm title $win $title
		
		
		set axes [BessyHDFViewer::bessy_get_keys_flist $hdfs Axes]
		set mfr [ttk::frame $win.mfr]
		pack $mfr -expand yes -fill both

		install formfr using ttk::frame $mfr.formfr
		set butfr [ttk::frame $mfr.butfr]
		
		grid $formfr -sticky nsew
		grid $butfr

		# add channel selectors
		grid columnconfigure $mfr $formfr -weight 1
		grid columnconfigure $formfr 1 -weight 1

		# get default values from the preferences
	
		# add buttons
		set okbut [ttk::button $butfr.ok -text "OK" -command [mymethod OK] -default active]
		set cancelbut [ttk::button $butfr.quit -text "Cancel" -command [mymethod Cancel] -default normal]
		pack $okbut $cancelbut -side left -anchor c
		focus $okbut
		bind $self <Return> [mymethod OK]
		bind $self <Escape> [mymethod Cancel]
	}

	method AxisSearch {args} {
		patsearch $axes {*}$args
	}

	proc patsearch {list args} {
		# search a list with a list of patterns
		# return first hit or "" for not found
		foreach pat $args {
			set hit [lindex $list [lsearch -nocase -glob $list $pat]]
			if {$hit != "" } { return $hit }
		}
		return ""
	}

	method Cancel {} {
		set answers {}
	}

	method OK {} {
		# BessyHDFViewer::PreferenceSet DiodeRefData $refdata
		set answers [array get input]
	}

	method execute {} {
		vwait [myvar answers]
		if {![info exists answers]} { return {} }
		return [$self close $answers]
	}
	
	method close {ans} {
		destroy $win
		return $ans
	}
	
	method parseargs {} {
		# parse common args
		upvar 1 args uargs
		upvar 1 var uvar
		# -enableif
		if {[dict exists $uargs -enableif]} {
			dict set conditions $uvar [dict get $uargs -enableif]
			dict unset uargs -enableif
		}
		
		# -default
		puts "$uargs"
		if {[dict exists $uargs -default]} {
			puts "Found: -default in $uargs"
			set input($uvar) [dict get $uargs -default]
			dict unset uargs -default
		}
		
		incr id
	}

	proc poparg {arg default} {
		upvar 1 args uargs
		if {[dict exists $uargs $arg]} {
			set val [dict get $uargs $arg]
			dict unset uargs $arg
			return $val
		} else {
			return $default
		}
	}

	method enum {label var args} {
		$self parseargs
		set enumlink [poparg -linkchannel {}]
		if {$enumlink ne {}} {
			dict set links $var $enumlink
		}
		set lbl($var) [ttk::label $formfr.l$id -text $label]
		set widgets($var) [ttk::combobox $formfr.c$id -textvariable [myvar input($var)] {*}$args]
		bind $widgets($var)	<<ComboboxSelected>> [mymethod UpdateStates $var]
		grid $lbl($var) $widgets($var) -sticky nsew
	}

	method channel {label var args} {
		$self parseargs
		set lbl($var) [ttk::label $formfr.l$id -text $label]
		set widgets($var) [ttk::combobox $formfr.c$id -textvariable [myvar input($var)] -values $axes]
		bind $widgets($var)	<<ComboboxSelected>> [mymethod UpdateStates $var]
		grid $lbl($var) $widgets($var) -sticky nsew

		if {![info exists input($var)] || $input($var) ni $axes} {
			set input($var) [lindex $axes 0]
		}
	}

	method double {label var args} {
		$self parseargs
		set lbl($var) [ttk::label $formfr.l$id -text $label]
		set widgets($var) [ttk::entry $formfr.e$id -textvariable [myvar input($var)]]
		bind $widgets($var)	<FocusOut> [mymethod UpdateStates $var]
		grid $lbl($var) $widgets($var) -sticky nsew
	}

	method integer {label var args} {
		$self parseargs
		set lbl($var) [ttk::label $formfr.l$vid -text $label]
		set widgets($var) [ttk::entry $formfr.e$id -textvariable [myvar input($var)]]
		bind $widgets($var)	<FocusOut> [mymethod UpdateStates $var]
			-command [mymethod UpdateStates $var]]
		grid $lbl($var) $widgets($var) -sticky nsew
	}

	method string {label var args} {
		$self parseargs
		set lbl($var) [ttk::label $formfr.l$id -text $label]
		set widgets($var) [ttk::entry $formfr.e$id -textvariable [myvar input($var)]]
		bind $widgets($var)	<FocusOut> [mymethod UpdateStates $var]
		grid $lbl($var) $widgets($var) -sticky nsew
	}

	method bool {label var args} {
		$self parseargs
		set lbl($var) [ttk::label $formfr.l$id -text $label]
		set widgets($var) [ttk::checkbutton $formfr.b$id -variable [myvar input($var)] \
			-command [mymethod UpdateStates $var]]
		grid $lbl($var) $widgets($var) -sticky w
	}

	method radio {label var args} {
		$self parseargs
		set active [poparg -active false]
		set value [poparg -value $label]
		if {$active} {
			set input($var) $value
		}
		set lbl($var) [ttk::label $formfr.l$id -text $label]
		set widgets($var) [ttk::radiobutton $formfr.r$id -variable [myvar input($var)] \
			-command [mymethod UpdateStates $var] -value $value]
		grid $lbl($var) $widgets($var) -sticky w
	}

	method separator {} {
		incr id
		ttk::separator $formfr.sep$id
		grid  $formfr.sep$id - -sticky ew

	}

	method hdf {label var args} {
		$self parseargs
		set lbl($var) [ttk::label $formfr.l$id -text $label]
		set widgets($var) [BHDFFilePicker $formfr.hdf$id -variable [myvar input($var)] \
			-command [mymethod UpdateStates $var]]
		grid $lbl($var) $widgets($var) -sticky nsew
		
	}

	method file {label var args} {	
		$self parseargs
		set lbl($var) [ttk::label $formfr.l$id -text $label]
		set widgets($var) [GeneralFilePicker $formfr.file$id -variable [myvar input($var)] \
			-command [mymethod UpdateStates $var] {*}$args]
		grid $lbl($var) $widgets($var) -sticky nsew
	
	}

	method UpdateStates {var args} {
		puts "Change in $var"
		parray widgets
		# check enableif and links
		dict for {cvar cond} $conditions {
			if {$var ne $cvar} {
				if {[catch {expr $cond} result]} {
					puts "Condition error: $result"
				} else {
					if {$result} {
						$widgets($cvar) state !disabled
						$lbl($cvar) state !disabled
					} else {
						$widgets($cvar) state disabled
						$lbl($cvar) state disabled
					}
				}
			}
		}

		dict for {cvar linkvar} $links {
			puts "$cvar $linkvar"
			if {$var ne $cvar} {
				if {[catch {subst $linkvar} linkvarsubst]} {
					puts "Link error: $linkvarsubst"
				} else {
					set uniqvalues [lsort -unique \
						[lmap x [BessyHDFViewer::SELECT [list $linkvarsubst] $options(-hdfs)] {lindex $x 0}]]
					$widgets($cvar) configure -values $uniqvalues
					if {![info exists input($cvar)] || $input($cvar) ni $uniqvalues} {
						set input($cvar) [lindex $uniqvalues 0]
					}
				}
			}
		}
	}
}


if {0} {
BHDFDialog .dialog -hdfs $BessyHDFViewer::HDFFiles -title "Test dialog"
foreach e {
	{channel "Energy:" energy}
	{double  "Height:" height -enableif $input(norm)}
	separator
	{bool    "Normalize:" norm}
	{hdf     "Reference scan:" refhdf -enableif $input(norm)}
	{enum	 "Pet preference" pet -values {Cat Dog Bunny}}
	{enum    "Select energy" senergy -linkchannel $input(energy)}
} {
	.dialog {*}$e
}

.dialog UpdateStates {}

puts "Selected: [.dialog execute]"
}

