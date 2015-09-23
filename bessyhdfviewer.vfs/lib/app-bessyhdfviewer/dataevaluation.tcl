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
	}

	# peak-locating using the AMPD method
	# Algorithms 2012, 5(4), 588-603; doi:10.3390/a5040588
	#
	# NOTE: Scholkmann's algorithm description is a bit confusing
	# using random numbers and standard deviations
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
					if {![catch {expr {$y/$rval}} val]} {
						lappend divdata $x $val
					}
				}
				$BessyHDFViewer::w(Graph) update $id data $divdata title "$title / $rtitle"
			}
		}
	}

	proc XRR-FFT {} {
		package require math::fourier

		# extract plot info from file, with energy and file attached
		set rawdata [BessyHDFViewer::SELECT \
			[list Energy HDF $BessyHDFViewer::xformat $BessyHDFViewer::yformat] \
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
			lappend output "# format x: $BessyHDFViewer::xformat"
			lappend output "# format x: $BessyHDFViewer::yformat"
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

	proc makeArdeViewer {} {
		# make sure ardeviewer is up
		set ardecmd [BessyHDFViewer::PreferenceGet ViewerCmd "ardeviewer --slave"]
		if {[llength [info commands Viewer]]==0} { ardeviewer Viewer $ardecmd }
	}

	proc ArdeViewerHDF {} {
		if {[llength $BessyHDFViewer::HDFFiles] != 1} {
			error "Only a single HDF can be loaded in the external viewer"
		}
		
		set fn [pyquote [lindex $BessyHDFViewer::HDFFiles 0]]
		
		makeArdeViewer
		Viewer exec [format {self.plugins['HDF-SAXS'].openHDF(%s)} $fn]
		Viewer configure -command {}
	}

	proc ArdeViewer {} {
		# run an instance of ardeviewer, if not yet started
		variable ns
		set tifffmt [BessyHDFViewer::PreferenceGet TiffFmt "pilatus_%s_%04d.tif"]

		# create the correspondence map, only keep valid TIFF numbers
		set tifflist {}
		set ptnr 0
		variable viewdpmap {}
		foreach hdfpath $BessyHDFViewer::HDFFiles {
			set tiffnum [BessyHDFViewer::SELECT Pilatus_Tiff \
				[list $hdfpath] -allnan true]

			set dpnr -1
			foreach tiff $tiffnum {
				incr dpnr
				# parse tiffnr into integer
				if {[catch {expr {int($tiff)}} tiffnr]} { continue }

				# decompose hdf file name into directory, prefix and number
				set hdfdir [file dirname $hdfpath]
				set hdfname [file rootname [file tail $hdfpath]]

				regexp {^(.*)_(.*)_(\d+)$} $hdfname -> fcm prefix num

				lappend  tifflist [file join $hdfdir [format $tifffmt $prefix $tiffnr]]
				
				dict set viewdpmap [list $hdfpath $dpnr] $ptnr
				incr ptnr
			}
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
		
		constructor {path args} {
			$self configurelist $args
			set pipe [open "| $path" w+]
			fconfigure $pipe -buffering line -blocking 0 -encoding utf-8
			fileevent $pipe readable [mymethod feedback]
		}

		destructor {
			close $pipe
		}

		method exec {cmd} {
			# puts "Sending command $cmd"
			puts $pipe $cmd
		}

		method openlist {flist} {
			# open a list of files in the instance
			$self exec "self.open_flist([pylist $flist])"

		}

		method feedback {} {
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
		
}
