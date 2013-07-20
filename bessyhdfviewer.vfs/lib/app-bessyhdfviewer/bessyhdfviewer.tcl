package provide app-bessyhdfviewer 1.0


package require hdfpp
package require ukaz
package require Tk
package require tablelist_tile 5.9

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

	# trigger opening of files from Mac OSX signal
	proc ::tk::mac::OpenDocument {args} {
		OpenArgument $args
	}
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
set tkcon::PRIV(protocol) {tkcon hide}
set tkcon::OPT(exec) ""

namespace eval BessyHDFViewer {
	variable ns [namespace current]
	variable basedir [file dirname [info script]]


	# load support modules
	foreach module {dirViewer.tcl listeditor.tcl hformat.tcl exportdialog.tcl autocomplete.tcl dataevaluation.tcl} {
		namespace eval :: [list source [file join $basedir $module]]
	}

	proc Init {argv} {
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

		if {[llength $argv] != 0 && [tk windowingsystem] != "aqua"} {
			# start arguments
			OpenArgument $argv
		}
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
		
		variable browsepath [PreferenceGet HomeDir {/messung/}]
		if {![file isdirectory $browsepath]} {
			set browsepath [file normalize [pwd]]
		}

		bind $w(pathent) <FocusOut> ${ns}::DirUpdate
		bind $w(pathent) <Key-Return> ${ns}::DirUpdate

		set w(filelist) [dirViewer::dirViewer $w(listfr).filelist $browsepath \
			-classifycommand ${ns}::ClassifyHDF \
			-selectcommand ${ns}::PreviewFile \
			-globpattern {*.hdf *.h5} \
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
		set w(dumpButton) [ttk::button $w(bbar).dumpbut -command ${ns}::ExportCmd -text "Export" -image [IconGet document-export] -compound left]

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
		set w(toolbar) [ttk::frame $w(plotfr).toolbar]

		set w(canv) [canvas $w(plotfr).c -background white]
		set w(legend) [ttk::label $w(plotfr).frame]
		

		grid $w(axebar) -sticky nsew
		grid $w(toolbar) -sticky nsew
		grid $w(canv) -sticky nsew
		grid $w(legend) -sticky nsew
		grid columnconfigure $w(plotfr) 0 -weight 1
		grid rowconfigure $w(plotfr) $w(canv) -weight 1

		# pointer info. Series of labels

		foreach {wid desc var } {
			xlb "x: " xv 
			ylb "y: " yv 
			nrlb "Point: " cnr 
			cxlb "x: " cx
			cylb "y: " cy } {
			set w(point.$wid) [ttk::label $w(legend).$wid -text $desc]
			set w(point.$var) [ttk::label $w(legend).$var -textvariable ${ns}::pointerinfo($var) -width 10]

			pack $w(point.$wid) $w(point.$var) -anchor w -side left
		}
		
		set w(xlbl) [ttk::label $w(axebar).xlbl -text "X axis:"]
		set w(xent) [ttk::combobox $w(axebar).xent -textvariable ${ns}::xformat -exportselection 0]
		set w(ylbl) [ttk::label $w(axebar).ylbl -text "Y axis:"]
		set w(yent) [ttk::combobox $w(axebar).yent -textvariable ${ns}::yformat -exportselection 0]
		set w(keepformat) [ttk::checkbutton $w(axebar).keepformat -variable ${ns}::keepformat -text "Keep format"]
		variable keepformat false
		
		bind $w(xent) <<ComboboxSelected>> [list ${ns}::DisplayPlot -explicit true]
		bind $w(yent) <<ComboboxSelected>> [list ${ns}::DisplayPlot -explicit true]
		AutoComplete $w(xent) -aclist {Energy Row}
		AutoComplete $w(yent) -aclist {Energy Row}
		bind $w(xent) <Return> [list ${ns}::DisplayPlot -explicit true -focus x]
		bind $w(yent) <Return> [list ${ns}::DisplayPlot -explicit true -focus y]
		bind $w(xlbl) <1> ${ns}::ConsoleShow

		grid $w(xlbl) $w(xent) $w(ylbl) $w(yent) $w(keepformat) -sticky ew
		grid columnconfigure $w(axebar) 1 -weight 1
		grid columnconfigure $w(axebar) 3 -weight 1

		# Graph
		set w(Graph) [ukaz::box %AUTO% $w(canv)]
		bind [$w(Graph) getcanv] <<MotionEvent>> [list ${ns}::UpdatePointerInfo motion %d]
		$w(Graph) bind <1> [list ${ns}::UpdatePointerInfo click]
		
		# Toolbar: Peak detection button
		
		set w(peakbtn) [ttk::button $w(toolbar).peakbtn -text "Peak detection" -image [IconGet peakdetect] \
						-command DataEvaluation::FindPeaks -style Toolbutton]

		grid $w(peakbtn) -sticky nw

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
		
		#update
		# bug in tablelist? Creation blocks if update is left out
		# no, bug in tkcon :(

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
		
		# Difference display tab
		#
		set w(difffr) [ttk::frame $w(displayfr).difffr]
		set w(difftbl) [tablelist::tablelist $w(difffr).tbl \
			-movablecolumns yes -setgrid no -showseparators yes \
			-exportselection 0 -selectmode single -stretch end \
			-columns {0 Variable left 0 Value1 left 0 Value2 left}]

		set w(diffvsb) [ttk::scrollbar $w(difffr).vsb -orient vertical -command [list $w(difftbl) yview]]
		set w(diffhsb) [ttk::scrollbar $w(difffr).hsb -orient horizontal -command [list $w(difftbl) xview]]
		$w(difftbl) configure -xscrollcommand [list $w(diffhsb) set] -yscrollcommand [list $w(diffvsb) set]
		
		grid $w(difftbl) $w(diffvsb) -sticky nsew
		grid $w(diffhsb)  x           -sticky nsew

		grid columnconfigure $w(difffr) 0 -weight 1
		grid rowconfigure $w(difffr) 0 -weight 1

		$w(displayfr) add $w(difffr) -text "Diff"
		

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
		set columns [ListEditor getList -initiallist $ActiveColumns -valuetree $ColumnsAvailableTree -title "Select columns" -parent .]
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
		if {[dict exists $HDFCache $fn Modified] && $mtime == [dict get $HDFCache $fn Modified] } {
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
				
				dict_assign [bessy_class $temphdfdata] class motor detector nrows
				
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

				NRows {
					set value $nrows
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
			# write back class & mtime to cache
			dict set HDFCache $fn class $class
			dict set HDFCache $fn Modified $mtime
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
		variable BessyClass

		switch [llength $files]  {

			0 {
				# nothing selected
				set BessyClass {class {} axes {} motors {} detectors {} motor {} detector {}}
				wm title . "BessyHDFViewer"
			}

			1 {
				# focus on one single file - display this
				variable hdfdata [bessy_reshape [lindex $files 0]]

				# select the motor/det
				set BessyClass [bessy_class $hdfdata]
				dict_assign $BessyClass class motor detector motors detectors

				if {$class == "MCA"} {
					$w(xent) configure -values {Row}
					$w(yent) configure -values {MCA}
					$w(xent) state !disabled
					$w(yent) state !disabled
				} else {

					# insert available axes into axis choosers
					if {[catch {
						
						$w(xent) configure -values $motors
						$w(yent) configure -values $detectors
						$w(xent) state !disabled
						$w(yent) state !disabled

					} err]} {
						# could not get sensible plot axes - not BESSY hdf?
						puts $err

						$w(xent) configure -values {}
						$w(yent) configure -values {}
						$w(xent) state disabled
						$w(yent) state disabled

						return 
					}
				}
				
				# reshape plotdata into table form
				MakeTable
				
				wm title . "BessyHDFViewer - [lindex $files 0]"

			}

			default {
				# multiple files selected - prepare for batch work
				set BessyClass {class {} axes {} motors {} detectors {} motor {} detector {}}
				wm title . "BessyHDFViewer"
			}
		}
		InvalidateDisplay
		ReDisplay
	}

	proc MakeTable {} {
		# reformat plotdata into table
		# compute maximum length for each data column - might be different due to BESSY_INF trimming
		variable BessyClass
		variable hdfdata 

		variable plotdata
		variable tbldata
		variable tblheader 
		
		if {[dict get $BessyClass class] == "MCA"} {
			set plotdata [list MCA [dict get $hdfdata MCA]]
		} else {
			# insert available axes into plotdata
			if {[catch {
				set plotdata [dict merge [dict get $hdfdata Motor] [dict get $hdfdata Detector]]
			} err]} {
				# could not get sensible plot axes - not BESSY hdf?
				puts $err
				return 
			}
		}

		set tblheader Row
		lappend tblheader {*}[dict keys $plotdata]
		set tbldata {}
		for {set i 0} {$i<[dict get $BessyClass nrows]} {incr i} {
			set line $i
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

	proc Dump {hdfdata {headerfmt {Attributes Columns}}} {
		# create readable ASCII representation of Bessy HDF files
		set result ""

		# look for global attributes
		if {[dict exists $hdfdata {}] && "Attributes" in $headerfmt} {
			# bessy_reshape put the attributes directly under {}
			append result [DumpAttrib [dict get $hdfdata {}]]
			append result "#\n"
		}
		if {[dict exists $hdfdata MCA]} {
			# MCA file, has only one key with attribs and data
			if {"Attributes" in $headerfmt} {
				append result "# MCA:\n"
				append result [DumpAttrib [dict get $hdfdata MCA attrs] \t]
			}
			if {"Columns" in $headerfmt} {
				append result "# Channel\tcounts\n"
			}
			if {"BareColumns" in $headerfmt} {
				append result "Channel\tcounts\n"
			}
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
				if {[dict exists $hdfdata $key] && "Attributes" in $headerfmt} {
					append result "# $key:\n"
					append result [DumpAttrib [dict get $hdfdata $key] \t]
					append result "#\n"
				}
			}

			set motors [dict keys [dict get $hdfdata Motor]]
			set detectors [dict keys [dict get $hdfdata Detector]]
			set variables [list {*}$motors {*}$detectors]
			set table [dict merge [dict get $hdfdata Motor] [dict get $hdfdata Detector]]


			# write header lines
			if {"Attributes" in $headerfmt} {
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
			}

			if {"Columns" in $headerfmt} {
				append result "# [join $variables \t]\n"
			}
			if {"BareColumns" in $headerfmt} {
				append result "[join $variables \t]\n"
			}
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
		hformat $hdfdata
	}
		
	proc ExportCmd {} {
		# when pressing the export button
		variable HDFFiles

		set nfiles [llength $HDFFiles]
		set aclist [bessy_get_keys_flist $HDFFiles]
		set suggestion [bessy_get_keys_flist $HDFFiles Axes]
		lappend aclist HDF
		set choice [ExportDialog show -files $HDFFiles \
			-aclist $aclist \
			-format [PreferenceGet ExportFormat $suggestion] \
			-suggestion $suggestion \
			-stdformat [PreferenceGet StdExportFormat true] \
			-grouping [PreferenceGet ExportGrouping false] \
			-groupby [PreferenceGet ExportGroupBy {}] \
			-headerfmt [PreferenceGet HeaderFormat {Attributes Columns Filename}] \
			-title "Export $nfiles files to ASCII" -parent .]
		
		if {$choice == {}} {
			# dialog was cancelled
			return
		}

		# write back settings to prefs
		PreferenceSet ExportFormat [dict get $choice format]
		PreferenceSet ExportGrouping [dict get $choice grouping]
		PreferenceSet ExportGroupBy [dict get $choice groupby]
		PreferenceSet StdExportFormat [dict get $choice stdformat]
		PreferenceSet HeaderFormat [dict get $choice headerfmt]
		
		set singlefile [dict get $choice singlefile]
		set stdformat [dict get $choice stdformat]
		set headerfmt [dict get $choice headerfmt]
		set grouping  [dict get $choice grouping]
		set groupby [dict get $choice groupby]
		

		if {$stdformat} {
			# Text dump
			if {$singlefile} {
				SmallUtils::autofd fd [dict get $choice path] wb
			}

			foreach hdf $HDFFiles {
				if {!$singlefile} {
					# in case of multiple files, open separately for each 
					# HDF input file. Path is the dirname then
					set roottail [file rootname [file tail $hdf]]
					SmallUtils::autofd fd [file join [dict get $choice path] $roottail.dat] wb
				}

				# read HDF
				set hdfdata [bessy_reshape $hdf]
				if {"Filename" in $headerfmt} {
					puts $fd "# $hdf"
				}
				puts $fd [Dump $hdfdata $headerfmt]
			}
		}  else {
			# formatted output
			set format [dict get $choice format]
			if {$singlefile} {
				SmallUtils::autofd fd [dict get $choice path] wb
				if {"Filename" in $headerfmt} {
					foreach hdf $HDFFiles {
						puts $fd "# $hdf"
					}
				}

				if {"Columns" in $headerfmt} {
					if {$grouping} {
						puts $fd "# [join $groupby \t]"
					}
					puts $fd "# [join $format \t]"
				}
				
				if {"BareColumns" in $headerfmt} {
					puts $fd "[join $format \t]"
				}

				set data [SELECT $format $HDFFiles -allnan true]
				if {$grouping} {
					set data [GROUP_BY $data $groupby]
				}	
				puts $fd [deepjoin $data \t \n]

			} else {
				# individual files
				foreach hdf $HDFFiles {
					set roottail [file rootname [file tail $hdf]]
					SmallUtils::autofd fd [file join [dict get $choice path] $roottail.dat] wb
					if {"Filename" in $headerfmt} {
						puts $fd "# $hdf"
					}
					if {"Columns" in $headerfmt} {
						if {$grouping} {
							puts $fd "# [join $groupby \t]"
						}
						puts $fd "# [join $format \t]"
					}
					if {"BareColumns" in $headerfmt} {
						puts $fd "[join $format \t]"
					}
					set data [SELECT $format $hdf -allnan true]
					if {$grouping} {
						set data [GROUP_BY $data $groupby]
					}
					puts $fd [deepjoin $data \t \n]

				}
			}
		}
	}

	set pointerinfo(clickx) ""
	set pointerinfo(clicky) ""
	proc UpdatePointerInfo {action args} {
		# callback for mouse events on canvas
		variable pointerinfo
		variable w
		switch $action {
			motion {
				lassign $args coords
				lassign $coords x y
				set pointerinfo(x) $x
				set pointerinfo(y) $y
				set pointerinfo(xv) [format %8.5g $x]
				set pointerinfo(yv) [format %11.5g $y]
			}

			click {
				lassign $args nr tag
				set coords [$w(Graph) getpointfromtag $tag $nr]
				set pointerinfo(cnr) $nr
				if {[llength $coords] == 2} {
					lassign $coords x y
					set pointerinfo(clickx) $x
					set pointerinfo(clicky) $y
					set pointerinfo(cx) [format %8.5g $x]
					set pointerinfo(cy) [format %8.5g $y]
				} else {
					set pointerinfo(cx) ""
					set pointerinfo(cy) ""
				}
			}
		}
	}



	variable plotstylecache {}
	variable formathistory [dict create x {} y {}] ; # 
	proc DisplayPlot {args} {
		variable w
		variable plotdata
		variable hdfdata
		variable HDFFiles
		variable xformat
		variable yformat
		variable keepformat

		variable plotstylecache
		variable formathistory
		
		# parse arg
		set defaults [dict create -explicit false -focus {}]
		set opts [dict merge $defaults $args]
		if {[dict size $opts] != [dict size $defaults]} {
			return -code error "DisplayPlot ?-explicit bool? ?-focus x|y?"
		}

		set explicit [dict get $opts -explicit]
		set focus [dict get $opts -focus]

		variable plotid
		if {[info exists plotid]} {
			$w(Graph) reset_dimensioning
			$w(Graph) clear
			set plotid {}
		}

		set nfiles [llength $HDFFiles]
		if {$nfiles==0} { return }
		# nothing to plot

		if {$nfiles == 1} {
			# check the data already read for plot axis 
			# and enable/disable the axis format choosers appropriately
			variable BessyClass
			dict_assign $BessyClass class motor detector motors detectors axes
			if {$class == "MCA"} {
				set xformatlist {Row}
				set yformatlist {MCA}
				$w(xent) state !disabled
				$w(yent) state !disabled
				set stdx Row
				set stdy MCA
			} elseif {$axes!= {}} {
				# insert available axes into axis choosers
				set xformatlist $motors
				set yformatlist $detectors
				$w(xent) state !disabled
				$w(yent) state !disabled
				set stdx $motor
				set stdy $detector
			} else {
				set xformatlist {}
				set yformatlist {}
				$w(xent) state disabled
				$w(yent) state disabled
				$w(Graph) clear
				return
			}

			if {!$explicit && !$keepformat} {
				set xformat $stdx
				set yformat $stdy
			}

		} else {
			# more than one file selected
			set xformatlist {}
			set yformatlist {}
		}

		# append history to format entries
		# if the value in xformat or yformat is no standard axis, add to dropdown list
		if {$explicit && $xformat ne {} && $yformat ne {}} {
			if {$xformat ni $xformatlist} {
				dict unset formathistory x $xformat
				dict set formathistory x $xformat 1
			}

			if {$yformat ni $yformatlist} {
				dict unset formathistory y $yformat
				dict set formathistory y $yformat 1
			}

			# for more than 10 entries, clear format history
			set maxhistsize [PreferenceGet MaxFormatHistorySize 10]
			dict with formathistory {
				while {[dict size $x]>$maxhistsize} { 
					dict unset x [lindex [dict keys $x] 0]
				}
			
				while {[dict size $y]>$maxhistsize} { 
					dict unset y [lindex [dict keys $y] 0]
				}
			}

		}
		
		lappend xformatlist  {*}[lreverse [dict keys [dict get $formathistory x]]]
		lappend yformatlist {*}[lreverse [dict keys [dict get $formathistory y]]]

		$w(xent) configure -values $xformatlist
		$w(yent) configure -values $yformatlist

		if {$explicit && $focus=="x"} {
			focus $w(yent)
			$w(yent) selection range 0 end
			$w(yent) icursor end
		}
		
		if {$explicit && $focus=="y"} {
			focus $w(xent)
			$w(xent) selection range 0 end
			$w(xent) icursor end
		}

		# get units / axis labels for the current plot
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


		set fmtlist [list $xformat $yformat]

		# determine plot styles for the data sets

		# transform available styles into dictionary
		foreach style [PreferenceGet PlotStyles { {line { black } point { red circle }} }] {
			dict set plotstylesfree $style 1
		}

		set styles {}
		foreach fn $HDFFiles {
			if {[dict exists $plotstylecache $fn]} {
				# first reserve all styles with the same style that has been used before
				set style [dict get $plotstylecache $fn]
				dict set styles $fn $style
				dict set plotstylesfree $style 0
			}
		}
		
		# transform free styles into list
		set plotstylesfree [dict keys [dict filter $plotstylesfree value 1]]

		# 2nd pass: alloc styles for remaining files
		foreach fn $HDFFiles {
			if {[llength $plotstylesfree]==0} { break }

			if {![dict exists $styles $fn]} {
				set plotstylesfree [lassign $plotstylesfree style]
				dict set styles $fn $style
			}

		}


		
		# plot the data
		variable pointerinfo
		set extravars [dict create CLICKX $pointerinfo(clickx) CLICKY $pointerinfo(clicky)] 
		set aclist {CLICKX CLICKY Row}
		
		# cache the current data sets in this list
		variable datashown {}

		dict for {fn style} $styles {
			if {$nfiles != 1} {
				# for multiple files, read the content to hdfdata
				# for single file, it's already there
				set hdfdata [bessy_reshape $fn]
			}
				
			# operate on the cached data
			set data [SELECTdata $fmtlist $hdfdata -allnan true -extravars $extravars]
			# reduce to flat list
			set data [concat {*}$data]

			if {[llength $data] >= 2} {
				lappend plotid [$w(Graph) connectpoints_autodim $data {*}[dict get $style line]]
				lappend plotid [$w(Graph) showpoints_autodim $data {*}[dict get $style point]]
			}
			
			lappend datashown $fn $data

			# build up autocomplete list
			lappend aclist {*}[bessy_get_keys $hdfdata]
		}

		set plotstylecache $styles

		if {$plotid != {}} {
			$w(Graph) autoresize
		}
		

		# configure the autocompletion list
		set aclist [lsort -uniq -dictionary $aclist]
		$w(xent) configure -aclist $aclist
		$w(yent) configure -aclist $aclist

		ValidateDisplay Plot
	}

	proc DisplayTextDump {} {
		# put the contents of the file into the text display
		variable HDFFiles
		variable hdfdata
		variable w
		$w(textdump) delete 1.0 end
		if {[llength $HDFFiles]!=1} { return }

		$w(textdump) insert end [Dump $hdfdata]
		ValidateDisplay Text 
	}

	proc DisplayTable {} {
		variable w
		variable tbldata
		variable tblheader
		variable HDFFiles

		$w(tbltbl) delete 0 end
		if {[llength $HDFFiles]!=1} { return }
		
		foreach var $tblheader {
			lappend columns 0 $var left
		}
		$w(tbltbl) configure -columns $columns

		# set sortmode to dictionary for all columns
		for {set col 0} {$col<[llength $tblheader]} {incr col} {
			$w(tbltbl) columnconfigure $col -sortmode dictionary
		}

		$w(tbltbl) insertlist 0 $tbldata
		ValidateDisplay Table
	}

	proc DisplayTree {} {
		variable w
		variable ns
		variable hdfdata
		variable HDFFiles

		if {[llength $HDFFiles]!=1} { return }
		# create dictionary for values of standard motors etc.
		set values {}
		
		foreach key [bessy_get_keys $hdfdata] {
			dict set values $key [list [ListFormat %g [bessy_get_field $hdfdata $key]]]
		}

		dict_assign [bessy_class $hdfdata] class motor detector nrows
		set mtime [file mtime [lindex $HDFFiles 0]]

		dict set values class $class
		dict set values Motor $motor
		dict set values Detector $detector
		dict set values Modified [list [formatDate $mtime]]
		dict set values NRows $nrows

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

	proc DisplayDiff {} {
		variable w
		variable HDFFiles
		$w(difftbl) delete 0 end
		
		# create heading
		set filenames {}
		set data {}
		set columnconfig {0 Variables left}
		foreach fullname $HDFFiles {
			set shortname [file tail $fullname]
			lappend data [bessy_reshape $fullname]
			append columnconfig " 0 $shortname left"
		}

		$w(difftbl) configure -columns $columnconfig

		# make alphabetically sorted list of keys
		set allkeys {Motor {} Detector {} Meta {}}
		foreach category {Motor Detector Meta} {
			foreach dataset $data {
				dict lappend allkeys $category {*}[bessy_get_keys $dataset $category]
			}
		}
		
		dict for {category keys} $allkeys {
			dict set allkeys $category [lsort -dictionary -uniq $keys]
		}

		# compute difference
		foreach category  {Motor Detector Meta} {
			set node [$w(difftbl) insertchild root end [list $category]]
			set diff {}
			foreach key [dict get $allkeys $category] {
				set values {}
				foreach dataset $data {
					lappend values [bessy_get_field $dataset $key]
				}
				if {!allequal($values)} {
					set fmts {}
					foreach value $values {
						lappend fmts [ListFormat %g $value]
					}
					lappend diff [list $key {*}$fmts]
				}
			}
			$w(difftbl) insertchildlist $node end $diff
		}
		ValidateDisplay Diff
	}

	proc InvalidateDisplay {} {
		variable displayvalid
		dict set displayvalid Plot 0
		dict set displayvalid Text 0
		dict set displayvalid Table 0
		dict set displayvalid Tree 0
		dict set displayvalid Diff 0
	}

	proc ValidateDisplay {what} {
		variable displayvalid
		if {$what=="all"} {
			foreach display {Plot Text Table Tree Diff} {
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
		# don't want to condense (i.e. Display$display)
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
			Diff {
				if {![dict get $displayvalid Diff]} {
					DisplayDiff
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
		PreferenceSet HomeDir $dir
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
			PreferenceSet HomeDir $browsepath
		} else {
			tk_messageBox -type ok -icon error -title "Error opening directory" \
				-message $errmsg -detail "when opening '$browsepath'"
		}
	}

	proc OpenArgument {files} {
		variable w
		# take a number of absolute file names
		# navigate to top dir and display
		if {[llength $files]<1} { return }	
		
		# find common ancestor
		set ancestor [SmallUtils::file_common_dir $files]
		$w(filelist) display $ancestor
		$w(filelist) selectfiles $files
		set fileabs [lmap x $files {file normalize $x}]
		PreviewFile $fileabs
	}

	proc OpenStart {max} {
		variable w
		variable ProgressClock [clock milliseconds]
		variable ProgressDelay 100 ;# only after 100ms one feels a delay
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

	proc ::formatDate {date} {
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
				if {![string is double -strict $min] || ![string is double -strict $max]} {
					return "$min \u2014 $max"
				}
				return "[ListFormat $formatString $min] \u2014 [ListFormat $formatString $max]"
			}

			# single double value
			if {[string is double -strict $what]} {
				if {[catch {format $formatString $what} formatresult]} {
					return $what;# error formatting, return string rep
				} else {
					return $formatresult
				}
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

	proc SELECT {fmtlist fnlist args} {
		# "analog" to SQL SELECT
		# open all HDF file in fnlist, join all datasets
		# and compute a table from the expressions in fmtlist
		# optional arguments:
		#   LIMIT n     return at maximum n results
		#  -allnan bool if true, put NaN for every error from expression evaluation
		#               if false, put NaN only from genuine NaNs (0/0, NaN in data...)

		set defaults [dict create LIMIT Inf -allnan false -extravars {}]
		set opts [dict merge $defaults $args]
		if {[dict size $opts] != [dict size $defaults]} {
			return -code error "SELECT formats files ?LIMIT max? ?-allnan boolean? ?-extravars dict?"
		}

		set result {}
		set firstrow 0
		set limit [dict get $opts LIMIT]
		foreach fn $fnlist {
			# read HDF file 
			set data [bessy_reshape $fn]
			
			dict set opts -extravars HDF $fn
			
			set fresult [SELECTdata $fmtlist $data {*}$opts -firstrow $firstrow]
			lappend result {*}$fresult
			incr firstrow [llength $fresult]
			if {$firstrow>=$limit} { break }
		}

		return $result
	}


	proc SELECTdata {fmtlist hdfdata args} {	
		# "analog" to SQL SELECT
		#  compute a table from the expressions in fmtlist
		# optional arguments:
		#   LIMIT n     return at maximum n results
		#  -allnan bool if true, put NaN for every error from expression evaluation
		#               if false, put NaN only from genuine NaNs (0/0, NaN in data...)

		set defaults [dict create LIMIT Inf -allnan false -extravars {} -firstrow 0]
		set opts [dict merge $defaults $args]
		if {[dict size $opts] != [dict size $defaults]} {
			return -code error "SELECTdata formats data ?LIMIT max? ?-allnan boolean? ?-extravars dictvalue? ?-firstrow n?"
		}

		set limit [dict get $opts LIMIT]
		set allnan [dict get $opts -allnan]
		
		set result {}
		set Row [dict get $opts -firstrow]
		# set common values 
		catch {namespace delete ::SELECT}
		namespace eval ::SELECT {} 
		dict for {var val} [dict get $opts -extravars] {
			namespace eval ::SELECT [list set $var $val]
		}

		foreach key {MotorPositions DetectorValues OptionalPositions Plot} {
			if {[dict exists $hdfdata $key]} {
				dict for {key value} [dict get $hdfdata $key] {
					namespace eval ::SELECT [list set $key $value]
				}
			}
		}

		set table [dict create]
		
		if {[dict exists $hdfdata MCA]} {
			dict set table MCA [dict get $hdfdata MCA]
		}

		if {[dict exists $hdfdata Motor]} {
			set table [dict merge $table [dict get $hdfdata Motor]]
		}
		
		if {[dict exists $hdfdata Detector]} {
			set table [dict merge $table [dict get $hdfdata Detector]]
		}

		set i 0
		foreach fmt $fmtlist {
			if {[string first {$} $fmt]<0} {
				# no $ found - interpret the whole thing as one variable name
				lset fmtlist $i "\${$fmt}"
			}
			if {$fmt == {}} {
				lset fmtlist $i {{}}
			}
			incr i
		}
		
		# compute maximum length for each data column - might be different due to BESSY_INF trimming
		set maxlength 0
		dict for {var entry} $table {
			set maxlength [tcl::mathfunc::max $maxlength [llength [dict get $entry data]]]
		}

		for {set i 0} {$i<$maxlength && $Row<$limit} {incr i; incr Row} {
			namespace eval ::SELECT [list set Row $Row] 
			
			foreach {var entry} $table {
				namespace eval ::SELECT [list set $var [lindex [dict get $entry data] $i]]
			}

			set line {}
			foreach fmt $fmtlist {
				if {[catch {namespace eval ::SELECT [list expr $fmt]} lresult]} {
					# expr handles NaN in many different ways by throwing errors:(
					if {$allnan || [regexp {Not a Number|domain error|non-numeric} $lresult]} { set lresult NaN }
				}
				lappend line $lresult
			}
			lappend result $line
		}


		return $result

	}

	proc GROUP_BY {selectdata grouplist} {
		# simulate SQL GROUP BY operator and
		# aggregate functions over result set from SELECT
		
		catch {namespace delete ::GROUP}
		namespace eval ::GROUP {
			proc join {sep list} {
				# same as ::join, but with different order
				::join $list $sep
			}
			proc index {idx list} { lindex $list $idx }

			proc first {list} { lindex $list 0 }

			proc last {list} { lindex $list end }

			proc mean {list} { expr {[sum $list]/[count $list]} }

			proc sum {list} {
				set result 0
				foreach v $list {
					set result [expr {$result+$v}]
				}
				return $result
			}

			proc min {list} { tcl::mathfunc::min {*}$list }

			proc max {list} { tcl::mathfunc::max {*}$list }
	 
			proc count {list} { llength $list }
		} 
		
		set ncols [llength $grouplist]
		# build list of format strings for each 
		# group_by element idx1 fmt1 idx2 fmt2 ...
		set groupidx {}
		set idx 0
		foreach col $grouplist {
			set args [lassign $col aggregate_func]
			switch $aggregate_func {
				group {
					if {[llength $col]==1} { 
						set fmt %s
					} else { 
						set fmt [lindex $args 0]
					}
					lappend groupidx $idx $fmt
				}

				default {
				}
			}
			incr idx
		}

		set groupdata {}
		# reshape into dictionary with index group_by
		foreach row $selectdata {
			if {[llength $row]!=$ncols} {
				return -code error "Length of format $ncols doesn't match row $row"
			}
			# compute groupkey
			set groupkey {}
			foreach {idx fmt} $groupidx {
				lappend groupkey [format $fmt [lindex $row $idx]]
			}
			dictlappend_vec groupdata $groupkey $row
		}
		
		# groupdata is now a grouped dictionary
		# now apply aggregate functions
		set result {}
		dict for {rowkey rowdata} $groupdata {
			set row {}
			set gidx 0
			foreach col $grouplist vlist $rowdata {
				set args [lassign $col aggregate_func]
				switch $aggregate_func {
					group {
						lappend row [lindex $rowkey $gidx]
						incr gidx
					}

					default {
						# call the given aggregate function 
						lappend row [namespace eval ::GROUP [linsert $col end $vlist]]
					}
				}
			}
			lappend result $row
		}
		return $result
	}

	proc dictlappend_vec {varname key vlist} {
		# lappend into nested structure with 
		# dict-list scheme
		upvar $varname dl
		if {![dict exists $dl $key]} {
			set newlist {}
			foreach v $vlist {
				lappend newlist [list $v]
			}
			dict set dl $key $newlist
		} else {
			set newlist {}
			foreach row [dict get $dl $key] val $vlist {
				lappend row $val
				lappend newlist $row
			}
			dict set dl $key $newlist
		}
	}


	proc ConsoleShow {} {
		tkcon show
		tkcon title "BessyHDFViewer Console"
	}

	proc bessy_reshape {fn} {
		# switch on the file extension
		switch [file extension $fn] {
			.hdf { return [bessy_reshape_hdf4 $fn] }
			default { return [bessy_reshape_hdf5 $fn] }
		}
	}

	proc bessy_reshape_hdf4 {fn} {

		SmallUtils::autovar hdf HDFpp %AUTO% $fn
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

	proc dict_move {dict1 key1 dict2 key2} {
		upvar $dict1 d1
		upvar $dict2 d2
		if {[dict exists $d1 {*}$key1]} {
			dict set d2 {*}$key2 [dict get $d1 {*}$key1]
			dict unset d1 {*}$key1
		}
	}

	proc eveH5getDSNames {d chain} {
		dict keys [dict filter [dict get $d data c1 data] script {key value} {
			expr {[dict get $value type]=="DATASET"}
		}]
	}

	proc eveH5OuterJoin {reshapedvar joinlist} {
		upvar $reshapedvar reshaped
		
		# read data 
		set data {}
		foreach {group dset} $joinlist {
			set ds [dict get $reshaped $group $dset data]
			lappend data $ds
		}

		# build unique PosList
		set PosList {}
		foreach ds $data {
			foreach {Pos dummy} $ds { lappend PosList $Pos }
		}
		
		# OUTER JOIN into result
		set UniquePosList [lsort -unique -integer $PosList]
		set result {}
		foreach ds $data {
			set column {}
			foreach Pos $UniquePosList {
				if {![dict exists $ds $Pos]} {
					set val NaN
				} else {
					set val [dict get $ds $Pos]
				}
				lappend column $val
			}
			lappend result $column
		}

		# write back
		foreach {group dset} $joinlist {column} $result {
			dict set reshaped $group $dset data $column
		}

		return $result
	}

	proc bessy_reshape_hdf5 {fn} {
		SmallUtils::autovar hdf H5pp %AUTO% $fn
		set rawd [$hdf dump]
		# new HDF5 stores data under /c1/deviceid
		# and MotorPos etc. under /device/
		set reshaped {}
		dict_move rawd {attrs} reshaped {{}}
		set chain c1
		set DSnames [eveH5getDSNames $rawd $chain]
		set joinsets {}
		foreach ds $DSnames {
			if {![catch {
				switch [dict get $rawd data $chain data $ds attrs DeviceType] {
					Channel { set group Detector }
					Axis { set group Motor }
					default { set group Detector }
				}
			}]} {
				# no error - move this dataset
				set name [dict get $rawd data $chain data $ds attrs Name]
				dict_move rawd [list data $chain data $ds attrs] reshaped [list $group $name attrs]
				dict_move rawd [list data $chain data $ds data] reshaped [list $group $name data]
				lappend joinsets $group $name
			}

		}
		
		dict_move rawd [list data $chain data meta data PosCountTimer attrs] reshaped [list Detector PosCountTimer attrs]
		dict_move rawd [list data $chain data meta data PosCountTimer data] reshaped [list Detector PosCountTimer data]
		lappend joinsets Detector PosCountTimer

		# now join the datasets via PosCount
		eveH5OuterJoin reshaped $joinsets

		foreach {group name} $joinsets {
			dict_move reshaped [list $group $name attrs unit] reshaped [list $group $name attrs Unit]
		}

		dict set reshaped Unresolved $rawd

		return $reshaped
	}

	proc bessy_class {data} {
		# classify dataset into Images, Plot and return plot axes
		set images [dict exists $data Detector Pilatus_Tiff data]
		set mca [dict exists $data MCA]
		
		# determine available axes = motors and detectors
		if {[catch {dict keys [dict get $data Motor]} motors]} {
			set motors {}
		}
		
		if {[catch {dict keys [dict get $data Detector]} detectors]} {
			set detectors {}
		}
		
		set axes [list {*}$motors {*}$detectors]

		set Plot true
		if {[catch {dict get $data Plot Motor} motor]} {
			# if Plot is unavailable take the first motor
			# if that fails, give up
			set Plot false
			set motor [lindex $motors 0]
		}
			
		if {[catch {dict get $data Plot Detector} detector]} {
			set Plot false
			set detector [lindex $detectors 0]
		}

		# now check for different classes. MCA has only this dataset, no motors etc.
		set class UNKNOWN

		if {$mca} {
			set motors {Row}
			set detectors {MCA}
			set length [llength [dict get $data MCA data]]
			set class MCA
		} elseif {$images} {
			# file contains Pilatus images. Check for one or more
			set length [llength [dict get $data Detector Pilatus_Tiff data]]
			if {$length == 1} {
				set class SINGLE_IMG
			}

			if {$length > 1} {
				set class MULTIPLE_IMG
			}
			# otherwise no images are found
		} else {
			if {$Plot} {
				# there is a valid Plot
				set class PLOT
			} else {
				# could not identify
				set class UNKNOWN
			}

			# determine length from motor
			if {[catch {llength [dict get $data Motor $motor data]} length]} {
				if {[catch {llength [dict get $data Detector $detector data]} length]} {
					set length 0
				}
			}
		}
		return [dict create class $class motor $motor detector $detector \
					nrows $length motors $motors detectors $detectors axes $axes]
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

		foreach attrkey {DetectorValues MotorPositions OptionalPositions Plot {}} {
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

	proc bessy_get_keys {hdfdata {category {Detector Motor Meta}}} {
		set datakeys {}
		set attrkeys {}
		foreach catkey $category {
			switch $catkey {
				Detector {
					lappend datakeys Detector 
					lappend attrkeys DetectorValues 
				}
				Motor {
					lappend datakeys Motor 
					lappend attrkeys MotorPositions OptionalPositions
				}
				Meta {
					lappend attrkeys Plot {}
				}
				Axes {
					lappend datakeys Detector Motor
				}
				default {
					return -code error "Unknown category: $catkey. Expected Motor, Detector or Meta"
				}
			}
		}

		set keys {}
		foreach datakey $datakeys {
			# keys that are tried to find data
			if {[dict exists $hdfdata $datakey]} {
				lappend keys {*}[dict keys [dict get $hdfdata $datakey]]
			}
		}

		foreach attrkey $attrkeys {
			# keys that might store the field as a single value in the attrs
			if {[dict exists $hdfdata $attrkey]} {
				lappend keys {*}[dict keys [dict get $hdfdata $attrkey]]
			}
		}
		return [lsort -uniq $keys]
	}

	proc bessy_get_keys_flist {flist {category {Detector Motor Meta}}} {
		set allkeys {}
		foreach fn $flist {
			if {![catch {bessy_reshape $fn} data]} {
				lappend allkeys {*}[bessy_get_keys $data $category]
			}
		}
		return [lsort -uniq $allkeys]
	}


	proc ::tcl::mathfunc::isnan {x} {
		expr {$x != $x}
	}

	proc ::tcl::mathfunc::allequal {l} {
		# return true if all elements in l are equal
		set first [lindex $l 0]
		foreach el $l {
			if {$el ne $first} {
				return false
			}
		}
		return true
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

	proc zip {l1 l2} {
		# create intermixed list
		set result {}
		foreach v1 $l1 v2 $l2 {
			lappend result $v1 $v2
		}
		return $result
	}

	proc deepjoin {list args} { 
		if {[llength $args]==0} { return $list }
		set i 0
		foreach v $list {
			lset list $i [deepjoin $v {*}[lrange $args 0 end-1]] 
			incr i
		}
		join $list [lindex $args end]
	}

	proc dict_assign {dictvalue args} {
		# extract variables from dict
		# unset -> unset
		foreach var $args {
			upvar $var v 
			if {[catch {dict get $dictvalue $var} v]} {
				unset v
			}
		}
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

}

BessyHDFViewer::Init $argv
