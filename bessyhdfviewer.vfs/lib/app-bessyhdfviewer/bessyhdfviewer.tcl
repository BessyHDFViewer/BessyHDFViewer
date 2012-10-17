package provide app-bessyhdfviewer 1.0

set basedir [file dirname [info script]]

package require hdfpp
package require ukaz
package require Tk

if {[tk windowingsystem]=="x11"} {
	ttk::setTheme default
	package require fsdialog
	interp alias {} tk_getOpenFile {} ttk::getOpenFile
	interp alias {} tk_getSaveFile {} ttk::getSaveFile
	interp alias {} tk_getDirectory {} ttk::getDirectory
} else {
	# on aqua and win, tk_chooseDirectory does not allow -filetypes
	# just remove it from the args
	proc tk_getDirectory {args} {
		dict unset args -filetypes
		tk_chooseDirectory {*}$args
	}
}

if {[tk windowingsystem]=="aqua"} {
	# on aqua, tk busy leads to a crash - disable
	interp alias {} tk_busy {} nop
	proc ::nop {args} {}

} else {
	interp alias {} tk_busy {} tk busy
}

set tversion [package require tkcon]
# setup tkcon, as in http://wiki.tcl.tk/17616
#------------------------------------------------------
#  The console doesn't exist yet.  If we create it
#  with show/hide, then it flashes on the screen.
#  So we cheat, and call tkcon internals to create
#  the console and customize it to our application.
#------------------------------------------------------
set tkcon::PRIV(showOnStartup) 0
set tkcon::PRIV(root) .console
#set tkcon::PRIV(protocol) {tkcon hide}
set tkcon::OPT(exec) ""
tkcon::Init
tkcon title "BessyHDFViewer Console (tkcon $tversion)"

variable ns [namespace current]

# load support modules
foreach module {dirViewer.tcl listeditor.tcl dictunsupported.tcl exportdialog.tcl} {
	source [file join $basedir $module]
}

proc Init {} {
	variable ns
	variable profiledir
	
	# find user profile directory
	switch -glob $::tcl_platform(platform) {
		win* {
			set profiledir $::env(APPDATA)/BessyHDFViewer
		}
		unix {
			set profiledir $::env(HOME)/.BessyHDFViewer
		}
		default {
			set profiledir [pwd]
		}
	}

	if {[catch {file mkdir $profiledir}]} {
		# give up - no persistent cache
		puts "No persistent cache - could not access profile dir $profiledir"
		set profiledir {}
	}

	variable ColumnTraits {
		Modified {
			Display { -sortmode integer -formatcommand formatDate }
		}

		Energy {
			FormatString %.5g
		}
	}
	
	ReadPreferences
	InitCache
	InitGUI
}

proc ExitProc {} {
	SavePreferences
}

