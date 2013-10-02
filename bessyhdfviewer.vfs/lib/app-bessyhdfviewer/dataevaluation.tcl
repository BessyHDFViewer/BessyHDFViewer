namespace eval DataEvaluation {
	# built-in methods for general data evaluation

	# list of available commands, to be evaluated by the main program
	# function, icon, description

	set commands {
		FindPeaks	peakdetect	"Find peaks by Scholkmann's method"
		ShowDerivative derivative "Compute derivative"
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
		foreach {fn data} $BessyHDFViewer::datashown {
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
			lappend output "# $fn"
			lappend output "# Minima:"
			set minimaxy {}
			foreach idx $minima {
				set x [lindex $fdata [expr {2*$idx}]]
				set y [lindex $fdata [expr {2*$idx+1}]]
				lappend output "$x $y"
				lappend minimaxy $x $y
			}
			
			lappend output "# Maxima:"
			set maximaxy {}
			foreach idx $maxima {
				set x [lindex $fdata [expr {2*$idx}]]
				set y [lindex $fdata [expr {2*$idx+1}]]
				lappend output "$x $y"
				lappend maximaxy $x $y
			}

		}
		#puts [join $output \n]

		$BessyHDFViewer::w(Graph) plot $minimaxy with points color green pt filled-hexagons
		$BessyHDFViewer::w(Graph) plot $maximaxy with points color red pt filled-hexagons
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
		$BessyHDFViewer::w(Graph) clear
		$BessyHDFViewer::w(Graph) set auto y

		set plotid {}
		foreach {fn data} $BessyHDFViewer::datashown {
			# filter NaNs from the dataset
			set fdata {}
			foreach {x y} $data {
				if {isnan($x) || isnan($y)} { continue }
				lappend fdata $x $y
			}
			set fdata [lsort -stride 2 -real -uniq $fdata]
			set deriv [derive $fdata]
			if {[llength $deriv]<2} { continue }
			# plot derivative with the style used in the orginal data
			if {[catch {set style [dict get $BessyHDFViewer::plotstylecache $fn]}]} {
				# no style in the cache (?) - default to black with red points
				set style  {linespoints color black pt squares}
			}
			lappend plotid [$BessyHDFViewer::w(Graph) plot $deriv with {*}$style]
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
