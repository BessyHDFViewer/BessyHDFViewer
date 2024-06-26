#   dirViewer.tcl
#
#   (C) Copyright 2021 Physikalisch-Technische Bundesanstalt (PTB)
#   Christian Gollwitzer
#  
#   This file is part of BessyHDFViewer.
#
#   BessyHDFViewer is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   BessyHDFViewer is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with BessyHDFViewer.  If not, see <https://www.gnu.org/licenses/>.
# 

# This file was adapted from the dirViewer example of tablelist
# and extended with a classification callback of the file content
# for icon selection and property columns

#==============================================================================
# Demonstrates how to use a tablelist widget for displaying the contents of a
# directory.
#
# Copyright (c) 2010-2012  Csaba Nemethi (E-mail: csaba.nemethi@t-online.de)
#==============================================================================

package require tablelist_tile
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

		component watch ;# inotify watching paths
		variable watchlist {}

		variable homedir
		variable cwd

		variable RebuildPending false
		variable PendingState [dict create]
		typevariable haveinotify

		option -globpattern -default {*}
		option -columns -default {} -configuremethod ChangeColumns
		option -columnoptions -default {} -configuremethod ChangeColumns
		option -foldcolumn -default {}

		option -classifycommand -default {}
		option -selectcommand -default {}
		option -hasparent -default 1 -readonly 1
		delegate option -selectmode to tbl
	
		proc globmatch {fname patterns} {
			# match fname against patternlist similar to glob 
			foreach p $patterns {
				if {[string match $p $fname]} {
					return true
				}
			}
			return false
		}

		typeconstructor {
			if {[catch {package require inotify}]} {
				set haveinotify false
			} else {
				set haveinotify true
			}
		}

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


			# create inotify watch (if available)
			if {$haveinotify} {
				set watch ${selfns}::mywatch
				inotify create $watch [mymethod inotifyhandler]
			}

			$self ChangeColumns -columns {}

			# read in the options
			$self configurelist $args

			#
			# Request un update of the contents of this viewer
			#
			$tbl sortbycolumn 0
			
			$self RefreshRequest
		}

		destructor {
			if {$haveinotify} {
				catch {rename $watch {}}
			}
		}


		method ChangeColumns {option value} {
			set options($option) $value
			# either columns or columnoptions have changed. Rebuild. 
		
			if {!$RebuildPending} {
				set PendingState [$self saveView]
				set RebuildPending true
				$self cleartable
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
			
			$self RefreshRequest
		}

		method cleartable {} {
			$tbl delete 0 end
			# remove all watches
			if {$haveinotify} {
				if {[catch {
					foreach {path watchid flags} [$watch info] {
						$watch remove $path
						dict unset watchlist $watchid
					}
				} err]} {
					puts stderr "Error happened in inotify: $err, watch=$watch"
				}
			}
		}

		#------------------------------------------------------------------------------
		# putDir
		#
		# Outputs the contents of the directory dir into the tablelist widget tbl, as
		# child items of the one identified by nodeIdx.
		#------------------------------------------------------------------------------
		method putDir {dir nodeIdx} {
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
							# TODO buggy on Windows
							# file readable can return false on a network share
							set dir [file dirname $dir]
						}
					} else {
						return ""
					}
				} else {
					return ""
				}
			}

			if {$nodeIdx eq "root"} {
				$self cleartable
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
		
			$self putItems $nodeIdx $files $directories
			
			if {$haveinotify} {
				# set up the watch for this directory
				if {$dir != ""} {
					set wid [$watch add $dir CM]
					if {$nodeIdx eq "root"} {
						set key root
					} else {
						set key [$tbl getfullkeys $nodeIdx]
					}
					dict set watchlist $wid node $key
					dict set watchlist $wid path $dir
				}
			}

		}


		method putItems {node files directories {sorting yes}} {
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
				set dirname [SmallUtils::abspath $dirname]
				set dirtail [file tail $dirname]
				if {$dirtail eq ""} {
					# on Windows, file tail truncates C:/ to ""
					# use expanded name instead
					set dirtail $dirname
				}

				if {$options(-classifycommand) != {}} {
					if {[catch {uplevel #0 $options(-classifycommand) [list directory $dirname]} class]} {
						puts stderr "Classifier error: $class"
						# in case the classifier fails, set the default icon
						set class [$self classifydefault directory $dirname]
					}
				} else {
					set class [$self classifydefault directory $dirname]
				}

				lappend itemList [list [list directory $dirtail] {*}$class $dirname]
				incr progress
				event generate $win <<Progress>> -data $progress

			}
			
			foreach fn $files {
				set fullname [SmallUtils::abspath $fn]
				set tail [file tail $fn]
				
				if {$options(-classifycommand) != {}} {
					if {[catch {uplevel #0 $options(-classifycommand) [list file $fullname]} class]} {
						puts stderr "Classifier error: $class"
						# in case the classifier fails, set the default icon
						set  class [$self classifydefault file $fullname]
					}
				} else {
					set class [$self classifydefault file $fullname]
				}
				
				# if the classification is SKIP, don't show this file
				if {[lindex $class end] != "SKIP"} {
					set item [list [list file $tail] {*}$class $fullname]
					lappend itemList $item
				}
				incr progress
				event generate $win <<Progress>> -data $progress

			}

			#
			# Sort the above list and insert it into the tablelist widget
			# tbl as list of children of the row identified by nodeIdx
			#
			if {$sorting} {
				set itemList [$tbl applysorting $itemList]
			}
			# puts $itemList
			set fcindex [lsearch $options(-columns) $options(-foldcolumn)]
			if {$options(-foldcolumn) != {} && $fcindex >= 0} {
				incr fcindex
				
				set oldtrait {}
				set nthitems {}
				
				set parents [lrange $itemList 0 0]
				set childlists {}
				
				foreach item [lrange $itemList 1 end] {
					set trait [lindex $item $fcindex]
					set type [lindex $item 0 0]
					if {$trait != $oldtrait || $trait == {} || $type == "directory" } {
						lappend childlists $nthitems
						lappend parents $item
						set nthitems {}
					} else {
						lappend nthitems $item
					}
					
					if {$type == "directory"} { 
						set oldtrait {}
					} else {
						set oldtrait $trait
					}
				}
				lappend childlists $nthitems

				# now insert into tablelist, first all firsts
				set parentkeys [$tbl insertchildlist $node end $parents]
				set fullkeys {}
				foreach p $parentkeys cl $childlists {
					lappend fullkeys $p
					if {[llength $cl] != 0} {
						lappend fullkeys {*}[$tbl insertchildlist $p end $cl]
						$tbl collapse $p
					}
				}

			} else {
				set fullkeys [$tbl insertchildlist $node end $itemList]
			}
			#
			# Insert an image into the first cell of each newly inserted row
			#
			foreach item $itemList row $fullkeys {
				set fullname [lindex $item end]
				set image [lindex $item end-1]
				set type [lindex $item 0 0]

				if {$type == "file"} {			;# file
					$tbl cellconfigure $row,0 -image $image
				} else {						;# directory
					$tbl cellconfigure $row,0 -image [BessyHDFViewer::IconGet closed-folder]

					#
					# Mark the row as collapsed
					$tbl collapse $row
				}

				# store the full absolute path in this node
				$tbl rowattrib $row pathName $fullname 
			}


			event generate $win <<ProgressFinished>>
			return $fullkeys
		}

		method removeItem {node fullpath} {
			foreach key [$tbl childkeys $node] {
				if {[$tbl rowattrib $key pathName] eq $fullpath} {
					$tbl delete [list $key]
				}
			}
		}
		
		variable vfolders {}
		method AddVirtualFolder {foldername filelist} {
			if {[dict exists $vfolders $foldername node]} {
				set node [dict get $vfolders $foldername node]
				$tbl delete [$tbl delete [dict get $vfolders $foldername tblkeys]]
			} else {
				set node [$tbl insertchild root end [list [list virtualfolder $foldername]]]
				dict set vfolders $foldername node $node
			}
			dict set vfolders $foldername files $filelist
			$tbl cellconfigure $node,0 -image [BessyHDFViewer::IconGet open-folder]
			$tbl expand $node
			set fkeys [$self putItems $node $filelist {} no]
			dict set vfolders $foldername tblkeys $fkeys

			if {[llength $fkeys] != 0 } {
				$tbl see [lindex $fkeys 0]
			} else {
				$tbl see $node
			}
		}

		method RemoveVirtualFolder {foldername} {
			if {[dict exists $vfolders $foldername node]} {
				set node [dict get $vfolders $foldername node]
				$tbl delete $node
				dict unset vfolders $foldername
			}
		}

		method RefreshVirtualFolders {} {
			set vfolders {}
			
			# set oldvfolders $vfolders
			# set vfolders {}
			# dict for {folder content} $oldvfolders {
			# 	$self AddVirtualFolder $folder [dict get $oldvfolders $folder files]
			# }
		}

		method inotifyhandler {wid} {
			if {[catch {
				while {[$watch queue]} {
					set events [$watch read]
					#puts "Debug info: $events"

					foreach ev $events {
						if {[string match {[CM]} [dict get $ev flags]]} {
							# a file was finalized or moved here
							set fn [dict get $ev filename]
							set wid [dict get $ev watchid]

							if {[dict exists $watchlist $wid]} {
								# find corresponding path in the tree
								set node [dict get $watchlist $wid node]
								set path [dict get $watchlist $wid path]

								# check if this file is in the filterlist
								if {[globmatch $fn $options(-globpattern)]} {
									set fullpath [file join $path $fn]
									# remove this file, if it is already there
									
									$self removeItem $node $fullpath 
									set newnode [$self putItems $node [list $fullpath] {}]
									# we passed only one. Move the cursor to this
									$tbl see [lindex $newnode 0]
								}
							}
						}
					}

				}
			} err]} {
				puts stderr "Error in handling inotify event: $err $::errorInfo"
			}
		}

		method display {dir} {
			set cwd $dir
			$self putDir $dir root
			set options(-hasparent) [expr {$cwd != {}}]
			$self RefreshVirtualFolders
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

		method classifydefault {pathspec what} {
			set emptycols [lmap x $options(-columns) {string cat}] 
			lappend emptycols [BessyHDFViewer::IconGet unknown]
			return $emptycols
		}

		#------------------------------------------------------------------------------
		# expandCmd
		#
		# Outputs the contents of the directory whose leaf name is displayed in the
		# first cell of the specified row of the tablelist widget tbl, as child items
		# of the one identified by row, and updates the image displayed in that cell.
		#------------------------------------------------------------------------------
		method expandCmd {ttbl row} {
			set data [$tbl get $row]
			if {[lindex $data 0 0] != "directory"} { return }

			if {[$tbl childcount $row] == 0} {
				set dir [$tbl rowattrib $row pathName]
				$self putDir $dir $row
			}

			if {[$tbl childcount $row] != 0} {
				$tbl cellconfigure $row,0 -image [BessyHDFViewer::IconGet open-folder]
			}
		}

		#------------------------------------------------------------------------------
		# collapseCmd
		#
		# Updates the image displayed in the first cell of the specified row of the
		# tablelist widget tbl.
		#------------------------------------------------------------------------------
		method collapseCmd {ttbl row} {
			set data [$tbl get $row]
			if {[lindex $data 0 0] == "directory"} {
				$tbl cellconfigure $row,0 -image [BessyHDFViewer::IconGet closed-folder]
			}
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

	    method RefreshRequest {} {
			SmallUtils::defer [mymethod refreshView]
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

		method selectfiles {flist} {
			# iteratively expand directories
			# such that the files given in flist can 
			# be selected. Silently ignore errors
			set cwds [file split [SmallUtils::abspath $cwd]]
			set splitidx [expr {[llength $cwds]-1}]

			set selectkeys {}

			foreach fn $flist {
				set abspath [SmallUtils::abspath $fn]
				# skip directories
				if {[file isdirectory $abspath]} { continue }
				
				# skip files which are not under the current cwd
				set fns [file split $abspath]
				if {[lrange $fns 0 $splitidx] != $cwds} { continue }

				set rem [lrange $fns $splitidx+1 end-1]
				set curnode root
				foreach part $rem { 
					# expand node
					set keylist [$tbl childkeys $curnode]
					foreach key $keylist {
						if {[lindex [$tbl get $key] 0]==$part} {
							set curnode $key
							$tbl expand $key -partly
							break
						}
					}
				}

				set part [lindex $fns end]
				# puts "$part"
				set keylist [$tbl childkeys $curnode]
				# puts "$keylist"
				foreach key $keylist {
					# puts [$tbl get $key]
					if {[lindex [$tbl get $key] 0 1]==$part} {
						lappend selectkeys $key
						break
					}
				}
			}
		
			# puts "$tbl selection set \{$selectkeys\}"
			$tbl selection set $selectkeys
		}
		
		method getSelection {{what {file}}} {
			# what defines the category of the
			# entries to be returned. 
			# can be file directory virtualfolder 
			set rows [$tbl curselection]
			set fullnames {}
			foreach row $rows {
				set type [lindex [$tbl get $row] 0 0]
				if {$type in $what} {
					# only for entries of the selected category
					lappend fullnames [$tbl rowattrib $row pathName]
				}
			}

			return $fullnames
		}

		method notifySelect {} {
			if {$options(-selectcommand) != {}} {
				uplevel #0 $options(-selectcommand) [list [$self getSelection]]
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
