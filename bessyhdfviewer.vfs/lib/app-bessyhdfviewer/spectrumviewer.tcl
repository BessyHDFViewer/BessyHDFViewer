namespace eval SpectrumViewer {
	proc Open {} {
		spectrumviewer .spectrum
	}

	snit::widget spectrumviewer {
		hulltype toplevel
		
		component Graph

		variable spectra
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
				set spectra [dict create $spectrumfn [dict get $BessyHDFViewer::hdfdata HDDataset $firstkey]]

				puts "vars: $spectrumfn $firstkey"

				install Graph using ukaz::graph $win.g

				pack $Graph -fill both -expand yes
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

			if {$fn ne $spectrumfn} { return }

			set poscounter [SmallUtils::dict_getdefault $BessyHDFViewer::hdfdata Dataset PosCounter data {}]
			set Pos [lindex $poscounter $dpnr]

			if {[dict exists $spectrashown $fn $Pos]} {
				# toggle
				set id [dict get $spectrashown $fn $Pos]
				$Graph remove $id
				BessyHDFViewer::HighlightDataPoint $fn $dpnr pt ""
				dict unset spectrashown $fn $Pos
				StyleAlloc free [list $fn $Pos]
				set lastselected {}
			} else {
			
				if {[dict exists $spectra $fn $Pos]} {
					set specdata [SmallUtils::enumerate [dict get $spectra $fn $Pos]]
					
					set ls [StyleAlloc alloc [list $fn $Pos]]
					BessyHDFViewer::HighlightDataPoint $fn $dpnr pt circles {*}$ls lw 3 ps 1.5
					set id [$Graph plot $specdata with lines title "[file tail $fn] $Pos" {*}$ls]
					dict set spectrashown $fn $Pos $id

					set lastselected [list $fn $dpnr]

				}
			}
		}

		method cycle {} {
		}

		destructor {
			BessyHDFViewer::UnRegisterPickCallback [mymethod SpectrumPick]
			BessyHDFViewer::ClearHighlights
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
