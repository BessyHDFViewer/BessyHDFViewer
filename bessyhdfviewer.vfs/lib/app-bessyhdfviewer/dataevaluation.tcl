namespace eval DataEvaluation {
	# built-in methods for general data evaluation

	# list of available commands, to be evaluated by the main program
	# function, icon, description

	set commands {
		FindPeaks	peakdetect	"Find peaks by Scholkmann's method"
		FindCenter	peakcenter	"Compute peak and center like measurement program"
		ShowDerivative derivative "Compute derivative"
		RefDivide  refdivide "Divide by first dataset"
	}

	# peak-locating using the AMPD method
	# Algorithms 2012, 5(4), 588-603; doi:10.3390/a5040588
	#
	# NOTE: Scholkmann's algorithm description is a bit confusing
	# using random numbers and standrad deviations
	# This implementation tries to follow the original idea,
	# but in a deterministic way 
	proc ampd_max {v} {
		set N [llength $v]
		# find maximum of gamma
		set lambda 1
		set gmax 0
		for {set k 1} {$k<$N/2-1} {incr k} {
			set gamma 0
			for {set i $k} {$i<$N-$k} {incr i} {
				# negative copmarisons are needed to properly deal with NaN
				incr gamma [expr {!([lindex $v $i] <= [lindex $v [expr {$i-$k}]]) &&
					!([lindex $v $i] <= [lindex $v [expr {$i+$k}]])}]
			}
			
			if {$gamma > $gmax} {
				set gmax $gamma
				set lambda $k
			}
		}

		# now find maxima for all levels up to k<=lambda
		set maxima {}
		for {set i $lambda} {$i<$N-$lambda} {incr i} {
			# find total maximum in the window of size 2*lambda+1
			# centered around i
			set goon false
			for {set k 1} {$k<=$lambda} {incr k} {
				if {([lindex $v $i] <= [lindex $v [expr {$i-$k}]]) ||
					([lindex $v $i] <= [lindex $v [expr {$i+$k}]])} {
					set goon true
					break
				}
			}
			if {$goon} { continue }
			set val [lindex $v $i]
			lappend maxima $i
		}
		return $maxima
	}

	proc ampd_min {v} {
		set N [llength $v]
		# find maximum of gamma
		set lambda 1
		set gmax 0
		for {set k 1} {$k<$N/2-1} {incr k} {
			set gamma 0
			for {set i $k} {$i<$N-$k} {incr i} {
				# negative copmarisons are needed to properly deal with NaN
				incr gamma [expr {!([lindex $v $i] >= [lindex $v [expr {$i-$k}]]) &&
					!([lindex $v $i] >= [lindex $v [expr {$i+$k}]])}]
			}
			
			if {$gamma > $gmax} {
				set gmax $gamma
				set lambda $k
			}
		}

		# now find minima for all levels up to k<=lambda
		set minima {}
		for {set i $lambda} {$i<$N-$lambda} {incr i} {
			# find total maximum in the window of size 2*lambda+1
			# centered around i
			set goon false
			for {set k 1} {$k<=$lambda} {incr k} {
				if {([lindex $v $i] >= [lindex $v [expr {$i-$k}]]) ||
					([lindex $v $i] >= [lindex $v [expr {$i+$k}]])} {
					set goon true
					break
				}
			}
			if {$goon} { continue }
			set val [lindex $v $i]
			lappend minima $i
		}
		return $minima
	}


	proc FindPeaks {} {
		# run the peak detector on the currently displayed list
		set output ""
		set plotids [$BessyHDFViewer::w(Graph) getdatasetids]
		foreach id $plotids {
			# filter NaNs from the dataset
			set data [$BessyHDFViewer::w(Graph) getdata $id data]
			set title [$BessyHDFViewer::w(Graph) getdata $id title]
			# filter NaNs from the dataset
			set fdata {}
			foreach {x y} $data {
				if {isnan($x) || isnan($y)} { continue }
				lappend fdata $x $y
			}
			set fdata [lsort -stride 2 -real -uniq $fdata]
			# now rip off the y-values only
			set vlist {}
			foreach {x y} $fdata { lappend vlist $y }
			# compute minima / maxima
			set minima [ampd_min $vlist]
			set maxima [ampd_max $vlist]
			# generate output
			lappend output "# $title"
			lappend output "# Minima:"
			set minimaxy {}
			foreach idx $minima {
				set x [lindex $fdata [expr {2*$idx}]]
				set y [lindex $fdata [expr {2*$idx+1}]]
				lappend output "[format %.15g $x] [format %.15g $y]"
				lappend minimaxy $x $y
			}
			
			lappend output "# Maxima:"
			set maximaxy {}
			foreach idx $maxima {
				set x [lindex $fdata [expr {2*$idx}]]
				set y [lindex $fdata [expr {2*$idx+1}]]
				lappend output "[format %.15g $x] [format %.15g $y]"
				lappend maximaxy $x $y
			}

			$BessyHDFViewer::w(Graph) plot $minimaxy with points color green pt filled-hexagons
			$BessyHDFViewer::w(Graph) plot $maximaxy with points color red pt filled-hexagons

		}

		TextDisplay Show [join $output \n]
	}
	
	proc FindCenter {{thresh 0.5}} {
		# simplistic peak & center detector as in measurement program
		set output ""
		set plotids [$BessyHDFViewer::w(Graph) getdatasetids]
		foreach id $plotids {
			# filter NaNs from the dataset
			set data [$BessyHDFViewer::w(Graph) getdata $id data]
			set title [$BessyHDFViewer::w(Graph) getdata $id title]
			# filter NaNs from the dataset
			set fdata {}
			foreach {x y} $data {
				if {isnan($x) || isnan($y)} { continue }
				lappend fdata $x $y
			}
			set fdata [lsort -stride 2 -real -uniq $fdata]

			if {[llength $fdata] < 3} { continue }

			# compute min/max position 
			set maxx 0; set maxy -Inf; set miny +Inf; set ind 0
			foreach {x y} $fdata {
				if {$y > $maxy} { 
					set maxy $y
					set maxx $x
					set maxi $ind
				}
				if {$y < $miny} {
					set miny $y
				}
				incr ind
			}
			
			set indmax $ind

			# go from max position to the left and right
			# until we hit the threshold
			set rightx {}
			set leftx {}
			set ythresh [expr {$miny*$thresh + $maxy*(1.0-$thresh)}]
			set xold $maxx; set yold $maxy

			for {set ind $maxi} {$ind < $indmax} {incr ind 1} {
				set xcur [lindex $fdata [expr {2*$ind}]]
				set ycur [lindex $fdata [expr {2*$ind+1}]]
				if {$ycur < $ythresh} {
					# interpolate for position 
					set rightx [expr {$xold + ($xcur-$xold)*double($ythresh-$yold)/double($ycur-$yold)}]
					break
				}
				set xold $xcur
				set yold $ycur
			}
			
			set xold $maxx; set yold $maxy
			for {set ind $maxi} {$ind >= 0} {incr ind -1} {
				set xcur [lindex $fdata [expr {2*$ind}]]
				set ycur [lindex $fdata [expr {2*$ind+1}]]
				if {$ycur < $ythresh} {
					# interpolate for position 
					set leftx [expr {$xold + ($xcur-$xold)*double($ythresh-$yold)/double($ycur-$yold)}]
					break
				}
				set xold $xcur
				set yold $ycur
			}

			if {$leftx != {} && $rightx != {}} {
				set width [expr {$rightx-$leftx}]
				set cx [expr {($leftx+$rightx)/2}]
			}

			# generate output
			lappend output "# $title"
			lappend output "# Peak:"
			lappend output "[format %.15g $maxx] [format %.15g $maxy]"
			if {$leftx != {} && $rightx != {}} {
				lappend output "# Center:"
				lappend output "[format %.15g $cx]"
				lappend output "# Width:"
				lappend output "[format %.15g $width]"
			}

			lappend output "# Bounds:"
			lappend output "$leftx $rightx"
			
			# visualize
			$BessyHDFViewer::w(Graph) plot [list -Inf $ythresh +Inf $ythresh] with lines color black dash -

			if {$leftx != {}} {
				$BessyHDFViewer::w(Graph) plot [list $leftx -Inf $leftx +Inf] with lines color black dash .
			}

			if {$rightx != {}} {
				$BessyHDFViewer::w(Graph) plot [list $rightx -Inf $rightx +Inf] with lines color black dash .
			}

			if {$leftx != {} && $rightx != {}} {
				$BessyHDFViewer::w(Graph) plot [list $cx -Inf $cx +Inf] with lines color black dash -
			}

			$BessyHDFViewer::w(Graph) plot [list $maxx $maxy] with points color red pt filled-hexagons

		}

		TextDisplay Show [join $output \n]
	}

	proc derive {data} {
		# compute unregularized finite differences
		# for x y data
		set result {}
		set data [lassign $data xold yold]
		foreach {x y} $data {
			# prepare for signalling NaNs
			if {![catch {
				set xm [expr {($x+$xold)/2.0}]
				set xd [expr {($x-$xold)/2.0}]
				set yd [expr {($y-$yold)/2.0}]
				set deriv [expr {$yd/$xd}]
			}]} {
				lappend result $xm $deriv
			}
			set xold $x
			set yold $y
		}
		return $result
	}

	proc ShowDerivative {} {
		$BessyHDFViewer::w(Graph) set auto y

		set plotids [$BessyHDFViewer::w(Graph) getdatasetids]
		foreach id $plotids {
			# filter NaNs from the dataset
			set data [$BessyHDFViewer::w(Graph) getdata $id data]
			set fdata {}
			foreach {x y} $data {
				if {isnan($x) || isnan($y)} { continue }
				lappend fdata $x $y
			}
			set fdata [lsort -stride 2 -real -uniq $fdata]
			set deriv [derive $fdata]
			if {[llength $deriv]<2} { 
				# no derivative - delete this dataset
				$BessyHDFViewer::w(Graph) remove $id
			} else {
				# replace this dataset by it's derivative
				$BessyHDFViewer::w(Graph) update $id data $deriv
			}
		}
		# replace y axis title
		$BessyHDFViewer::w(Graph) set ylabel "d/dx ([$BessyHDFViewer::w(Graph) cget -ylabel])"
	}

	proc mkspline {data} {
		set sdata [lsort -stride 2 -real -uniq $data]
		# repack this into a list of lists
		set spline {}
		foreach {x y} $sdata {
			lappend spline [list $x $y]
		}
		return $spline
	}

	proc evalspline {spline xval} {
		# locate position
		set index [lsearch -bisect -real -index 0 $spline $xval]
		if {$index == -1} { 
			# left of 1st point
			return [lindex $spline 0 1]
		}
		
		if {$index == [llength $spline]-1} { 
			# right of last point
			return [lindex $spline end 1]
		}

		# we are in between index and index+1
		lassign [lindex $spline $index] x0 y0
		lassign [lindex $spline $index+1] x1 y1

		# compute linear interpolation
		expr {$y0+double($y1-$y0)*double($xval-$x0)/double($x1-$x0)}
	}

	proc RefDivide {} {
		# divide all datasets by the first one
		# shorten if necessary
		set plotids [$BessyHDFViewer::w(Graph) getdatasetids]
		if {[llength $plotids] < 2} {
			return -code error "Need at least two datasets"
		}

		set start true

		foreach id $plotids {
			# filter NaNs from the dataset
			set data [$BessyHDFViewer::w(Graph) getdata $id data]
			set title [$BessyHDFViewer::w(Graph) getdata $id title]
			set fdata {}
			foreach {x y} $data {
				if {isnan($x) || isnan($y)} { continue }
				lappend fdata $x $y
			}
			
			if {$start} {
				set refdata [mkspline $fdata]
				set rtitle $title
				$BessyHDFViewer::w(Graph) remove $id
				set start false
			} else {
				set divdata {}
				foreach {x y} $fdata {
					set rval [evalspline $refdata $x]
					lappend divdata $x [expr {$y/$rval}]
				}
				$BessyHDFViewer::w(Graph) update $id data $divdata title "$title / $rtitle"
			}
		}
	}

	snit::widget TextDisplay {
		hulltype toplevel
		component text
		component vsb
		component hsb

		option -text -default {}
		
		typevariable instc 0

		typemethod Show {msg args} {
			set name .textdisplay_$instc
			incr instc
			TextDisplay $name -text $msg {*}$args
		}


		constructor {args} {
			$self configurelist $args
			install text using text $win.text \
				-xscrollcommand [list $win.hsb set] \
				-yscrollcommand [list $win.vsb set]

			install hsb using ttk::scrollbar $win.hsb -orient horizontal -command [list $text xview]
			install vsb using ttk::scrollbar $win.vsb -orient vertical -command [list $text yview]

			grid $text $vsb -sticky nsew
			grid $hsb  -    -sticky nsew
			
			grid rowconfigure $win 0 -weight 1
			grid columnconfigure $win 0 -weight 1

			$text insert 1.0 $options(-text)
		}
	}
		
}
