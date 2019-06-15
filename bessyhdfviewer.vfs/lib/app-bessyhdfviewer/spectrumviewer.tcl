namespace eval SpectrumViewer {
	proc Open {} {
		spectrumviewer .spectrum
	}

	snit::widget spectrumviewer {
		hulltype toplevel
		
		component Graph
		component bbar

		variable spectra
		variable poscountersets {}
		variable spectrumfn
		variable spectrashown {}
		variable lastselected {}

		constructor {} {
			if {[llength $BessyHDFViewer::HDFFiles] != 1} {
				return -code error "Only 1 file can be selected!"
			}
			if {[dict exists $BessyHDFViewer::hdfdata HDDataset]} {
				set firstkey [lindex [dict keys [dict get $BessyHDFViewer::hdfdata HDDataset]] 0]
				set spectrumfn [lindex $BessyHDFViewer::HDFFiles 0]
				set thisspectrum [dict get $BessyHDFViewer::hdfdata HDDataset $firstkey]
				set spectra [dict create $spectrumfn $thisspectrum]
				set poscounter [SmallUtils::dict_getdefault $BessyHDFViewer::hdfdata Dataset PosCounter data {}]

				dict set poscountersets $spectrumfn $poscounter

				puts "vars: $spectrumfn $firstkey"
				
				install bbar using ttk::frame $win.bbar
				install Graph using ukaz::graph $win.g
				
				grid $bbar -sticky nsew
				grid $Graph -sticky nsew
				grid columnconfigure $win $Graph -weight 1
				grid rowconfigure $win $Graph -weight 1
				
				
				set cycleroibtn [ttk::button $bbar.cycle -text "Cycle" -command [mymethod cycle]]
				set plotallbtn [ttk::button $bbar.plotall -text "Plot all" -command [mymethod plotall]]
				set addroibtn [ttk::button $bbar.add -text "Add ROI" -command [mymethod AddROICmd]]
				set computebtn [ttk::button $bbar.compute -text "Compute" -command [mymethod ComputeROIs]]

				pack $cycleroibtn -side left
				pack $plotallbtn -side left
				pack $addroibtn -side left
				pack $computebtn -side left

				$Graph set log y

				BessyHDFViewer::RegisterPickCallback [mymethod SpectrumPick]
				
				set linestyles {
					{color red}
					{color black}
					{color blue}
					{color green}
					{color red dash .}
					{color black dash .}
					{color blue dash .}
					{color green dash .}
				}

				ResourceAllocator StyleAlloc $linestyles
				
				BessyHDFViewer::ClearHighlights
				
				# find first spectrum
				foreach {ind Pos}  [SmallUtils::enumerate $poscounter] {
					if {[dict exists $thisspectrum $Pos]} {
						$self showspec $spectrumfn $ind
						set lastselected [list $spectrumfn $ind]
						break
					}
				}

			}
		}

		method showspec {fn dpnr} {
			set Pos [lindex [SmallUtils::dict_getdefault $poscountersets $fn {}] $dpnr]
			if {![dict exists $spectrashown $fn $Pos]} {
				if {![dict exists $spectra $fn $Pos]} { return }
				
				set specdata [SmallUtils::enumerate [dict get $spectra $fn $Pos]]
				
				set ls [StyleAlloc alloc [list $fn $Pos]]
				BessyHDFViewer::HighlightDataPoint $fn $dpnr pt circles {*}$ls lw 3 ps 1.5
				set id [$Graph plot $specdata with lines title "[file tail $fn] $Pos" {*}$ls]
				dict set spectrashown $fn $Pos $id
			}
		}

		method unshowspec {fn dpnr} {
			set Pos [lindex [SmallUtils::dict_getdefault $poscountersets $fn {}] $dpnr]
			if {[dict exists $spectrashown $fn $Pos]} {
				set id [dict get $spectrashown $fn $Pos]
				$Graph remove $id
				BessyHDFViewer::HighlightDataPoint $fn $dpnr pt ""
				dict unset spectrashown $fn $Pos
				StyleAlloc free [list $fn $Pos]
			}
		}

		method specvisible {fn dpnr} {
			set Pos [lindex [SmallUtils::dict_getdefault $poscountersets $fn {}] $dpnr]
			dict exists $spectrashown $fn $Pos
		}

		method SpectrumPick {clickdata} {
			set dpnr [dict get $clickdata dpnr]
			set fn [dict get $clickdata fn]
			set shiftstate [dict get $clickdata state]

			puts "Shift state $shiftstate"

			set Shift 1
			set Control 4

			if {$shiftstate & $Shift || $shiftstate & $Control} {
				set shift true
				puts "Hold shift/control"
			} else {
				set shift false
			}

			if {$fn ne $spectrumfn} { return }

			set poscounter [SmallUtils::dict_getdefault $poscountersets $fn {}]
			set Pos [lindex $poscounter $dpnr]

			if {[$self specvisible $fn $dpnr]} {
				$self unshowspec $fn $dpnr
				set lastselected {}
			} else {
				$self showspec $fn $dpnr
				set lastselected [list $fn $dpnr]
			}
		}

		method cycle {} {
			lassign $lastselected fn dpnr
			$self unshowspec $fn $dpnr

			if {$fn eq {} || $dpnr eq {}} {
				return
			}
			
			incr dpnr
			
			set N [llength [SmallUtils::dict_getdefault $poscountersets $fn {}]]
			if {$dpnr >= $N} { set dpnr 0 }

			$self showspec $fn $dpnr
			set lastselected [list $fn $dpnr]
		}

		method plotall {} {
			lassign $lastselected fn dpnr
			if {$fn ne {}} {
				set poscounter [SmallUtils::dict_getdefault $poscountersets $fn {}]
				set thisspectrum [SmallUtils::dict_getdefault $spectra $fn {}]
				foreach {ind Pos}  [SmallUtils::enumerate $poscounter] {
					if {[dict exists $thisspectrum $Pos]} {
						$self showspec $spectrumfn $ind
						set lastselected [list $spectrumfn $ind]
					}
				}
			}
		}

		variable ROIs {}
		variable regions {}

		method AddROI {label min max} {
			set reg [ukaz::dragregion %AUTO% -orient vertical]
			$Graph addcontrol $reg
			$reg setPosition $min $max
			
			dict set regions $label $reg

			puts "ROI $reg"
		}

		variable ROInr 0
		method AddROICmd {} {
			# figure out a peak and add a ROI for it
			# fake it for now
			$self AddROI ROI$ROInr 2000 2100
			incr ROInr
		}

		method ComputeROIs {} {
			lassign [dict keys $regions] firstROIname
			dict for {fn spectrum} $spectra {
				set counter [BessyHDFViewer::SELECT {PosCounter} [list $fn] -allnan true]
				set result {}
				
				dict for {name reg} $regions {
					lassign [$reg getPosition] cmin cmax

					
					set column {}
					foreach posc $counter {
						lappend column [$self ROIeval $spectrum $posc $cmin $cmax]
					}

					dict set result $name data $column
					dict set result $name attrs leftMarker $cmin
					dict set result $name attrs rightMarker $cmax
				}
				
				BessyHDFViewer::SetPlotColumn $fn Detector $firstROIname
				BessyHDFViewer::SetExtraColumns $fn $result
			}
			
			#return $result
			BessyHDFViewer::ReDisplay
		}

		method ROIeval {spectrum posc cmin cmax} {
			if {![dict exists $spectrum $posc]} { return NaN }
			set spec [dict get $spectrum $posc]
			
			set indmin [expr {int($cmin+0.5)}]
			set indmax [expr {int($cmax+0.5)}]
			set range [lrange $spec $indmin $indmax]
			set result [tcl::mathop::+ {*}$range]
		
			return $result
		}

		method SaveROIEval {} {
			set rdata [$self ComputeROIs]
		}

		destructor {
			BessyHDFViewer::UnRegisterPickCallback [mymethod SpectrumPick]
			BessyHDFViewer::ClearHighlights
			StyleAlloc destroy
		}
	}

	snit::type ResourceAllocator {
		variable freeheap {}
		variable allocation {}

		constructor {resources} {
			# transform resources into heap
			foreach r $resources {
				dict set freeheap $r 1
			}
		}

		method alloc {key} {
			if {[dict exists $allocation $key]} {
				return [dict get $allocation $key]
			}

			# not in cache - try to alloc
			set freeres [dict keys [dict filter $freeheap value 1]]
			if {[llength $freeres] == 0} {
				# hm. Nothing left
				return {}
			}
			
			lassign $freeres r

			dict set allocation $key $r
			dict set freeheap $r 0
			return $r
		}

		method free {key} {
			set r [dict get $allocation $key]
			dict unset allocation $key
			dict set freeheap $r 1
		}

		method clear {} {
			set allocation {}
			foreach r [dict keys $freeheap] { dict set freeheap $r 1 }
		}
	}

}
