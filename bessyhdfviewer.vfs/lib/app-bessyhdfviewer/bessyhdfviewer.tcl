package provide app-bessyhdfviewer 1.0

set basedir [file dirname [info script]]
lappend auto_path [file join $basedir lib]

package require hdfpp
package require ukaz
package require tablelist_tile

variable ns [namespace current]

source [file join $basedir dirViewer.tcl]

proc InitGUI {} {
	variable w
	variable ns
	# paned window, left file selection, right plot window
	set w(mainfr) [ttk::panedwindow .mainfr -orient horizontal]
	pack $w(mainfr) -expand yes -fill both

	set w(listfr) [ttk::frame $w(mainfr).listfr]
	set w(plotfr) [ttk::frame $w(mainfr).plotfr]

	$w(mainfr) add $w(listfr)
	$w(mainfr) add $w(plotfr)

	set w(pathent) [ttk::entry $w(listfr).pathent -textvariable ${ns}::browsepath]
	variable browsepath [file normalize [pwd]]
	bind $w(pathent) <FocusOut> ${ns}::DirUpdate
	bind $w(pathent) <Key-Return> ${ns}::DirUpdate

	set w(filelist) [dirViewer::dirViewer $w(listfr).filelist $browsepath \
		-columns \
		{
			0 "Motor" left
			0 "Detector" left
			0 "Modified" left
		} \
		-classifycommand ${ns}::ClassifyHDF \
		-selectcommand ${ns}::PreviewFile \
		-globpattern {*.hdf} \
		-columnoptions [list {} {} [list -sortmode integer -formatcommand ${ns}::formatDate ]]]

	bind $w(filelist) <<DirviewerSelect>> [list ${ns}::DirChanged %d]

	grid $w(pathent) -sticky nsew 
	grid $w(filelist) -sticky nsew
	grid rowconfigure $w(listfr) $w(filelist) -weight 1
	grid columnconfigure $w(listfr) 0 -weight 1

	set w(canv) [canvas $w(plotfr).c]
	set w(bbar) [ttk::frame $w(plotfr).bbar]
	grid $w(bbar) -sticky nsew
	grid $w(canv) -sticky nsew
	grid columnconfigure $w(plotfr) 0 -weight 1
	grid rowconfigure $w(plotfr) 1 -weight 1

	# Toolbar
	set w(xlbl) [ttk::label $w(bbar).xlbl -text "X axis:"]
	set w(xent) [ttk::combobox $w(bbar).xent -textvariable ${ns}::xformat -exportselection 0]
	set w(ylbl) [ttk::label $w(bbar).ylbl -text "Y axis:"]
	set w(yent) [ttk::combobox $w(bbar).yent -textvariable ${ns}::yformat -exportselection 0]
	
	bind $w(xent) <<ComboboxSelected>> ${ns}::RePlot
	bind $w(yent) <<ComboboxSelected>> ${ns}::RePlot


	grid $w(xlbl) $w(xent) $w(ylbl) $w(yent) -sticky nsew

	set w(Graph) [ukaz::box %AUTO% $w(canv)]
	
}

proc ClassifyHDF {type fn} {
	variable w
	
	if {[catch {file mtime $fn} mtime]} {
		# could not get mtime - something is wrong
		return {}
	}

	if {$type == "directory"} {
		return [list "" "" $mtime ""]
	}

	if {[catch {bessy_class [bessy_reshape $fn]} class]} {
		puts "Error reading hdf file $fn"
		return [list "" "" $mtime [IconGet unknown]]
	} else {
		puts "$fn $class"
		lassign $class type motor detector
		switch $type {
			MCA {
				return [list $motor $detector $mtime [IconGet mca]]
			}

			MULTIPLE_IMG {
				return [list $motor $detector $mtime [IconGet image-multiple]]
			}

			SINGLE_IMG {
				return [list $motor $detector $mtime [IconGet image-x-generic]]
			}

			PLOT {
				return [list $motor $detector $mtime [IconGet graph]]
			}

			default -
			UNKNOWN {
				return [list $motor $detector $mtime [IconGet unknown]]
			}
		}
	}
}

proc PreviewFile {fn} {
	# get selected file from list
	variable w

	variable hdfdata [bessy_reshape $fn]

	# insert available axes into axis choosers
	if {[catch {
		set motors [dict keys [dict get $hdfdata Motor]]
		set detectors [dict keys [dict get $hdfdata Detector]]
		set axes $motors
		lappend axes {*}$detectors

		$w(xent) configure -values $motors 
		$w(yent) configure -values $detectors
	}]} {
		# could not get sensible plot axes - not BESSY hdf?
		$w(xent) configure -values {}
		$w(yent) configure -values {}
		return 
	}

	# select the motor/det from plot
	variable xformat
	variable yformat
	if {[catch {dict get $hdfdata Plot Motor} motor]} {
		# use the first motor, if no plot available
		set motor [lindex $motors 0]
	}

	if {[catch {dict get $hdfdata Plot Detector} detector]} {
		# use the first motor, if no plot available
		set detector [lindex $detectors 0]
	}
	
	set xformat $motor
	set yformat $detector

	RePlot
}


