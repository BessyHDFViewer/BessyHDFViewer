package require numeric_entry


snit::widget thresholdpicker {
	hulltype ttk::frame
	component numentry
	component dragline

	option -variable -default {}

	delegate option -orient to dragline
	delegate option * to numentry

	delegate method gotoRel to dragline
	
	constructor {args} {
		install numentry using numeric_entry $win.nume
		pack $numentry -expand yes -fill both
		set dragline [ukaz::dragline $win.line]
		incr id
		$BessyHDFViewer::w(Graph) addcontrol $dragline
		
		$self configurelist $args
		# set the variable for both widgets
		$dragline configure -variable $options(-variable)
		$numentry configure -variable $options(-variable)
	}

	destructor {
		catch { $dragline destroy }
	}
}

snit::widget rangepicker {
	hulltype ttk::frame
	component numentry_min
	component numentry_max
	component dragregion


	variable minvalue {}
	variable maxvalue {}

	# machinery to attach a list variable
	option -variable -default {} -configuremethod SetVariable
	option -command -default {}

	variable loopescape false
	variable commandescape false

	delegate option -orient to dragregion
	delegate option -label to dragregion
	delegate option -color to dragregion
	
	constructor {args} {
		install numentry_min using numeric_entry $win.nume_min
		install numentry_max using numeric_entry $win.nume_max
		set lbl [ttk::label $win.lbl -text \u2014]

		grid $numentry_min $lbl $numentry_max -sticky nsew
		grid columnconfigure $win $numentry_min -weight 1
		grid columnconfigure $win $numentry_max -weight 1

		set dragregion [ukaz::dragregion $win.region]
		$BessyHDFViewer::w(Graph) addcontrol $dragregion
		
		$self configurelist $args
		# set the variable for both widgets
		$dragregion configure -minvariable [myvar minvalue] -maxvariable [myvar maxvalue]
		$numentry_min configure -variable [myvar minvalue]
		$numentry_max configure -variable [myvar maxvalue]

	}

	destructor {
		$self untrace
		catch { $dragregion destroy }
	}
	
	method SetVariable {option varname} {
		$self untrace
		if {$varname != {}} {
			upvar #0 $varname v
			if {![info exists v]} { set v {} }
			
			trace add variable v write [mymethod SetValue]
			trace add variable minvalue write [mymethod DoTraces]
			trace add variable maxvalue write [mymethod DoTraces]
			set options(-variable) $varname
			$self SetValue
		}
	}

	method untrace {} {
		if {$options(-variable)!={} } {
			upvar #0 $options(-variable) v
			trace remove variable v write [mymethod SetValue]
			trace remove variable minvalue write [mymethod DoTraces]
			trace remove variable maxvalue write [mymethod DoTraces]
			set options(-variable) {}
		}
	}
	
	method SetValue {args} {
		if {$loopescape} {
			set loopescape false
			return
		}
		set loopescape true
		upvar #0 $options(-variable) v
		if {[info exists v]} {
			# ignore any errors if the graph is incomplete
			lassign $v minvalue maxvalue
		}
	}

	method DoTraces {args} {
		if {$loopescape} {
			set loopescape false
		} else {
			if {$options(-variable)!={}} {
				set loopescape true
				upvar #0 $options(-variable) v
				set v [list $minvalue $maxvalue]
			}
		}

		if {$options(-command)!={}} {
			if {$commandescape} {
				set commandescape false
			} else {
				uplevel #0 [list {*}$options(-command) $minvalue $maxvalue]
			}
		}
	}

}

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
		set icon [dict get {open document-open-inline save document-save-as-inline dir document-open-folder-inline} $options(-mode)]
		install pickbutton using ttk::button $win.button -style Toolbutton \
			-command [mymethod Pick] -image [BessyHDFViewer::IconGet $icon] -text $btext
		$self configurelist $args
		$fname_entry configure -textvariable $options(-variable)
		grid $fname_entry $pickbutton -sticky nsew
		grid columnconfigure $win $fname_entry -weight 1

		# create the methods for constructing the dialog
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
				set cmd [list tk_getOpenFile -initialfile [file tail $initial] -initialdir [file dirname $initial]]
			}
			save {
				set cmd [list tk_getSaveFile -initialfile  [file tail $initial] -initialdir [file dirname $initial]]
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
	variable fields
	variable widgets
	variable lbl
	variable conditions {}
	variable links {}
	variable id 0
	variable dns
	variable persistency {}
	variable prefkey
	variable defaults {}
	variable settings {}

	variable answers


	component formfr
	option -shortname
	option -hdfs
	option -datastorens

	# supported entry types:	
	variable aliases { enum channel number threshold range bool radio path hdf separator entry }

	constructor {args} {
		$self configurelist $args
		set dns $options(-datastorens)
		
		foreach cmd $aliases {
			interp alias {} ${dns}::$cmd {} {*}[mymethod $cmd]
		}
		
		set prefkey $options(-shortname)
		set settings [BessyHDFViewer::PreferenceGet PluginSettings $prefkey {}]
		
		set hdfs $options(-hdfs)
		
		set title "$options(-shortname) [file tail [lindex $hdfs 0]]"
		if {[llength $hdfs] > 1} { append title "..." }
		wm title $win $title
		
		
		# retrieve possible axes for channels
		set axes [BessyHDFViewer::bessy_get_keys_flist $hdfs Axes]
		set fields [BessyHDFViewer::bessy_get_keys_flist $hdfs]
		
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
		set answers [array get ${dns}::input]
		BessyHDFViewer::PreferenceSet PluginSettings $prefkey $answers
	}

	method execute {} {
		# update all constraints
		$self UpdateStates {}
		# wait for the buttons
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
		
		# -persistent
		if {[dict exists $persistency $uvar]} {
			# this variable was handled by a previous entry
			set persist false
		} else {
			if {[dict exists $uargs -persistent]} {
				set persist [dict get $uargs -persistency]
				dict unset uargs -persistency
			} else {
				set persist true
			}
			dict set persistency $uvar $persist
		}

		# -default
		if {[dict exists $uargs -default]} {
			set def [dict get $uargs -default]
			set ${dns}::input($uvar) $def
			dict unset uargs -default
			dict lappend defaults $uvar $def
		}
		
		# check the cache in the preferences
		if {[dict exists $settings $uvar]} {
			# check that this is really a persistent variable
			if {$persist} {
				set def [dict get $settings $uvar]
				set ${dns}::input($uvar) $def
				dict lappend defaults $uvar $def
			}
		}

		if {![dict exists $defaults $uvar]} {
			dict set defaults $uvar {}
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

	proc movetodict {from_ to_ key} {
		upvar 1 $from_ from
		upvar 1 $to_ to
		if {[dict exists $from $key]} {
			dict set to $key [dict get $from $key]
			dict unset to $key
			return true
		} else {
			return false
		}
	}

	method enum {label var args} {
		$self parseargs
		set enumlink [poparg -linkchannel {}]
		if {$enumlink ne {}} {
			dict set links $var $enumlink
		}
		set lbl($var) [ttk::label $formfr.l$id -text $label]
		set widgets($var) [ttk::combobox $formfr.c$id -textvariable ${dns}::input($var) {*}$args]
		bind $widgets($var)	<<ComboboxSelected>> [mymethod UpdateStates $var]
		grid $lbl($var) $widgets($var) -sticky nsew
	}

	method channel {label var args} {
		$self parseargs
		set lbl($var) [ttk::label $formfr.l$id -text $label]
		set widgets($var) [ttk::combobox $formfr.c$id -textvariable ${dns}::input($var) -values $axes]
		bind $widgets($var)	<<ComboboxSelected>> [mymethod UpdateStates $var]
		AutoComplete $widgets($var) -aclist $fields
		grid $lbl($var) $widgets($var) -sticky nsew
		
		# handle defaults in the order of appearance, 
		# keep only sensible defaults
		set bestdefault [lindex $axes 0]
		foreach def [dict get $defaults $var] {
			if {$def in $fields} {
				set bestdefault $def
			}
		}
		
		set ${dns}::input($var) $bestdefault
	}

	method number {label var args} {
		$self parseargs
		set lbl($var) [ttk::label $formfr.l$id -text $label]
		set widgets($var) [numeric_entry $formfr.e$id -variable ${dns}::input($var)]
		bind $widgets($var)	<FocusOut> [mymethod UpdateStates $var]
		grid $lbl($var) $widgets($var) -sticky nsew
	}

	method threshold {label var args} {
		$self parseargs
		set lbl($var) [ttk::label $formfr.l$id -text $label]
		set widgets($var) [thresholdpicker $formfr.t$id -variable ${dns}::input($var) {*}$args]
		bind $widgets($var)	<FocusOut> [mymethod UpdateStates $var]
		grid $lbl($var) $widgets($var) -sticky nsew

		# compute sensible value to start with from xmin, xmax, ymin ymax
		
		# retrieve orientation to check if the widget is visible
		set orient [$widgets($var) cget -orient]
		if {$orient == "horizontal"} {
			set min [set ${dns}::ymin]
			set max [set ${dns}::ymax]
		} else {
			set min [set ${dns}::xmin]
			set max [set ${dns}::xmax]
		}

		# set to default if it is not visible
		upvar #0 ${dns}::input($var) myvar
		if {! [info exists myvar] || $myvar < $min || $myvar > $max} {
			set myvar [expr {($min + $max) / 2}]
		}
	}	

	method range {label var args} {
		$self parseargs
		set lbl($var) [ttk::label $formfr.l$id -text $label]

		set widgets($var) [rangepicker $formfr.r$id -variable ${dns}::input($var) {*}$args]
		bind $widgets($var)	<FocusOut> [mymethod UpdateStates $var]
		grid $lbl($var) $widgets($var) -sticky nsew
		
		# retrieve orientation to check if the widget is visible
		set orient [$widgets($var) cget -orient]
		if {$orient == "horizontal"} {
			set min [set ${dns}::ymin]
			set max [set ${dns}::ymax]
		} else {
			set min [set ${dns}::xmin]
			set max [set ${dns}::xmax]
		}

		#  compute sensible value to start with from xmin, xmax, ymin ymax
		set defmin [expr {$min*0.4 + $max*0.6}]
		set defmax [expr {$min*0.6 + $max*0.4}]
		set default [list $defmin $defmax]

		# set to default if it is not visible
		upvar #0 ${dns}::input($var) myvar
	
		if {![info exists myvar]} {
			set myvar $default
		} else {
			lassign $myvar vmin vmax
			if { $vmin < $min || $vmin > $max || $vmax < $min || $vmax > $max } {
				set myvar $default
			}
		}

	}	

	method entry {label var args} {
		$self parseargs
		set lbl($var) [ttk::label $formfr.l$id -text $label]
		set widgets($var) [ttk::entry $formfr.e$id -textvariable ${dns}::input($var)]
		bind $widgets($var)	<FocusOut> [mymethod UpdateStates $var]
		grid $lbl($var) $widgets($var) -sticky nsew
	}

	method bool {label var args} {
		$self parseargs
		set lbl($var) [ttk::label $formfr.l$id -text $label]
		set widgets($var) [ttk::checkbutton $formfr.b$id -variable ${dns}::input($var) \
			-command [mymethod UpdateStates $var]]
		grid $lbl($var) $widgets($var) -sticky w
	}

	method radio {label var args} {
		$self parseargs
		set active [poparg -active false]
		set value [poparg -value $label]
		if {$active && [llength [dict get $defaults $var]] == 0} {
			set ${dns}::input($var) $value
		}
		set lbl($var) [ttk::label $formfr.l$id -text $label]
		set widgets($var) [ttk::radiobutton $formfr.r$id -variable ${dns}::input($var) \
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
		set widgets($var) [BHDFFilePicker $formfr.hdf$id -variable ${dns}::input($var) \
			-command [mymethod UpdateStates $var]]
		grid $lbl($var) $widgets($var) -sticky nsew
		
	}

	method path {label var args} {	
		$self parseargs
		set lbl($var) [ttk::label $formfr.l$id -text $label]
		set widgets($var) [GeneralFilePicker $formfr.file$id -variable ${dns}::input($var) \
			-command [mymethod UpdateStates $var] {*}$args]
		grid $lbl($var) $widgets($var) -sticky nsew
	
	}

	method UpdateStates {var args} {
		upvar #0 ${dns}::input input
		
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
			if {$var ne $cvar} {
				if {[catch {namespace eval $dns [list subst $linkvar]} linkvarsubst]} {
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