proc InitGUI {} {
	variable w
	variable ns

	wm title . "BessyHDFViewer"
	wm iconphoto . [IconGet BessyHDFViewer]
	
	set w(mainfr) [ttk::panedwindow .mainfr -orient horizontal]
	pack $w(mainfr) -expand yes -fill both	
	# create exit proc
	bind $w(mainfr) <Destroy> ${ns}::ExitProc


	# paned window, left file selection, right data display
	set w(listfr) [ttk::frame $w(mainfr).listfr]
	set w(displayfr) [ttk::notebook $w(mainfr).displaynb]
	bind $w(displayfr) <<NotebookTabChanged>> ${ns}::ReDisplay
	ValidateDisplay all

	$w(mainfr) add $w(listfr)
	$w(mainfr) add $w(displayfr)

	# Main directory browser
	# 
	#  Dir entry
	#  Table
	#  Navigation buttons
	#  Progress bar 
	set w(pathent) [ttk::entry $w(listfr).pathent -textvariable ${ns}::browsepath]
	
	variable browsepath /messung/kmc/daten 
	if {![file isdirectory $browsepath]} {
		set browsepath [file normalize [pwd]]
	}

	bind $w(pathent) <FocusOut> ${ns}::DirUpdate
	bind $w(pathent) <Key-Return> ${ns}::DirUpdate

	set w(filelist) [dirViewer::dirViewer $w(listfr).filelist $browsepath \
		-classifycommand ${ns}::ClassifyHDF \
		-selectcommand ${ns}::PreviewFile \
		-globpattern {*.hdf} \
		-selectmode extended]

	bind $w(filelist) <<DirviewerChDir>> [list ${ns}::DirChanged %d]
	bind $w(filelist) <<DirviewerColumnMoved>> [list ${ns}::DirColumnMoved %d]

	bind $w(filelist) <<ProgressStart>> [list ${ns}::OpenStart %d]
	bind $w(filelist) <<Progress>> [list ${ns}::OpenProgress %d]
	bind $w(filelist) <<ProgressFinished>> ${ns}::OpenFinished

	set w(coleditbut) [ttk::button $w(listfr).coleditbut -text "Configure columns" \
		-image [IconGet configure] -command ${ns}::ColumnEdit -style Toolbutton]

	ChooseColumns [PreferenceGet Columns {"Motor" "Detector" "Modified"}]

	
	# Create navigation buttons
	#
	set w(bbar) [ttk::frame $w(listfr).bbar]
	set w(brefresh) [ttk::button $w(bbar).brefresh -text "Refresh" -image [IconGet view-refresh] -compound left  -command [list $w(filelist) refreshView]]
	set w(bupwards) [ttk::button $w(bbar).bupwards -text "Parent" -image [IconGet go-up] -compound left -command [list $w(filelist) goUp]]
	set w(bhome) [ttk::button $w(bbar).bhome -text "Home" -image [IconGet go-home] -compound left -command [list $w(filelist) goHome]]
	set w(bcollapse) [ttk::button $w(bbar).coll -text "Collapse" -image [IconGet tree-collapse] -compound left -command [list $w(filelist) collapseCurrent]]
	set w(dumpButton) [ttk::button $w(bbar).dumpbut -command ${ns}::DumpCmd -text "Export" -image [IconGet document-export] -compound left]

	pack $w(bhome) $w(bupwards) $w(bcollapse) $w(brefresh) $w(dumpButton) -side left -expand no -padx 2

	
	set w(foldbut) [ttk::button $w(listfr).foldbut -text "<" -command ${ns}::FoldPlotCmd -image [IconGet fold-close] -style Toolbutton]
	variable PlotFolded false

	set w(progbar) [ttk::progressbar $w(listfr).progbar]
	grid $w(pathent) $w(coleditbut) -sticky ew 
	grid $w(filelist)    -          -sticky nsew
	grid $w(bbar)		 $w(foldbut) -sticky nsew
	grid $w(progbar)     -          -sticky nsew

	grid rowconfigure $w(listfr) $w(filelist) -weight 1
	grid columnconfigure $w(listfr) 0 -weight 1
	
	
	#############################################
	#
	# Data display window

	# Plot tab 
	#
	# Toolbar

	set w(plotfr) [ttk::frame $w(mainfr).plotfr]
	set w(axebar) [ttk::frame $w(plotfr).axebar]
	set w(canv) [canvas $w(plotfr).c -background white]

	grid $w(axebar) -sticky nsew
	grid $w(canv) -sticky nsew
	grid columnconfigure $w(plotfr) 0 -weight 1
	grid rowconfigure $w(plotfr) 1 -weight 1
	
	set w(xlbl) [ttk::label $w(axebar).xlbl -text "X axis:"]
	set w(xent) [ttk::combobox $w(axebar).xent -textvariable ${ns}::xformat -exportselection 0]
	set w(ylbl) [ttk::label $w(axebar).ylbl -text "Y axis:"]
	set w(yent) [ttk::combobox $w(axebar).yent -textvariable ${ns}::yformat -exportselection 0]
	
	bind $w(xent) <<ComboboxSelected>> ${ns}::DisplayPlot
	bind $w(yent) <<ComboboxSelected>> ${ns}::DisplayPlot
	bind $w(xlbl) <1> { tkcon show }

	grid $w(xlbl) $w(xent) $w(ylbl) $w(yent) -sticky ew
	grid columnconfigure $w(axebar) 1 -weight 1
	grid columnconfigure $w(axebar) 3 -weight 1

	# Graph
	set w(Graph) [ukaz::box %AUTO% $w(canv)]

	$w(displayfr) add $w(plotfr) -text "Plot"


	# Text display tab
	# 
	set w(tdumpfr) [ttk::frame $w(displayfr).textfr]
	set w(textdump) [text $w(tdumpfr).text]
	set w(textvsb) [ttk::scrollbar $w(tdumpfr).vsb -orient vertical -command [list $w(textdump) yview]]
	set w(texthsb) [ttk::scrollbar $w(tdumpfr).hsb -orient horizontal -command [list $w(textdump) xview]]
	$w(textdump) configure -xscrollcommand [list $w(texthsb) set] -yscrollcommand [list $w(textvsb) set]

	grid $w(textdump) $w(textvsb) -sticky nsew
	grid $w(texthsb)  x           -sticky nsew

	grid columnconfigure $w(tdumpfr) 0 -weight 1
	grid rowconfigure $w(tdumpfr) 0 -weight 1

	$w(displayfr) add $w(tdumpfr) -text "Text"
	
	update
	# bug in tablelist? Creation blocks if update is left out

	# Table display tab
	#
	set w(ttblfr) [ttk::frame $w(displayfr).tblfr]
	set w(tbltbl) [tablelist::tablelist $w(ttblfr).tbl \
		-movablecolumns yes -setgrid no -showseparators yes \
		-exportselection 0 -selectmode single -stretch all]

	set w(tblvsb) [ttk::scrollbar $w(ttblfr).vsb -orient vertical -command [list $w(tbltbl) yview]]
	set w(tblhsb) [ttk::scrollbar $w(ttblfr).hsb -orient horizontal -command [list $w(tbltbl) xview]]
	$w(tbltbl) configure -xscrollcommand [list $w(tblhsb) set] -yscrollcommand [list $w(tblvsb) set]

	grid $w(tbltbl) $w(tblvsb) -sticky nsew
	grid $w(tblhsb)  x           -sticky nsew

	grid columnconfigure $w(ttblfr) 0 -weight 1
	grid rowconfigure $w(ttblfr) 0 -weight 1

	$w(displayfr) add $w(ttblfr) -text "Table"
	
	# Tree display tab
	#
	set w(ttreefr) [ttk::frame $w(displayfr).treefr]
	set w(treetbl) [tablelist::tablelist $w(ttreefr).tree \
		-movablecolumns yes -setgrid no -showseparators yes \
		-exportselection 0 -selectmode single -stretch end \
		-columns {0 Variable left 0 Value left}]

	set w(treevsb) [ttk::scrollbar $w(ttreefr).vsb -orient vertical -command [list $w(treetbl) yview]]
	set w(treehsb) [ttk::scrollbar $w(ttreefr).hsb -orient horizontal -command [list $w(treetbl) xview]]
	$w(treetbl) configure -xscrollcommand [list $w(treehsb) set] -yscrollcommand [list $w(treevsb) set]

	grid $w(treetbl) $w(treevsb) -sticky nsew
	grid $w(treehsb)  x           -sticky nsew

	grid columnconfigure $w(ttreefr) 0 -weight 1
	grid rowconfigure $w(ttreefr) 0 -weight 1

	$w(displayfr) add $w(ttreefr) -text "Tree"
	

}

