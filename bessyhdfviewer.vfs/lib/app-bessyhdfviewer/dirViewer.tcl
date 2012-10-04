#!/bin/sh
# the next line restarts using wish \
	exec wish "$0" ${1+"$@"}

#==============================================================================
# Demonstrates how to use a tablelist widget for displaying the contents of a
# directory.
#
# Copyright (c) 2010-2012  Csaba Nemethi (E-mail: csaba.nemethi@t-online.de)
#==============================================================================

package require tablelist_tile 5.6
package require snit
package require SmallUtils

#
# Add some entries to the Tk option database
#
#==============================================================================
# Contains some Tk option database settings.
#
# Copyright (c) 2004-2012  Csaba Nemethi (E-mail: csaba.nemethi@t-online.de)
#==============================================================================

namespace eval dirViewer {} {
	#
	# Get the current windowing system ("x11", "win32", "classic", or "aqua")
	#
	variable winSys
	if {[catch {tk windowingsystem} winSys] != 0} {
		switch $::tcl_platform(platform) {
		unix      { set winSys x11 }
		windows   { set winSys win32 }
		macintosh { set winSys classic }
		}
	}

	#
	# Add some entries to the Tk option database
	#
	if {[string compare $winSys "x11"] == 0} {
		#
		# Create the font TkDefaultFont if not yet present
		#
		catch {font create TkDefaultFont -family Helvetica -size -12}

		option add *Font			TkDefaultFont
		option add *selectBackground	#678db2
		option add *selectForeground	white
	} else {
		option add *ScrollArea.borderWidth			1
		option add *ScrollArea.relief			sunken
		option add *ScrollArea.Tablelist.borderWidth	0
		option add *ScrollArea.Tablelist.highlightThickness	0
		option add *ScrollArea.Text.borderWidth		0
		option add *ScrollArea.Text.highlightThickness	0
	}

	option add *Tablelist.background	white
	option add *Tablelist.stripeBackground	#e4e8ec
	option add *Tablelist.setGrid		yes
	option add *Tablelist.movableColumns	yes
	option add *Tablelist.labelCommand	tablelist::sortByColumn
	option add *Tablelist.labelCommand2	tablelist::addToSortColumns

