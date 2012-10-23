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

	option -files -default {}
	option -format -default {{$Energy}}
	option -title -default {Select export options} -configuremethod SetTitle
	delegate option -aclist to fmtfield
	option -stdformat -default true
	option -parent -default {}

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
		set fmtframe  [ttk::labelframe $mainframe.fmtfr -text "Format"]
		set butframe [ttk::frame $mainframe.butframe]

		grid $pathframe -sticky nsew
		grid $fmtframe -sticky nsew
		grid $butframe -sticky nsew

		grid rowconfigure $mainframe 1 -weight 1
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

		
		set stdbtn [ttk::radiobutton $fmtframe.sfbtn -text "Standard Format" \
			-variable [myvar stdformat] -value 1 -command [mymethod SwitchStdFormat]]
		set custbtn [ttk::radiobutton $fmtframe.custbtn -text "Custom Format" \
			-variable [myvar stdformat] -value 0 -command [mymethod SwitchStdFormat]]
		
		install colfmtframe using ttk::frame $fmtframe.colfmtfr
		install previewtable using tablelist::tablelist $fmtframe.tbl \
			-labelcommand [mymethod EditColumn] \
			-movablerows 0 -movablecolumns 1 \
			-movecolumncursor hand1 -exportselection 0 -selectmode single
		set prevhsb [ttk::scrollbar $fmtframe.hsb -orient horizontal -command [list $previewtable xview]]
		$previewtable configure -xscrollcommand [list $prevhsb set]
		
		bind $previewtable <<TablelistColumnMoved>> [mymethod ColumnMoved]

		
		grid $stdbtn $custbtn -sticky w
		grid $colfmtframe - -sticky nsew
		grid $previewtable - -sticky nsew
		grid $prevhsb     -  -sticky nsew
		grid rowconfigure $fmtframe 2 -weight 1
		grid columnconfigure $fmtframe 1 -weight 1


		install fmtfield using ttk::entry $colfmtframe.fent -textvariable [myvar colformat]
		set pbutton [ttk::button $colfmtframe.pbut -text "+" -image [IconGet list-add] -command [mymethod Add] -style Toolbutton]
		set mbutton [ttk::button $colfmtframe.mbut -text "-" -image [IconGet list-remove] -command [mymethod Remove] -style Toolbutton]

		grid $fmtfield $pbutton $mbutton -sticky ew
		grid columnconfigure $colfmtframe 0 -weight 1

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
			format $options(-format)]

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

	method EditColumn {w col} {
		# click on the table header 
		# copy that format into the field
		set activecolumn $col
		set colformat [lindex $options(-format) $col]
	}

	method AcceptEditColumn {} {
		if {$activecolumn != {} && $colformat != {}} {
			lset options(-format) $activecolumn $colformat
			$self PreviewFormat
		}
	}

	method Add {} {
		# insert current format at the active column
		if {$colformat eq {}} { return }

		if {$activecolumn == {}} { 
			set activecolumn end
		}
		set options(-format) [linsert $options(-format) $activecolumn $colformat]
		$self PreviewFormat
	}

	method Remove {} {
		if {$activecolumn != {}} {
			set options(-format) [lreplace $options(-format) $activecolumn $activecolumn]
			set activecolumn {}
			$self PreviewFormat
		}
	}

	method ColumnMoved {} {
		# user has changed the order of the columns interactively
		set options(-format) [$previewtable cget -columntitles]
		set activecolumn {}
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
				set data [SELECT $options(-format) $options(-files) LIMIT 20]
				$previewtable insertlist end $data
			}
		}
	}

}
