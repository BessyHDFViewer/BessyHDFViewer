#   spectrumviewer.tcl
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

namespace eval SpectrumViewer {
	namespace import ::SmallUtils::*
	
	proc transpose {matrix} {
		set res {}
		for {set j 0} {$j < [llength [lindex $matrix 0]]} {incr j} {
			set newrow {}
			foreach oldrow $matrix {
				lappend newrow [lindex $oldrow $j]
			}
			lappend res $newrow
		}
		return $res
	}
	
	proc Open {} {
		spectrumviewer .spectrum
	}

	snit::widget spectrumviewer {
		hulltype toplevel
		
		component Graph
		component bbar
		component scroller

		variable allspectra
		variable spectrometers {}
		variable poscountersets {}
		variable spectrumfn
		variable lastselected -1
		variable validpoints {}

		constructor {} {
			
			install bbar using ttk::frame $win.bbar
			install Graph using ukaz::graph $win.g
			
			install scroller using ttk::scrollbar $win.scroll -orient horizontal -command [mymethod scrollview]
			
			grid $bbar -sticky nsew
			grid $scroller -sticky nsew
			grid $Graph -sticky nsew
			grid columnconfigure $win $Graph -weight 1
			grid rowconfigure $win $Graph -weight 1
			
			
			set cycleroibtn [ttk::button $bbar.cycle -text "Cycle" -command [mymethod cycle]]
			set plotallbtn [ttk::button $bbar.plotall -text "Plot all" -command [mymethod plotall]]
			set addroibtn [ttk::button $bbar.add -text "Add ROI" -command [mymethod AddROICmd]]
			set delroibtn [ttk::button $bbar.del -text "Delete ROI" -command [mymethod DeleteROICmd]]
			set computebtn [ttk::button $bbar.compute -text "Compute" -command [mymethod ComputeROIs]]
			set exportbtn [ttk::button $bbar.export -text "Export" -command [mymethod ExportCmd]]

			pack $cycleroibtn -side left
			pack $plotallbtn -side left
			pack $addroibtn -side left
			pack $delroibtn -side left
			pack $computebtn -side left
			pack $exportbtn -side left

			$Graph set log y

			BessyHDFViewer::RegisterPickCallback [mymethod SpectrumPick]
			
			set linestyles {
				{color red dash {}}
				{color black dash {}}
				{color blue dash {}}
				{color green dash {}}
				{color red dash {2 6}}
				{color black dash {2 6}}
				{color blue dash {2 6}}
				{color green dash {2 6}}
				{color red dash {8 6}}
				{color black dash {8 6}}
				{color blue dash {8 6}}
				{color green dash {8 6}}
				{color red dash {8 6 2 6}}
				{color black dash {8 6 2 6}}
				{color blue dash {8 6 2 6}}
				{color green dash {8 6 2 6}}
			}

			ResourceAllocator StyleAlloc $linestyles
			ResourceAllocator RegionColorAlloc {#FF0000 #00A000 #0000FF #800000 #005000 #000080}
			
			BessyHDFViewer::ClearHighlights
		
			$self reshape_spectra

			$self showspec 0
			$self adjustScrollbar 0
		}

		method reshape_spectra {} {	
			# read the spectra of the displayed files
			foreach fn $BessyHDFViewer::HDFFiles {
				set hdfdata [BessyHDFViewer::bessy_reshape $fn]
				
				if {![dict exists $hdfdata HDDataset]} { continue }
				
				set poscounter [dict_getdefault $hdfdata Dataset PosCounter data {}]
				dict set poscountersets $fn $poscounter
				set spectra [dict get $hdfdata HDDataset]
				set devices {}
				foreach {spectrometer data} $spectra {
					dict set devices $spectrometer 1
					foreach {Pos counts} [dict get $data data] {
						dict set allspectra $fn $Pos $spectrometer $counts
					}
				}
				
				set devicelist [dict keys $devices]
				foreach device $devicelist {
					# try to get calibration data
					set basename [regsub {spectrum$} $device ""]
					set caliblist [BessyHDFViewer::SELECTdata [list PosCounter ${basename}_CalO ${basename}_CalS ${basename}_CalQ ${basename}_lifeTime] $hdfdata -allnan true]
					# reformat into dict format
					set calib {}
					foreach {pc calo cals calq lifetime} [concat {*}$caliblist] {
						dict set calib $pc CalO $calo
						dict set calib $pc CalS $cals
						dict set calib $pc CalQ $calq
						dict set calib $pc LifeTime $lifetime
					}
					dict set spectrometers $fn $device calib $calib
				}

				# check for data points with spectra
				foreach {dpnr Pos}  [SmallUtils::enumerate $poscounter] {
					# check if at least one spectrometer has measured a spectrum here
					if {[dict exists $allspectra $fn $Pos]} {
						lappend validpoints [list $fn $dpnr]
					}
				}
			}
		}

		
		method export_spectra {dir} {
			dict for {fn fndata} $allspectra {
				dict for {pos posdata} $fndata {
					puts "Exporting $pos"
					dict for {spectrometer countlist} $posdata {
						set base [file rootname [file tail $fn]]
						set npos [format %05d $pos]
						set outfn [file join $dir ${base}_${spectrometer}_${npos}.dat]
						# find out calibration coefficients, if known
						set calo [dict get $spectrometers $fn $spectrometer calib $pos CalO]
						set cals [dict get $spectrometers $fn $spectrometer calib $pos CalS]
						set calq [dict get $spectrometers $fn $spectrometer calib $pos CalQ]
						set lifetime [dict get $spectrometers $fn $spectrometer calib $pos LifeTime]
						
						if {isfinite($calo) && isfinite($cals) && isfinite($calq)} {
							set calibrated true
						} else {
							set calibrated false
						}
						
						if {isfinite($lifetime) && ($lifetime > 0.0)} {
							set normalize true
						} else {
							set normalize false
						}

						set units {}
						set header [list "# File = $fn"]
						lappend header "# Spectrometer = $spectrometer"
						lappend header "# PosCounter = $pos"
	
						if {$calibrated} {
							lappend header "# CalO = $calo"
							lappend header "# CalS = $cals"
							lappend header "# CalQ = $calq"
							dict set units Energy eV
						}

						if {$normalize} {
							lappend header "# LifeTime = $lifetime"
							dict set units Countrate s^-1
						}

						set datacols {}
						if {$calibrated} {
							for {set i 0} {$i<[llength $countlist]} {incr i} {
								set energy [expr {$calo + $cals*$i + $calq*$i**2}]
								dict lappend datacols Energy $energy
							}
						} else {
							for {set i 0} {$i<[llength $countlist]} {incr i} {
								dict lappend datacols Channel $i
							}
						}

						if {$normalize} {
							foreach count $countlist {
								dict lappend datacols Countrate [expr {double($count)/$lifetime}]
							}
						}
						
						dict set datacols Counts $countlist
						
						set lines $header
						# append header with dataset description
						if {$units ne {}} {
							lappend lines "# Datasets:"
							dict for {col unit} $units {
								lappend lines "# \t$col:"
								lappend lines "# \t\tUnit\t= $unit"
							}
						}

						# append column names
						set colnames [dict keys $datacols]
						lappend lines "# [join $colnames \t]"

						foreach dataline [transpose [dict values $datacols]] {
							lappend lines [join $dataline \t]
						}
						
						fileutil::writeFile $outfn [join $lines \n]
					}
				}
			}
		}


		method ExportCmd {} {
			set fn1 [lindex [dict keys $allspectra] 0]
			set basedir [file dirname $fn1]
			set dir [tk_getDirectory -title "Choose directory for the exported spectra..." -initialdir $basedir]
			if {$dir ne ""} {
				$self export_spectra $dir
			}
		}

		variable spectrashown {}
		method showspec {ind} {
			lassign [lindex $validpoints $ind] fn dpnr
			
			set Pos [lindex [dict_getdefault $poscountersets $fn {}] $dpnr]
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
		}

		method unshowspec {ind} {
			lassign [lindex $validpoints $ind] fn dpnr
			
			set Pos [lindex [dict_getdefault $poscountersets $fn {}] $dpnr]
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
			
			set Pos [lindex [dict_getdefault $poscountersets $fn {}] $dpnr]
			dict exists $spectrashown $fn $Pos
		}

		method unshowall {} {
			dict for {fn fnspec} $spectrashown {
				dict for {Pos data} $fnspec {
					$self unshowspec [dict get $data ind]
				}
			}
		}

		method SpectrumPick {clickdata} {
			set dpnr [dict get $clickdata dpnr]
			set fn [dict get $clickdata fn]
			set shiftstate [dict get $clickdata state]

			set Shift 1
			set Control 4

			if {$shiftstate & $Shift || $shiftstate & $Control} {
				set shift true
			} else {
				set shift false
			}

			set poscounter [dict_getdefault $poscountersets $fn {}]
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

			$self adjustScrollbar $ind
		}

		method getSpecNr {fn dpnr} {
			set ind [lsearch -exact $validpoints [list $fn $dpnr]]
			return $ind
		}

		method cycle {} {
			set N [llength $validpoints]
			set ind [expr {($lastselected+1) % $N}]

			$self goto $ind
		}
		
		variable curhidden {}
		method goto {ind} {
			if {$lastselected != -1 } {
				$self unshowspec $lastselected
			}
						
			$self showspec $ind

			$self adjustScrollbar $ind
			set lastselected $ind
			
			# move scrollbar

		}

		method adjustScrollbar {ind} {
			set N [llength $validpoints]
			set delta [expr {1.0/double($N)}]
			$scroller set [expr {$ind*$delta}] [expr {($ind+1)*$delta}]
		}

		method scrollview {op args} {
			switch $op {
				scroll {
					lassign $args distance units
					set ind $lastselected
					incr ind $distance
					$self goto $ind
				}

				moveto {
					lassign $args frac
					set ind [expr {int($frac * [llength $validpoints])}]
					$self goto $ind
				}

				default { puts "Unknown scroll command" }
			}
			
		}

		method plotall {} {
			for {set i 0} {$i < [llength $validpoints]} {incr i} {
				$self showspec $i
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
			# compute a sensible region in the middle of the visible area
			dict_assign [$Graph cget -displayrange] xmin xmax

			set vmin [expr {$xmin + 0.48*$xmax}]
			set vmax [expr {$xmin + 0.52*$xmax}]
			$self AddROI ROI$ROInr $vmin $vmax
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
					
					set devicenames [dict keys [dict get $spectrometers $fn]]
					set Ndevices [llength $devicenames]
					foreach spectrometer $devicenames {
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
			catch { StyleAlloc destroy }
			catch { RegionColorAlloc destroy }
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