proc ReadPreferences {} {
	variable profiledir
	variable basedir
	variable PrefFileName
	variable Preferences {}

	# read hardcoded prefs from package - must not fail
	set fd [open [file join $basedir Preferences_default.dict] r]
	set Preferences [read $fd]
	close $fd
	
	# read from profile dir
	if {$profiledir == {}} {
		set PrefFileName {}
		puts "No preferences file"
	} else {
		if {[catch {
			set PrefFileName [file join $profiledir Preferences.dict]
			set fd [open $PrefFileName r]
			fconfigure $fd -translation binary -encoding binary
			set Preferences [dict merge $Preferences [read $fd]]
			close $fd
		}]} {
			# error - maybe cleanup fd
			# cache file remains valid - maybe simply didn't exist
			if {[info exists fd]} { catch {close $fd} }
		}
	}

}

proc PreferenceGet {key default} {
	variable Preferences
	if {![dict exists $Preferences $key]} {
		dict set Preferences $key $default
		return $default
	} else {
		return [dict get $Preferences $key]
	}
}

proc PreferenceSet {key value} {
	variable Preferences
	dict set Preferences $key $value
}

proc SavePreferences {} {
	variable Preferences
	variable PrefFileName
	# hide errors when writing the pref file
	catch { 
		set fd [open $PrefFileName w]
		puts -nonewline $fd $Preferences
	}
	catch { close $fd }
}


proc InitCache {} {
	variable HDFCache {}
	variable HDFCacheFile {}
	variable HDFCacheDirty false
	variable profiledir

	if {$profiledir == {} } {
		set HDFCacheFile {}
		puts "No persistent Cache"
	} else {
		set HDFCacheFile [file join $profiledir HDFClassCache.dict]
		ReadCache
	}
}

