namespace eval DataEvaluation {
	# built-in methods for general data evaluation
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
		puts [join $output \n]

		$BessyHDFViewer::w(Graph) showpoints $minimaxy green filled-hexagon
		$BessyHDFViewer::w(Graph) showpoints $maximaxy red filled-hexagon
	}
}
