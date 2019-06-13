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

		variable ROIs {}
		variable regions {}

		method AddROI {label min max} {
			set reg [dragregion %AUTO% -orient vertical]
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

	# GUI control for ukaz graphs to define a ROI
	snit::type dragregion {
		variable dragging

		option -command -default {}
		option -orient -default vertical -configuremethod SetOrientation
		
		option -minvariable -default {} -configuremethod SetVariable
		option -maxvariable -default {} -configuremethod SetVariable

		option -color -default {#FFB0B0}
		option -linecolor -default {gray}
		
		variable pos
		variable pixpos
		variable canv {}
		variable graph {}
		variable xmin
		variable xmax
		variable ymin
		variable ymax

		variable loopescape false
		variable commandescape false
		
		constructor {args} {
			$self configurelist $args
		}
		
		destructor {
			$self untrace -minvariable
			$self untrace -maxvariable
			if { [info commands $canv] != {} } { 
				$canv delete $selfns.min
				$canv delete $selfns.max
				$canv delete $selfns.region
			}
		}


		method Parent {parent canvas} {
			if {$parent != {}} {
				# this control is now managed
				if {$graph != {}} {
					return -code error "$self: Already managed by $graph"
				}

				if {[info commands $canvas] == {}} {
					return -code error "$self: No drawing canvas: $canv"
				}

				set graph $parent
				set canv $canvas
				
				$canv create line {-1 -1 -1 -1} -fill $options(-linecolor) -dash . -tag $selfns.min
				$canv create line {-1 -1 -1 -1} -fill $options(-linecolor) -dash . -tag $selfns.max
				$canv create rectangle -2 -2 -1 -1 -outline "" -fill $options(-color) -tag $selfns.region
				$canv lower $selfns.region
				
				# Bindings for dragging
				$canv bind $selfns.min <ButtonPress-1> [mymethod dragstart min %x %y]
				$canv bind $selfns.min <Motion> [mymethod dragmove min %x %y]
				$canv bind $selfns.min <ButtonRelease-1> [mymethod dragend min %x %y]
				
				$canv bind $selfns.max <ButtonPress-1> [mymethod dragstart max %x %y]
				$canv bind $selfns.max <Motion> [mymethod dragmove max %x %y]
				$canv bind $selfns.max <ButtonRelease-1> [mymethod dragend max %x %y]
		
				# Bindings for hovering - change cursor
				$canv bind $selfns.min <Enter> [mymethod dragenter]
				$canv bind $selfns.min <Leave> [mymethod dragleave]
				$canv bind $selfns.max <Enter> [mymethod dragenter]
				$canv bind $selfns.max <Leave> [mymethod dragleave]
				
				set dragging {}
			
			} else {
				# this control was unmanaged. Remove our line
				if {$canv != {} && [info commands $canv] != {}} {
					$canv delete $selfns
				}
				set graph {}
				set canv {}
			}
		}

		variable configured false
		
		method Configure {range} {
			# the plot range has changed
			set loopescape false

			set xmin [dict get $range xmin]
			set xmax [dict get $range xmax]
			set ymin [dict get $range ymin]
			set ymax [dict get $range ymax]

			set configured true

			set loopescape false
			set commandescape true
			$self Redraw
		}

		method SetVariable {option varname} {
			$self untrace $option
			if {$varname != {}} {
				upvar #0 $varname v
				trace add variable v write [mymethod SetValue]
				set options($option) $varname
				$self SetValue
			}
		}

		method untrace {option} {
			if {$options($option)!={} } {
				upvar #0 $options($option) v
				trace remove variable v write [mymethod SetValue]
				set options($option) {}
			}			
		}
		
		method SetValue {args} {
			if {$loopescape} {
				set loopescape false
				return
			}
			set loopescape true
			upvar #0 $options(-minvariable) vmin
			upvar #0 $options(-maxvariable) vmax
			if {[info exists vmin] && [info exists vmax]} {
				catch {$self setPosition $vmin $vmax} err
				# ignore any errors if the graph is incomplete
			}
		}

		method DoTraces {} {
			if {$loopescape} {
				set loopescape false
			} else {
				if {$options(-minvariable) ne {} && $options(-maxvariable) ne {}} {
					set loopescape true
					upvar #0 $options(-minvariable) vmin
					upvar #0 $options(-maxvariable) vmax
					lassign $pos vmin vmax
				}
			}

			if {$options(-command)!={}} {
				if {$commandescape} {
					set commandescape false
				} else {
					uplevel #0 [list {*}$options(-command) {*}$pos]
				}	
			}
		}

		method SetOrientation {option value} {
			switch $value {
				vertical  -
				horizontal {
					set options($option) $value
				}
				default {
					return -code error "Unknown orientation $value: must be vertical or horizontal"
				}
			}
		}
					
		method dragenter {} {
			if {$dragging eq {}} {
				$canv configure -cursor hand2
			}
		}

		method dragleave {} {
			if {$dragging eq {}} {
				$canv configure -cursor {}
			}
		}

		method dragstart {what x y} {
			set dragging $what
		}

		method dragmove {what x y} {
			if {$dragging ne {}} {
				$self GotoPixel $dragging $x $y
			}
		}

		method dragend {what x y} {
			set dragging {}
		}

		method GotoPixel {what px py} {
			if {$graph=={}} { return }

			lassign $pos vmin vmax
			lassign $pixpos pmin pmax

			set vx [$graph pixToX $px]
			set vy [$graph pixToY $py]
			
			if {$options(-orient) eq "horizontal"} {
				if {$what eq "min"} {
					set vmin $vy
					set pmin $py
				} else {
					set vmax $vy
					set pmax $py
				}
			} else {
				if {$what eq "min"} {
					set vmin $vx
					set pmin $px
				} else {
					set vmax $vx
					set pmax $px
				}

			}
			
			set pixpos [list $pmin $pmax]
			set pos [list $vmin $vmax]

			$self drawregion
			$self DoTraces
		}

		method setPosition {vmin vmax} {
			set pos [list $vmin $vmax]
			$self Redraw
		}

		method Redraw {} {

			if {$graph=={}} { return }

			lassign $pos vmin vmax
			lassign [$graph graph2pix [list $vmin $vmin]] nxmin nymin
			lassign [$graph graph2pix [list $vmax $vmax]] nxmax nymax

			if {$options(-orient) eq "horizontal"} {
				set pmin $nymin
				set pmax $nymax
			} else {
				set pmin $nxmin
				set pmax $nxmax
			}

			set pixpos [list $pmin $pmax]
			$self drawregion
			$self DoTraces
		}

		method drawregion {} {
			if {!$configured} { return }

			lassign $pixpos pmin pmax

			#	puts "pos: $pos pixpos: $pixpos"

			if {$options(-orient)=="horizontal"} {
				$canv coords $selfns.min [list $xmin $pmin $xmax $pmin]
				$canv coords $selfns.max [list $xmin $pmax $xmax $pmax]
				$canv coords $selfns.region [list $xmin $pmin $xmax $pmax]
			} else {
				$canv coords $selfns.min [list $pmin $ymin $pmin $ymax]
				$canv coords $selfns.max [list $pmax $ymin $pmax $ymax]
				$canv coords $selfns.region [list $pmin $ymin $pmax $ymax]
			}

			$canv raise $selfns.min
			$canv raise $selfns.max
		}

		method getPosition {} {
			return $pos
		}
	
	}

}