proc SaveCache {} {
	variable HDFCache
	variable HDFCacheFile
	variable HDFCacheDirty

	if {!$HDFCacheDirty || ($HDFCacheFile == {})} { return }
	
	if {[catch {
		set fd [open $HDFCacheFile w]
		fconfigure $fd -translation binary -encoding binary
		puts -nonewline $fd $HDFCache
		close $fd
	}]} {
		# error - maybe cleanup fd
		if {[info exists fd]} { catch {close $fd} }
		set HDFCacheFile {}
	}	
}

proc ReadCache {} {
	variable HDFCache
	variable HDFCacheFile
	if {[catch {
		set fd [open $HDFCacheFile r]
		fconfigure $fd -translation binary -encoding binary
		set HDFCache [read $fd]
		close $fd
	}]} {
		# error - maybe cleanup fd
		# cache file remains valid - maybe simply didn't exist
		if {[info exists fd]} { catch {close $fd} }
	}	
}

proc ChooseColumns {columns} {
	variable w
	variable ns
	variable ColumnTraits
	variable ActiveColumns $columns

	set columnopts {}

	foreach col $columns {
		if {[dict exists $ColumnTraits $col Display]} {
			lappend columnopts [dict get $ColumnTraits $col Display]
		} else {
			if {[dict exists $ColumnTraits $col FormatString]} {
				set formatString [dict get $ColumnTraits $col FormatString]
			} else {
				set formatString %.4g
			}

			lappend columnopts [list -sortmode dictionary -formatcommand [list ${ns}::ListFormat $formatString]]
		}
	}

	$w(filelist) configure -columns $columns -columnoptions $columnopts

}

proc DirColumnMoved {columns} {
	# Columns were interactively changed 
	# just accept new setting
	variable ActiveColumns $columns
}


proc ColumnEdit {} {
	variable ActiveColumns
	set ColumnsAvailableTree [PreferenceGet ColumnsAvailableTree {{GROUP General {{LIST {Motor Detector Modified}}}} {GROUP Motors {{LIST {Energy}}}}}]
	set columns [ListEditor getList -initiallist $ActiveColumns -valuetree $ColumnsAvailableTree -title "Select columns"]
	if {$columns != $ActiveColumns} {
		ChooseColumns $columns
		PreferenceSet Columns $columns 
	}
}

proc ClassifyHDF {type fn} {
	variable w
	variable HDFCache
	variable ActiveColumns
	
	if {[catch {file mtime $fn} mtime]} {
		# could not get mtime - something is wrong
		set result [lrepeat [llength $ActiveColumns] {}]
		lappend result [IconGet unknown]
		return $result
	}

	if {$type == "directory"} {
		# for directories, only check the mtime if requested
		foreach col $ActiveColumns {
			if {$col == "Modified"} {	
				lappend result $mtime
			} else {
				lappend result ""
			}
		}
		lappend result "" ;# icon handled by dirViewer
		return $result
	}


	set cachemiss false
	# check cache
	if {[dict exists $HDFCache $fn]} {
		set cached [dict get $HDFCache $fn]
		set class [dict get $cached class]
	} else {
		set cached {}
	}

	# loop over requested columns. 
	set result {}
	foreach col $ActiveColumns {
		# 1. check cache
		if {[dict exists $cached $col] && !$cachemiss} {
			lappend result [dict get $cached $col]
			continue
		}

		# 2. if we get here, either the value could not be found in the cache 
		# or cachemiss == true, i.e. we have already read the file
		if {!$cachemiss} {
			# first time we have a cache miss -- try to read the file
			if {[catch {bessy_reshape $fn} temphdfdata]} {
				puts "Error reading hdf file $fn"
				set temphdfdata {}

			}
			
			lassign [bessy_class $temphdfdata] class motor detector
			
			# don't check cache for this file any longer
			set cachemiss true
		}

		# 3. try to get the value from temphdfdata and feed back to cache

		switch $col {
			Motor {
				set value $motor
			}

			Detector {
				set value $detector
			}

			Modified {
				set value $mtime
			}

			default {
				set value [bessy_get_field $temphdfdata $col]
			}
		}

		lappend result $value

		# mark cache dirty and write back value
		variable HDFCacheDirty true
		dict set HDFCache $fn $col $value
	}

	if {$cachemiss} {
		# write back class to cacha
		dict set HDFCache $fn class $class
	}
	

	# last column is always the icon for the class
	switch $class {
		MCA {
			lappend result [IconGet mca]
		}

		MULTIPLE_IMG {
			lappend result [IconGet image-multiple]
		}

		SINGLE_IMG {
			lappend result [IconGet image-x-generic]
		}

		PLOT {
			lappend result [IconGet graph]
		}

		UNKNOWN {
			lappend result [IconGet unknown]
		}
		
		default {
			variable HDFCacheFile
			error "Unknown file class '$class'. Should not happen - maybe delete your cache file \n $HDFCacheFile\n and restart."
		}
	}

	return $result
}