proc RePlot {} {
	variable w
	variable hdfdata
	variable xformat
	variable yformat

	# plot the data 
	set xdata [dict get $hdfdata Motor $xformat data]
	set ydata [dict get $hdfdata Detector $yformat data]

	set data [zip $xdata $ydata]

	variable plotid
	if {[info exists plotid]} {
		$w(Graph) remove $plotid
	}

	if {[llength $data] > 4} {
		if {[catch {dict get $hdfdata Motor $xformat attrs Unit} xunit]} {
			$w(Graph) configure -xlabel "$xformat"
		} else {
			$w(Graph) configure -xlabel "$xformat ($xunit)"
		}
		
		if {[catch {dict get $hdfdata Detector $yformat attrs Unit} yunit]} {
			$w(Graph) configure -ylabel "$yformat"
		} else {
			$w(Graph) configure -ylabel "$yformat ($yunit)"
		}

		set plotid [$w(Graph) connectpoints_autodim $data black]
		lappend plotid [$w(Graph) showpoints $data red circle]
		$w(Graph) autoresize
	}

}

proc DirChanged {dir} {
	# dir was changed by double clicking in dirviewer
	variable browsepath
	set browsepath $dir
}

proc DirUpdate {} {
	# dir was entered into entry
	variable browsepath
	variable w
	set errmsg ""
	if {[catch {expr {[file isdirectory $browsepath] && [file readable $browsepath]}} result]} {
		# I/O error during check
		set errmsg $result
		set isdir 0
	} else {
		set isdir $result
		if {!$isdir} {
			set errmsg "Directory unreadable"
		}
	}

	if {$isdir} {
		$w(filelist) display $browsepath
	} else {
		tk_messageBox -type ok -icon error -title "Error opening directory" \
			-message $errmsg -detail "when opening '$browsepath'"
	}
}


proc formatDate {date} {
	clock format $date -format {%Y-%m-%d %H:%S}
}

proc bessy_reshape {fn} {
	set hdf [HDFpp %AUTO% $fn]
	set hlist [$hdf dump]
	$hdf -delete
	foreach dataset $hlist {
		set dname [dict get $dataset name]
		dict unset dataset name
		if {[catch {dict get $dataset attrs Name} name]} {
			# there is no name - put it directly
			set key [list $dname]
		} else {
			# sub-name in the attrs - put it as a subdict
			dict unset dataset attrs Name
			set key [list $dname $name]
		}
		
		if {[llength [dict get $dataset data]]==0} {
			# key contains only attrs -- put it directly there
			set dataset [dict get $dataset attrs]
		} else {	
			# filter all data entries to the last occurence >= BESSY_INF
			set BESSY_INF 9.9e36
			set data [dict get $dataset data]
			set index -1
			set lastindex end
			foreach v $data {
				if {abs($v) >= $BESSY_INF} {
					set lastindex $index
					break
				}
				incr index
			}
			dict set dataset data [lrange $data 0 $lastindex]
		}

		dict set hdict {*}$key $dataset
	}
	return $hdict
}

proc bessy_class {data} {
	# classify dataset into Images, Plot and return plot axes
	set images [dict exists $data Detector Pilatus_Tiff data]
	set mca [dict exists $data MCA]

	set Plot true
	if {[catch {dict get $data Plot Motor} motor]} {
		# if Plot is unavailable take the first motor
		# if that fails, give up
		set Plot false
		if {[catch {lindex [dict keys [dict get $data Motor]] 0} motor} {
			set motor {}
		}
	}
		
	if {[catch {dict get $data Plot Detector} detector]} {
		set Plot false
		if {[catch {lindex [dict keys [dict get $data Detector]] 0} motor} {
			set detector {}
		}
	}

	# now check for different classes. MCA has only this dataset, no motors etc.
	if {$mca} {
		return [list MCA "" ""]
	}

	if {$images} {
		# file contains Pilatus images. Check for one or more
		set nimages [llength [dict get $data Detector Pilatus_Tiff data]]
		if {$nimages == 1} {
			return [list SINGLE_IMG $motor $detector]
		}

		if {$nimages > 1} {
			return [list MULTIPLE_IMG $motor $detector]
		}
		# otherwise no images are found
	}

	if {$Plot} {
		# there is a valid Plot
		return [list PLOT $motor $detector]
	}
	# could not identify 
	return [list UNKNOWN $motor $detector]
}

proc zip {l1 l2} {
	# create intermixed list
	set result {}
	foreach v1 $l1 v2 $l2 {
		lappend result $v1 $v2
	}
	return $result
}


variable iconcache {}
proc IconGet {name} {
	variable iconcache
	variable basedir
	if {[dict exists $iconcache $name]} {
		return [dict get $iconcache $name]
	} else {
		if {[catch {image create photo -file [file join $basedir icons $name.png]} iname]} {
			return {} ;# not found
		} else {
			dict set iconcache $name $iname
			return $iname
		}
	}
}

InitGUI
