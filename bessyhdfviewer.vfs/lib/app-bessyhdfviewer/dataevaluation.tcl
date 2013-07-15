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


	proc FindPeaks {minmax} {
		
	}
}
