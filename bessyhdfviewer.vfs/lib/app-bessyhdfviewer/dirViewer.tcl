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
		component tf
		component tbl
		component vsb
		component hsb
		component bf
		component b1
		component b2

		option -globpattern -default {*}
		option -columns -default {}
		option -columnoptions -default {}
		option -classifycommand -default {}
		option -selectcommand -default {}

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
			$self configurelist $args

			if {$options(-classifycommand) == ""} {
				set options(-classifycommand) [myproc classifydefault]
			}

			if {[llength $options(-columns)] != [llength $options(-columnoptions)]*3 && [llength $options(-columnoptions)]!=0 } {
				return -code error "Columnoptions must be given for all additional columns"
			}
	
			set columnspec [concat {0 "Name" left} $options(-columns)]

			install tf using ttk::frame $win.tf -class ScrollArea
			install tbl using tablelist::tablelist $tf.tbl \
				-columns $columnspec \
				-expandcommand [mymethod expandCmd] -collapsecommand [mymethod collapseCmd] \
				-xscrollcommand [list $tf.hsb set] -yscrollcommand [list $tf.vsb set] \
				-movablecolumns no -setgrid no -showseparators yes -height 18 -width 80 -exportselection 0

			if {[$tbl cget -selectborderwidth] == 0} {
				$tbl configure -spacing 1
			}

			$tbl columnconfigure 0 -formatcommand [myproc formatFile] -sortmode command -sortcommand [myproc compareFile]
			set col 1
			foreach opt $options(-columnoptions) {
				$tbl columnconfigure $col {*}$opt
				incr col
			}


			install vsb using ttk::scrollbar $tf.vsb -orient vertical   -command [list $tbl yview]
			install hsb using ttk::scrollbar $tf.hsb -orient horizontal -command [list $tbl xview]
			
			set bodyTag [$tbl bodytag]
			bind $bodyTag <Double-1>   [mymethod putContentsOfSelFolder]

			bind $tbl <<TablelistSelect>> [mymethod notifySelect]

			#
			# Create three buttons within a frame child of the main widget
			#
			install bf using ttk::frame $win.bf
			install b1 using ttk::button $bf.b1 -width 10 -text "Refresh"
			install b2 using ttk::button $bf.b2 -width 10 -text "Parent"

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
			grid rowconfigure    $tf 1 -weight 1
			grid columnconfigure $tf 0 -weight 1
			pack $b1 $b2 -side left -expand yes -pady 10
			pack $bf -side bottom -fill x
			pack $tf -side top -expand yes -fill both

			#
			# Populate the tablelist with the contents of the given directory
			#
			$tbl sortbycolumn 0
			$self putContents $dir root
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

			#
			# Build a list from the data of the subdirectories and
			# files of the directory dir.
			# structure is: First column contains a list with file|directory and relative name
			# then comes the data to be displayed in the additional columns, then an image
			# for directories, the image is ignored
			
			set itemList {}
			
			foreach dirname [glob -nocomplain -types d -directory $dir *] {
				
				set dirname [file normalize $dirname]
				set dirtail [file tail $dirname]
				set class [uplevel #0 $options(-classifycommand) [list directory $dirname]]
				if {$class != {}} {
					lappend itemList [list [list directory $dirtail] {*}$class $dirname]
				}

			}
			
			foreach fn [glob -nocomplain -types f -directory $dir {*}$options(-globpattern)] {
				set fullname [file normalize $fn]
				set tail [file tail $fn]
				set class [uplevel #0 $options(-classifycommand) [list file $fullname]]
				lappend itemList [list [list file $tail] {*}$class $fullname]


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

			if {[string compare $nodeIdx "root"] == 0} {
				#
				# Configure the "Refresh" and "Parent" buttons
				#
				$b1 configure -command [mymethod refreshView $dir]
				set p [file dirname $dir]
				if {[string compare $p $dir] == 0} {
					# top level
					$b2 state disabled
				} else {
					$b2 state !disabled
					$b2 configure -command [mymethod putContents $p root]
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
			puts "Double click, isdir == $isdir, [lindex [$tbl get $row] 0]"
			if {$isdir} {		;# directory item
				set dir [$tbl rowattrib $row pathName]
				$self putContents $dir root
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
		method refreshView {dir} {
			#
			# Save the vertical view and get the path names
			# of the folders displayed in the expanded rows
			#
			set yView [$tbl yview]
			foreach key [$tbl expandedkeys] {
				set pathName [$tbl rowattrib $key pathName]
				set expandedFolders($pathName) 1
			}

			#
			# Redisplay the directory's (possibly changed) contents and restore
			# the expanded states of the folders, along with the vertical view
			#
			$self putContents $dir root
			$self restoreExpandedStates root expandedFolders
			$tbl yview moveto [lindex $yView 0]
		}

		#------------------------------------------------------------------------------
		# restoreExpandedStates
		#
		# Expands those children of the parent identified by nodeIdx that display
		# folders whose path names are the names of the elements of the array specified
		# by the last argument.
		#------------------------------------------------------------------------------
		method restoreExpandedStates {nodeIdx expandedFoldersName} {
			upvar $expandedFoldersName expandedFolders

			foreach key [$tbl childkeys $nodeIdx] {
				set pathName [$tbl rowattrib $key pathName]
				if {[string compare $pathName ""] != 0 &&
				[info exists expandedFolders($pathName)]} {
					$tbl expand $key -partly
					$self restoreExpandedStates $tbl $key expandedFolders
				}
			}
		}

		method notifySelect {} {
			set row [$tbl curselection]
			set type [lindex [$tbl get $row] 0 0]
			if {$type == "file"} {
				# only for ordinary files
				set fullname [$tbl rowattrib $row pathName]
				if {$options(-selectcommand) != {}} {
					uplevel #0 $options(-selectcommand) [list $fullname]
				}
			}		
		}
	}
}