proc PreviewFile {files} {
	# get selected file from list
	variable w
	variable HDFFiles $files

	switch [llength $files]  {

		0 {
			# nothing selected
			return
		}

		1 {
			# focus on one single file - plot this
			variable hdfdata [bessy_reshape [lindex $files 0]]
			variable plotdata {}

			# select the motor/det 
			variable xformat
			variable yformat
			lassign [bessy_class $hdfdata] type xformat yformat
			
			if {$type == "MCA"} {
				set xformat Row
				set yformat MCA
				$w(xent) configure -values {Row}
				$w(yent) configure -values {MCA}
				$w(xent) state !disabled
				$w(yent) state !disabled
				set plotdata $hdfdata
			} else {

				# insert available axes into axis choosers
				if {[catch {
					set motors [dict keys [dict get $hdfdata Motor]]
					set detectors [dict keys [dict get $hdfdata Detector]]
					set axes $motors
					lappend axes {*}$detectors

					$w(xent) configure -values $motors 
					$w(yent) configure -values $detectors
					$w(xent) state !disabled
					$w(yent) state !disabled

					set plotdata [dict merge [dict get $hdfdata Motor] [dict get $hdfdata Detector]]
				}]} {
					# could not get sensible plot axes - not BESSY hdf?
					$w(xent) configure -values {}
					$w(yent) configure -values {}
					$w(xent) state disabled
					$w(yent) state disabled

					return 
				}
			}
				
			# compute maximum data length
			variable plotdatalength 0
				dict for {var entry} $plotdata {
				set plotdatalength [tcl::mathfunc::max $plotdatalength [llength [dict get $entry data]]]
			}

			# create Row column from first key of data
			set rowdata {}
			for {set i 0} {$i<$plotdatalength} {incr i} {
				lappend rowdata $i
			}

			dict set rowdict Row data $rowdata
			set plotdata [dict merge $rowdict $plotdata]
			
			# reshape plotdata into table form
			MakeTable
			
			wm title . "BessyHDFViewer - [lindex $files 0]"

			InvalidateDisplay
			ReDisplay
		}

		default {
			# multiple files selected - prepare for batch work
			$w(xent) state disabled
			$w(yent) state disabled
		}
	}
}

proc MakeTable {} {
	# reformat plotdata into table
	# compute maximum length for each data column - might be different due to BESSY_INF trimming
	variable plotdatalength
	variable plotdata
	variable tbldata
	variable tblheader [dict keys $plotdata]

	set tbldata {}
	for {set i 0} {$i<$plotdatalength} {incr i} {
		set line {}
		foreach {var entry} $plotdata {
			lappend line [lindex [dict get $entry data] $i]
		}
		lappend tbldata $line
	}
}


proc DumpAttrib {data {indent ""}} {
	set result ""
	dict for {key val} $data {
		append result "# ${indent}${key}\t = ${val}\n"
	}
	return $result
}