	snit::widget dirViewer {

		hulltype ttk::frame
		component tbl
		component vsb
		component hsb
		variable homedir
		variable cwd

		variable RebuildPending false
		variable PendingState [dict create]

		option -globpattern -default {*}
		option -columns -default {} -configuremethod ChangeColumns
		option -columnoptions -default {} -configuremethod ChangeColumns
		option -classifycommand -default {}
		option -selectcommand -default {}
		option -hasparent -default 1 -readonly 1
		delegate option -selectmode to tbl

		#------------------------------------------------------------------------------
		# Constructor
		#
		# Displays the contents of the directory dir in a tablelist widget.
		#------------------------------------------------------------------------------
		constructor {dir args} {
			#
			# Create a scrolled tablelist widget with 3 dynamic-
			# width columns and interactive sort capability
			#
			set homedir $dir
			set cwd $homedir

			install tbl using tablelist::tablelist $win.tbl \
				-expandcommand [mymethod expandCmd] -collapsecommand [mymethod collapseCmd] \
				-xscrollcommand [list $win.hsb set] -yscrollcommand [list $win.vsb set] \
				-movablecolumns no -setgrid no -showseparators yes -height 18 -width 80 -exportselection 0 \
				-stretch end -titlecolumns 1 -protecttitlecolumns 1 -movablecolumns 1 -movecolumncursor hand1

			if {[$tbl cget -selectborderwidth] == 0} {
				$tbl configure -spacing 1
			}

			$self ChangeColumns -columns {}

			install vsb using ttk::scrollbar $win.vsb -orient vertical   -command [list $tbl yview]
			install hsb using ttk::scrollbar $win.hsb -orient horizontal -command [list $tbl xview]
			
			set bodyTag [$tbl bodytag]
			bind $bodyTag <Double-1>   [mymethod putContentsOfSelFolder]
			bind $tbl <<TablelistSelect>> [mymethod notifySelect]
			bind $tbl <<TablelistColumnMoved>> [mymethod notifyColumnMoved]

			#
			# Manage the widgets
			#
			grid $tbl -row 0 -rowspan 2 -column 0 -sticky news
			if {[string compare $dirViewer::winSys "aqua"] == 0} {
				grid [$tbl cornerpath] -row 0 -column 1 -sticky ew
				grid $vsb	       -row 1 -column 1 -sticky ns
			} else {
				grid $vsb -row 0 -rowspan 2 -column 1 -sticky ns
			}

			grid $hsb -row 2 -column 0 -sticky ew
			grid rowconfigure    $win 1 -weight 1
			grid columnconfigure $win 0 -weight 1

			# read in the options
			$self configurelist $args

			#
			# Request un update of the contents of this viewer
			#
			$tbl sortbycolumn 0
			SmallUtils::defer [mymethod refreshView]
		}


		method ChangeColumns {option value} {
			set options($option) $value
			# either columns or columnoptions have changed. Rebuild. 
		
			if {!$RebuildPending} {
				set PendingState [$self saveView]
				set RebuildPending true
				$tbl delete 0 end
			}

			switch $option {
				-columns {
					# set column headings 
					set columnspec {0 "Name" left}
					foreach col $options(-columns) {
						lappend columnspec 0 $col left
					}

					$tbl configure -columns $columnspec
					
					if {[$tbl sortcolumn] >= [llength $options(-columns)] + 1 } {
						# index of sorted column is out of range
						$tbl sortbycolumn 0
					}
				}

				-columnoptions {
					$tbl columnconfigure 0 -formatcommand [myproc formatFile] -sortmode command -sortcommand [myproc compareFile]

					set col 1
					foreach opt $options(-columnoptions) {
						if {$col > [llength $options(-columns)]} { break }
						$tbl columnconfigure $col {*}$opt
						incr col
					}
				}
			}

			SmallUtils::defer [mymethod refreshView]
		}

		#------------------------------------------------------------------------------
		# putContents
		#
		# Outputs the contents of the directory dir into the tablelist widget tbl, as
		# child items of the one identified by nodeIdx.
		#------------------------------------------------------------------------------
		method putContents {dir nodeIdx} {
			#
			# The following check is necessary because this procedure
			# is also invoked by the "Refresh" and "Parent" buttons
			#
			if {[string compare $dir ""] != 0 &&
			(![file isdirectory $dir] || ![file readable $dir])} {
				bell
				if {[string compare $nodeIdx "root"] == 0} {
					set choice [tk_messageBox -title "Error" -icon warning -message \
					"Cannot read directory \"[file nativename $dir]\"\
						-- replacing it with nearest existent ancestor" \
						-type okcancel -default ok]
					if {[string compare $choice "ok"] == 0} {
						while {![file isdirectory $dir] || ![file readable $dir]} {
							set dir [file dirname $dir]
						}
					} else {
						return ""
					}
				} else {
					return ""
				}
			}

			if {[string compare $nodeIdx "root"] == 0} {
				$tbl delete 0 end
				set row 0
			} else {
				set row [expr {$nodeIdx + 1}]
			}

			# create list of directories and files. If $dir == ""
			# special case on Windows (list volumes)
			if {$dir == ""} {
				set directories [file volumes]
				set files {}
			} else {
				set directories [glob -nocomplain -types d -directory $dir *]
				set files [glob -nocomplain -types f -directory $dir {*}$options(-globpattern)]
			}
			

			set prog_max [expr {max(1,[llength $directories]+[llength $files]-1)}]
			event generate $win <<ProgressStart>> -data $prog_max
			set progress 0
			event generate $win <<Progress>> -data $progress

			#
			# Build a list from the data of the subdirectories and
			# files of the directory dir.
			# structure is: First column contains a list with file|directory and relative name
			# then comes the data to be displayed in the additional columns, then an image
			# for directories, the image is ignored
		
			set itemList {}
			
			foreach dirname $directories {
				
				if {$dir == "" } {
					# in case of volume display, avoid [file tail]
					# as it truncates C:/ to ""
					set dirtail $dirname
				} else {
					set dirname [file normalize $dirname]
					set dirtail [file tail $dirname]
				}

				if {$options(-classifycommand) != {}} {
					set class [uplevel #0 $options(-classifycommand) [list directory $dirname]]
				} else {
					set class [$self classifydefault [list directory $dirname]]
				}

				lappend itemList [list [list directory $dirtail] {*}$class $dirname]
				incr progress
				event generate $win <<Progress>> -data $progress

			}
			
			foreach fn $files {
				set fullname [file normalize $fn]
				set tail [file tail $fn]
				
				if {$options(-classifycommand) != {}} {
					set class [uplevel #0 $options(-classifycommand) [list file $fullname]]
				} else {
					set class [$self classifydefault [list file $fullname]]
				}

				set class [uplevel #0 $options(-classifycommand) [list file $fullname]]
				lappend itemList [list [list file $tail] {*}$class $fullname]

				incr progress
				event generate $win <<Progress>> -data $progress

			}

			#
			# Sort the above list and insert it into the tablelist widget
			# tbl as list of children of the row identified by nodeIdx
			#
			set itemList [$tbl applysorting $itemList]
			$tbl insertchildlist $nodeIdx end $itemList

			#
			# Insert an image into the first cell of each newly inserted row
			#
			foreach item $itemList {
				set fullname [lindex $item end]
				set image [lindex $item end-1]
				set type [lindex $item 0 0]

				if {$type == "file"} {			;# file
					$tbl cellconfigure $row,0 -image $image
				} else {						;# directory
					$tbl cellconfigure $row,0 -image [IconGet closed-folder]

					#
					# Mark the row as collapsed
					$tbl collapse $row
				}

				# store the full absolute path in this node
				$tbl rowattrib $row pathName $fullname 

				incr row
			}


			event generate $win <<ProgressFinished>>
		}

		method display {dir} {
			set cwd $dir
			$self putContents $dir root
			set options(-hasparent) [expr {$cwd != {}}]
		}

		method getcwd {} {
			return $cwd
		}

		method displayCmd {dir} {
			$self display $dir
			event generate $win <<DirviewerChDir>> -data $dir
		}

		method goHome {} {
			$self displayCmd $homedir
		}

		method goUp {} {
			set parent [file dirname $cwd]
			if {$parent == $cwd} {
				# we are on the top level of this volume
				# set parent to "" to signal displaying of volumes
				set parent ""
			}

			if {$cwd != ""} {
				$self displayCmd $parent
			}
		}

		method collapseCurrent {} {
			set id ""
			lassign [$tbl curselection] id
			if {$id != ""} {
				set parent [$tbl parent $id]
				if {$parent != "root"} {
					$tbl collapse $parent -partly
					$tbl selection clear 0 end
					$tbl selection set $parent
				}
			}
		}

		#------------------------------------------------------------------------------
		# formatFile
		#
		# Returns the file name which is the second item in the list
		#------------------------------------------------------------------------------
		proc formatFile val {
			lindex $val 1
		}

		proc compareFile {f1 f2} {
			lassign $f1 t1 n1
			lassign $f2 t2 n2
			if {$t1 == $t2} {
				return [string compare $n1 $n2]
			} else {
				if {$t1 == "directory"} {
					return -1
				} else {
					return 1
				}
			}
		}

		proc classifydefault {type fn} {
			return [IconGet unknown]
		}

		#------------------------------------------------------------------------------
		# expandCmd
		#
		# Outputs the contents of the directory whose leaf name is displayed in the
		# first cell of the specified row of the tablelist widget tbl, as child items
		# of the one identified by row, and updates the image displayed in that cell.
		#------------------------------------------------------------------------------
		method expandCmd {ttbl row} {
			if {[$tbl childcount $row] == 0} {
				set dir [$tbl rowattrib $row pathName]
				$self putContents $dir $row
			}

			if {[$tbl childcount $row] != 0} {
				$tbl cellconfigure $row,0 -image [IconGet open-folder]
			}
		}

		#------------------------------------------------------------------------------
		# collapseCmd
		#
		# Updates the image displayed in the first cell of the specified row of the
		# tablelist widget tbl.
		#------------------------------------------------------------------------------
		method collapseCmd {ttbl row} {
			$tbl cellconfigure $row,0 -image [IconGet closed-folder]
		}

		#------------------------------------------------------------------------------
		# putContentsOfSelFolder
		#
		# Outputs the contents of the selected folder into the tablelist widget tbl.
		#------------------------------------------------------------------------------
		method putContentsOfSelFolder {} {
			set row [$tbl curselection]
			set isdir [expr {[lindex [$tbl get $row] 0 0]=="directory"}]
			if {$isdir} {		;# directory item
				set dir [$tbl rowattrib $row pathName]
				$self displayCmd $dir
			} else {						;# file item
				bell
			}
		}

		
		#------------------------------------------------------------------------------
		# refreshView
		#
		# Redisplays the contents of the directory dir in the tablelist widget tbl and
		# restores the expanded states of the folders as well as the vertical view.
		#------------------------------------------------------------------------------
		method refreshView {} {
			#
			# Save the vertical view and get the path names
			# of the folders displayed in the expanded rows
			#
			if {$RebuildPending} {
				set view $PendingState
				set RebuildPending false
			} else {
				set view [$self saveView]
			}
			#
			# Redisplay the directory's (possibly changed) contents and restore
			# the expanded states of the folders, along with the vertical view
			#
			$self display $cwd
			$self restoreView $view
		}

		#------------------------------------------------------------------------------
		# restoreView
		#
		# Expands those children of the parent identified by nodeIdx that display
		# folders whose path names are the names of the elements of the dict specified
		# by the last argument.
		#------------------------------------------------------------------------------
		method restoreView {state} {
			$self restoreExpandedStates_rec root [dict get $state expandedFolders]
			$tbl yview moveto [lindex [dict get $state yview] 0]
		}

		method restoreExpandedStates_rec {nodeIdx expandedFolders} {
			foreach key [$tbl childkeys $nodeIdx] {
				set pathName [$tbl rowattrib $key pathName]
				if {[string compare $pathName ""] != 0 &&
				[dict exists $expandedFolders $pathName]} {
					$tbl expand $key -partly
					$self restoreExpandedStates_rec $key $expandedFolders
				}
			}
		}


		method saveView {} {
			# return a dictionary with the information 
			# about the view - current position and expanded directories
			set state [dict create expandedFolders {}]
			dict set state yview [$tbl yview]
			foreach key [$tbl expandedkeys] {
				set pathName [$tbl rowattrib $key pathName]
				dict set state expandedFolders $pathName 1
			}

			return $state
		}

		method notifySelect {} {
			set rows [$tbl curselection]
			set fullnames {}
			foreach row $rows {
				set type [lindex [$tbl get $row] 0 0]
				if {$type == "file"} {
					# only for ordinary files
					lappend fullnames [$tbl rowattrib $row pathName]
				}
			}
			if {$options(-selectcommand) != {}} {
				uplevel #0 $options(-selectcommand) [list $fullnames]
			}		
		}

		method notifyColumnMoved {} {
			# rebuild extra columns and options from current state of tablelist
			set newcolumns [lrange [$tbl cget -columntitles] 1 end]
			set optmapping {}
			foreach opt $options(-columnoptions) old $options(-columns) {
				dict set optmapping $old $opt
			}
			
			set options(-columnoptions) {}
			foreach new $newcolumns {
				set opt [dict get $optmapping $new]
				lappend options(-columnoptions) $opt
			}
			set options(-columns) $newcolumns

			event generate $win <<DirviewerColumnMoved>> -data $options(-columns)
		}
	}
}
