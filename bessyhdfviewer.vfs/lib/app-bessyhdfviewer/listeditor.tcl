#   listeditor.tcl
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

package require snit
package require tablelist_tile

snit::widget ListEditor {
	# dialog for choosing and sorting a subset of a large list
	hulltype toplevel

	component includetbl
	component valuestbl
	component bbar
	component mainframe
	component newent

	# current lists
	variable includelist
	variable newitem
	

	option -initiallist
	option -values -default {} -configuremethod SetValues
	option -valuetree -default {} -configuremethod  SetValueTree
	option -showtree -default false
	option -resultvar {}
	option -title -default {Select options} -configuremethod SetTitle
	option -parent -default {}
	option -aclist -configuremethod SetACList

	# call this function to get the modal dialog
	typevariable resultlist
	typemethod getList {args} {
		set newobj [ListEditor .__leditwin -resultvar [mytypevar resultlist] {*}$args]
		grab $newobj
		vwait [mytypevar resultlist]
		return $resultlist
	}

	
	constructor {args} {
		# first fill toplevel with themed frame
		install mainframe using ttk::frame $win.mfr
		pack $mainframe -expand yes -fill both 

		set editframe  [ttk::frame $mainframe.editfr]
		set butframe [ttk::frame $mainframe.butframe]
		set sep [ttk::separator $mainframe.sep -orient horizontal]

		grid $editframe -sticky nsew
		grid $sep -sticky ew
		grid $butframe -sticky nsew

		grid rowconfigure $mainframe 0 -weight 1
		grid columnconfigure $mainframe 0 -weight 1

		set curlabel [ttk::label $editframe.curlabel -text "Current"]
		set avllabel [ttk::label $editframe.avllabel -text "Available"]
		set curframe [ttk::frame $editframe.curframe]
		set avlframe [ttk::frame $editframe.avlframe]
		set pmbar [ttk::frame $editframe.pmbar]

		install newent using ttk::combobox $curframe.newent -textvariable [myvar newitem]
		AutoComplete $newent

		bind $newent <Return> [mymethod Add]

		if {$options(-showtree)} {
			grid $curlabel $avllabel -sticky nsew
		} else {
			grid $curlabel -sticky nsew
		}
		grid $pmbar -sticky ew
		grid $newent -sticky ew
		if {$options(-showtree)} {
			grid $curframe $avlframe -sticky nsew
		} else {
			grid $curframe -sticky nsew
		}

		grid rowconfigure $editframe 1 -weight 1
		grid columnconfigure $editframe 0 -weight 1

		if {$options(-showtree)} {
			grid columnconfigure $editframe 1 -weight 1
		}

		# create tablelist elements
		install includetbl using tablelist::tablelist $curframe.tbl \
			-listvariable [myvar includelist] -movablerows 1 \
			-xscrollcommand [list $curframe.hsb set] -yscrollcommand [list $curframe.vsb set] \
			-exportselection 0 -selectmode single -columns {0 "Option" left} -stretch all \
			-height 25 -width 30
		
		bind [$includetbl bodytag] <BackSpace> [mymethod Remove]
		bind [$includetbl bodytag] <Delete> [mymethod Remove]

		set curvsb [ttk::scrollbar $curframe.vsb -orient vertical   -command [list $includetbl yview]]
		set curhsb [ttk::scrollbar $curframe.hsb -orient horizontal -command [list $includetbl xview]]

		grid $includetbl $curvsb -sticky nsew
		grid $curhsb     ^       -sticky nsew

		grid rowconfigure $curframe 0 -weight 1
		grid columnconfigure $curframe 0 -weight 1


		install valuestbl using tablelist::tablelist $avlframe.tbl \
			-movablerows 0 \
			-xscrollcommand [list $avlframe.hsb set] -yscrollcommand [list $avlframe.vsb set] \
			-exportselection 0 -selectmode single -columns {0 "Option" left} -stretch all \
			-height 25 -width 30

		bind $valuestbl <<TablelistSelect>> [mymethod ValueSelect]
		bind [$valuestbl bodytag] <Return> [mymethod Add]
		bind [$valuestbl bodytag] <Double-1> [mymethod Add]

		set avlvsb [ttk::scrollbar $avlframe.vsb -orient vertical   -command [list $valuestbl yview]]
		set avlhsb [ttk::scrollbar $avlframe.hsb -orient horizontal -command [list $valuestbl xview]]

		grid $valuestbl $avlvsb -sticky nsew
		grid $avlhsb     ^      -sticky nsew

		grid rowconfigure $avlframe 0 -weight 1
		grid columnconfigure $avlframe 0 -weight 1


		set pbutton [ttk::button $pmbar.pbut -text "+" -image [BessyHDFViewer::IconGet list-add] -command [mymethod Add] -style Toolbutton]
		set mbutton [ttk::button $pmbar.mbut -text "-" -image [BessyHDFViewer::IconGet list-remove] -command [mymethod Remove] -style Toolbutton]

		pack $pbutton $mbutton -side left



		set okbut [ttk::button $butframe.ok -text OK -image [BessyHDFViewer::IconGet dialog-ok] -command [mymethod OK] -compound left]
		set cancelbut [ttk::button $butframe.cancel -text Cancel -image [BessyHDFViewer::IconGet dialog-cancel] -command [mymethod Cancel] -compound left] 

		pack $okbut $cancelbut -side left -padx 5

		$self configurelist $args	
		if {$options(-parent) != {}} {
			wm transient $win $options(-parent)
		}

		set includelist [lmap x $options(-initiallist) {list $x}]
	}

	method SetValues {option values} {
		set options($option) $values
		$valuestbl delete 0 end
		$valuestbl insertlist end $values
	}


	method SetValueTree {option tree} {
		set options($option) $tree
		$valuestbl delete 0 end
		foreach line $tree {
			$self InsertChild_rec root $line
		}
	}

	method SetTitle {option title} {
		set options($option) $title
		wm title $win $title
	}
	
	method SetACList {option aclist} {
		set options($option) $aclist
		$newent configure -values $aclist -aclist $aclist
	}


	method InsertChild_rec {node tree} {
		set tree [lassign $tree type]
		switch -nocase $type {
			GROUP {
				# a group of items with a list of trees in values
				lassign $tree name values
				set childnode [$valuestbl insertchild $node end [list $name]]
				if {$node != "root"} {
					$valuestbl collapse $childnode
				}
				$valuestbl rowconfigure $childnode -selectable 0
				foreach value $values {
					$self InsertChild_rec $childnode $value
				}
			}

			LIST {
				# a list of items
				lassign $tree values
				$valuestbl insertchildlist $node end $values
			}

			default {
				error "Unknown element in tree: $type. Should be GROUP or LIST"
			}
		}
	}
	
	method ValueSelect {} {
		set cur [$valuestbl curselection]
		if {[llength $cur] > 0} {
			set newitem [$valuestbl get $cur]
		}
	}

	method Add {} {
		if {$newitem != {}} {
			set insertpos [$includetbl curselection]
			if {[llength $insertpos] != 1} {
				set insertpos end
			}
			$includetbl insert $insertpos [list $newitem]
		}
	}


	method Remove {} {
		set cursel [$includetbl curselection]
		if {[llength $cursel] == 1} {
			$includetbl delete $cursel $cursel
		}
	}

	method OK {} {
		if {$options(-resultvar) != {}} {
			upvar #0 $options(-resultvar) var
			set var [lmap x $includelist {lindex $x 0}]
		}
		destroy $win
	}

	method Cancel {} {
		if {$options(-resultvar) != {}} {
			upvar #0 $options(-resultvar) var
			set var $options(-initiallist)
		}
		destroy $win
	}	

}