proc Dump {hdfdata} {
	# create readable ASCII representation of Bessy HDF files
	set result ""


	if {[dict exists $hdfdata MCA]} {
		# MCA file, has only one key with attribs and data
		append result "# MCA:\n"
		append result [DumpAttrib [dict get $hdfdata MCA attrs] \t]
		append result "# Channel\tcounts\n"
		set ch 0
		foreach v [dict get $hdfdata MCA data] {
			append result "$ch\t$v\n"
			incr ch
		}

		return $result
	}

	if {[dict exists $hdfdata Motor]} {
		# usual scan
		foreach key {MotorPositions DetectorValues OptionalPositions Plot} {
			if {[dict exists $hdfdata $key]} {
				append result "# $key:\n"
				append result [DumpAttrib [dict get $hdfdata $key] \t]
				append result "#\n"
			}
		}

		set motors [dict keys [dict get $hdfdata Motor]]
		set detectors [dict keys [dict get $hdfdata Detector]]
		set variables [list {*}$motors {*}$detectors]
		set table [dict merge [dict get $hdfdata Motor] [dict get $hdfdata Detector]]


		# write header line
		append result "# Motors:\n"
		foreach motor $motors {
			append result "# \t$motor:\n"
			append result [DumpAttrib [dict get $table $motor attrs] \t\t]
		}
		append result "# Detectors:\n"
		foreach detector $detectors {
			append result "# \t$detector:\n"
			append result [DumpAttrib [dict get $table $detector attrs] \t\t]
		}

		append result "# [join $variables \t]\n"
		
		# compute maximum length for each data column - might be different due to BESSY_INF trimming
		set maxlength 0
		dict for {var entry} $table {
			set maxlength [tcl::mathfunc::max $maxlength [llength [dict get $entry data]]]
		}
		for {set i 0} {$i<$maxlength} {incr i} {
			set line {}
			foreach {var entry} $table {
				lappend line [lindex [dict get $entry data] $i]
			}
			append result "[join $line \t]\n"
		}

		return $result
	}

	# if we are here, it is not a BESSY HDF file. Dump the internal representation
	dict format $hdfdata
}

proc DumpToFile {hdf dat} {
	set dump "# $hdf\n"
	append dump [Dump [bessy_reshape $hdf]]

	if {[catch {
		set fd [open $dat w]
		fconfigure $fd -encoding binary -translation binary
		puts $fd $dump
		close $fd
	} err]} {
		catch { close $fd }
		return -code error $err
	}
}
	
proc DumpCmd {} {
	# when pressing the export button
	variable HDFFiles
	set nfiles [llength $HDFFiles]

	if {$nfiles==1} {
		# when a single file is selected, prompt for file name
		set initialfile "[file rootname [file tail [lindex $HDFFiles 0]]].dat"
		set initialdir [file dirname [lindex $HDFFiles 0]]
		set datfn [tk_getSaveFile -filetypes { {{ASCII data files} {.dat}} {{All files} {*}}} \
			-defaultextension .dat \
			-title "Export HDF file to ASCII" \
			-initialfile $initialfile \
			-initialdir $initialdir]
		if {$datfn != {}} {
			DumpToFile [lindex $HDFFiles 0] $datfn
		}
	} else {
		if {$nfiles > 0} {
			# multiple files selected - prompt for directory
			set initialdir [file dirname [lindex $HDFFiles 0]]
			set outputdir [tk_getDirectory -title "Select directory to export $nfiles HDF files to ASCII" \
				-initialdir $initialdir -filetypes { {{HDF files} {.hdf}} {{ASCII data files} {.dat}} {{All files} {*}}} ]
			if {$outputdir != {}} {
				foreach hdf $HDFFiles {
					set roottail [file rootname [file tail $hdf]]
					DumpToFile $hdf [file join $outputdir $roottail.dat]
				}
			}
		}
	}
}


proc DisplayPlot {} {
	variable w
	variable plotdata
	variable xformat
	variable yformat

	# plot the data 
	set xdata [dict get $plotdata $xformat data]
	set ydata [dict get $plotdata $yformat data]

	set data [zip $xdata $ydata]

	variable plotid
	if {[info exists plotid]} {
		$w(Graph) remove $plotid
	}

	if {[llength $data] >= 4} {
		if {[catch {dict get $plotdata $xformat attrs Unit} xunit]} {
			$w(Graph) configure -xlabel "$xformat"
		} else {
			$w(Graph) configure -xlabel "$xformat ($xunit)"
		}
		
		if {[catch {dict get $plotdata $yformat attrs Unit} yunit]} {
			$w(Graph) configure -ylabel "$yformat"
		} else {
			$w(Graph) configure -ylabel "$yformat ($yunit)"
		}

		set plotid [$w(Graph) connectpoints_autodim $data black]
		lappend plotid [$w(Graph) showpoints $data red circle]
		$w(Graph) autoresize
	}

	ValidateDisplay Plot
}

proc DisplayTextDump {} {
	# put the contents of the file into the text display
	variable hdfdata
	variable w
	$w(textdump) delete 1.0 end
	$w(textdump) insert end [Dump $hdfdata]
	ValidateDisplay Text 
}

