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
	

	option -files
	option -defaultformat
	option -title -default {Select export options} -configuremethod SetTitle

	# call this function to get the modal dialog
	typevariable resultlist
	typemethod getList {args} {
		set newobj [ExportDialog .__exportwin {*}$args]
		grab $newobj
		vwait [mytypevar resultlist]
		return $resultlist
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

		set sfbtn [ttk::radiobutton $pathframe.sfbtn -text "Single file"]
		set dirbtn [ttk::radiobutton $pathframe.sfbtn -text "Directory"]
		install pathentry using ttk::entry $pathframe.pent -textvariable [myvar curpath]
		set selbtn [ttk::button $pathframe.selbtn -text "Choose..." -image [IconGet document-open-folder]

		grid $sfbtn $dirbtn x -sticky e
		grid $pathentry - $selbtn -sticky ew
		grid columnconfigure $pathframe 1 -weight 1


		set okbut [ttk::button $butframe.ok -text OK -image [IconGet dialog-ok] -command [mymethod OK] -compound left]
		set cancelbut [ttk::button $butframe.cancel -text Cancel -image [IconGet dialog-cancel] -command [mymethod Cancel] -compound left] 

		pack $okbut $cancelbut -side left -padx 5

		$self configurelist $args
	}

	method SetTitle {option title} {
		set options($option) $title
		wm title $win $title
	}

	method OK {} {
		set resultlist [list test]
		destroy $win
	}

	method Cancel {} {
		destroy $win
	}	

}
