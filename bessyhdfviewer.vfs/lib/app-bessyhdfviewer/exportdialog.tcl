package require snit

snit::widget ExportDialog {
	# dialog for choosing and sorting a subset of a large list
	hulltype toplevel

	component mainframe
	component pathentry
	component fmtfield
	component mbutton
	component pbutton
	component colfmtframe
	component previewtable

	# 
	variable curpath
	variable singlefile
	variable stdformat
	variable firstfile
	variable fmtlist
	variable colformat
	variable activecolumn
	variable selectcolors
	variable previewlimit 100

	variable headerFN
	variable headerAtt
	variable headerCol
	variable headerBareCol

	option -files -default {}
	option -format -default {{$Energy}}
	option -title -default {Select export options} -configuremethod SetTitle
	delegate option -aclist to fmtfield
	option -stdformat -default true
	option -parent -default {}
	option -headerfmt -default {}

	# call this function to get the modal dialog
	typevariable resultdict
	typemethod show {args} {
		set newobj [ExportDialog .__exportwin {*}$args]
		grab $newobj
		tkwait window $newobj
		return $resultdict
	}

	
	constructor {args} {
		# first fill toplevel with themed frame
		install mainframe using ttk::frame $win.mfr
		pack $mainframe -expand yes -fill both 

		set pathframe  [ttk::labelframe $mainframe.pathfr -text "Destination"]
		set hfmtframe  [ttk::labelframe $mainframe.hfmtfr -text "Header"]
		set fmtframe  [ttk::labelframe $mainframe.fmtfr -text "Format"]
		set butframe [ttk::frame $mainframe.butframe]

		grid $pathframe -sticky nsew
		grid $hfmtframe -sticky nsew
		grid $fmtframe -sticky nsew
		grid $butframe -sticky nsew

		grid rowconfigure $mainframe 2 -weight 1
		grid columnconfigure $mainframe 0 -weight 1

		set sfbtn [ttk::radiobutton $pathframe.sfbtn -text "Single file" \
			-variable [myvar singlefile] -value 1 -command [mymethod SwitchSingleFile]]

		set dirbtn [ttk::radiobutton $pathframe.dirbtn -text "Directory" \
			-variable [myvar singlefile] -value 0 -command [mymethod SwitchSingleFile]]

		install pathentry using ttk::entry $pathframe.pent -textvariable [myvar curpath]
		set selbtn [ttk::button $pathframe.selbtn -text "Choose..." -image [IconGet document-open-folder] -style Toolbutton -command [mymethod SelectPath]]

		grid $sfbtn $dirbtn x -sticky w
		grid $pathentry - $selbtn -sticky ew
		grid columnconfigure $pathframe 1 -weight 1
		
		set hbtnFn	[ttk::checkbutton $hfmtframe.hbtnFn -text "Original filename" -variable [myvar headerFN]]
		set hbtnAtt [ttk::checkbutton $hfmtframe.hbtnAtt -text "Attributes" -variable [myvar headerAtt]]
		set hbtnCol [ttk::checkbutton $hfmtframe.hbtnCols -text "Column names" -variable [myvar headerCol]]
		set hbtnBCol [ttk::checkbutton $hfmtframe.hbtnBCols -text "Bare column names" -variable [myvar headerBareCol]]

		grid $hbtnFn -sticky w
		grid $hbtnAtt -sticky w
		grid $hbtnCol -sticky w
		grid $hbtnBCol -sticky w

		
		set stdbtn [ttk::radiobutton $fmtframe.sfbtn -text "Standard Format" \
			-variable [myvar stdformat] -value 1 -command [mymethod SwitchStdFormat]]
		set custbtn [ttk::radiobutton $fmtframe.custbtn -text "Custom Format" \
			-variable [myvar stdformat] -value 0 -command [mymethod SwitchStdFormat]]
		
		install colfmtframe using ttk::frame $fmtframe.colfmtfr
		install previewtable using tablelist::tablelist $fmtframe.tbl \
			-labelcommand [mymethod EditColumn] \
			-movablerows 0 -movablecolumns 1 \
			-movecolumncursor hand1 -exportselection 0 -selectmode none \
			-stripebg ""
		set prevhsb [ttk::scrollbar $fmtframe.hsb -orient horizontal -command [list $previewtable xview]]
		$previewtable configure -xscrollcommand [list $prevhsb set]
		# get matching colors for selected items for the current theme
		set selectcolors [list [$previewtable cget -selectforeground] [$previewtable cget -selectbackground]]
		
		bind $previewtable <<TablelistColumnMoved>> [mymethod ColumnMoved %d]
		bind [$previewtable bodytag] <1> [mymethod CellClicked %W %x %y]
		
		grid $stdbtn $custbtn -sticky w
		grid $colfmtframe - -sticky nsew
		grid $previewtable - -sticky nsew
		grid $prevhsb     -  -sticky nsew
		grid rowconfigure $fmtframe 2 -weight 1
		grid columnconfigure $fmtframe 1 -weight 1


		install fmtfield using ttk::entry $colfmtframe.fent -textvariable [myvar colformat]
		set pbutton [ttk::button $colfmtframe.pbut -text "+" -image [IconGet list-add] -command [mymethod Add] -style Toolbutton]
		set mbutton [ttk::button $colfmtframe.mbut -text "-" -image [IconGet list-remove] -command [mymethod Remove] -style Toolbutton]
		set xbutton [ttk::button $colfmtframe.xbut -text "x" -image [IconGet edit-clear] -command [mymethod RemoveAll] -style Toolbutton]
		set limlabel [ttk::label $colfmtframe.llable -text "Preview row limit"]
		set limentry [ttk::entry $colfmtframe.lentry -textvariable [myvar previewlimit]]

		grid $xbutton $pbutton $mbutton $fmtfield -sticky ew
		grid columnconfigure $colfmtframe 3 -weight 1

		bind $fmtfield <Return> [mymethod AcceptEditColumn]
		AutoComplete $fmtfield
		set activecolumn {}

		set okbut [ttk::button $butframe.ok -text OK -image [IconGet dialog-ok] -command [mymethod OK] -compound left]
		set cancelbut [ttk::button $butframe.cancel -text Cancel -image [IconGet dialog-cancel] -command [mymethod Cancel] -compound left] 

		pack $okbut $cancelbut -side left -padx 5

		$self configurelist $args

		if {$options(-parent) != {}} {
			wm transient $win $options(-parent)
		}

		set title "Export\n"
		set firstfile [lindex $options(-files) 0]
		# configure initial settings from -files
		switch [llength $options(-files)] {
			0 { error "No files given" }
			1 { 
				set singlefile 1
				set curpath [file dirname $firstfile]
				append title "  $firstfile\n"
			}
			default {
				set singlefile 0
				set curpath $firstfile
				append title "  [llength $options(-files)] HDF files\n"
			}
		}
		append title "to ASCII"

		# configure checkbuttons for header format
		set headerFN [expr {"Filename" in $options(-headerfmt)}]
		set headerAtt [expr {"Attributes" in $options(-headerfmt)}]
		set headerCol [expr {"Columns" in $options(-headerfmt)}]
		set headerBareCol [expr {"BareColumns" in $options(-headerfmt)}]

		if {$options(-stdformat)} {
			set stdformat 1
		} else {
			set stdformat 0
		}

		$self SwitchSingleFile
		$self SwitchStdFormat
		$self PreviewFormat
		set resultdict {}
	}

	method SetTitle {option title} {
		set options($option) $title
		wm title $win $title
	}

	method OK {} {
		set resultdict [dict create \
			singlefile $singlefile \
			stdformat $stdformat \
			path $curpath \
			format $options(-format) \
			headerfmt {}]
		# make header format list
		if {$headerFN} { dict lappend resultdict headerfmt Filename }
		if {$headerAtt} { dict lappend resultdict headerfmt Attributes }
		if {$headerCol} { dict lappend resultdict headerfmt Columns }
		if {$headerBareCol} { dict lappend resultdict headerfmt BareColumns }

		destroy $win
	}

	method Cancel {} {
		set resultdict {}
		destroy $win
	}	

	method SwitchSingleFile {} {
		if {$singlefile} {
			# path is currently a dir
			set curpath [file join $curpath [file tail [file rootname $firstfile]].dat]
		} else {
			# path is currently a file name, trucate
			set curpath [file dirname $curpath]
		}
	}

	method SwitchStdFormat {} {
		if {$stdformat} {
			$previewtable configure -state disabled
			$fmtfield configure -state disabled
			$pbutton state disabled
			$mbutton state disabled
		} else {
			$previewtable configure -state normal
			$fmtfield configure -state normal
			$pbutton state !disabled
			$mbutton state !disabled
		}
		$self PreviewFormat
	}

	method SelectPath {} {
		if {$singlefile} {
			set initialfile [file tail $curpath]
			set initialdir [file dirname $curpath]
			set newfile [tk_getSaveFile -filetypes { {{ASCII data files} {.dat}} {{All files} {*}}} \
			-defaultextension .dat \
			-title "Select ASCII file for export" \
			-initialfile $initialfile \
			-initialdir $initialdir]
			
			if {$newfile != ""} {
				set curpath $newfile
			}
		} else {
			set newpath [tk_getDirectory -title "Select directory to export ASCII files" \
				-initialdir $curpath \
				-filetypes { {{HDF files} {.hdf}} {{ASCII data files} {.dat}} {{All files} {*}}} ]
			if {$newpath != ""} {
				set curpath $newpath
			}
		}

	}

	method SetActiveColumn {col} {
		# change background for selected column
		# as visual feedback
		if {$activecolumn != {}} {
			# remove tag from all columns, 
			# as the previous activecolumn might have 
			# moved or disappeared
			set ncols [llength [$previewtable cget -columntitles]]
			for {set i 0} {$i<$ncols} {incr i} {
				$previewtable columnconfigure $i -fg "" -bg ""
			}
		}
		if {$col != {}} {
			lassign $selectcolors fg bg
			$previewtable columnconfigure $col -bg $bg -fg $fg
		} 
		set activecolumn $col
	}

	method CellClicked {W x y} {
        lassign [tablelist::convEventFields $W $x $y] W x y
		set col [$previewtable containingcolumn $x]
		if {$col>=0} { 
			$self EditColumn $previewtable $col
		} else {
			$self SetActiveColumn {}
			set colformat {}
		}
		return -code break
	}

	method EditColumn {w col} {
		# click on the table header 
		# copy that format into the field
		$self SetActiveColumn $col
		set colformat [lindex $options(-format) $col]
	}

	method AcceptEditColumn {} {
		if {$colformat != {}} {
			if {$activecolumn != {}} {
				lset options(-format) $activecolumn $colformat
			} else {
				lappend options(-format) $colformat
				set colformat {}
			}
			$self PreviewFormat
		}
	}

	method Add {} {
		# insert new empty column
		if {$activecolumn == {}} { 
			set insertcolumn [llength $options(-format)]
		} else {
			set insertcolumn $activecolumn
		}
		# remove selection
		$self SetActiveColumn {}
		# rebuild table
		set options(-format) [linsert $options(-format) $insertcolumn ""]
		$self PreviewFormat
		# select new column
		$self SetActiveColumn $insertcolumn
	}

	method Remove {} {
		if {$activecolumn != {}} {
			set deletecolumn $activecolumn
			$self SetActiveColumn {}
			set options(-format) [lreplace $options(-format) $deletecolumn $deletecolumn]
			$self PreviewFormat
			if {$deletecolumn < [llength $options(-format)]} {
				$self SetActiveColumn $deletecolumn
			}
		}
	}

	method RemoveAll {} {
		set options(-format) ""
		$self PreviewFormat
		$self SetActiveColumn {}
	}	

	method ColumnMoved {idxlist} {
		# user has changed the order of the columns interactively
		set options(-format) [$previewtable cget -columntitles]
		lassign $idxlist from to
		if {$to<$from} {
			$self SetActiveColumn $to
		} else {
			$self SetActiveColumn [expr {$to-1}]
		}
		# Preview not necessary
	}

	method PreviewFormat {} {
		# create columnlist from formats
		if {$stdformat} {
			$previewtable delete 0 end
			# maybe insert TextDump, but not necessary
		} else {
			set cols {}
			foreach fmt $options(-format) {
				lappend cols 0 $fmt left
			}
			$previewtable delete 0 end
			if {$cols != {}} {
				$previewtable configure -columns $cols
				# get data
				set data [SELECT $options(-format) $options(-files) LIMIT $previewlimit]
				$previewtable insertlist end $data
			}
		}
	}

}
