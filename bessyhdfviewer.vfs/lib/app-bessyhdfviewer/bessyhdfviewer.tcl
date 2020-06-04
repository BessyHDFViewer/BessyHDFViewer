package provide app-bessyhdfviewer 1.0

package require hdfpp
package require ukaz 2.1
package require Tk
package require tooltip
package require tablelist_tile 5.9
package require sqlite3
package require vfs::zip

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
		BessyHDFViewer::OpenArgument $args
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
	foreach module {dirViewer.tcl listeditor.tcl hformat.tcl exportdialog.tcl 
		autocomplete.tcl dataevaluation.tcl spectrumviewer.tcl searchdialog.tcl} {
		namespace eval :: [list source [file join $basedir $module]]
	}

	namespace import ::SmallUtils::*
	
	proc Init {argv} {
		variable ns
		variable profiledir
		variable localcachedir
		
		# find user profile directory
		switch -glob $::tcl_platform(platform) {
			win* {
				set profiledir $::env(APPDATA)/BessyHDFViewer
				set localcachedir $profiledir
			}
			unix {
				set profiledir $::env(HOME)/.BessyHDFViewer
				set localcachedir [file join /var/tmp BessyHDFViewerCache-$::env(USER)]
			}
			default {
				set profiledir [pwd]
			}
		}

		if {[catch {file mkdir $profiledir}]} {
			# give up - no persistent cache
			puts "No profile dir available (tried $profiledir)"
			set profiledir {}
		}
		
		if {[catch {file mkdir $localcachedir}]} {
			# give up - no persistent cache
			puts "No local cache dir available (tried $localcachedir)"
			set localcachedir $profiledir
		}


		variable ColumnTraits {
			Modified {
				Display { -sortmode integer -formatcommand formatDate }
			}

			Energy {
				FormatString %.5g
			}

			Motor {
				Display { -sortmode dictionary }
			}

			Detector {
				Display { -sortmode dictionary }
			}

			NRows {
				Display { -sortmode integer }
			}

			class {
				Display {}
			}
		}

		ReadPreferences
		InitCache
		InitIconCache
		InitGUI

		if {[llength $argv] != 0} {
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
		set w(pathfr) [ttk::frame $w(listfr).pathfr]
		set w(pathent) [ttk::entry $w(pathfr).pathent -textvariable ${ns}::browsepath]
		
		variable browsepath [PreferenceGet HomeDir {/messung/}]
		if {![file isdirectory $browsepath]} {
			set browsepath [file normalize [pwd]]
		}

		bind $w(pathent) <FocusOut> ${ns}::RestoreCWD
		bind $w(pathent) <Key-Return> ${ns}::DirUpdate

		set w(filterbut) [ttk::checkbutton $w(pathfr).filterbut -text "Filter" -style Toolbutton \
			-variable ${ns}::filterenabled \
			-command ${ns}::SwitchFilterState]
		variable filterenabled [PreferenceGet FilterEnabled 0]
		ClearFilterErrors
		
		set w(filterent) [ttk::combobox $w(pathfr).filter -textvariable ${ns}::filterexpression \
			-width 20 -values [PreferenceGet FilterHistory {{$class != "MCA"} {$class == "MULTIPLE_IMG"}}] ]
		AutoComplete $w(filterent) -aclist {class Motor Detector Energy NRows}
		
		variable filterexpression [PreferenceGet FilterExpression {}]
		
		bind $w(filterent) <Key-Return> ${ns}::FilterUpdate
		bind $w(filterent) <<ComboboxSelected>> ${ns}::FilterUpdate
		
		set w(groupbut) [ttk::checkbutton $w(pathfr).groupbut -text "Grouping" -style Toolbutton \
			-variable ${ns}::groupingenabled \
			-command ${ns}::SwitchGroupingState\
			-image [IconGet tree-collapse]]
		
		tooltip::tooltip $w(groupbut) "Enable grouping of files"

		variable groupingenabled [PreferenceGet GroupingEnabled 0]
		
		set w(groupbox) [ttk::combobox $w(pathfr).grouping -textvariable ${ns}::GroupColumn \
			-width 20 -state readonly]
		variable GroupColumn [PreferenceGet GroupColumn {Comment}]
		
		bind $w(groupbox) <<ComboboxSelected>> ${ns}::GroupingUpdate


		set w(coleditbut) [ttk::button $w(pathfr).coleditbut -text "Configure columns" \
			-image [IconGet configure] -command ${ns}::ColumnEdit -style Toolbutton]
		tooltip::tooltip $w(coleditbut) "Edit displayed columns in browser"

		set w(infobutton) [ttk::button $w(pathfr).infobut -text "About BessyHDFViewer" \
			-image [IconGet info] -command ${ns}::About -style Toolbutton]
		tooltip::tooltip $w(infobutton) "About BessyHDFViewer"

		grid $w(pathent) $w(infobutton) $w(filterbut) $w(filterent) $w(groupbut) $w(groupbox) $w(coleditbut) -sticky ew
		grid columnconfigure $w(pathfr) $w(pathent) -weight 1

		set w(filelist) [dirViewer::dirViewer $w(listfr).filelist $browsepath \
			-classifycommand ${ns}::ClassifyHDF \
			-selectcommand ${ns}::PreviewFile \
			-globpattern {*.hdf *.h5 *.dat} \
			-selectmode extended]

		bind $w(filelist) <<DirviewerChDir>> [list ${ns}::DirChanged %d]
		bind $w(filelist) <<DirviewerColumnMoved>> [list ${ns}::DirColumnMoved %d]

		bind $w(filelist) <<ProgressStart>> [list ${ns}::OpenStart %d]
		bind $w(filelist) <<Progress>> [list ${ns}::OpenProgress %d]
		bind $w(filelist) <<ProgressFinished>> ${ns}::OpenFinished

		ChooseColumns [PreferenceGet Columns {"Motor" "Detector" "Modified"}]
		SwitchFilterState
		SwitchGroupingState

		# Create navigation buttons
		#
		set w(bbar) [ttk::frame $w(listfr).bbar]
		set w(bhome) [ttk::button $w(bbar).bhome -text "Home" -image [IconGet go-home] -compound left -command [list $w(filelist) goHome]]
		set w(bupwards) [ttk::button $w(bbar).bupwards -text "Parent" -image [IconGet go-up] -compound left -command [list $w(filelist) goUp]]
		set w(brefresh) [ttk::button $w(bbar).brefresh -text "Refresh" -image [IconGet view-refresh] -compound left  -command [list $w(filelist) RefreshRequest]]
		set w(dumpButton) [ttk::button $w(bbar).dumpbut -command ${ns}::ExportCmd -text "Export" -image [IconGet document-export] -compound left]
		set w(bsearch) [ttk::button $w(bbar).bsearch -command ${ns}::SearchCmd -text "Search" -image [IconGet dialog-search] -compound left]

		set w(foldbut) [ttk::button $w(bbar).foldbut -text "<" -command ${ns}::FoldPlotCmd -image [IconGet fold-close] -style Toolbutton]
		tooltip::tooltip $w(foldbut) "Fold away data display"

		variable PlotFolded false
		
		pack $w(bhome) $w(bupwards) $w(brefresh) $w(dumpButton) $w(bsearch) -side left -expand no -padx 2
		pack $w(foldbut) -side left -expand yes -fill none -anchor e

		set w(progbar) [ttk::progressbar $w(listfr).progbar]
		grid $w(pathfr)	    -sticky nsew 
		grid $w(filelist)   -sticky nsew
		grid $w(bbar)		-sticky nsew
		grid $w(progbar)    -sticky nsew

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

		# Graph
		set w(Graph) [ukaz::graph $w(plotfr).graph -background white]
		bind $w(Graph) <<MotionEvent>> [list ${ns}::UpdatePointerInfo motion %d]
		bind $w(Graph) <<Click>> [list ${ns}::UpdatePointerInfo click %x %y %s]
		
		set w(legend) [ttk::label $w(plotfr).frame]
		

		grid $w(axebar) -sticky nsew
		grid $w(toolbar) -sticky nsew
		grid $w(Graph) -sticky nsew
		grid $w(legend) -sticky nsew
		grid columnconfigure $w(plotfr) 0 -weight 1
		grid rowconfigure $w(plotfr) $w(Graph) -weight 1

		# pointer info. Series of labels

		foreach {wid desc var } {
			xlb "x: " xv 
			ylb "y: " yv 
			nrlb "Point: " dpnr 
			cxlb "x: " cx
			cylb "y: " cy } {
			set w(point.$wid) [ttk::label $w(legend).$wid -text $desc]
			set w(point.$var) [ttk::label $w(legend).$var -textvariable ${ns}::pointerinfo($var) -width 10]

			pack $w(point.$wid) $w(point.$var) -anchor w -side left
		}
		
		set w(xlbl) [ttk::label $w(axebar).xlbl -text "X axis:"]
		set w(xent0) [ttk::combobox $w(axebar).xent -textvariable ${ns}::xformat(0) -exportselection 0]
		set w(xlog) [ttk::checkbutton $w(axebar).xlog -variable ${ns}::xlog -style Toolbutton \
			-image [list [IconGet linscale] selected [IconGet logscale]] \
			-command [list ${ns}::PlotProperties]]
		variable xlog 0
		tooltip::tooltip $w(xlog) "Switch logscale for x-axis"

		set w(ylbl) [ttk::label $w(axebar).ylbl -text "Y axis:"]
		set w(yent0) [ttk::combobox $w(axebar).yent -textvariable ${ns}::yformat(0) -exportselection 0]
		set w(ylog) [ttk::checkbutton $w(axebar).ylog -variable ${ns}::ylog -style Toolbutton \
			-image [list [IconGet linscale] selected [IconGet logscale]] \
			-command [list ${ns}::PlotProperties]]
		variable ylog 0
		tooltip::tooltip $w(ylog) "Switch logscale for y-axis"

		set w(gridon) [ttk::checkbutton $w(axebar).grid -variable ${ns}::gridon -style Toolbutton \
			-image [IconGet grid] \
			-command [list ${ns}::PlotProperties]]
		variable gridon 0
		tooltip::tooltip $w(gridon) "Switch grid in plot window"

		set w(keep) [ttk::label $w(axebar).keeplbl -text "Keep"]
		set w(keepformat) [ttk::checkbutton $w(axebar).keepformat -variable ${ns}::keepformat -text "format"]
		set w(keepzoom) [ttk::checkbutton $w(axebar).keepzoom -variable ${ns}::keepzoom -text "zoom"]
		variable keepformat false
		variable keepzoom false
		tooltip::tooltip $w(keepformat) "Check to keep the plot format when switching files"
		tooltip::tooltip $w(keepzoom) "Check to keep the plot range when switching files"

		
		set w(addrow) [ttk::button $w(axebar).addbtn -image [IconGet list-add-small] \
			-command ${ns}::AddPlotRow -style Toolbutton]
		tooltip::tooltip $w(addrow) "Add another plot from the same file"

		bind $w(xent0) <<ComboboxSelected>> [list ${ns}::DisplayPlot -explicit true]
		bind $w(yent0) <<ComboboxSelected>> [list ${ns}::DisplayPlot -explicit true]
		AutoComplete $w(xent0) -aclist {Energy Row}
		AutoComplete $w(yent0) -aclist {Energy Row}
		bind $w(xent0) <Return> [list ${ns}::DisplayPlot -explicit true]
		bind $w(yent0) <Return> [list ${ns}::DisplayPlot -explicit true]
		bind $w(xlbl) <1> ${ns}::ConsoleShow

		grid $w(addrow) $w(xlbl) $w(xlog) $w(xent0) $w(ylbl) $w(ylog) $w(yent0) $w(gridon) \
			$w(keep) $w(keepformat) $w(keepzoom) -sticky ew
		variable Nformats 1

		grid columnconfigure $w(axebar) $w(xent0) -weight 1
		grid columnconfigure $w(axebar) $w(yent0) -weight 1

		# Toolbar: Command buttons from dataevaluation namespace
		
		DataEvaluation::maketoolbar $w(toolbar)

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

	proc AddPlotRow {} {
		variable w
		variable Nformats
		variable ns
		variable xformat
		variable yformat
		variable xformatlist
		variable yformatlist

		set i $Nformats
		incr Nformats
		set w(xlbl$i) [ttk::label $w(axebar).xlbl$i -text "X axis"]
		set w(ylbl$i) [ttk::label $w(axebar).ylbl$i -text "Y axis"]
		set w(xent$i) [ttk::combobox $w(axebar).xent$i -textvariable ${ns}::xformat($i) -exportselection 0 -values $xformatlist]
		set w(yent$i) [ttk::combobox $w(axebar).yent$i -textvariable ${ns}::yformat($i) -exportselection 0 -values $yformatlist]

		set xformat($i) ""
		set yformat($i) ""
		grid x $w(xlbl$i) x $w(xent$i) $w(ylbl$i) x $w(yent$i) -sticky nsew
		
		bind $w(xent$i) <<ComboboxSelected>> [list ${ns}::DisplayPlot -explicit true]
		bind $w(yent$i) <<ComboboxSelected>> [list ${ns}::DisplayPlot -explicit true]
		AutoComplete $w(xent$i) -aclist {Energy Row}
		AutoComplete $w(yent$i) -aclist {Energy Row}
		bind $w(xent$i) <Return> [list ${ns}::DisplayPlot -explicit true]
		bind $w(yent$i) <Return> [list ${ns}::DisplayPlot -explicit true]
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

		set PrefVersion [dict get $Preferences Version]
		
		# read from profile dir
		if {$profiledir == {}} {
			set PrefFileName {}
			puts "No preferences file"
		} else {
			if {[catch {
				set PrefFileName [file join $profiledir Preferences.dict]
				set fd [open $PrefFileName r]
				fconfigure $fd -translation binary -encoding binary
				set UserPreferences [read $fd] 
				close $fd
				
				# hopefully this is a valid dict
				if {[dict get $UserPreferences Version] == $PrefVersion} {
					# throws for invalid dict and non-existent version
					set Preferences [dict merge $Preferences $UserPreferences]
				} else {
					tk_messageBox -title "Settings were reset" -message "Your settings were reset to defaults because of an update of BessyHDFViewer."
				}

			} err]} {
				# error - maybe cleanup fd
				# cache file remains valid - maybe simply didn't exist
				if {[info exists fd]} { catch {close $fd} }
				puts "Error reading preferences: $err"
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


	proc InitCache {{fn {}}} {
		variable localcachedir
		variable HDFCacheFile
		
		# check preferences if the cache was set to another location
		if {$fn eq {}} {
			set HDFCacheFile [PreferenceGet HDFCacheFile {}]
		} else {
			set HDFCacheFile $fn
		}
		
		if {$HDFCacheFile eq {}} {
			if {$localcachedir == {} } {
				set HDFCacheFile :memory:
				puts stderr "No persistent Cache"
			} else {
				set HDFCacheFile [file join $localcachedir HDFCache.db]
			}
		}

		sqlite3 HDFCache $HDFCacheFile
		
		HDFCache eval {
			CREATE TABLE IF NOT EXISTS HDFFiles (id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE, 
				mtime INTEGER NOT NULL, class TEXT NOT NULL, motor TEXT NOT NULL, detector TEXT NOT NULL, nrows INTEGER NOT NULL);
			CREATE UNIQUE INDEX IF NOT EXISTS idx_filename ON HDFFiles(path);
			CREATE INDEX IF NOT EXISTS idx_mtime ON HDFFiles(mtime);
			CREATE INDEX IF NOT EXISTS idx_nrows ON HDFFiles(nrows);
			CREATE TABLE IF NOT EXISTS Fields (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE);
			CREATE TABLE IF NOT EXISTS FieldValues (hdfid INTEGER, fieldid INTEGER, minimum REAL, maximum REAL,
				PRIMARY KEY (hdfid, fieldid),
				FOREIGN KEY (hdfid) REFERENCES HDFFiles(id)
				ON DELETE CASCADE ON UPDATE CASCADE,
				FOREIGN KEY (fieldid) REFERENCES Fields(id)
				ON DELETE CASCADE ON UPDATE CASCADE
			);
			CREATE INDEX IF NOT EXISTS idx_values ON FieldValues(minimum,maximum,hdfid,fieldid);
		}

	}

	proc ClearCache {} {
		# remove everything. Easiest implementation: delete cache file
		variable HDFCacheFile
		HDFCache close
		file delete -force $HDFCacheFile
		InitCache
	}

	proc ImportCache {fn} {
		# open foreign database and import it into the current cache

		HDFCache eval {
			ATTACH DATABASE :fn AS foreign_cache;
			BEGIN;
			INSERT OR IGNORE INTO hdffiles(path, mtime, class, motor, detector, nrows) 
				SELECT path,mtime,class,motor,detector,nrows 
				FROM foreign_cache.hdffiles;
			
			INSERT OR IGNORE INTO Fields(name) SELECT name FROM foreign_cache.Fields;
			
			INSERT OR IGNORE INTO FieldValues(hdfid, fieldid, minimum, maximum) 
				SELECT main.HDFFiles.id, main.Fields.id, foreign_cache.FieldValues.minimum, foreign_cache.FieldValues.maximum
				FROM main.HDFFiles, main.Fields, foreign_cache.HDFFiles, foreign_cache.Fields, foreign_cache.FieldValues

					WHERE main.HDFFiles.path = foreign_cache.HDFFiles.path AND main.Fields.name = foreign_cache.Fields.name
					AND foreign_cache.FieldValues.hdfid = foreign_cache.HDFFiles.id 
					AND foreign_cache.FieldValues.fieldid = foreign_cache.Fields.id;


			COMMIT;
			DETACH DATABASE foreign_cache;
		}
	}

	proc CacheStats {{cachdb HDFCache}} {
		set nfiles [$cachdb eval {select count(*) from hdffiles }]
		set nvalues [$cachdb eval {select count(*) from fieldvalues }]

		puts "$nfiles Files, $nvalues Values"
		return [list $nfiles $nvalues]
	} 

	proc UpdateCache {fn mtime classinfo fields {transaction true}} {
		dict_assign $classinfo class motor detector nrows

		if {$transaction} {
			HDFCache eval BEGIN
		}
		HDFCache eval {
			INSERT OR REPLACE INTO HDFFiles (id, path, mtime, class, motor, detector, nrows) 
				SELECT id, :fn, :mtime, :class, :motor, :detector, :nrows 
				FROM ( SELECT NULL ) LEFT JOIN ( SELECT * FROM HDFFiles WHERE path = :fn );
		}

		foreach {name value} $fields {
			lassign $value minimum maximum
			HDFCache eval {
				INSERT OR IGNORE INTO Fields (name) VALUES(:name);
				INSERT OR REPLACE INTO FieldValues(hdfid, fieldid, minimum, maximum) 
					SELECT HDFFiles.id, Fields.id, :minimum, :maximum FROM HDFFiles, Fields
						WHERE HDFFiles.path = :fn AND Fields.name = :name ;
			}

		}
		if {$transaction} {
			HDFCache eval COMMIT
		}
	}

	proc UpdateCacheForFile {fn {transaction true}} {
		set mtime [file mtime $fn]
		set metainfo [FindCache $fn $mtime]

		if {[llength $metainfo] == 0} {
			if {[catch {bessy_reshape $fn -shallow} temphdfdata]} {
				puts "Error reading hdf file $fn"
				return
			}

			set classinfo [bessy_class $temphdfdata]
			set fieldvalues [bessy_get_all_fields $temphdfdata]
			BessyHDFViewer::UpdateCache $fn $mtime $classinfo $fieldvalues $transaction
		}
	}

	proc QueryCache {fn field} {
		HDFCache eval {
			SELECT  FieldValues.minimum, FieldValues.maximum FROM HDFFiles, Fields, FieldValues 
				WHERE FieldValues.hdfid = HDFFiles.id AND FieldValues.fieldid = Fields.id 
				AND HDFFiles.path = :fn AND Fields.name = :field
		}
	}

	proc GetCachedFields {fn} {
		set result {}
		HDFCache eval {
			SELECT  Fields.name AS name, FieldValues.minimum AS minimum, FieldValues.maximum AS maximum FROM HDFFiles, Fields, FieldValues 
				WHERE FieldValues.hdfid = HDFFiles.id AND FieldValues.fieldid = Fields.id 
				AND HDFFiles.path = :fn
		} {
			dict set result $name [list $minimum $maximum]
		}

		return $result
	}

	proc GetCachedFieldNames {} {
		HDFCache eval { 
			SELECT name FROM Fields ORDER BY name ASC
		}
	}

	proc FindCache {fn mtime} {
		HDFCache eval {
			SELECT class, motor, detector, nrows FROM HDFFiles 
			WHERE HDFFiles.path = :fn AND HDFFiles.mtime = :mtime
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
		$w(filterent) configure -aclist $columns
		GroupingUpdate

	}

	proc DirColumnMoved {columns} {
		# Columns were interactively changed 
		# just accept new setting
		variable ActiveColumns $columns
	}

	snit::widget AboutDialog {
		hulltype toplevel
		component text
		component vsb
		component hsb

		variable title
		variable copyright
		variable vinfotext

		constructor {args} {
			$self CreateText
			
			wm title $win $title
			
			set mfr [ttk::frame $win.mfr]
			pack $mfr -expand yes -fill both

			set textfr [ttk::frame $mfr.textfr]
			set butfr [ttk::frame $mfr.butfr]
			set eyecandy [ttk::label $mfr.icon -image [IconGet BessyHDFViewer_large]]
			set cplabel [ttk::label $mfr.lbl -text $copyright]
			
			grid $eyecandy $cplabel -sticky nsew -padx 10 -pady 10
			grid $textfr - -sticky nsew -padx 10
			grid $butfr - 

			grid rowconfigure $mfr $textfr -weight 1
			grid columnconfigure $mfr $textfr -weight 1
			
			
			install text using text $textfr.text \
				-xscrollcommand [list $textfr.hsb set] \
				-yscrollcommand [list $textfr.vsb set]

			install hsb using ttk::scrollbar $textfr.hsb -orient horizontal -command [list $text xview]
			install vsb using ttk::scrollbar $textfr.vsb -orient vertical -command [list $text yview]

			grid $text $vsb -sticky nsew
			grid $hsb  -    -sticky nsew
			
			grid rowconfigure $textfr $text -weight 1
			grid columnconfigure $textfr $text -weight 1

			$text insert 1.0 $vinfotext

			# add buttons
			set okbut [ttk::button $butfr.ok -text "OK" -command [mymethod Quit] -default active]
			set instbut [ttk::button $butfr.inst -text "Install Package..." -command [mymethod InstallPackageCmd] -default normal]
			pack $okbut $instbut -side left -anchor c
			focus $okbut
			bind $self <Return> [mymethod Quit]
			bind $self <Escape> [mymethod Quit]
		}

		method AddText {msg} {
			$text insert end $msg
			$text see end
			raise $win
		}
		
		method CreateText {} {	
			set exebasedir [info nameofexecutable]
			set version [AboutReadVersion $exebasedir]
			set title "About BessyHDFViewer"
			set copyright "BessyHDFViewer - a program for browsing\nand analysing PTB@BESSY measurement files"
			append copyright "\n(C) Christian Gollwitzer, PTB 2012 - [clock format [clock scan now] -format %Y]"
			append copyright "\nAll rights reserved"
			append copyright "\nUsing Tcl [info patchlevel]"

			set vinfotext "Git version:\n"
			append vinfotext $version\n
			append vinfotext "\nPlugin versions:\n"

			foreach pdir $::DataEvaluation::plugindirs {
				append vinfotext [file tail $pdir]:\n
				append vinfotext [AboutReadVersion $pdir]\n\n
			}
			
			append vinfotext "\nExecutable path:\n[info nameofexecutable]\n"
			append vinfotext "\nProfile path:\n$BessyHDFViewer::profiledir\n"
			append vinfotext "\n Tcl platform info:\n"
			append vinfotext [join [lmap {key val} [array get ::tcl_platform] { string cat "   $key = $val" }] \n]

		}

		method InstallPackageCmd {} {
			set filetypes { 
				{{BessyHDFViewer package} {.bpkg}}
				{{All Files}        *  }
			}

			set fn [tk_getOpenFile -title "Select BessyHDFViewer package..." -filetypes $filetypes]

			if {$fn != "" } {
				InstallPackage $fn
			}
		}

		method Quit {} {
			destroy $win
		}
	}

	proc About {} {
		# create dialog window
		AboutDialog .about
		tkwait window .about
	}

	proc AboutReadVersion {dir} {
		if {[catch {fileutil::cat [file join $dir VERSION]} vers]} {
			return "Development"
			puts $vers
		} else {
			# check that there are 2 lines with commit and Date
			# if so, return these, otherwise the whole thing
			set commitinfo {}
			foreach line [split $vers \n] {
				switch -glob $line {
					commit* -
					Date:* { lappend commitinfo $line }
				}
			}
			if {[llength $commitinfo] >= 2} {
				return [join $commitinfo \n]
			} else {
				return $vers
			}
		}
	}

	proc ColumnEdit {} {
		variable ActiveColumns
		set ColumnsAvailableTree [PreferenceGet ColumnsAvailableTree {{GROUP General {{LIST {Motor Detector Modified}}}} {GROUP Motors {{LIST {Energy}}}}}]
		set columns [ListEditor getList -initiallist $ActiveColumns -valuetree $ColumnsAvailableTree -title "Select columns" -parent . -aclist [GetCachedFieldNames]]
		if {$columns != $ActiveColumns} {
			ChooseColumns $columns
			PreferenceSet Columns $columns 
		}
	}
	
	proc ClearFilterErrors {} {
		variable w
		variable filtererror {}
		$w(filterbut) configure -image [list [IconGet hopper] selected [IconGet hopper-blue]]
		tooltip::tooltip $w(filterbut) "Set filter"
	}

	proc FilterError {err} {
		variable w
		variable filtererror
		
		if {[llength $filtererror]==0} {
			# first error. make button red
			$w(filterbut) configure -image [IconGet hopper-red]
		}
		lappend filtererror $err
	}

	proc FilterFinish {} {
		variable w
		variable filtererror
		if {[llength $filtererror]==0} { return }

		set maxerr 10
		# maximum number of errors to display 

		set msg "Errors during filtering:\n"
		if {[llength $filtererror] <= $maxerr} {
			append msg [join $filtererror \n]
		} else {
			append msg [join [lrange $filtererror 0 $maxerr-1] \n]
			append msg "\n ( [expr {[llength $filtererror]-$maxerr-1}] more errors )"
		}
		tooltip::tooltip $w(filterbut) $msg
	}

	proc ClassifyHDF {type fn} {
		variable w
		variable ActiveColumns
		variable IconClassMap
		variable filterexpression
		variable filterenabled
		
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


		# check cache
		set metainfo [FindCache $fn $mtime]
		if {[llength $metainfo] == 0} {
			# the file was not found in the cache, or the mtime was different
			# read the file and update the cache
			# puts "$fn $mtime not found in cache"
			set temphdfdata {}
			if {[catch {bessy_reshape $fn -shallow} temphdfdata]} {
				puts "Error reading hdf file $fn"

				set result [lrepeat [llength $ActiveColumns] {}]
				lappend result [IconGet unknown]
				return $result
			} else {
				set classinfo [bessy_class $temphdfdata]
				set fieldvalues [bessy_get_all_fields $temphdfdata]
				UpdateCache $fn $mtime $classinfo $fieldvalues false
				
				dict_assign [bessy_class $temphdfdata] class motor detector nrows
			}
		} else {
			# puts "$fn $mtime found in cache"
			# retrieve basic meta info
			lassign $metainfo class motor detector nrows
			set fieldvalues [GetCachedFields $fn]
		}

		# build dictionary with all information
		set metainfodict [dict create class $class Motor $motor Detector $detector NRows $nrows Modified $mtime]
		set fieldvalues [dict merge $fieldvalues $metainfodict]

		# loop over requested columns and retrieve values from cache
		set result [lmap col $ActiveColumns {SmallUtils::dict_getdefault $fieldvalues $col {}}]
		
		# last column is always the icon for the class
		set classicon [dict get $IconClassMap $class]
		if {$filterenabled && [string trim $filterexpression]!= ""} {
			if {[catch {dict_expr $fieldvalues $filterexpression} filterres]} {
				# an error occured during filtering
				FilterError $filterres
			} else {
				if {[string is bool $filterres]} {
					if {!$filterres} { 
						set classicon SKIP
					}
				} else {
					FilterError "Result of filter not boolean: $filterres"
				}
			}
		}
		lappend result $classicon
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
				variable hdfdata {} 
				set hdfdata [bessy_reshape [lindex $files 0] -shallow]

				# select the motor/det
				set BessyClass [bessy_class $hdfdata]
				dict_assign $BessyClass class motor detector motors detectors datasets

				# reshape plotdata into table form
				MakeTable
				
				wm title . "BessyHDFViewer - [lindex $files 0]"

			}

			default {
				# multiple files selected - prepare for batch work
				set BessyClass {class {} axes {} motors {} detectors {} motor {} detector {} datasets {}}
				wm title . "BessyHDFViewer"
			}
		}
		InvalidateDisplay
		ReDisplay
	}

	proc MakeTable {} {
		# reformat plotdata into table
		variable BessyClass
		variable hdfdata 

		variable plotdata
		variable tbldata {}
		variable tblheader {}
		
		if {[dict get $BessyClass class] == "MCA"} {
			set plotdata [list MCA [dict get $hdfdata MCA]]
		} else {
			# insert available axes into plotdata
			if {[catch {
				set plotdata {}
				foreach key {Motor Detector Dataset} {
					set plotdata [dict merge $plotdata [SmallUtils::dict_getdefault $hdfdata $key {}]]
				}
			} err]} {
				# could not get sensible plot axes - not BESSY hdf?
				puts $err
				return 
			}
		}

		# compute maximum length for each data column - might be different due to BESSY_INF trimming
		set maxlength 0
		dict for {var entry} $plotdata {
			set maxlength [tcl::mathfunc::max $maxlength [llength [dict get $entry data]]]
		}

		set tblheader Row
		lappend tblheader {*}[dict keys $plotdata]
		set tbldata {}
		for {set i 0} {$i<$maxlength} {incr i} {
			set line $i
			dict for {var entry} $plotdata {
				lappend line [lindex [dict get $entry data] $i]
			}
			lappend tbldata $line
		}
	}

	proc quotedjoin {list {sep " "}} {
		# serialize a list into quoted format
		# Tcl's "list" uses braces for quoting, which is not well understood
		# from other software. Using more conventional double quotes and backslashes
		# makes the result more portable (and also readable from within Tcl)
		set result {}
		foreach el $list {
			if {[regexp {[\s{}"'"\\]} $el]} {
				# found metacharacters
				set eltrans [string map [list \" \\" \\ \\\\] $el]
				lappend result "\"$eltrans\""
			} else {
				lappend result $el
			}
		}
		return [join $result $sep]
	}

	proc exprquote {varname} {
		# quote a vraible name for use with expr
		# for "simple" names, preceeding with $ is sufficient
		# in more complex cases use ${}, and for list metacharacters
		# [set varname]
		if {[regexp {^[[:alpha:]_][[:alnum:]_]*$} $varname]} {
			# only alphanumeric - don't use braces
			return "\$$varname"
		} elseif [regexp "\[\]\[{}\\\\\"]" $varname] {
			# list metacharacters - use the set form
			return "\[set [list $varname]\]"
		} else {
			# weird, but not completely weird - 
			# insert braces
			return "\$\{$varname\}"
		}
	}

	proc DumpAttrib {data {indent ""}} {
		set result ""
		dict for {key val} $data {
			append result "# ${indent}${key}\t = ${val}\n"
		}
		return $result
	}

	proc DumpData {data {indent ""}} {
		set result ""
		dict for {key val} $data {
			if {[dict exists $val data]} {
				set values [dict get $val data]
				append result "# ${indent}${key}\t = ${values}\n"
			}
		}
		return $result
	}

	proc DumpFields {hdfdata} {
		# functional style, yeah
		set fieldlist {}
		dict for {field value} [bessy_get_all_fields $hdfdata] {
			append fieldlist "[list $field $value]\n"
		}
		return $fieldlist
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
		
		set checkkeys {Motor Detector Dataset MotorPositions DetectorValues OptionalPositions Plot SnapshotValues}
		# if at least one of the above keys exists, it is a PTB HDF file

		set measurementfile [tcl::mathop::+ {*}[lmap key $checkkeys {dict exists $hdfdata $key}]]
		
		if {!$measurementfile} {
			# if it is not a measurement file
			# dump the internal representation in a human readable format
			return [hformat $hdfdata]
		}

		foreach key {MotorPositions DetectorValues OptionalPositions Plot} {
			if {[dict exists $hdfdata $key] && "Attributes" in $headerfmt} {
				append result "# $key:\n"
				append result [DumpAttrib [dict get $hdfdata $key] \t]
				append result "#\n"
			}
		}

		# check Snapshot 
		if {[dict exists $hdfdata SnapshotValues]} {
			append result "# SnapshotValues:\n"
			foreach category {Motor Detector Meta} {
				if {[dict exists $hdfdata SnapshotValues $category]} {
					append result "# \t${category}:\n"
					append result [DumpData [dict get $hdfdata SnapshotValues $category] \t\t]
				}
			}
		}

		dict_assign [bessy_class $hdfdata] motors detectors datasets
		
		set table {}
		foreach key {Motor Detector Dataset} {
			set table [dict merge $table [SmallUtils::dict_getdefault $hdfdata $key {}]]
		}
		
		set variables [list {*}$motors {*}$detectors {*}$datasets]
		# write header lines

		if {"Attributes" in $headerfmt} {
			
			foreach {category keys} \
				[list Motors $motors Detectors $detectors Datasets $datasets] {

				if {[llength $keys] > 0} {
					append result "# $category:\n"
				}
				foreach key $keys {
					append result "# \t$key:\n"
					append result [DumpAttrib [SmallUtils::dict_getdefault $table $key attrs {}] \t\t]
				}
			}
		}

		if {"Columns" in $headerfmt} {
			append result "# [quotedjoin $variables \t]\n"
		}
		if {"BareColumns" in $headerfmt} {
			append result "[quotedjoin $variables \t]\n"
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
		
		if {$choice != {}} {
			# dialog was not cancelled
			dict set choice files $HDFFiles
			Export $choice
		}

	}

	proc Export {choice} {
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
		set files [dict get $choice files]
		

		if {$stdformat} {
			# Text dump
			if {$singlefile} {
				SmallUtils::autofd fd [dict get $choice path] wb
			}

			foreach hdf $files {
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
					foreach hdf $files {
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

				set data [SELECT $format $files -allnan true]
				if {$grouping} {
					set data [GROUP_BY $data $groupby]
				}	
				puts $fd [deepjoin $data \t \n]

			} else {
				# individual files
				foreach hdf $files {
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
	variable pickcallbacks {}
	proc UpdatePointerInfo {action args} {
		# callback for mouse events on canvas
		variable pointerinfo
		variable w
		variable HDFsshown

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
				lassign $args x y s
				lassign [$w(Graph) pickpoint $x $y] id dpnr xd yd
				
				if {$id == {}} { return }

				if {[catch {dict get $HDFsshown $id} fn]} {	
					return
				}

				set pointerinfo(dpnr) $dpnr
				set pointerinfo(fn) $fn
				set pointerinfo(id) $id
				set pointerinfo(state) $s

				if {$id != {}} {
					set pointerinfo(clickx) $xd
					set pointerinfo(clicky) $yd
					set pointerinfo(cx) [format %8.5g $xd]
					set pointerinfo(cy) [format %8.5g $yd]
				} else {
					set pointerinfo(cx) ""
					set pointerinfo(cy) ""
				}
				
				variable pickcallbacks
				dict for {cmd dummy} $pickcallbacks {
					{*}$cmd [array get pointerinfo]
				}
			}
		}
	}

	
	proc RegisterPickCallback {cmd} {
		variable pickcallbacks
		dict set pickcallbacks $cmd 1
		return $cmd
	}
	
	proc UnRegisterPickCallback {cmd} {
		variable pickcallbacks
		dict unset pickcallbacks $cmd
	}

	variable highlightids {}
	proc HighlightDataPoint {hdf dpnr args} {
		# if hdf is currently plotted, mark the point dpnr
		variable HDFsshown
		variable highlightids
		variable w
		set hdfids [dict keys [dict filter $HDFsshown value $hdf]]

		foreach hdfid $hdfids {
			# if this HDF is shown at the moment, highlight the 
			# corresponding data point
			$w(Graph) highlight $hdfid $dpnr {*}$args
			dict set highlightids $hdf $dpnr $args
		}
	}
	
	proc HighlightRefresh {} {
		variable HDFsshown
		variable highlightids
		variable w

		dict for {hdfid hdf} $HDFsshown {
			if {[dict exists $highlightids $hdf]} {
				dict for {dpnr style} [dict get $highlightids $hdf] {
					$w(Graph) highlight $hdfid $dpnr {*}$style
				}
			}
		}

	}
	
	proc ClearHighlights {} {
		# remove the highlights
		variable highlightids
		variable w
		
		$w(Graph) clearhighlight all
		set highlightids {}
	}

	proc PlotProperties {} {
		variable xlog
		variable ylog
		variable gridon
		variable w

		$w(Graph) set log x $xlog
		$w(Graph) set log y $ylog
		$w(Graph) set grid $gridon
	}

	proc not_only_whitespace {string} {
		regexp {\S} $string
	}

	variable plotstylecache {}
	variable xformatlist {}
	variable yformatlist {}
	proc DisplayPlot {args} {
		variable w
		variable plotdata
		variable hdfdata
		variable HDFFiles
		variable xformat
		variable yformat
		variable xformatlist
		variable yformatlist
		variable keepformat
		variable keepzoom
		variable Nformats

		variable plotstylecache
		
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
			dict_assign $BessyClass class motor detector motors detectors datasets axes
			if {$class == "MCA"} {
				set xformatlist {{$calS*$Row+$calO} Row}
				set yformatlist {MCA}
				for {set i 0} {$i < $Nformats} {incr i} {
					$w(xent$i) state !disabled
					$w(yent$i) state !disabled
				}
				set stdx Row
				set stdy MCA
			} elseif {$axes!= {}} {
				# insert available axes into axis choosers
				set xformatlist [list {*}$motors {*}$detectors {*}$datasets]
				set yformatlist [list {*}$detectors {*}$motors {*}$datasets]
				for {set i 0} {$i < $Nformats} {incr i} {
					$w(xent$i) state !disabled
					$w(yent$i) state !disabled
				}
				set stdx $motor
				set stdy $detector
				
				# check if mean was enabled in the detector
				if {"${detector}_mean" in $detectors} {
					set stdy ${detector}_mean
				}
				
				# check for normalization 
				if {[dict exists $hdfdata Plot Monitor]} {
					set monitor [dict get $hdfdata Plot Monitor]
					if {"${monitor}_mean" in $detectors} {
						set monitor "${monitor}_mean"
					}

					if {$monitor in $detectors} {
						set stdy "[exprquote $stdy]/[exprquote $monitor]"
						# append normalized form to suggestions
						lappend yformatlist $stdy
					}
				}
			
			} else {
				set xformatlist {}
				set yformatlist {}
				for {set i 0} {$i < $Nformats} {incr i} {
					$w(xent$i) state disabled
					$w(yent$i) state disabled
				}
				$w(Graph) clear
				return
			}

			if {!$explicit && !$keepformat} {
				set xformat(0) $stdx
				set yformat(0) $stdy

				for {set i 1} {$i < $Nformats} {incr i} {
					set xformat($i) ""
					set yformat($i) ""
				}
			}

		} else {
			# more than one file selected
			set xformatlist {}
			set yformatlist {}
		}

		# append history to format entries
		# if the value in xformat or yformat is no standard axis, add to dropdown list
		set formathistory [PreferenceGet FormatHistory {x {} y {}}] 
		if {$explicit && $xformat(0) ne {} && $yformat(0) ne {}} {
			if {$xformat(0) ni $xformatlist} {
				dict unset formathistory x $xformat(0)
				dict set formathistory x $xformat(0) 1
			}

			if {$yformat(0) ni $yformatlist} {
				dict unset formathistory y $yformat(0)
				dict set formathistory y $yformat(0) 1
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

		PreferenceSet FormatHistory $formathistory

		lappend xformatlist {*}[lreverse [dict keys [dict get $formathistory x]]]
		lappend yformatlist {*}[lreverse [dict keys [dict get $formathistory y]]]

		for {set i 0} {$i < $Nformats} {incr i} {
			$w(xent$i) configure -values $xformatlist
			$w(yent$i) configure -values $yformatlist
		}

		if {$explicit && $focus=="x"} {
			focus $w(yent0)
			$w(yent0) selection range 0 end
			$w(yent0) icursor end
		}
		
		if {$explicit && $focus=="y"} {
			focus $w(xent0)
			$w(xent0) selection range 0 end
			$w(xent0) icursor end
		}

		# get units / axis labels for the current plot
		if {[catch {dict get $plotdata $xformat(0) attrs Unit} xunit]} {
			$w(Graph) set xlabel "$xformat(0)"
		} else {
			$w(Graph) set xlabel "$xformat(0) ($xunit)"
		}
		
		if {[catch {dict get $plotdata $yformat(0) attrs Unit} yunit]} {
			$w(Graph) set ylabel "$yformat(0)"
		} else {
			$w(Graph) set ylabel "$yformat(0) ($yunit)"
		}


		# determine plot styles for the data sets

		# transform available styles into dictionary
		foreach style [PreferenceGet PlotStyles { {linespoints color black pt circle } }] {
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

		# reset plot range if not requested otherwise
		if {!$keepzoom} {
			$w(Graph) set auto x
			$w(Graph) set auto y
		}

		
		# plot the data
		variable pointerinfo
		set extravars [dict create CLICKX $pointerinfo(clickx) CLICKY $pointerinfo(clicky)] 
		set aclist {CLICKX CLICKY Row}
		
		# cache the current data sets in this list
		variable HDFsshown {}

		set xyformats {}
		for {set i 0} {$i < $Nformats} {incr i} {
			if {[not_only_whitespace $yformat($i)]} {
				if {[not_only_whitespace $xformat($i)]} {
					lappend xyformats $xformat($i)
				} else {
					lappend xyformats $xformat(0)
				}
				lappend xyformats $yformat($i)
			}
		}
		
		dict for {fn style} $styles {
			if {$nfiles != 1} {
				# for multiple files, read the content to hdfdata
				# for single file, it's already there
				set hdfdata {}
				set hdfdata [bessy_reshape $fn -shallow]
			}
			
			foreach {xf yf} $xyformats {
				set fmtlist [list $xf $yf]

				set data [SELECTdata $fmtlist $hdfdata -allnan true -allnumeric true -extravars $extravars]
				# reduce to flat list
				set data [concat {*}$data]

				set title [file tail $fn]

				if {[llength $data] >= 2} {
					set id [$w(Graph) plot $data with {*}$style title $title]
					lappend plotid $id
					dict set HDFsshown $id $fn
				}
			}
			
			# build up autocomplete list
			lappend aclist {*}[bessy_get_keys $hdfdata]
		}

		# only show key for more than 1 file
		if {$nfiles > 1} {
			$w(Graph) set key on
		} else {
			$w(Graph) set key off
		}

		set plotstylecache $styles		

		# configure the autocompletion list
		set aclist [lsort -uniq -dictionary $aclist]
		
		for {set i 0} {$i < $Nformats} {incr i} {
			$w(xent0) configure -aclist $aclist
			$w(yent0) configure -aclist $aclist
		}

		HighlightRefresh
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
			lappend data [bessy_reshape $fullname -shallow]
			append columnconfig " 0 $shortname left"
		}

		$w(difftbl) configure -columns $columnconfig

		# make alphabetically sorted list of keys
		set allkeys {Motor {} Detector {} Dataset {} Meta {}}
		foreach category {Motor Detector Dataset Meta} {
			foreach dataset $data {
				dict lappend allkeys $category {*}[bessy_get_keys $dataset $category]
			}
		}
		
		dict for {category keys} $allkeys {
			dict set allkeys $category [lsort -dictionary -uniq $keys]
		}

		# compute difference
		foreach category  {Motor Detector Dataset Meta} {
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

	proc RestoreCWD {} {
		# focus out from path entry
		# set displayed path to CWD
		variable w
		DirChanged [$w(filelist) getcwd]
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

	proc SwitchFilterState {} {
		variable w
		variable filterenabled
		if {$filterenabled} {
			grid $w(filterent)
		} else {
			grid remove $w(filterent)
		}
		
		PreferenceSet FilterEnabled $filterenabled
		
		$w(filelist) RefreshRequest
	}

	proc SwitchGroupingState {} {
		variable w
		variable groupingenabled
		if {$groupingenabled} {
			grid $w(groupbox)
		} else {
			grid remove $w(groupbox)
		}
		
		PreferenceSet GroupingEnabled $groupingenabled
		
		GroupingUpdate
	}


	proc FilterUpdate {} {
		# filter was changed manually
		variable w
		variable filterexpression
		set hist [$w(filterent) cget -values]
		if {($filterexpression ni $hist) && ([string trim $filterexpression] != "")} {
			set hist [lrange [linsert $hist 0 $filterexpression] 0 15]
			PreferenceSet FilterHistory $hist
			$w(filterent) configure -values $hist
		}
		PreferenceSet FilterExpression $filterexpression
		$w(filelist) RefreshRequest
	}

	proc GroupingUpdate {} {
		variable w
		variable ActiveColumns
		variable GroupColumn 
		variable groupingenabled
		if {$groupingenabled} {
			$w(groupbox) configure -values $ActiveColumns
			$w(filelist) configure -foldcolumn $GroupColumn
			PreferenceSet GroupColumn $GroupColumn
		} else {
			$w(filelist) configure -foldcolumn {}
		}
		$w(filelist) RefreshRequest
	}


	proc OpenArgument {files} {
		variable w
		# take a number of absolute file names
		# navigate to top dir and display
		if {[llength $files]<1} { return }

		# check if "Test" is the first argument. In that case, 
		# run the test suite instead of opening the file

		lassign $files Test folder

		if {$Test eq "Test"} {
			RunTest $folder
			exit
		}
		
		if {[llength $files] == 1} {
			# check if the argument is a directory
			lassign $files dir
			if {[file isdirectory $dir]} {
				set absdir [file normalize $dir]
				$w(filelist) display $absdir
				DirChanged $absdir
				return
			}
		}
		# find common ancestor
		set ancestor [SmallUtils::file_common_dir $files]
		$w(filelist) display $ancestor
		DirChanged [file normalize $ancestor]
		$w(filelist) selectfiles $files
		set fileabs [lmap x $files {file normalize $x}]
		PreviewFile $fileabs
	}

	proc OpenStart {max} {
		variable w
		variable ProgressClock [clock milliseconds]
		variable ProgressDelay 100 ;# only after 100ms one feels a delay
		ClearFilterErrors
		$w(progbar) configure -maximum $max
		tk_busy hold .
		# puts "tk busy hold succeeded"
		nohup {HDFCache eval BEGIN}
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
		# sometimes tk busy fails - simply catch the error
		if {[catch { tk_busy forget . } err]} {
			puts stderr "tk busy failed: $err"
		} else {
			# puts stderr "tk busy forget succeeded"
		}

		FilterFinish
		nohup {HDFCache eval COMMIT}
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
			switch [llength $what] {
				0 { return {} }
				
				2 {
					# two-element list for min/max
					lassign $what min max
					if {$min eq $max} {
						# single value
						if {[catch {format $formatString $min} formatresult]} {
							# error formatting, return string rep
							return $min
						} else {
							return $formatresult
						}
					}

					if {[catch {format $formatString $min} minformatted]} {
						set minformatted $min
					}

					if {[catch {format $formatString $max} maxformatted]} {
						set maxformatted $max
					}

					return "$minformatted \u2014 $maxformatted"
				}

				1 {
					# single value
					puts stderr "Shouldn'be: single value in ListFormat $what"
					lassign $what value
					if {[catch {format $formatString $value} formatresult]} {
						# error formatting, return string rep
						return $value
					} else {
						return $formatresult
					}
				}

				default { 
					puts stderr "Multiple values in ListFormat $what"
					return $what
				}
			}
		} else {
			puts stderr "Not a list in ListFormat: $what"
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
			set data {}
			set data [bessy_reshape $fn -shallow]
			
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

		set defaults [dict create LIMIT Inf -allnan false -allnumeric false -extravars {} -firstrow 0]
		set opts [dict merge $defaults $args]
		if {[dict size $opts] != [dict size $defaults]} {
			return -code error "SELECTdata formats data ?LIMIT max? ?-allnan boolean? ?-extravars dictvalue? ?-firstrow n?"
		}

		set limit [dict get $opts LIMIT]
		set allnan [dict get $opts -allnan]
		set allnumeric [dict get $opts -allnumeric]

		set result {}
		set Row [dict get $opts -firstrow]
		# set common values
		set allkeys {}
		catch {namespace delete ::SELECT}
		namespace eval ::SELECT {} 
		dict for {var val} [dict get $opts -extravars] {
			namespace eval ::SELECT [list set $var $val]
			lappend allkeys $var
		}

		foreach key {MotorPositions DetectorValues OptionalPositions Plot {}} {
			if {[dict exists $hdfdata $key]} {
				dict for {var value} [dict get $hdfdata $key] {
					namespace eval ::SELECT [list set $var $value]
					lappend allkeys $var
				}
			}
		}

		set table [dict create]
		
		if {[dict exists $hdfdata MCA]} {
			dict set table MCA [dict get $hdfdata MCA]
			# put attributes of MCA into global variable space
			dict for {key value} [dict get $hdfdata MCA attrs] {
				namespace eval ::SELECT [list set $key $value]
				lappend allkeys $key
			}

		}

		if {[dict exists $hdfdata Motor]} {
			set table [dict merge $table [dict get $hdfdata Motor]]
		}
		
		if {[dict exists $hdfdata Detector]} {
			set table [dict merge $table [dict get $hdfdata Detector]]
		}

		if {[dict exists $hdfdata Dataset]} {
			set table [dict merge $table [dict get $hdfdata Dataset]]
		}

		lappend allkeys {*}[dict keys $table] Row

		set i 0
		foreach fmt $fmtlist {
			if {[lsearch -exact $allkeys $fmt]>=0} {
				# equal to one of the columns - interpret the whole thing as one variable name
				lset fmtlist $i "\[set [list $fmt]\]"
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
				if {$allnumeric &&  ![string is double -strict $lresult]} { set lresult NaN }
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

			proc truncmean {quant list} {
				# compute a truncated mean
				# which discards quant amount of the data
				# at the low and high end and computes the mean
				# of the remaining data
				
				set count [llength $list]
				
				# can't work for less than 3 items. 
				# For 3 should give median value
				if {$count < 3} { return [mean $list] }

				set slist [lsort -real $list]
				# leave at least 1 sample in the center
				# remove at least 1 from each side
				set trlength [expr {min(int(ceil($quant*$count)), ($count-1)/2)}]

				return [mean [lrange $slist $trlength end-$trlength]]
			}

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

	proc bessy_reshape {fn args} {
		# switch on the file extension
		switch [file extension $fn] {
			.hdf { set data [bessy_reshape_hdf4 $fn] 
				dict set data {} FileFormat HDF4 }
			.h5 { set data [bessy_reshape_hdf5 $fn {*}$args]
				dict set data {} FileFormat HDF5 }
			.dat { set data [bessy_reshape_ascii $fn]
				dict set data {} FileFormat ASCII }
			default { set data [bessy_reshape_ascii $fn] 
				dict set data {} FileFormat ASCII }
		}
		
		variable extradata
		if {[dict exists $extradata $fn]} {
			set edata [SmallUtils::dict_getdefault $data Dataset {}]
			dict set data Dataset [dict merge $edata [dict get $extradata $fn]]
		}
		variable extraplotdata
		if {[dict exists $extraplotdata $fn]} {
			set oplot [SmallUtils::dict_getdefault $data Plot {}]
			dict set data Plot [dict merge $oplot [dict get $extraplotdata $fn]]
		}

		return $data
	}

	proc bessy_reshape_hdf4 {fn} {

		SmallUtils::autovar hdf HDFpp -args $fn
		set hlist [$hdf dump]
		
		set BESSY_INF 9.9e36
		set BESSY_NAN -7.7e36

		set hdict {}
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
					catch {
						if {abs($v) >= $BESSY_INF || $v == $BESSY_NAN} {
							# invalid data point, replace by NaN
							lset data $index NaN
						} else {
							if {$index > $maxindex} {
								set maxindex $index
							}
						}
					} ;# silence error (if v is already NaN)
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

	proc eveH5getDSNames {d path} {
		dict keys [dict filter [dict get $d {*}$path] script {key value} {
			expr {[dict get $value type] eq "DATASET"}
		}]
	}

	proc eveH5getHDDSNames {d path} {
		dict keys [dict filter [dict get $d {*}$path] script {key value} {
			expr { ([dict get $value type] eq "GROUP") &&
				[dict exists $value attrs Name] }
		}]
	}

	proc eveH5OuterJoin {reshapedvar joinlist extrajoinlist} {
		upvar $reshapedvar reshaped
		
		# read data 
		set data {}
		foreach {group dset} $joinlist {
			set ds [dict get $reshaped $group $dset data]
			lappend data $ds
			lappend grouplist $group
		}

		# build unique PosList
		set PosList {}
		foreach ds $data {
			foreach {Pos dummy} $ds { lappend PosList $Pos }
		}
		set UniquePosList [lsort -unique -integer $PosList]

		# append data from extra list
		foreach {group dset} $extrajoinlist {
			set ds [dict get $reshaped $group $dset data]
			lappend data $ds
			lappend grouplist $group
		}

		# OUTER JOIN into result
		set result [list $UniquePosList]
		foreach ds $data  group $grouplist {
			set column {}
			set val NaN
			foreach Pos $UniquePosList {
				if {![dict exists $ds $Pos]} {
					# in case of a motor, continue old value
					# i.e. don't touch "val"
					# else, i.e. Detector, set to NaN = not measured
					if {$group != "Motor"} {
						set val NaN
					}
				} else {
					set val [dict get $ds $Pos]
				}
				lappend column $val
			}
			lappend result $column
		}

		set posjoinlist [list Dataset PosCounter {*}$joinlist {*}$extrajoinlist]
		# write back
		foreach {group dset} $posjoinlist {column} $result {
			dict set reshaped $group $dset data $column
		}

		dict set reshaped Dataset PosCounter attrs {}

		return $posjoinlist
	}
	
	variable extradata {}
	proc SetExtraColumns {fn data} {
		variable extradata
		variable hdfdata
		variable BessyClass
		variable HDFFiles

		dict for {name column} $data {
			set oldextra [SmallUtils::dict_getdefault $extradata $fn $name {}]
			dict set extradata $fn $name [dict merge $oldextra $column]
		}

		if {[llength $HDFFiles] == 1} {
			# in case of caching, add the extra data
			# also directly to the cached data
			lassign $HDFFiles curfn
			if {$fn eq $curfn} {
				set edata [SmallUtils::dict_getdefault $hdfdata Dataset {}]
				dict set hdfdata Dataset [dict merge $edata $data]
				set BessyClass [bessy_class $hdfdata]
			}
		}

		InvalidateDisplay
	}

	variable extraplotdata {}
	proc SetPlotColumn {fn type name} {
		if {$type ni {Motor Detector}} {
			return -code error "Unknown type $type"
		}

		variable hdfdata
		variable BessyClass
		variable HDFFiles
		variable extraplotdata


		dict set extraplotdata $fn $type $name
		if {[llength $HDFFiles] == 1} {
			# in case of caching, add the extra data
			# also directly to the cached data
			lassign $HDFFiles curfn
			if {$fn eq $curfn} {
				dict set hdfdata Plot $type $name
			}
			set BessyClass [bessy_class $hdfdata]
		}
	}


	proc h52dictpath {hpath} {
		set dpath {}
		foreach c [split $hpath /] {
			lappend dpath data $c
		}
		return $dpath
	}

	proc bessy_reshape_hdf5 {fn {shallow {}}} {
		SmallUtils::autovar hdf H5pp -args $fn
		switch $shallow {
			-shallow {
				set level 4
			}

			{} {
				set level 0
			}

			default { return -code error "Unknown option $shallow" }
		}

		set rawd [$hdf dump $level]
		# read version of HDF file
		if {![dict exists $rawd attrs EVEH5Version]} {
			# this is the original version without a version tag
			set EVEH5Version 1.0
		} else {
			set EVEH5Version [dict get $rawd attrs EVEH5Version]
		}

		# only "real" difference: path to the datasets
		set chain c1

		switch $EVEH5Version {
			1.0 { 
				set path [list data $chain data]
				set optpath {}
				set subfieldpaths {}
			}
			2.0 -
			3.0 -
			3.1 {
				set path [list data $chain data default data]
				set optpath [list data $chain data alternate data]
				set subfieldpaths {}
			}

			4.0 -
			5.0 -
			6  {
				set path [list data $chain data main data]
				set optpath [list data $chain data snapshot data]
				set subfieldpaths [list $chain/main/standarddev $chain/main/averagemeta]
			}


			default {
				error "Unknown EVE H5 data version: $EVEH5Version"

			}
		}
		
		# check for stddev data, which was not read from this level
		foreach h5path $subfieldpaths {
			set dpath [h52dictpath $h5path]
			if {[dict exists $rawd {*}$dpath]} {
				if {[dict size [dict get $rawd {*}$dpath data]] == 0} {
					# read the data back in
					set stdddata [$hdf dump 0 $h5path]
					dict set rawd {*}$dpath $stdddata
				}
			}
		}

		# new HDF5 stores data under /c1/deviceid
		# and MotorPos etc. under /device/
		set reshaped {}
		dict_move rawd {attrs} reshaped {{}}
		
		set DSnames [eveH5getDSNames $rawd $path]
		set joinsets {}
		foreach ds $DSnames {
			if {![catch {
				switch [dict get $rawd {*}$path $ds attrs DeviceType] {
					Channel { set group Detector }
					Axis { set group Motor }
					default { set group Detector }
				}
			}]} {
				# no error - move this dataset
				set name [dict get $rawd {*}$path $ds attrs Name]
				dict_move rawd [list {*}$path $ds attrs] reshaped [list $group $name attrs]
				dict_move rawd [list {*}$path $ds data] reshaped [list $group $name data]
				dict set rawd EVETranslate $ds $name
				lappend joinsets $group $name
			}

		}
		
		dict_move rawd [list data $chain data meta data PosCountTimer attrs] reshaped [list Dataset PosCountTimer attrs]
		dict_move rawd [list data $chain data meta data PosCountTimer data] reshaped [list Dataset PosCountTimer data]
		
		# check for stdddev data from averaging
		foreach h5path $subfieldpaths {
			set dpath [h52dictpath $h5path]
			if {[dict exists $rawd {*}$dpath] && [catch {
				set stdddata {}
				dict for {key dset} [dict get $rawd {*}$dpath data] {
					dict_assign $dset ndata dspace dtype data attrs
					
					# entries in the stddev group can have multiple 
					# columns with the PosCounter
					
					set fields [lassign $dtype poscounter]
					set name [dict get $dset attrs Name]

					set i 0
					while {$i < [llength $data]} {
						set poscount [lindex $data $i]
						#puts "$i $poscount"
						incr i
						foreach field $fields {
							set val [lindex $data $i]
							incr i
							dict lappend stdddata $name:$field $poscount $val
						}
					}

					foreach field $fields {
						dict set fattrs $name:$field $attrs
					}


				}

				#puts $stdddata
				#puts $attrs
				dict for {field data} $stdddata {
					dict set reshaped Dataset $field data $data
					dict set reshaped Dataset $field attrs [dict get $fattrs $field]
					lappend joinsets Dataset $field
				}

			} stddeverr]} {
				puts stderr "stddev: $stddeverr, $h5path, [dict keys [dict get $rawd data]]"
			}
		}


		# now join the datasets via PosCount
		# add PosCountTimer values, but don't use them in the join
		# this avoids empty lines for snapshot modules
		eveH5OuterJoin reshaped $joinsets {Dataset PosCountTimer}

		foreach {group name} $joinsets {
			dict_move reshaped [list $group $name attrs unit] reshaped [list $group $name attrs Unit]
		}

		# check for multidimensional data
		set HDDSnames [eveH5getHDDSNames $rawd $path]

		foreach MPname $HDDSnames {
			set rawmca [dict get $rawd {*}$path $MPname]
			set name [dict get $rawmca attrs Name]
			dict set reshaped HDDataset $name attrs [dict get $rawmca attrs]
			dict for {Pos dataset} [dict get $rawmca data] {
			       dict set reshaped HDDataset $name data $Pos [dict get $dataset data]
	       		}
			dict unset rawd {*}$path $MPname
		}

		dict set reshaped Unresolved $rawd

		# check for single-shot data stored in alternate / snapshot
		if {$optpath ne {} && [catch {
			dict for {key dset} [dict get $rawd {*}$optpath] {
				set name [dict get $dset attrs Name]
				set dtype [dict get $dset attrs DeviceType]
				set ndata [dict get $dset ndata]

				# a single data point goes to the traditional fields
				# MotorPositions, DetectorValues, OptionalPositions
				# 
				# multiple positions go to the new fields SnapshotValues
				# with timestamps
				switch $ndata {
					0 { continue }
					1 {
						lassign [dict get $dset data] timeval data
						
						switch $dtype {
							Axis {
								dict set reshaped MotorPositions $name $data
							}
							Channel {
								dict set reshaped DetectorValues $name $data
							}
							default {
								dict set reshaped OptionalPositions $name $data
							}
						}
					}
					default {
						switch $dtype {
							Axis {
								dict set reshaped SnapshotValues Motor $name $dset
							}
							Channel {
								dict set reshaped SnapshotValues Detector $name $dset
							}
							default {
								dict set reshaped SnapshotValues Meta $name $dset
							}
						}
					}
				}
			}
		} snaperr]} {
			puts stderr $snaperr
		}

		# check for preferredChannel / Axis and create Plot info
		set plotinfo [dict get $rawd data $chain attrs]
		if {![catch {dict get $plotinfo preferredAxis} axis]} {
			# find corresponding axis name
			if {![catch {dict get $rawd EVETranslate $axis} Motor]} {
				dict set reshaped Plot Motor $Motor
			}
		}

		if {![catch {dict get $plotinfo preferredChannel} channel]} {
			# find corresponding axis name
			if {![catch {dict get $rawd EVETranslate $channel} Detector]} {
				dict set reshaped Plot Detector $Detector
			}
		}

		if {![catch {dict get $plotinfo PreferredNormalizationChannel} normchannel]} {
			# find corresponding axis name
			if {![catch {dict get $rawd EVETranslate $normchannel} Monitor]} {
				dict set reshaped Plot Monitor $Monitor
			}
		}

		return $reshaped
	}

	proc bessy_reshape_ascii {fn} {
		# read file completely into RAM
		SmallUtils::autofd fd $fn r
		set lines [split [read $fd] \n]

		set reshaped {}
		# extract header: all lines from beginning
		# which start with # as the first non-blank character
		set header {}
		foreach line $lines {
			if {[regexp {^\s*#(.*)$} $line -> hline]} {
				lappend header $hline
			} else {
				break
			}
		}

		dict set reshaped Motor {}
		dict set reshaped Motors {}
		dict set reshaped Detector {}
		dict set reshaped Detectors {}
		dict set reshaped Dataset {}
		dict set reshaped Datasets {}
		
		set columns {}
		set attribpath {{}}
		set indents [list 0]
		foreach hline $header {
			# skip empty lines
			if {[regexp {^\s*$} $hline]} { continue }
			
			# parse attributes of the form key = value
			if {[regexp {^\s*(.*?)\s*=\s*(.*)\s*$} $hline -> key value]} {
				dict set reshaped {*}$attribpath $key $value
				continue
			} 			
			
			# parse 
			if {[regexp {^(\s*)(.*):\s*$} $hline -> indent key]} {
				if {$attribpath eq {{}} } { set attribpath {} }
				set newindlength [string length $indent]
				if {$newindlength > [lindex $indents end]} {
					lappend attribpath $key
					lappend indents $newindlength
				} else {
					while {$newindlength <= [lindex $indents end]} {
						set indents [lrange $indents 0 end-1]
						set attribpath [lrange $attribpath 0 end-1]
					}
					lappend indents $newindlength
					lappend attribpath $key
				}

				dict set reshaped {*}$attribpath {}
				continue
			}
			 # not an attribute or folder name
			 # could be a column definition
			 if {[string is list $hline]} {
				set columns $hline
			} else {
				set columns [regexp -all -inline {\S+} $hline]
			}

		}
		
		# move the contents from Motors to Motor/attrs
		dict for {motor attrs} [dict get $reshaped Motors] {
			dict set reshaped Motor $motor attrs $attrs
			dict set reshaped Motor $motor data {}
		}

		# move the contents from Detectors to Detector/attrs
		dict for {detector attrs} [dict get $reshaped Detectors] {
			dict set reshaped Detector $detector attrs $attrs
			dict set reshaped Detector $detector data {}
		}

		# move the contents from Datasets to Dataset/attrs
		dict for {detector attrs} [dict get $reshaped Datasets] {
			dict set reshaped Dataset $detector attrs $attrs
			dict set reshaped Dataset $detector data {}
		}


		set table {}
		set NR 0
		set maxcolnum 0
		foreach line $lines {
			# ignore all empty and commented lines
			if {[regexp {^\s*(#.*)?$} $line]} { continue }
			
			set data [regexp -all -inline {\S+} $line]
			# try to convert them into double, if possible
			set allnan true
			set dconv [lmap x $data {
				if {[string is double -strict $x]} {
					set allnan false
					set v $x
				} else {
					set v NaN
				}
				set v
			}]

			if {$allnan} { 
				# assume that this is an unquoted column definition line
				# == Origin format
				if {[string is list $line]} {
					set columns $line
				} else {
					set columns $data
				}
				continue
			}

			if {[llength $dconv] > $maxcolnum} {
				# add new columns 
				set newmaxcolnum [llength $dconv]
				for {set i $maxcolnum} {$i<$newmaxcolnum} {incr i} {
					dict set table $i [lrepeat $NR NaN]
				}
				set maxcolnum $newmaxcolnum
			}
			
			for {set i 0} {$i<$maxcolnum} {incr i} {
				set x [lindex $dconv $i]
				if {$x eq {}} { set x NaN }
				dict lappend table $i $x
			}
		
			incr NR

		}
		
		set allsets {}
		
		# stick data into reshaped array
		for {set i 0} {$i<$maxcolnum} {incr i} {
			set c [lindex $columns $i]
			set data [dict get $table $i]
			if {[dict exists $reshaped Motor $c]} {
				dict set reshaped Motor $c data $data
				continue
			}
			if {[dict exists $reshaped Detector $c]} {
				dict set reshaped Detector $c data $data
				continue
			}
			if {[dict exists $reshaped Dataset $c]} {
				dict set reshaped Dataset $c data $data
				continue
			}
			# if not found in either motor or detector array
			# set path to Datasets
			
			if {$c ne {}} {
				dict set reshaped Dataset $c data $data
			}
			set colname Column[expr {$i+1}]
			dict set allsets $colname data $data
			# always save to Columnx, in case it got mixed up badly
		}

		dict set reshaped Dataset [dict merge [dict get $reshaped Dataset] $allsets]
		
		# reshape SnapshotValues
		foreach category {Motor Detector Meta} {
			if {[dict exists $reshaped SnapshotValues $category]} {
				set keys [dict keys [dict get $reshaped SnapshotValues $category]]
				foreach key $keys {
					set data [dict get $reshaped SnapshotValues $category $key]
					dict unset reshaped SnapshotValues $category $key
					dict set reshaped SnapshotValues $category $key data $data
				}
			}
		}
		
		return $reshaped

	}

	proc bessy_class {data} {
		# classify dataset into Images, Plot and return plot axes
		set images false
		foreach imagekey [PreferenceGet ImageDetectorFilePathRules {}] {
			if {[dict exists $data Detector $imagekey data]} {
				set images true
				# keep imagekey to read the images later
				break
			}
		}

		set mca [dict exists $data MCA]
		set hdds [dict exists $data HDDataset]
		set fileformat [SmallUtils::dict_getdefault $data {} FileFormat {}]
		
		# determine available axes = motors and detectors
		if {[catch {dict keys [dict get $data Motor]} motors]} {
			set motors {}
		}
		
		if {[catch {dict keys [dict get $data Detector]} detectors]} {
			set detectors {}
		}
		
		if {[catch {dict keys [dict get $data Dataset]} datasets]} {
			set datasets {}
		}
		
		set axes [list {*}$motors {*}$detectors {*}$datasets]

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

		if {$motor eq {} || $detector eq {}} {
			# take the first two different columns
			if {[llength $axes]==1} {
				set motor Row
				set detector [lindex $axes 0]
			} else {
				lassign $axes motor detector
			}
		}

		# now check for different classes. MCA has only this dataset, no motors etc.
		set class UNKNOWN

		if {$mca && $fileformat eq "HDF4"} {
			set motors {Row}
			set detectors {MCA}
			set length [llength [dict get $data MCA data]]
			set class MCA
		} elseif {$images} {
			# file contains images. Check for one or more
			set length [llength [filternan [dict get $data Detector $imagekey data]]]
			if {$length == 1} {
				set class SINGLE_IMG
			}

			if {$length > 1} {
				set class MULTIPLE_IMG
			}
			# otherwise no images are found
		} else {
			if {$hdds} {
				set class HDDS
			} elseif {$Plot} {
				# there is a valid Plot
				set class PLOT
			} else {
				# could not identify
				set class UNKNOWN
			}

			# determine length from first axis
			set firstaxis [lindex $axes 0]
			foreach cat {Motor Detector Dataset} {
				if {[catch {llength [dict get $data $cat $firstaxis data]} length]} {
					set length 0
				} else {
					break
				}
			}
		}
		
		return [dict create class $class motor $motor detector $detector \
					nrows $length motors $motors detectors $detectors \
					datasets $datasets axes $axes]
	}

	proc bessy_get_field {hdfdata field} {
		# return min/max for a given field of the data
		# or empty string, if the field is not found
		
		set values {}

		foreach datakey {Detector Motor Dataset} {
			# keys that are tried to find data
			if {[dict exists $hdfdata $datakey $field data]} {
				lappend values {*}[dict get $hdfdata $datakey $field data]
			}
		}
		
		if {[llength $values] == 0} {
			# only consult the snapshot values, when nothing was found
			# this inhibits wrong ranges from stale motor positions
			foreach attrkey {DetectorValues MotorPositions OptionalPositions Plot {}} {
				# keys that might store the field as a single value in the attrs
				if {[dict exists $hdfdata $attrkey $field]} {
					lappend values [dict get $hdfdata $attrkey $field]
				}
			}
			
			foreach category {Detector Motor Meta} {
				if {[dict exists $hdfdata SnapshotValues $category $field data]} {
					lappend values {*}[lmap {_ val} [dict get $hdfdata SnapshotValues $category $field data] {set val}]
				}
			}

			# MCA stores values as an attribute in the main field
			if {[dict exists $hdfdata MCA attrs $field]} {
				lappend values [dict get $hdfdata MCA attrs $field]
			}

		}

		if {[llength $values] == 0} { return {} }

		if {[llength $values] == 1} {
			# only a single value - min and max are equal
			lassign $values value
			return [list $value $value]
		}

		# if more than one value is found, compute range 
		# first try sorting as numbers, then try dictionary (works always)
		if {[catch {lsort -real [filternan $values]} sortedvalues]} {
			set sortedvalues [lsort -dictionary $values]
		}
		
		if {[llength $sortedvalues] == 0} {
			# all values were NaN and kicked out
			return [list NaN NaN]
		}

		set minval [lindex $sortedvalues 0]
		set maxval [lindex $sortedvalues end]
		return [list $minval $maxval]
	}

	proc bessy_get_all_fields {hdfdata} {
		# return a dictionary which describes the datafile
		# inefficient but .. hey
		set result {}
		set allkeys [bessy_get_keys $hdfdata]
		foreach key $allkeys {
			dict set result $key [bessy_get_field $hdfdata $key]
		}
		return $result
	}

	proc bessy_get_keys {hdfdata {category {Detector Motor Dataset Meta}}} {
		set datakeys {}
		set attrkeys {}
		
		foreach catkey $category {
			switch $catkey {
				Detector {
					lappend datakeys Detector
					lappend datakeys {SnapshotValues Detector}
					lappend attrkeys DetectorValues
				}
				Motor {
					lappend datakeys Motor
					lappend datakeys {SnapshotValues Motor}
					lappend attrkeys MotorPositions OptionalPositions
				}
				Dataset {
					lappend datakeys Dataset
				}
				Meta {
					lappend datakeys {SnapshotValues Meta}
					lappend attrkeys Plot {}
				}
				Axes {
					lappend datakeys Detector Motor Dataset
				}
				default {
					return -code error "Unknown category: $catkey. Expected Motor, Detector or Meta"
				}
			}
		}

		set keys {}
		foreach datakey $datakeys {
			# keys that are tried to find data
			if {[dict exists $hdfdata {*}$datakey]} {
				lappend keys {*}[dict keys [dict get $hdfdata {*}$datakey]]
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

	proc bessy_get_keys_flist {flist {category {Detector Motor Dataset Meta}}} {
		set allkeys {}
		foreach fn $flist {
			if {![catch {bessy_reshape $fn -shallow} data]} {
				lappend allkeys {*}[bessy_get_keys $data $category]
			}
		}
		return [lsort -uniq $allkeys]
	}

	proc SearchCmd {} {
		set wname .__searchdialog
		if {[winfo exists $wname]} {
			raise $wname
		} else {
			SearchDialog $wname -fieldlist [GetCachedFieldNames] -title "Search data file"
		}
	}

	proc SearchHDF {foldername criteria {limit 100}} {
		variable w
		set jointables "HDFFiles"
		set whereclauses {}
		set count 0
		foreach crit $criteria {
			lassign $crit var mode val1 val2
			if { $mode eq "meta"} {
				lappend whereclauses "HDFFiles.$var $val1 :value$count"
				set value$count $val2
				continue
			}

			incr count
			append jointables ", Fields as f$count, FieldValues as fv$count"
			set whereclause "fv$count.hdfid = HDFFiles.id  AND f$count.name = :var$count AND f$count.id = fv$count.fieldid "
			switch $mode {
				contains {
					append whereclause "AND (fv$count.minimum LIKE :pattern$count OR fv$count.maximum LIKE :pattern$count)"
					set pattern$count "%$val1%"
				}

				between {
					append whereclause "AND (fv$count.minimum <= :maxval$count AND fv$count.maximum >= :minval$count)"
				}

				covers {
					append whereclause "AND (fv$count.minimum <= :minval$count AND fv$count.maximum >= :maxval$count)"
				}

				included {
					append whereclause "AND (fv$count.minimum >= :minval$count AND fv$count.maximum <= :maxval$count)"

				}

				"" {
					append whereclause ""
				}

				default {
					return -code error "Unknown clause $mode"
				}
			}
			
			
			set var$count $var
			set minval$count $val1
			set maxval$count $val2
			lappend whereclauses "( $whereclause )"
		}
		set query "SELECT HDFFiles.path FROM $jointables\n WHERE HDFFiles.class != 'MCA' AND [join $whereclauses "\nAND "]\n ORDER BY HDFFiles.mtime DESC LIMIT $limit;"
		puts $query
		puts [HDFCache eval "EXPLAIN QUERY PLAN $query"]
		set timing [time {set result [HDFCache eval $query]}]
		puts $timing
		$w(filelist) AddVirtualFolder $foldername $result
		return [llength $result]
	}

	proc RunTest {folder} {
		# open all .hdf .h5 and .dat files in the given folder
		# compare with the ASCII dump in the dump folder
		package require fileutil

		set files [lsort [glob -directory $folder *.hdf *.h5 *.dat]]
		set errors {}
		set diffs  {}
		set success 0
		set failed 0
		foreach fn $files {
			puts "Testing $fn"
			set rootname [file rootname [file tail $fn]]

			if {[catch {
				set hdfdata [bessy_reshape $fn]
				set dump [Dump $hdfdata]
				set fielddump [DumpFields $hdfdata]
				
				set refdump [fileutil::cat -encoding utf-8 -translation binary $folder/dump/${rootname}_dump.dat]
				set reffdump [fileutil::cat -encoding utf-8 -translation binary $folder/dump/${rootname}_fields.dat]


				set diff [SmallUtils::difftext $refdump $dump]
				set fdiff [SmallUtils::difftext $reffdump $fielddump]

				} _ errdict]} {
				# got an error
				set error [dict get $errdict -errorinfo]
				dict set errors $fn $error
				incr failed
				puts "Test failed with error: $fn"
				puts $error
			} else {
				if {$diff ne {} || $fdiff ne {}} {
					dict set $diffs $fn $diff
					puts "Test failed $fn: Result was different"
					puts $diff
					puts $fdiff

					catch { 
						# write result into file in the dumps dir
						fileutil::writeFile -encoding utf-8 -translation binary $folder/dump/${rootname}_faileddump.dat $dump 
					}

					catch { 
						# write fields into file in the dumps dir
						fileutil::writeFile -encoding utf-8 -translation binary $folder/dump/${rootname}_failedfields.dat $fielddump 
					}

					incr failed
				} else {
					incr success
				}
			}
			
		}

		set nerrors [dict size $errors]
		set ndiffs [dict size $diffs]

		puts "Result: failed $failed, successful $success,  total [expr {$success+$failed}]"

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

	proc dict_expr {dictvalue args} {
		# evaluate an expression by dict with
		# wrapping in a proc ensures that 
		# the variables do not clutter 
	
		# NOTE: Could be implemented by dict with
		# but that is 10x slower in case of big dicts
		namespace eval ::DICT_EXPR {}
		set expr [lindex $args end]
		set keys [lrange $args 0 end-1]
		set vardict [dict get $dictvalue {*}$keys]
		dict for {var val} $vardict {
			if {[string is list $val] && [llength $val] == 2} {
				# typical min / max value
				lassign $val min max
				if {$min eq $max} { set val $min }
			}
			set ::DICT_EXPR::$var $val
		}

		if {[catch {namespace eval ::DICT_EXPR [list expr $expr]} result]} {
			# delete vars and rethrow error
			namespace delete ::DICT_EXPR
			return -code error $result
		}
		namespace delete ::DICT_EXPR
		return $result
	}

	variable iconcache {{} {}}
	variable icondirs {}
	proc AddIconDir {dir} {
		variable icondirs
		if [file isdirectory $dir] {
			lappend icondirs $dir
		}
	}
	
	proc InitIconCache {} {
		variable basedir
		variable profiledir
		AddIconDir $basedir/icons
		AddIconDir $profiledir/icons
		
		# icons for the file browser
		variable IconClassMap {
			MCA  mca
			HDDS mca
			MULTIPLE_IMG image-multiple
			SINGLE_IMG image-x-generic
			PLOT graph
			UNKNOWN unknown
		}
			
		set IconClassMap [dict map {class icon} $IconClassMap {IconGet $icon}]	
	}

	proc IconGet {name} {
		variable iconcache
		variable icondirs
		if {[dict exists $iconcache $name]} {
			return [dict get $iconcache $name]
		} else {
			foreach dir $icondirs {
				set fn [file join $dir $name.png]
				if {[file exists $fn]} break
			}
			if {[catch {image create photo -file $fn} iname]} {
				return {} ;# not found
			} else {
				dict set iconcache $name $iname
				return $iname
			}
		}
	}
	
	proc InstallPackage {fn} {
		# takes a .bkpg package file and
		# installs it in the local plugin folder.
		set zipfd [vfs::zip::Mount $fn $fn]
		# first check for manifest and single directory
		set manifn [file join $fn MANIFEST]
		if {![file exists $manifn]} {
			AbortInstall "$fn is not a valid BessyHDFViewer package (missing manifest)"
		}
		
		set manifest [fileutil::cat $manifn]

		set pkgdirs [glob -type d -directory $fn -tails *]
		if {[llength $pkgdirs] != 1} {
			AbortInstall "$fn is not a valid BessyHDFViewer package (single subdir)"
		}
		lassign $pkgdirs pkgdir

		set msg "You are about to install package $pkgdir. Continue?"
		set ans [tk_messageBox -icon question -message $msg -detail $manifest -type yesno]
	
		if {$ans == "yes"} {
			set plugindir $::DataEvaluation::plugindir
			file mkdir $plugindir
			set targetdir $plugindir/$pkgdir
			if {[file exists $targetdir]} {
				set nolink [catch {file readlink $targetdir} linktarget]
				if {$nolink} {
					set version [AboutReadVersion $targetdir]
				} else {
					set version "Link to $linktarget"
				}

				set msg "Plugin already installed" 
				set detail "Installed version:\n"
				append detail "$version\n"
				append detail "Version in the package:"
				append detail [AboutReadVersion $fn/$pkgdir]\n
				append detail "Overwrite?"
				set ans [tk_messageBox -icon question -message $msg -detail "$version\n\nOverwrite?" -type okcancel -title "Overwrite?"]
				if {$ans == "cancel"} {
					AbortInstall "Cancelled"
				}

				if {$nolink} {
					file delete -force $targetdir
				} else {
					file delete $targetdir
				}
			}
			file copy -force $fn/$pkgdir $plugindir
			tk_messageBox -type ok -icon info -title "Package installed!" -message "Installation successful!" -detail "You need to restart BessyHDFViewer to take effect"
		}
		vfs::zip::Unmount $zipfd $fn
	}

	proc AbortInstall {msg} {
		catch {uplevel 1 {vfs::zip::Unmount $zipfd $fn}} err
		puts stderr $err
		tk_messageBox -message "Installation aborted" -detail $msg -type ok -icon info
		return -level 2
	}

}

BessyHDFViewer::Init $argv
