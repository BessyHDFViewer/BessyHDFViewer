#   dataevaluation.tcl
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

package require SmallUtils
namespace eval DataEvaluation {
	# built-in methods for general data evaluation
	variable ns [namespace current]
	# list of available commands, to be evaluated by the main program
	# function, icon, description

	set commands {
		FindPeaks	peakdetect	"Find peaks by Scholkmann's method"
		FindCenter	peakcenter	"Compute peak and center like measurement program"
		ShowDerivative derivative "Compute derivative"
		RefDivide  refdivide "Divide by first dataset"
		SaveData   document-save-as "Save plot as ASCII data"
		SavePDF    save-pdf  "Save plot as PDF"
		XRR-FFT	   xrr       "Perform FFT evaluation of XRR data"
		ArdeViewer	ardeviewer       "Show referenced TIFF in external viewer"
		ArdeViewerHDF	ardeviewer-hdf       "open selected HDF in external viewer"
		OpenSpectrum	spectrumviewer	"Display embedded spectra"
	}

	variable plugindirs {}
	
	variable commandbuttons {}
	proc maketoolbar {f} {
		# pack the toolbuttons into f
		variable commands
		variable commandbuttons
		variable ns
		variable toolframe $f
		
		variable cmdnr 0
		foreach {cmd icon description} $DataEvaluation::commands {
			set btn [optionbutton $f.cmdbtn$cmdnr -text $description -image [BessyHDFViewer::IconGet $icon] \
			         -command ${ns}::$cmd]
			grid $btn -row 0 -column $cmdnr -sticky nw
			tooltip::tooltip $btn $description
			dict set commandbuttons $cmd $btn
			incr cmdnr
		}

		# read extra commands from the plugin dir
		variable extracmds {}

		variable plugindir [file join $::BessyHDFViewer::profiledir plugins]
		variable nplugin 0
		set pdirs [glob -nocomplain -type d $plugindir/*]

		foreach pdir $pdirs {
			LoadPluginFromDir $pdir
		}
		
		# hard-coded popup menu for RefDivide
		variable refdivbtn [dict get $commandbuttons RefDivide] 
		$refdivbtn configure -optcallback [list ${ns}::RefDivide list]
	}

	proc LoadPluginFromDir {pdir} {
		variable ns
		variable nplugin
		variable toolframe
		variable cmdnr
		variable extracmds
		variable plugindirs

		incr nplugin
		set pns plugin$nplugin
		set pmainfile [file join $pdir/pluginmain.tcl]
		set pbutfile [file join $pdir/button.tcl]
		BessyHDFViewer::AddIconDir $pdir/icons

		namespace eval $pns [list set PluginHome $pdir]
		namespace eval $pns [list namespace path $ns]
		if {[file exists $pmainfile]} {
			if {[catch {
				namespace eval $pns [list source $pmainfile]
			} err errdict]} {
				tk_messageBox -title "Error reading $pmainfile" -message [dict get $errdict -errorstack]
			}
		}

		if {[file exists $pbutfile]} {
			if {[catch {SmallUtils::script2dict [fileutil::cat $pbutfile]} btndict errdict]} {
				tk_messageBox -title "Error reading $pbutfile" -message [dict get $errdict -errorstack]
			}
		

			dict set extracmds $pns $btndict

			if {![dict exists $btndict shortname]} {
				puts stderr "No shortname for user command $btndict"
				return
			}

			if {![dict exists $btndict eval]} {
				puts stderr "No eval for user command $btndict"
				return
			}
			
			set shortname [dict get $btndict shortname]
			set cmd [dict get $btndict eval]
			set icon [SmallUtils::dict_getdefault $btndict icon ""]
			set description [SmallUtils::dict_getdefault $btndict description ""]
			
			set btn [ttk::button $toolframe.pluginbtn$nplugin -text $shortname -image [BessyHDFViewer::IconGet $icon] \
					 -command [list ${ns}::RunUserCmd $pns] -style Toolbutton]
			grid $btn -row 0 -column $cmdnr -sticky nw
			incr cmdnr

			dict set extracmds $pns button $btn
			
			if {$description ne {}} {
				tooltip::tooltip $btn $description
			}

			lappend plugindirs $pdir
		} else {
			puts stderr "WARNING: No button definition found in plugin dir $pdir"
		}
	}


	# peak-locating using the AMPD method
	# Algorithms 2012, 5(4), 588-603; doi:10.3390/a5040588
	#
	# NOTE: Scholkmann's algorithm description is a bit confusing
	# using random numbers and standard deviations
	# This implementation tries to follow the original idea,
	# but in a deterministic way 
	#
	# Minima and maxima are determined from a common lambda
	# to ensure that they alternate
	# Finally, the peak centres are computed from the FWHM (as in FindCenter)
	proc ampd_minmax {v} {
		set N [llength $v]
		# find maximum of gamma for minima and maxima
		#
		set lambda_min 1
		set lambda_max 1
		set gmax 0
		set gmin 0
		for {set k 1} {$k<$N/2-1} {incr k} {
			set gamma_min 0
			set gamma_max 0
			for {set i $k} {$i<$N-$k} {incr i} {
				# negative copmarisons are needed to properly deal with NaN
				# Minima
				incr gamma_min [expr {!([lindex $v $i] >= [lindex $v [expr {$i-$k}]]) &&
					!([lindex $v $i] >= [lindex $v [expr {$i+$k}]])}]
				# Maxima
				incr gamma_max [expr {!([lindex $v $i] <= [lindex $v [expr {$i-$k}]]) &&
					!([lindex $v $i] <= [lindex $v [expr {$i+$k}]])}]
			}
			
			if {$gamma_max > $gmax} {
				set gmax $gamma_max
				set lambda_max $k
			}

			if {$gamma_min > $gmin} {
				set gmin $gamma_min
				set lambda_min $k
			}
		}
		 
		# Use the larger lambda of both maxima and minima
		# i.e. detect "less" peaks
		puts "min: $lambda_min, $gmin  max: $lambda_max, $gmax"
		set lambda [expr {max($lambda_min, $lambda_max)}]
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


		return [list $minima $maxima]
	}

	
	proc xyindex {fdata idx} {
		set x [lindex $fdata [expr {2*$idx}]]
		set y [lindex $fdata [expr {2*$idx+1}]]
		list $x $y
	}
	
	proc argmin {list} {
		lsearch -real $list [tcl::mathfunc::min {*}$list]
	}

	proc argmax {list} {
		lsearch -real $list [tcl::mathfunc::max {*}$list]
	}

	proc bracket {idxlist idx} {
		# find two indices in idxlist
		# such that ind1<idx<ind2
		# idxlist is assumed to be sorted 
		# and bracketing idx
		foreach curridx $idxlist {
			if {$curridx > $idx} {
				return [list $previdx $curridx]
			}
			set previdx $curridx
		}
		return -code error "$idx not bracketed in list $idxlist" 
	}

	proc centerpeaks {fdata ylist minima maxima} {
		# augmin and augmax are lists
		# with an artificial min/max appended
		# such that every real minimum is enclosed by two max
		# and vice versa

		lassign $minima firstmin
		lassign $maxima firstmax
		set lastmin [lindex $minima end]
		set lastmax [lindex $maxima end]

		if {$firstmin ne {} && ($firstmin < $firstmax || $firstmax eq {})} {
			set augmax [argmax [lrange $ylist 0 $firstmin]]
		}

		if {$firstmax ne {} && ($firstmax < $firstmin || $firstmin eq {})} {
			set augmin [argmin [lrange $ylist 0 $firstmax]]
		}

		lappend augmax {*}$maxima
		lappend augmin {*}$minima

		if {$lastmin ne {} && ($lastmin > $lastmax || $lastmax eq {})} {
			set pos [argmax [lrange $ylist $lastmin end]]
			lappend augmax [expr {$pos+$lastmin}]
		}

		if {$lastmax ne {} && ($lastmax > $lastmin || $lastmin eq {})} {
			set pos [argmin [lrange $ylist $lastmax end]]
			lappend augmin [expr {$pos+$lastmax}]
		}

		set cminima [lmap {minidx} $minima {
			lassign [bracket $augmax $minidx] max1 max2
			centermin $fdata $max1 $minidx $max2 
		}]

		set cmaxima [lmap {maxidx} $maxima {
			lassign [bracket $augmin $maxidx] min1 min2
			centermax $fdata $min1 $maxidx $min2 
		}]

		list $cminima $cmaxima
	}
	
	proc centermin {fdata idx1 idx2 idx3} {
		# 
		#puts "$idx1 $idx2 $idx3"
		lassign [xyindex $fdata $idx1] x1 y1
		lassign [xyindex $fdata $idx2] x2 y2
		lassign [xyindex $fdata $idx3] x3 y3	
		#puts "($x1,$y1) ($x2,$y2) ($x3,$y3)"
		# go from min position to the left and right
		# until we hit the threshold
		set rightx {}
		set leftx {}

		set thresh 0.5
		# ythresh is 50% (or thresh) above the minimum in y, 
		# but not lower than either end of the bracket y1 and y3
		set ythresh [expr {min($y1,$y3,max($y1,$y3)*$thresh + $y2*(1.0-$thresh))}]
		set xold $x2; set yold $y2
		
		if {$ythresh <= $y2} { return -code continue }

		# go right
		for {set ind $idx2} {$ind <= $idx3} {incr ind 1} {
			lassign [xyindex $fdata $ind] xcur ycur
			if {$ycur >= $ythresh} {
				# interpolate for position 
				#puts "ythresh=$ythresh (xcur,ycur)=($xcur,$ycur) yold=($xold,$yold) ind=$ind" 
				set rightx [expr {$xold + ($xcur-$xold)*double($ythresh-$yold)/double($ycur-$yold)}]
				break
			}
			set xold $xcur
			set yold $ycur
		}
		
		# go left
		set xold $x2; set yold $y2
		for {set ind $idx2} {$ind >= 0} {incr ind -1} {
			lassign [xyindex $fdata $ind] xcur ycur
			if {$ycur >= $ythresh} {
				# interpolate for position 
				set leftx [expr {$xold + ($xcur-$xold)*double($ythresh-$yold)/double($ycur-$yold)}]
				break
			}
			set xold $xcur
			set yold $ycur
		}

		set width [expr {$rightx-$leftx}]
		set cx [expr {($leftx+$rightx)/2}]

		return [list $x2 $y2 $cx $width]
	}


	proc centermax {fdata idx1 idx2 idx3} {
		# 
		#puts "$idx1 $idx2 $idx3"
		lassign [xyindex $fdata $idx1] x1 y1
		lassign [xyindex $fdata $idx2] x2 y2
		lassign [xyindex $fdata $idx3] x3 y3	
		#puts "($x1,$y1) ($x2,$y2) ($x3,$y3)"
		# go from max position to the left and right
		# until we hit the threshold
		set rightx {}
		set leftx {}

		set thresh 0.5
		# ythresh is 50% (or thresh) above the minimum in y, 
		# but not lower than either end of the bracket y1 and y3
		set ythresh [expr {max($y1,$y3,min($y1,$y3)*$thresh + $y2*(1.0-$thresh))}]
		set xold $x2; set yold $y2


		if {$ythresh >= $y2} { return -code continue }
		
		# go right
		for {set ind $idx2} {$ind <= $idx3} {incr ind 1} {
			lassign [xyindex $fdata $ind] xcur ycur
			if {$ycur <= $ythresh} {
				# interpolate for position 
				#puts "ythresh=$ythresh (xcur,ycur)=($xcur,$ycur) yold=($xold,$yold) ind=$ind" 
				set rightx [expr {$xold + ($xcur-$xold)*double($ythresh-$yold)/double($ycur-$yold)}]
				break
			}
			set xold $xcur
			set yold $ycur
		}
		
		# go left
		set xold $x2; set yold $y2
		for {set ind $idx2} {$ind >= 0} {incr ind -1} {
			lassign [xyindex $fdata $ind] xcur ycur
			if {$ycur <= $ythresh} {
				# interpolate for position 
				set leftx [expr {$xold + ($xcur-$xold)*double($ythresh-$yold)/double($ycur-$yold)}]
				break
			}
			set xold $xcur
			set yold $ycur
		}

		set width [expr {$rightx-$leftx}]
		set cx [expr {($leftx+$rightx)/2}]

		return [list $x2 $y2 $cx $width]
	}

	proc FindPeaks {} {
		# run the peak detector on the currently displayed list
		set output ""
		set plotids [$BessyHDFViewer::w(Graph) getdatasetids]
		lassign [$BessyHDFViewer::w(Graph) cget -xrange] xmin xmax
		if {$xmin eq "*"} { set xmin -Inf }
		if {$xmax eq "*"} { set xmax +Inf }
		foreach id $plotids {
			# filter NaNs from the dataset
			set data [$BessyHDFViewer::w(Graph) getdata $id data]
			set title [$BessyHDFViewer::w(Graph) getdata $id title]
			# filter NaNs from the dataset
			set fdata {}
			foreach {x y} $data {
				if {isnan($x) || isnan($y)} { continue }
				if {$x<$xmin || $x>$xmax } { continue }
				lappend fdata $x $y
			}
			set fdata [lsort -stride 2 -real -uniq $fdata]
			# now take out the y-values only
			set ylist [lmap {x y} $fdata {set y}]
			# compute minima / maxima
			lassign [ampd_minmax $ylist] minima maxima
			lassign [centerpeaks $fdata $ylist $minima $maxima] cminima cmaxima
			# generate output
			lappend output "# $title"
			lappend output "# Minima:"
			set minimaxy {}
			foreach idx $minima centre $cminima {
				lassign [xyindex $fdata $idx] x y
				lappend output [join [lmap c $centre {format %15.6g $c}] " "]
				lappend minimaxy $x $y
			}
			# output list for copying with two fixed decimal places
			foreach centre $cminima {
				lappend output [format "%.2f" [lindex $centre 2]]
			}
			
			lappend output "# Maxima:"
			set maximaxy {}
			foreach idx $maxima centre $cmaxima {
				lassign [xyindex $fdata $idx] x y
				lappend output [join [lmap c $centre {format %15.6g $c}] " "]

				lappend maximaxy $x $y
			}

			# output list for copying with two fixed decimal places
			foreach centre $cmaxima {
				lappend output [format "%.2f" [lindex $centre 2]]
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
		lassign [$BessyHDFViewer::w(Graph) cget -xrange] xmin xmax
		if {$xmin eq "*"} { set xmin -Inf }
		if {$xmax eq "*"} { set xmax +Inf }
		foreach id $plotids {
			# filter NaNs from the dataset
			set data [$BessyHDFViewer::w(Graph) getdata $id data]
			set title [$BessyHDFViewer::w(Graph) getdata $id title]
			# filter NaNs from the dataset
			set fdata {}
			foreach {x y} $data {
				if {isnan($x) || isnan($y)} { continue }
				if {$x<$xmin || $x>$xmax } { continue }
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
			lappend output "[format %.6g $maxx] [format %.6g $maxy]"
			if {$leftx != {} && $rightx != {}} {
				lappend output "# Center:"
				lappend output "[format %.7g $cx]"
				lappend output "# Width:"
				lappend output "[format %.7g $width]"
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

	variable refindex 0
	variable saveddata

	proc RefDivide {{index {}}} {
		variable refindex
		variable saveddata
		variable refdivbtn
		# divide all datasets by the first one
		# shorten if necessary

	
		# check if there was a previous division
		if {$BessyHDFViewer::RePlotFlag} {
			# first call - retrieve data
			set refindex 0
			set plotids [$BessyHDFViewer::w(Graph) getdatasetids]

			if {[llength $plotids] < 2} {
				return -code error "Need at least two datasets"
			}
		
			set saveddata {}
			foreach id $plotids {
				# filter NaNs from the dataset
				set data [$BessyHDFViewer::w(Graph) getdata $id data]
				set title [$BessyHDFViewer::w(Graph) getdata $id title]
				set style [$BessyHDFViewer::w(Graph) getstyle $id]
				set fdata {}
				foreach {x y} $data {
					if {isnan($x) || isnan($y)} { continue }
					lappend fdata $x $y
				}
				lappend saveddata [dict create data $fdata title $title plotstyle $style]
			}
		} else {
			# 2nd call - use the saved datasets
			incr refindex
			if {$refindex >= [llength $saveddata]} {
				set refindex 0
			}
			puts "Take next index: $refindex"
		}
		
		if {$index eq "list"} {
			# only retrieve the list of options
			set titles [lmap x $saveddata {dict get $x title}]
			$refdivbtn configure -values $titles -headline "Select reference data"
			return
		}

		if {$index ne ""} {
			set refindex $index
		}
		
		set refdset [lindex $saveddata $refindex]
		set refdata [mkspline [dict get $refdset data]]
		set rtitle  [dict get $refdset title]
		
		$BessyHDFViewer::w(Graph) clear
		
		set i 0
		foreach dset $saveddata {
		
			# skip the refdata itself
			if {$i == $refindex} { incr i; continue }
			incr i

			set plotstyle [dict get $dset plotstyle]
			set fdata [dict get $dset data]
			set title [dict get $dset title]
			
			set divdata {}
			foreach {x y} $fdata {
				set rval [evalspline $refdata $x]
				if {![catch {expr {$y/$rval}} val]} {
					lappend divdata $x $val
				}
			}
			$BessyHDFViewer::w(Graph) plot $divdata {*}$plotstyle title "$title / $rtitle"
		}
		set BessyHDFViewer::RePlotFlag false
	}

	proc XRR-FFT {} {
		package require math::fourier

		# extract plot info from file, with energy and file attached
		set rawdata [BessyHDFViewer::SELECT \
			[list Energy HDF $BessyHDFViewer::xformat(0) $BessyHDFViewer::yformat(0)] \
			$BessyHDFViewer::HDFFiles -allnan true]

		lassign [$BessyHDFViewer::w(Graph) cget -xrange] thetamin thetamax
		if {$thetamin eq "*"} { set thetamin -Inf }
		if {$thetamax eq "*"} { set thetamax +Inf }

		$BessyHDFViewer::w(Graph) clear
		$BessyHDFViewer::w(Graph) set auto x
		$BessyHDFViewer::w(Graph) set auto y

		
		# split data into chunks with equal energy and file
		set splitdata {}
		set dataset {}
		lassign [lindex $rawdata 0] Energy_old HDF_old
		lappend rawdata {0 {} {} {}} ;# dummy dataset to force spilling the list
		foreach line $rawdata {
			lassign $line Energy HDF theta R
			if {isnan($Energy)} { continue }
			if {isnan($Energy_old)} { set Energy_old $Energy }
			if {abs($Energy - $Energy_old) > 0.1 || $HDF != $HDF_old} {
				# switch to different dataset
				set data {}
				dict set data data $splitdata
				dict set data energy $Energy_old
				dict set data HDF $HDF_old
				lappend dataset $data
				set splitdata {}
				set Energy_old $Energy 
				set HDF_old $HDF
			}
			if {$theta >= $thetamin && $theta <= $thetamax} {
				if {isnan($R)} { set R 0.0 }
				lappend splitdata $theta $R
			}
		}

	
		set pi 3.1415926535897932
		set plotstyles [BessyHDFViewer::PreferenceGet PlotStyles { {linespoints color black pt circle } }]

		foreach data $dataset style $plotstyles {
			if {$data == {}} { break }

			set energy [dict get $data energy]
			set xrrdata [dict get $data data]
			if {[llength $xrrdata] < 4} { continue }

			# compute wavelength
			set lambda [expr {1.9864455e-25/($energy*1.6021765e-19)*1e9}] ;# nm
			
			# compute theta step
			set xrrdata [lsort -real -stride 2 $xrrdata]
			set thetastep [expr {([lindex $xrrdata end-1]-[lindex $xrrdata 0])/([llength $xrrdata]/2)*2*$pi/180.0}]
			
			set xstep [expr {$lambda/$thetastep}]

			# compute normalized/windowed data
			# normalize by theta^4 (asymptote of Fresnel reflectivity)
			set ndata {}
			foreach {theta R} $xrrdata {
				lappend ndata [expr {$R*$theta**4}]
			}

			set L [llength $ndata]
			set wdata {}
			set ind 0
			foreach R $ndata {
				# lappend wdata [expr {$ind*$qbins}] [expr {$R*(0.5-0.5*cos(2*$pi/($L-1)*($ind-$L)))}]
				lappend wdata [expr {$R*(0.5-0.5*cos(2*$pi/($L-1)*($ind-$L)))}]
				incr ind
			}
			# $BessyHDFViewer::w(Graph) update $id data $wdata title "$title fresneled windowed"

			# compute padded length 2^n with at least 4X more data points

			set pL [expr {2**(int(ceil(log($L)/log(2)))+2)}]
			# puts "Length: $pL [llength $wdata]"

			lappend wdata {*}[lrepeat [expr {$pL-$L}] 0.0]
			# puts "Length: $pL [llength $wdata]"
			# compute FFT 
			set ftdata [math::fourier::dft $wdata]
			
			# compute nm binning
			# and cut off everything before the first rise
			set ind 0
			set oldpsd Inf
			set skip true
			set result {}
			foreach c $ftdata {
				lassign $c re im
				set psd [expr {$re**2+$im**2}]
				if {$psd > $oldpsd} { set skip false }

				if {!$skip} {
					lappend result [expr {$ind*$xstep/$pL}] $psd
				}
				
				set oldpsd $psd
				incr ind
				if {($ind > $pL/2)} { break }
				# break at Nyquist
			}

			# compute abbreviated title 
			set HDF [file tail [dict get $data HDF]]
			
			set title "XRR-FFT $HDF [format %.1feV $energy]"
			$BessyHDFViewer::w(Graph) plot $result title $title with {*}$style
		}

		$BessyHDFViewer::w(Graph) set xlabel "Thickness (nm)"
		$BessyHDFViewer::w(Graph) set ylabel "PSD"
		$BessyHDFViewer::w(Graph) set key on
	}

	proc SaveData {} {
		# prompt for file name and save 
		# ASCII data of the plot
		set filename [tk_getSaveFile -filetypes { {{ASCII data files} {.dat}} {{All files} {*}}} \
			-defaultextension .dat \
			-title "Select ASCII file for export"]
		
		if {$filename eq ""} { return }

		set idx 0
		set output {}
		lappend output "# ASCII export from BessyHDFViewer"
		lappend output "# xlabel: [$BessyHDFViewer::w(Graph) cget -xlabel]"
		lappend output "# ylabel: [$BessyHDFViewer::w(Graph) cget -ylabel]"
		set plotids [$BessyHDFViewer::w(Graph) getdatasetids]
		foreach id $plotids {
			set data [$BessyHDFViewer::w(Graph) getdata $id data]
			set title [$BessyHDFViewer::w(Graph) getdata $id title]
			
			lappend output "# Dataset $idx"
			lappend output "# $title"
			lappend output "# [BessyHDFViewer::quotedjoin [list $BessyHDFViewer::xformat(0) $BessyHDFViewer::yformat(0)]]"
			foreach {x y} $data {
				lappend output "$x $y"
			}
			lappend output "" ""
			incr idx
		}

		set fd [open $filename w]
		puts $fd [join $output \n]
		close $fd
	}

	proc SavePDF {} {
		set filename [tk_getSaveFile -filetypes { {{PDF files} {.pdf}} {{All files} {*}}} \
			-defaultextension .pdf \
			-title "Select PDF file for export"]

		if {$filename eq ""} { return }

		$BessyHDFViewer::w(Graph) saveAsPDF $filename
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
			if {[winfo exists $name]} {
				$name AddText "\n\n$msg"
			} else {
				incr instc
				set name .textdisplay_$instc
				TextDisplay $name -text $msg {*}$args
			}
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

		method AddText {msg} {
			$text insert end $msg
			$text see end
			raise $win
		}
	}

	proc makeArdeViewer {} {
		# make sure ardeviewer is up
		set ardecmd [BessyHDFViewer::PreferenceGet ViewerCmd [list ardeviewer --slave]]
		if {[llength [info commands Viewer]]==0} { ardeviewer Viewer $ardecmd }
	}

	proc ArdeViewerHDF {} {
		if {[llength $BessyHDFViewer::HDFFiles] > 2} {
			error "Only a single HDF with images and an optional transmission can be loaded"
		}
		
		makeArdeViewer
		foreach fn $BessyHDFViewer::HDFFiles {
			set pyfn [pyquote $fn]
			set hdfdata [BessyHDFViewer::bessy_reshape $fn -shallow]
			set properties [BessyHDFViewer::bessy_class $hdfdata]
			set fileformat [dict get $hdfdata {} FileFormat]
			set plugin [SmallUtils::dict_getdefault {HDF4 HDF-SAXS HDF5 HDF5-SAXS} $fileformat {}]
			if {[dict get $properties class] in {SINGLE_IMG MULTIPLE_IMG}} {
				Viewer exec [format {self.plugins['%s'].openHDF(%s)} $plugin $pyfn] -wait
			} else {
				Viewer exec [format {self.plugins['%s'].load_hdf_trans(%s)} $plugin $pyfn] -wait
			}
		}
		Viewer configure -command {}
	}

	proc ArdeViewer {} {
		# run an instance of ardeviewer, if not yet started
		variable ns
		set pathrules [BessyHDFViewer::PreferenceGet ImageDetectorFilePathRules {}]
		
		# get currently displayed zoom area
		lassign [$BessyHDFViewer::w(Graph) cget -xrange] xmin xmax
		lassign [$BessyHDFViewer::w(Graph) cget -yrange] ymin ymax
		
		if {$xmin eq "*"} { set xmin -Inf }
		if {$xmax eq "*"} { set xmax +Inf }

		if {$ymin eq "*"} { set ymin -Inf }
		if {$ymax eq "*"} { set ymax +Inf }


		# create the correspondence map, only keep valid TIFF numbers
		set tifflist {}
		set ptnr 0
		variable viewdpmap {}
		foreach hdfpath $BessyHDFViewer::HDFFiles {

			# check for the first available axis from the format table
			set imgaxis {}
			dict for {axis fmtdef} $pathrules {
				set val [BessyHDFViewer::QueryCache $hdfpath $axis]
				if {[llength $val] != 0} {
					set imgaxis $axis
					break
				}
			}

			if {$imgaxis eq ""} { continue }

			BessyHDFViewer::dict_assign $fmtdef regex fmtstring exprlist

			set imgnum [BessyHDFViewer::SELECT [list $imgaxis $BessyHDFViewer::xformat(0) $BessyHDFViewer::yformat(0)] \
				[list $hdfpath] -allnan true]
			
			# decompose hdf file name according to regexp 
			set dir [file dirname $hdfpath]
			set hdfname [file rootname [file tail $hdfpath]]

			if {![regexp $regex $hdfname -> 1 2 3 4 5 6 7 8]} {
				puts "Warning: regex $regex does not match filename $hdfname"
				puts "File skipped"
				continue 
			}


			set dpnr -1
			foreach line $imgnum { 
				lassign $line img x y 
				incr dpnr

				# try to evaluate the list of expressions
				# skip non-parseable expressions
				if {[catch {
					set exprresult [lmap e $exprlist {expr $e}]
				}]} { 
					puts "Skipped image $img"
					continue 
				}

				# skip images that do not fit into the plot region
				# careful: NaN-safe comparison 
				if {!( ($x>=$xmin) && ($x<=$xmax) && ($y>=$ymin) && ($y<=$ymax))} {
					continue
				}

				lappend  tifflist [file join $dir [format $fmtstring {*}$exprresult]]
				
				dict set viewdpmap [list $hdfpath $dpnr] $ptnr
				incr ptnr
			}
		}

		if {[llength $tifflist] == 0} {
			tk_messageBox -title "Error" -message "No images found in this file"
			return
		}

		makeArdeViewer

		Viewer openlist $tifflist
		BessyHDFViewer::RegisterPickCallback ${ns}::ArdeViewerPick
		trace add command ${ns}::Viewer delete ${ns}::ArdeViewerClearPick
		Viewer configure -command ${ns}::ArdeViewerScroll
	}

	proc ArdeViewerPick {clickdata} {
		variable viewdpmap
		
		set dpnr [dict get $clickdata dpnr]
		set fn [dict get $clickdata fn]
		set key [list $fn $dpnr]

		if {[dict exists $viewdpmap $key]} {
			set idx [dict get $viewdpmap $key]
			Viewer goto $idx 
		}
	}

	proc ArdeViewerClearPick {args} {
		variable ns
		BessyHDFViewer::UnRegisterPickCallback ${ns}::ArdeViewerPick
		puts "Viewer callback stopped."
	}

	proc ArdeViewerScroll {idx} {
		variable viewdpmap
		set dp [lindex [dict keys $viewdpmap] $idx]
		if {$dp != {}} {
			lassign $dp hdf dpnr
			BessyHDFViewer::ClearHighlights
			BessyHDFViewer::HighlightDataPoint $hdf $dpnr pt circles color red lw 3 ps 1.5
		}
	}

	proc pyquote {s} {
		# quote a string suitable for Python
		return "\"[string map {"\"" "\\\"" "\\" "\\\\" "\n" "\\n"} $s]\""
	}

	proc pylist {l} {
		return "\[[join [lmap x $l {pyquote $x}] ,]\]"
	}

	snit::type ardeviewer {
		variable pipe
		option -command {}
		variable ready false
		
		constructor {path args} {
			$self configurelist $args
			set pipe [open |[list {*}$path 2>@1] w+]
			fconfigure $pipe -buffering line -blocking 0 -encoding utf-8
			fileevent $pipe readable [mymethod feedback]
		}

		destructor {
			close $pipe
		}

		method exec {cmd {wait -nowait}} {
			# puts "Sending command $pipe $cmd"
			puts $pipe $cmd
			if {$wait == "-wait"} {
				vwait [myvar ready]
			}
		}

		method openlist {flist} {
			# open a list of files in the instance
			$self exec "self.open_flist([pylist $flist])"

		}

		method feedback {} {
			set ready true
			set data [read $pipe]
			puts "VIEWER: $data"
			if {[eof $pipe]} {
				$self destroy
			}

			# parse data to see if it contains goto commands
			set idx {}
			foreach line [split $data \n] {
				if {[regexp {###\s+GOTO\s+(\d+)} $line -> nr]} {
					set idx $nr
				}
			}

			if {$idx != {}} { 
				set cmd $options(-command)
				if {$cmd != {}} { $cmd $idx }
			}
		}

		method goto {idx} {
			$self exec "self.goto_img($idx)"
			set cmd $options(-command)
			if {$cmd != {}} { $cmd $idx }
		}
	}

	proc OpenSpectrum {} {
		SpectrumViewer::Open
	}

	proc if_exists {var default} {
		upvar 1 $var v
		if {[info exists v]} { 
			return $v
		} else {
			return $default
		}
	}

	proc parseformula {formula} {
		if {[string first {$} $formula] >= 0} {
			puts "Formula"
			if {![regexp "\\$\{?(\[^/\]+)\}?/\\$\{?(\[^\}\]+)\}?$" $formula -> nom denom]} {
				set nom $formula
				set denom 1
			}
		} else {
			set nom $formula
			set denom 1
		}
		return [list $nom $denom]
	}

	proc ExecPython {PluginHome script args} {
		set scriptpath [file join $PluginHome $script]
		set interpreter [BessyHDFViewer::PreferenceGet PythonInterpreter python3]
		tailcall exec $interpreter $scriptpath {*}$args
	}

	proc RunUserCmd {pns} {
		variable ns
		variable extracmds
		set hdfs [if_exists ::BessyHDFViewer::HDFFiles ""]
		set hdf1 [lindex $hdfs 0]
		if {[catch {$BessyHDFViewer::w(Graph) cget -displayrange} result]} {
			puts "Graph error: $result"
			lassign {* * * *} xmin xmax ymin ymax
		} else {
			BessyHDFViewer::dict_assign $result xmin xmax ymin ymax
		}

		# parse the format of first plotting formula into nominator / denominator
		set xyformulae $BessyHDFViewer::xyformats
		lassign $xyformulae xformula yformula

		lassign [parseformula $xformula] xnom xdenom
		lassign [parseformula $yformula] ynom ydenom

		foreach var {xmin xmax ymin ymax hdfs hdf1 
					xformula yformula xyformulae
					xnom xdenom ynom ydenom} {
			set ${pns}::$var [set $var]
		}
		set cmd [dict get $extracmds $pns eval]

		# if there is a dialog, execute it first 
		if {[dict exists $extracmds $pns dialog]} {
			set dialog [dict get $extracmds $pns dialog]
			
			BHDFDialog .dialog -datastorens ${ns}::$pns \
				-hdfs $BessyHDFViewer::HDFFiles -shortname [dict get $extracmds $pns shortname]
			
			namespace eval $pns $dialog
			set answer [.dialog execute]
			if {$answer eq {}} {
				# dialog was cancelled
				return
			}
			set ${pns}::inputs $answer

			# set individual variables - easier access
			dict for {var val} $answer {
				set ${pns}::$var $val
			}
		}

		# add extra command "python"
		interp alias {} ${pns}::python {} ${ns}::ExecPython [set ${pns}::PluginHome]

		namespace eval $pns $cmd
	}
		
}