proc DisplayTable {} {
	variable w
	variable plotdata
	variable plotdatalength
	variable tbldata
	variable tblheader
	
	foreach var $tblheader {
		lappend columns 0 $var left
	}
	$w(tbltbl) configure -columns $columns

	$w(tbltbl) delete 0 end
	$w(tbltbl) insertlist 0 $tbldata
	ValidateDisplay Table
}

proc DisplayTree {} {
	variable w
	variable hdfdata
	variable HDFFiles
	
	# create dictionary for values of standard motors etc.
	set values {}
	
	foreach key {MotorPositions DetectorValues OptionalPositions Plot} {
		if {[dict exists $hdfdata $key]} {
			set values [dict merge $values [dict get $hdfdata $key]]
		}
	}

	lassign [bessy_class $hdfdata] class motor detector
	set mtime [file mtime [lindex $HDFFiles 0]]

	dict set values class $class
	dict set values Motor $motor
	dict set values Detector $detector
	dict set values Modified [list [formatDate $mtime]]

	# save expansion state 
	set expandedkeys [$w(treetbl) expandedkeys]
	set yview [$w(treetbl) yview]
	set sel [$w(treetbl) curselection]
	$w(treetbl) delete 0 end
	SmallUtils::TablelistMakeTree $w(treetbl) [PreferenceGet ColumnsAvailableTree {}] $values

	# restore expansion state
	foreach key $expandedkeys {
		$w(treetbl) expand $key -partly
	}
	$w(treetbl) yview moveto [lindex $yview 0]
	$w(treetbl) selection set $sel
	ValidateDisplay Tree
}

proc InvalidateDisplay {} {
	variable displayvalid
	dict set displayvalid Plot 0
	dict set displayvalid Text 0
	dict set displayvalid Table 0
	dict set displayvalid Tree 0
}

proc ValidateDisplay {what} {
	variable displayvalid
	if {$what=="all"} {
		foreach display {Plot Text Table Tree} {
			ValidateDisplay $display
		}
	} else {
		dict set displayvalid $what 1
	}
}

