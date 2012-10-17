package require snit

snit::widget ExportDialog {
	# dialog for choosing and sorting a subset of a large list
	hulltype toplevel

	component mainframe
	component pathentry
	component fmtfield

	# 
	variable includelist
	variable newitem
	variable curpath
	variable singlefile
	variable stdformat
	variable firstfile

	option -files -default {}
	option -defaultformat
	option -title -default {Select export options} -configuremethod SetTitle

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
		set stdformat 1

		install fmtfield using text $fmtframe.fent

		grid $stdbtn $custbtn -sticky w
		grid $fmtfield - -sticky nsew
		grid rowconfigure $fmtframe 1 -weight 1
		grid columnconfigure $fmtframe 1 -weight 1

		set okbut [ttk::button $butframe.ok -text OK -image [IconGet dialog-ok] -command [mymethod OK] -compound left]
		set cancelbut [ttk::button $butframe.cancel -text Cancel -image [IconGet dialog-cancel] -command [mymethod Cancel] -compound left] 

		pack $okbut $cancelbut -side left -padx 5

		$self configurelist $args

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

		$self SwitchSingleFile
		$self SwitchStdFormat
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
			format [$fmtfield get 1.0 end]]

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
			$fmtfield configure -state disabled
		} else {
			$fmtfield configure -state normal
		}
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

}
