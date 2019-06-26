namespace eval SpectrumViewer {
	proc Open {} {
		spectrumviewer .spectrum
	}

	snit::widget spectrumviewer {
		hulltype toplevel
		
		component Graph
		component bbar

		variable allspectra
		variable spectrometers {}
		variable poscountersets {}
		variable spectrumfn
		variable lastselected {}
		variable validpoints {}

		constructor {} {
			
			install bbar using ttk::frame $win.bbar
			install Graph using ukaz::graph $win.g
			
			grid $bbar -sticky nsew
			grid $Graph -sticky nsew
			grid columnconfigure $win $Graph -weight 1
			grid rowconfigure $win $Graph -weight 1
			
			
			set cycleroibtn [ttk::button $bbar.cycle -text "Cycle" -command [mymethod cycle]]
			set plotallbtn [ttk::button $bbar.plotall -text "Plot all" -command [mymethod plotall]]
			set addroibtn [ttk::button $bbar.add -text "Add ROI" -command [mymethod AddROICmd]]
			set delroibtn [ttk::button $bbar.del -text "Delete ROI" -command [mymethod DeleteROICmd]]
			set computebtn [ttk::button $bbar.compute -text "Compute" -command [mymethod ComputeROIs]]

			pack $cycleroibtn -side left
			pack $plotallbtn -side left
			pack $addroibtn -side left
			pack $delroibtn -side left
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
			ResourceAllocator RegionColorAlloc {#FF0000 #00A000 #0000FF #800000 #005000 #000080}
			
			BessyHDFViewer::ClearHighlights
		
			$self reshape_spectra
			puts [join $validpoints \n]

			$self showspec 0
		}

		method reshape_spectra {} {	
			# read the spectra of the displayed files
			foreach fn $BessyHDFViewer::HDFFiles {
				# use the cache to accelerate loading for one file
				if {[llength $BessyHDFViewer::HDFFiles] == 1} {
					set hdfdata $BessyHDFViewer::hdfdata
				} else {
					set hdfdata [BessyHDFViewer::bessy_reshape $fn
				}
				
				if {![dict exists $hdfdata HDDataset]} { continue }
				
				set poscounter [SmallUtils::dict_getdefault $hdfdata Dataset PosCounter data {}]
				dict set poscountersets $fn $poscounter
				set spectra [dict get $hdfdata HDDataset]
				set devices {}
				foreach {spectrometer data} $spectra {
					dict set devices $spectrometer 1
					foreach {Pos counts} $data {
						dict set allspectra $fn $Pos $spectrometer $counts
					}
				}

				dict set spectrometers $fn [dict keys $devices]

				# check for data points with spectra
				foreach {dpnr Pos}  [SmallUtils::enumerate $poscounter] {
					# check if at least one spectrometer has measured a spectrum here
					if {[dict exists $allspectra $fn $Pos]} {
						lappend validpoints [list $fn $dpnr]
					}
				}
			}
		}

		variable spectrashown {}
		method showspec {ind} {
			lassign [lindex $validpoints $ind] fn dpnr
			
			set Pos [lindex [SmallUtils::dict_getdefault $poscountersets $fn {}] $dpnr]
			if {![dict exists $spectrashown $fn $Pos]} {
				if {![dict exists $allspectra $fn $Pos]} { return }

				set spectra [dict get $allspectra $fn $Pos]
				
				set ids {}
				foreach {spectrometer data} $spectra {
					set specdata [SmallUtils::enumerate $data]
				
					set ls [StyleAlloc alloc [list $fn $Pos $spectrometer]]
					BessyHDFViewer::HighlightDataPoint $fn $dpnr pt circles {*}$ls lw 3 ps 1.5
					lappend ids [$Graph plot $specdata with lines title "[file tail $fn] $Pos" {*}$ls]
				}

				dict set spectrashown $fn $Pos ids $ids
				dict set spectrashown $fn $Pos ind $ind
			}
			puts $spectrashown
		}

		method unshowspec {ind} {
			lassign [lindex $validpoints $ind] fn dpnr
			
			set Pos [lindex [SmallUtils::dict_getdefault $poscountersets $fn {}] $dpnr]
			if {[dict exists $spectrashown $fn $Pos]} {
				set ids [dict get $spectrashown $fn $Pos ids]
				foreach id $ids { $Graph remove $id }
				BessyHDFViewer::HighlightDataPoint $fn $dpnr pt ""
				dict unset spectrashown $fn $Pos
				foreach {spectrometer data} [dict get $allspectra $fn $Pos] {
					StyleAlloc free [list $fn $Pos $spectrometer]
				}
			}
		}

		method specvisible {ind} {
			lassign [lindex $validpoints $ind] fn dpnr
			
			set Pos [lindex [SmallUtils::dict_getdefault $poscountersets $fn {}] $dpnr]
			dict exists $spectrashown $fn $Pos
		}

		method unshowall {} {
			dict for {fn fnspec} $spectrashown {
				dict for {Pos data} $fnspec {
					puts $data
					$self unshowspec [dict get $data ind]
				}
			}
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

			set poscounter [SmallUtils::dict_getdefault $poscountersets $fn {}]
			set Pos [lindex $poscounter $dpnr]
			set ind [$self getSpecNr $fn $dpnr]

			if {$ind == -1} { return }

			if {$shift} {
				if {[$self specvisible $ind]} {
					$self unshowspec $ind
					set lastselected -1
				} else {
					$self showspec $ind
					set lastselected $ind
				}
			} else {
				$self unshowall
				$self showspec $ind
				set lastselected $ind
			}
		}

		method getSpecNr {fn dpnr} {
			set ind [lsearch -exact $validpoints [list $fn $dpnr]]
			return $ind
		}

		method cycle {} {
			if {$lastselected != -1} {
				$self unshowspec $lastselected
			}
						
			set ind $lastselected
			
			incr ind 
			set N [llength $validpoints]
			if {$ind >= $N} { set ind 0 }

			$self showspec $ind

			set lastselected $ind
		}

		method plotall {} {
			foreach pt $validpoints {
				$self showspec {*}$pt
			}
		}

		variable ROIs {}
		variable regions {}

		method AddROI {label min max} {
			set color [RegionColorAlloc alloc $label]
			set reg [ukaz::dragregion %AUTO% -orient vertical -label $label -color $color]
			$Graph addcontrol $reg
			$reg setPosition $min $max
			
			dict set regions $label $reg

			puts "ROI $reg"
		}

		method DeleteROICmd {} {
			set selROI [$Graph getSelectedControl]
			set ROIname [$selROI cget -label]

			if {[dict exists $regions $ROIname]} {
				RegionColorAlloc free $ROIname
				dict unset regions $ROIname
			}
			$selROI destroy

		}

		variable ROInr 0
		method AddROICmd {} {
			# figure out a peak and add a ROI for it
			# fake it for now
			$self AddROI ROI$ROInr 2000 2100
			incr ROInr
		}

		method ComputeROIs {} {
			
			set selROI [$Graph getSelectedControl]
			
			dict for {fn spectrum} $allspectra {
				set counter [BessyHDFViewer::SELECT {PosCounter} [list $fn] -allnan true]
				set result {}
				
				set first true
				dict for {rname reg} $regions {
					lassign [$reg getPosition] cmin cmax

					set Ndevices [llength [dict get $spectrometers $fn]]
					foreach spectrometer [dict get $spectrometers $fn] {
						set column {}
						foreach posc $counter {
							lappend column [$self ROIeval $spectrum $spectrometer $posc $cmin $cmax]
						}
						
						if {$Ndevices == 1 } {
							set ROIname $rname
						} else {
							set ROIname ${spectrometer}_${rname}
						}
						
						dict set result $ROIname data $column
						dict set result $ROIname attrs leftMarker $cmin
						dict set result $ROIname attrs rightMarker $cmax

						if {$first && (($reg eq $selROI) || ($selROI eq ""))} {
							set firstROIname $ROIname
							set first false
						}
					}
				}
				
				BessyHDFViewer::SetPlotColumn $fn Detector $firstROIname
				BessyHDFViewer::SetExtraColumns $fn $result
			}
			
			#return $result
			BessyHDFViewer::ReDisplay
		}

		method ROIeval {spectrum spectrometer posc cmin cmax} {
			if {![dict exists $spectrum $posc $spectrometer]} { return NaN }
			set spec [dict get $spectrum $posc $spectrometer]
			
			set indmin [expr {int($cmin+0.5)}]
			set indmax [expr {int($cmax+0.5)}]
			set range [lrange $spec $indmin $indmax]
			set result [tcl::mathop::+ {*}$range]
		
			return [expr {double($result)}]
		}

		method SaveROIEval {} {
			set rdata [$self ComputeROIs]
		}

		destructor {
			BessyHDFViewer::UnRegisterPickCallback [mymethod SpectrumPick]
			BessyHDFViewer::ClearHighlights
			StyleAlloc destroy
			RegionColorAlloc destroy
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
