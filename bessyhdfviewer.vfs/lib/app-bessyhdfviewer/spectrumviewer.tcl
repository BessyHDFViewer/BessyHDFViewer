namespace eval SpectrumViewer {
	proc Open {} {
		spectrumviewer .spectrum
	}

	snit::widget spectrumviewer {
		hulltype toplevel
		
		component Graph

		variable linestyles
		variable lsused 0
		variable spectra
		variable spectrumfn

		constructor {} {
			if {[llength $BessyHDFViewer::HDFFiles] != 1} {
				return -code error "Only 1 file can be selected!"
			}
			if {[dict exists $BessyHDFViewer::hdfdata HDDataset]} {
				set firstkey [lindex [dict keys [dict get $BessyHDFViewer::hdfdata HDDataset]] 0]
				set spectra [dict get $BessyHDFViewer::hdfdata HDDataset $firstkey]
				set spectrumfn [lindex $BessyHDFViewer::HDFFiles 0]

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
					{color red dash -}
					{color black dash -}
					{color blue dash -}
					{color green dash -}
				}
				
				BessyHDFViewer::ClearHighlights
			}
		}

		method SpectrumPick {clickdata} {
			set dpnr [dict get $clickdata dpnr]
			set fn [dict get $clickdata fn]
			set shiftstate [dict get $clickdata state]

			puts "Shift state $shiftstate"

			if {$fn ne $spectrumfn} { return }

			set poscounter [SmallUtils::dict_getdefault $BessyHDFViewer::hdfdata Dataset PosCounter data {}]
			set Pos [lindex $poscounter $dpnr]
			
			if {[dict exists $spectra $Pos]} {
				set specdata [SmallUtils::enumerate [dict get $spectra $Pos]]
				set ls [lindex $linestyles $lsused]
				incr lsused
				
				BessyHDFViewer::HighlightDataPoint $fn $dpnr pt circles {*}$ls lw 5 ps 1.5
				$Graph plot $specdata with lines title "Spec $Pos" {*}$ls
			}
		}

		destructor {} {
			BessyHDFViewer::UnRegisterPickCallback [mymethod SpectrumPick]
			BessyHDFViewer::ClearHighlights
		}
	}

}
