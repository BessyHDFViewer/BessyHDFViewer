package require snit
package require fileutil

snit::widget SearchDialog {
	# dialog for choosing and sorting a subset of a large list
	hulltype toplevel

	component mainframe
	component critframe
	component butframe
	component searchbutton
	component removebutton
	component closebutton

	#
	variable foldername "Search"
	variable limit 100
	variable epsilon 1e-5

	variable dbfile

	variable ncrit
	variable critwidget
	variable formdata
	variable searchdata {}

	variable status ""


	variable signatures {
		between { "" - and - }
		contains { "" - }
		covers { "range from" - to - }
		equal { to - }
		included { "in range from" - to - }
		"" { }
	}

	variable modes

	option -title -default {Select search criteria} -configuremethod SetTitle
	option -fieldlist -default {Comment Energy}
	option -parent -default {}

	constructor {args} {
		set modes [dict keys $signatures] 

		# first fill toplevel with themed frame
		install mainframe using ttk::frame $win.mfr
		pack $mainframe -expand yes -fill both 

		# Metainformation for this search
		set flabel [ttk::label $mainframe.flabel -text "Name:"]
		set fentry [ttk::entry $mainframe.fentry -textvariable [myvar foldername]]
		set llabel [ttk::label $mainframe.llabel -text "Limit:"]
		set lentry [ttk::entry $mainframe.lentry -textvariable [myvar limit]]
		set elabel [ttk::label $mainframe.elabel -text "Epsilon:"]
		set eentry [ttk::entry $mainframe.eentry -textvariable [myvar epsilon]]

		install critframe using ttk::labelframe $mainframe.crit -text "Criteria"
		install butframe using ttk::frame $mainframe.bbar
		
		set statusbar [ttk::label $mainframe.statbar -textvariable [myvar status]]
		set dbframe [ttk::labelframe $mainframe.db -text "Database"]

		# main layout
		grid $flabel       $fentry -sticky nsew
		grid $llabel       $lentry -sticky nsw
		grid $elabel       $eentry -sticky nsw
		grid $critframe      -     -sticky nsew
		grid $dbframe        -     -sticky nsew
		grid $statusbar      -     -sticky nsew
		grid $butframe       -

		grid columnconfigure $mainframe $fentry -weight 1
		grid rowconfigure $mainframe $critframe -weight 1
		
		# buttons for running
		install searchbutton using ttk::button $butframe.search -text "Search" -command [mymethod RunSearch]
		install removebutton using ttk::button $butframe.remove -text "Remove Search" -command [mymethod RemoveSearch]
		install closebutton using ttk::button $butframe.close -text "Close" -command [mymethod Exit]
		pack $searchbutton $removebutton $closebutton -side left
		
		# settings for the database
		
		set dblabel [ttk::label $dbframe.dbl -text "Database:"]
		set dbentry [ttk::entry $dbframe.dbe -state readonly -textvariable BessyHDFViewer::HDFCacheFile]
		set dbfile $BessyHDFViewer::HDFCacheFile
		set dbopen  [ttk::button $dbframe.dbo -command [mymethod OpenDB] -image [BessyHDFViewer::IconGet document-open-remote] -text O -style Toolbutton]
		set dbreset  [ttk::button $dbframe.dbr -command [mymethod ResetDB] -image [BessyHDFViewer::IconGet document-revert] -text R -style Toolbutton]

		set clearbtn [ttk::button $dbframe.clear -command [mymethod ClearCacheCmd] -text "Clear Cache"]
		set indexbtn [ttk::button $dbframe.index -command [mymethod IndexRunCmd] -text "Index Directory"]
		set importbtn [ttk::button $dbframe.import -command [mymethod ImportCmd] -text "Import database"]
		
		grid $dblabel $dbentry $dbopen  $dbreset -sticky nsew
		grid $indexbtn $importbtn
		grid $clearbtn

		grid columnconfigure $dbframe $dbentry -weight 1

		$self configurelist $args

		set ncrit 1
		$self CreateCriteriaWidgets
		
		if {$options(-parent) != {}} {
			wm transient $win $options(-parent)
		}

	}

	method RunSearch {} {
		set settings [$self Serialize]
		set criteria [lmap c $settings {$self AdjustCriterion $c}]

		set count [BessyHDFViewer::SearchHDF $foldername $criteria $limit]
		if {$limit == $count} {
			set status "Limit reached ($count results)"
		} else {
			set status "$count results"
		}
	}

	method RemoveSearch {} {
		$BessyHDFViewer::w(filelist) RemoveVirtualFolder $foldername
	}

	method Exit {} {
		destroy $win
	}	

	method CreateCriteriaWidgets {} {
		array unset formdata
		destroy {*}[winfo children $critframe]
		for {set i 0} {$i < $ncrit} {incr i} {
			if {$i == 0} {
				set icon [BessyHDFViewer::IconGet list-add-small]
				set cmd [mymethod AddCriterion]
			} else {
				set icon [BessyHDFViewer::IconGet list-remove-small]
				set cmd [mymethod RemoveCriterion $i]
			}
			set critwidget(addbtn,$i) [ttk::button $critframe.addbtn$i -image $icon -command $cmd -style Toolbutton -text R]
			set formdata(var,$i) ""
			set critwidget(varcbx,$i) [ttk::combobox $critframe.varcbx$i -values $options(-fieldlist) \
				-textvariable [myvar formdata(var,$i)]]
			
			AutoComplete $critwidget(varcbx,$i) -aclist $options(-fieldlist)
			
			set formdata(mode,$i) ""
			set modewidget(modecbx,$i) [ttk::combobox $critframe.modecbx$i -values $modes -state readonly \
				-textvariable [myvar formdata(mode,$i)] -width 7]
			bind $modewidget(modecbx,$i) <<ComboboxSelected>> [mymethod modeselect $i]

			set critwidget(parframe,$i) [ttk::frame $critframe.par$i]

			grid $critwidget(addbtn,$i) $critwidget(varcbx,$i) $modewidget(modecbx,$i) $critwidget(parframe,$i) -sticky nsew
		}
		grid columnconfigure $critframe 3 -weight 1
	}

	method AddCriterion {} {
		set settings [$self Serialize]
		incr ncrit
		$self CreateCriteriaWidgets
		$self Deserialize $settings
		for {set i 0} {$i < $ncrit - 1} {incr i} {
			$self modeselect $i
		}
	}

	proc lskip {list ind} {
		# return a list where the element
		# at position ind is removed
		set mind [expr {$ind-1}]
		set pind [expr {$ind+1}]
		list {*}[lrange $list -1 $mind] {*}[lrange $list $pind end]
	}

	method RemoveCriterion {ind} {
		set settings [$self Serialize]
		set redsettings [lskip $settings $ind]
		incr ncrit -1
		$self CreateCriteriaWidgets

		$self Deserialize $redsettings
		for {set i 0} {$i < $ncrit} {incr i} {
			$self modeselect $i
		}

	}

	method modeselect {ind} {
		set mode $formdata(mode,$ind)
		set frame $critwidget(parframe,$ind)
		set formalparams [dict get $signatures $mode]
		
		destroy {*}[winfo children $frame]
		
		set i 0
		foreach {text type} $formalparams {
			if {$text ne ""} {
				grid [ttk::label $frame.l$i -text $text] -column [expr {2*$i}] -row 0 -sticky nsew
			}
			set ent [ttk::entry $frame.e$i -width 6 -textvariable [myvar formdata(par,$ind,$i)]] 
			grid $ent -column [expr {2*$i+1}] -row 0 -sticky nsew
			
			incr i
		}
	}


	method Serialize {} {
		set result {}
		for {set i 0} {$i < $ncrit} {incr i} {
			set var $formdata(var,$i)
			set mode $formdata(mode,$i)
			set formalparams [dict get $signatures $mode]
			set line [list $var $mode]

			set j 0
			foreach {_ par} $formalparams {
				lappend line $formdata(par,$i,$j)
				incr j
			}

			lappend result $line
		}
		return $result
	}

	method Deserialize {settings} {
		set i 0
		foreach line $settings {
			set par [lassign $line formdata(var,$i) formdata(mode,$i)]
			set j 0
			foreach p $par {
				set formdata(par,$i,$j) $p
				incr j
			}
			incr i
		}
	}
	
	proc widenrange {from to epsilon} {
		set nfrom [expr {$from - $epsilon*abs($from)}]
		set nto [expr {$to + $epsilon*abs($to)}]
		list $nfrom $nto
	}

	proc narrowrange {from to epsilon} {
		set nfrom [expr {$from + $epsilon*abs($from)}]
		set nto [expr {$to - $epsilon*abs($to)}]
		list $nfrom $nto
	}

	method AdjustCriterion {crit} {
		# adjust search criteria by epsilon
		set par [lassign $crit var mode]
		switch $mode {
			between {
				set par [widenrange {*}$par $epsilon]
			}

			covers {
				set par [narrowrange {*}$par $epsilon]
			}

			included {
				set par [widenrange {*}$par $epsilon]
			}

			equal {
				lassign $par spar
				set par [widenrange $spar $spar $epsilon]
				set mode included
			}
		}
		
		return [list $var $mode {*}$par]
	}

	method SetTitle {option title} {
		set options($option) $title
		wm title $win $title
	}

	method ClearCacheCmd {} {
		set ans [tk_messageBox -message "Do you really want to clear the precious cache?" \
			-parent $win -title "Are you sure?" -default cancel -type okcancel]
		if {$ans eq "ok"} {
			BessyHDFViewer::ClearCache
		}
	}

	method OpenDB {} {
		set newdb [tk_getSaveFile -title "Choose cachefile" -initialfile $BessyHDFViewer::HDFCacheFile -filetypes {{"Cache files" *.db}} -defaultextension db]
		if {$newdb ne {}} {
			BessyHDFViewer::PreferenceSet HDFCacheFile $newdb
			BessyHDFViewer::InitCache
		}
	}

	method ResetDB {} {
		BessyHDFViewer::PreferenceSet HDFCacheFile {}
		BessyHDFViewer::InitCache
	}

	method IndexRunCmd {} {
		set rootdir [$BessyHDFViewer::w(filelist) getcwd]
		set ans [tk_messageBox -title "Are you sure?" \
		-message "Run the index over the current directory\n$rootdir\n ? This may take some time and cannot be interrupted." \
		-parent . -default cancel -type okcancel]
		if {$ans eq "ok"} {
			set status "Enumerating files..."
			update
			set files [fileutil::findByPattern $rootdir -glob {*.hdf *.h5}]
			set N [llength $files]
			set count 0
			foreach fn $files {
				if {$count % 10 == 0} {
					set status "Indexing $count from $N files..." 
					update
				}
				BessyHDFViewer::ClassifyHDF file $fn
				incr count
			}

			set status "Indexing done ($count files)"

		}
	}

	method ImportCmd {} {
		set foreigncache [tk_getOpenFile -title "Choose cachefile for import" -initialfile $BessyHDFViewer::HDFCacheFile \
			 -filetypes {{"Cache files" *.db} {"All files" *}} ]
		if {$foreigncache ne {}} {
			set mb ._message
			toplevel $mb
			pack [label $mb.l -text "Please wait while importing ...."]
			update

			BessyHDFViewer::ImportCache $foreigncache
			lassign [BessyHDFViewer::CacheStats] nfiles nvalues
			pack [label $mb.l2 -text "$nvalues from $nfiles imported"]
			pack [button $mb.b -command [list destroy $mb] -text "Close"]
		}
	}

}