proc ReDisplay {} {
	variable w
	variable displayvalid
	set index [$w(displayfr) index [$w(displayfr) select]]
	# ttk::notebook returns the widget name, convert to title
	set display [$w(displayfr) tab $index -text]

	# this mixes user-visible strings with commands
	# don'T want to condense (i.e. Display$display)
	switch $display {
		Plot {
			if {![dict get $displayvalid Plot]} {
				DisplayPlot
			}
		}
		Text {
			if {![dict get $displayvalid Text]} {
				DisplayTextDump
			}
		}
		Table {
			if {![dict get $displayvalid Table]} {
				DisplayTable
			}
		}
		Tree {
			if {![dict get $displayvalid Tree]} {
				DisplayTree
			}
		}
		default {
			error "Unknown data display method $display"
		}
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

proc OpenStart {max} {
	variable w
	variable ProgressClock [clock milliseconds]
	variable ProgressDelay 200 ;# only after 200ms one feels a delay
	$w(progbar) configure -maximum $max
	tk_busy hold .
}

proc OpenProgress {i} {
	variable w
	$w(progbar) configure -value $i
	set now [clock milliseconds]
	variable ProgressClock
	variable ProgressDelay
	if {$now - $ProgressClock > $ProgressDelay} {
		set ProgressClock $now
		set ProgressDelay 20 
		# update progress bar after each 20ms
		update
	}
}

proc OpenFinished {} {
	variable w
	$w(progbar) configure -value 0
	tk_busy forget .
	SaveCache
}

proc formatDate {date} {
	if {$date == {}} {
		return "Not known"
	} {
		clock format $date -format {%Y-%m-%d %H:%M}
	}
}

proc ListFormat {formatString what} {
	# try to do sensible formatting
	# what might be a two-element list for min/max
	if {[string is list $what]} {
		# two-element list for min/max
		if {[llength $what] ==2} {
			lassign $what min max
			return "[ListFormat $formatString $min] \u2014 [ListFormat $formatString $max]"
		}

		# single double value
		if {[string is double -strict $what]} {
			return [format $formatString $what]
		}

		# string
		return $what
	} else {
		return $what
	}
}

proc FoldPlotCmd {} {
	variable w
	variable PlotFolded
	if {$PlotFolded} {
		$w(mainfr) add $w(displayfr)
		$w(foldbut) configure -image [IconGet fold-open]
		set PlotFolded false
	} else {
		$w(mainfr) forget $w(displayfr)
		$w(foldbut) configure -image [IconGet fold-close]
		set PlotFolded true
	}
}

proc SELECT {fmtlist fnlist} {
	set result {}
	foreach fn $fnlist {
		# read HDF file 
		set data [bessy_reshape $fn]

		# set common values 
		namespace eval ::SELECT [list set HDF $fn]

		foreach key {MotorPositions DetectorValues OptionalPositions} {
			if {[dict exists $data $key]} {
				dict for {key value} [dict get $data $key] {
					namespace eval ::SELECT [list set $key $value]
				}
			}
		}

		set table [dict merge [dict get $data Motor] [dict get $data Detector]]
		
		# compute maximum length for each data column - might be different due to BESSY_INF trimming
		set maxlength 0
		dict for {var entry} $table {
			set maxlength [tcl::mathfunc::max $maxlength [llength [dict get $entry data]]]
		}

		for {set i 0} {$i<$maxlength} {incr i} {
			foreach {var entry} $table {
				namespace eval ::SELECT [list set $var [lindex [dict get $entry data] $i]]
			#	puts "Setting $var to [lindex [dict get $entry data] $i]"
			}

			set line {}
			foreach fmt $fmtlist {
				if {[catch {namespace eval ::SELECT [list expr $fmt]} lresult]} {
					# expr handles NaN in many different ways by throwing errors:(
					if {[regexp {Not a Number|domain error|non-numeric} $lresult]} { set lresult NaN }
				}
				lappend line $lresult
			}
			lappend result $line
		}
	}

	return $result
}

proc bessy_reshape {fn} {

	autovar hdf HDFpp %AUTO% $fn
	set hlist [$hdf dump]
	
	set BESSY_INF 9.9e36
	set BESSY_NAN -7.7e36

	set datakeys {}
	set maxindex -1
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
			lappend datakeys $key
			set data [dict get $dataset data]
			set index 0
			foreach v $data {
				if {abs($v) >= $BESSY_INF || $v == $BESSY_NAN} {
					# invalid data point, replace by NaN
					lset data $index NaN
				} else {
					if {$index > $maxindex} {
						set maxindex $index
					}
				}
				incr index
			}

			dict set dataset data $data
		}

		dict set hdict {*}$key $dataset
	}

	# shorten all data sets to max length
	foreach key $datakeys {
		set data [dict get $hdict {*}$key data]
		dict set hdict {*}$key data [lrange $data 0 $maxindex]
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
		if {[catch {lindex [dict keys [dict get $data Motor]] 0} motor]} {
			set motor {}
		}
	}
		
	if {[catch {dict get $data Plot Detector} detector]} {
		set Plot false
		if {[catch {lindex [dict keys [dict get $data Detector]] 0} detector]} {
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

proc bessy_get_field {hdfdata field} {
	# try to read a single value from dictionaries
	
	set values {}

	foreach datakey {Detector Motor} {
		# keys that are tried to find data
		if {[dict exists $hdfdata $datakey $field data]} {
			lappend values {*}[dict get $hdfdata $datakey $field data]
		}
	}

	foreach attrkey {DetectorValues MotorPositions OptionalPositions Plot} {
		# keys that might store the field as a single value in the attrs
		if {[dict exists $hdfdata $attrkey $field]} {
			lappend values [dict get $hdfdata $attrkey $field]
		}
	}
	
	if {[llength $values] <= 1} {
		# found nothing or single value - just return that
		return [lindex $values 0]
	}

	# if more than one value is found, compute range 
	# first try sorting as numbers, then try dictionary (works always)
	if {[catch {lsort -real [filternan $values]} sortedvalues]} {
		set sortedvalues [lsort -dictionary $values]
	}

	set minval [lindex $sortedvalues 0]
	set maxval [lindex $sortedvalues end]
	if {$minval == $maxval} {
		return [list $minval]
	} else {
		return [list $minval $maxval]
	}
}

proc ::tcl::mathfunc::isnan {x} {
	expr {$x != $x}
}

proc filternan {l} {
	# return list where all NaN values are removed
	set result {}
	foreach v $l {
		if {!isnan($v)} {
			lappend result $v
		}
	}
	return $result
}

proc autovar {var args} {
	upvar 1 $var v
	set v [uplevel 1 $args]
	trace add variable v unset [list autodestroy $v]
}

proc autodestroy {cmd args} {
	# puts "RAII destructing $cmd"
	rename $cmd ""
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


Init
