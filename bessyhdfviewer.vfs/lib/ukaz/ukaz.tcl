package require snit
package require uevent
package provide ukaz 1.0

namespace eval ukaz {

	namespace eval geometry {

		proc polylineclip {cdata xmin_ xmax_ ymin_ ymax_} {

			variable xmin $xmin_
			variable xmax $xmax_
			variable ymin $ymin_
			variable ymax $ymax_

			if {$xmin > $xmax} { lassign [list $xmin $xmax] xmax xmin }
			if {$ymin > $ymax} { lassign [list $ymin $ymax] ymax ymin }

			set result {}
			set piece {}
			
			# clip infinity of first point
			set x1 Inf
			set y1 Inf
			while {[indefinite $x1 $y1]} {
				set cdata [lassign $cdata x1 y1]
				if {[llength $cdata]<2} {
					return {}
				}
			}
			
			foreach {x2 y2} $cdata {
				# clip total indefinite points
				if {[indefinite $x2 $y2]} {	
					# end last line
					if {$piece != {}} {
						lappend result $piece
					}
					set piece {}
					continue
				}

				lassign [cohensutherland $x1 $y1 $x2 $y2] clipline type 
				switch $type {
					rightclip {
						# second point was clipped
						if {$piece == {}} {
							# it is the first line segment
							# make single segment
							lappend result $clipline
						} else {
							lappend piece {*}[lrange $clipline 2 3]
							lappend result $piece 
							set piece {}
						}
					}

					leftclip {
						# first point was clipped, begin new line
						set piece $clipline
					}

					noclip {
						# append as given
						# if we are the first, include 1st point
						if {[llength $piece]==0} {
							set piece [list $x1 $y1]
						}
						lappend piece $x2 $y2
					}

					empty {
						# end last line
						if {$piece != {}} {
							lappend result $piece
						}
						set piece {}
					}

					bothclip {
						# create line on it's own
						
						# end last line
						if {$piece != {}} {
							lappend result $piece
						}
						set piece {}

						lappend result $clipline
					}

				}
				# advance
				set x1 $x2
				set y1 $y2
			}
			# end last line
			if {$piece != {}} {
				lappend result $piece
			}

			return $result
		}

		proc cohensutherland {x1 y1 x2 y2} {
			variable xmin
			variable xmax
			variable ymin
			variable ymax
			
			set codeleft [pointcode $x1 $y1]
			set coderight [pointcode $x2 $y2]
			if {($codeleft | $coderight) == 0} {
				return [list [list $x1 $y1 $x2 $y2] noclip]
			}

			if {($codeleft & $coderight) != 0} {
				return {{} empty}
			}

			# if we are here, one of the points must be clipped
			set left false
			set right false
			for {set iter 0} {$iter<20} {incr iter} {
				if {$codeleft != 0} {
					# left point is outside
					set left true
					lassign [intersect $x1 $y1 $x2 $y2] x1 y1
					set codeleft [pointcode $x1 $y1]
				} else {
					# right point outside
					set right true
					lassign [intersect $x2 $y2 $x1 $y1] x2 y2
					set coderight [pointcode $x2 $y2]
				}
			
				if {($codeleft & $coderight) != 0} {
					return {{} empty}
				}

				if {($codeleft | $coderight) == 0} {
					if {$left && $right} {
						return [list [list $x1 $y1 $x2 $y2] bothclip]
					}
					if {$left} {
						return [list [list $x1 $y1 $x2 $y2] leftclip]
					}
					if {$right} {
						return [list [list $x1 $y1 $x2 $y2] rightclip]
					}
					return "Can't happen $x1 $y1 $x2 $y2"
				}
			}
			return "Infinite loop $x1 $y1 $x2 $y2 "
		}


		proc pointcode {x y} {
			variable xmin
			variable xmax
			variable ymin
			variable ymax
			
			expr {(($x<$xmin)?1:0) | 
				  (($x>$xmax)?2:0) | 
				  (($y<$ymin)?4:0) | 
				  (($y>$ymax)?8:0) }
		}

		proc intersect {x1 y1 x2 y2} {
			variable xmin
			variable xmax
			variable ymin
			variable ymax
			
			# check for infinity
			if {$y1 == Inf} {
				return [list $x2 $ymax]
			}

			if {$y1 == -Inf} {
				return [list $x2 $ymin]
			}

			if {$x1 == Inf} {
				return [list $xmax $y2]
			}

			if {$x1 == -Inf} {
				return [list $xmin $y2]
			}
			
			if {$y1>$ymax} {
				return [list [expr {$x1+($x2-$x1)*($ymax-$y1)/($y2-$y1)}] $ymax]
			}

			if {$y1<$ymin} {
				return [list [expr {$x1+($x2-$x1)*($ymin-$y1)/($y2-$y1)}] $ymin]
			}

			if {$x1>$xmax} {
				return [list $xmax [expr {$y1+($y2-$y1)*($xmax-$x1)/($x2-$x1)}]]
			}

			return [list $xmin [expr {$y1+($y2-$y1)*($xmin-$x1)/($x2-$x1)}]]
		}

		proc indefinite {x y} {
			expr {abs($x) == Inf && abs($y) == Inf}
		}
	}

	snit::type box {

		variable can
		variable deskxmin
		variable deskxmax
		variable deskymin
		variable deskymax

		variable dimensioned 0

		variable logx 0
		variable logy 0
		variable grid 0

		variable xmin
		variable xmax
		variable ymin
		variable ymax
		variable xtics
		variable ytics

		variable xticmin
		variable xticmax
		variable yticmin
		variable yticmax

		variable xmul
		variable xadd
		variable ymul
		variable yadd

		variable xaxisformat %g
		variable yaxisformat %g

		variable defaultfont fixed
		variable axisfont
		variable ticklength 5
		variable lineheight
		variable pttagnr

		variable autosize
		variable zoomstack

		variable linedata {}
		variable pointdata {}

		# global counter datasetnr
		variable datasetnr 0

		# click handler
		variable pointclickhandler {}
		variable rightclickhandler {}

		option -font -default "" -configuremethod setoption
		option -xlabel -default ""
		option -ylabel -default ""

		variable zooming
		variable zoomstartpos
		
		constructor {canv args} {
			set can $canv
			set defaultfont [font create -family Helvetica -size -14]
			$self configure -font ""

			::bind $can <Destroy> [mymethod destroy]
			# Bindings for zooming
			::bind $can <ButtonPress-1> [mymethod zoomstart %x %y]
			::bind $can <Motion> [mymethod zoommove %x %y]
			::bind $can <ButtonRelease-1> [mymethod zoomend %x %y]
			if {[tk windowingsystem]=="aqua"} {
				set rb <Button-2>
			} else {
				set rb <Button-3>
			}
			::bind $can $rb [mymethod zoomout %x %y]
			switch [llength $args] {
				4 {
					lassign $args deskxmin deskymax deskxmax deskymin
					set autosize 0
				}

				0 { set xmin 0
					set xmax 1.0
					set ymin 0
					set ymax 1
					$self compute_autosize
					::bind $can <Configure> [mymethod autoresize]
					set autosize 1
					$can configure -highlightthickness 0
				}
				default {
					error "box <canvas> {xmin ymin xmax ymax}"
				}
			}

			set xmul 1
			set xadd 0
			set ymul 1
			set yadd 0

			set pttagnr 0

			set zooming false
			set zoomstack {}
		}

		destructor {
			if [winfo exists $can] {
				$self empty
				# delete all graphics from this box
				# we are destroyed because the canvas vanished
				# restore bindings
				::bind $can <Configure> {}
				::bind $can <Destroy> {}
			}
			uevent::generate $self Destroy
		}

		method setoption { name value } {
			set options($name) $value
			switch -- $name {
				-font {
					if { $value == "" } {
						set axisfont $defaultfont
					} else {
						set axisfont $value
					}
					set lineheight [font metrics $axisfont -linespace]
				}
			}
		}

		method getaxisfont {} {
			return $axisfont
		}

		method setgrid { flag } { set grid $flag }

		method setlog {how {what 1}} {
			switch $how {
				x {
					set logx $what
				}
				y {
					set logy $what
				}
				xy {
					set logx $what
					set logy $what
				}

				default {
					set logx 0
					set logy 0
				}
			}

		}

		method resize {x1 y1 x2 y2} {
			set deskxmin $x1
			set deskxmax $x2
			set deskymin $y2
			set deskymax $y1
		}

		method compute_autosize {} {
			set w [winfo width $can]
			set h [winfo height $can]
			set lwidth1 [font measure $axisfont [format $yaxisformat $ymin]]
			set lwidth2 [font measure $axisfont [format $yaxisformat $ymax]]
			set xmaxwidth [font measure $axisfont [format $xaxisformat $xmax]]

			set lwidth [expr {max($lwidth1,$lwidth2)}]
			set lascent [font metrics $axisfont -ascent]
			set ldescent [font metrics $axisfont -descent]

			set margin [expr {0.05*$w}]

			set deskxmin [expr {($lwidth+2*$ticklength)+$margin}]
			if { $options(-ylabel) != "" } { set deskxmin [expr {$deskxmin + 1.2 * $lineheight}] }
			set deskxmax [expr {$w-0.5*$xmaxwidth}]
			set deskymax [expr {max($ticklength,$lascent)+0.05*$margin}]
			set deskymin [expr {($h-$ticklength-$lineheight-$ldescent)-0.05*$margin}]
			if { $options(-xlabel) != "" } { set deskymin [expr {$deskymin - 1.2 * $lineheight}] }

			#puts "$w x $h, font $lascent $ldescent $lineheight $xmaxwidth"
			#puts "$xmaxwidth $lwidth1 $lwidth2"
			#puts "$deskxmax $deskxmin"
			#puts "$deskymax $deskymin"
			#puts "Plot area: $xmin, $xmax, $ymin, $ymax"
		}

		method autoresize {} {
			$self compute_autosize
			# Redraw
			if {$dimensioned} {
				$self dim_internal $xmin $xmax $ymin $ymax $xtics $ytics

				dict for {pt data} $pointdata {
					lassign $data coords color shape cid
					$self showpoints_nosave $coords $color $shape $cid
					#puts "$selfns: Redraw pointset $pt"
				}

				dict for {pt data} $linedata {
					lassign $data coords color extraargs cid
					$self connectpoints_nosave $coords $color $extraargs $cid
					#puts "$selfns: Redraw line $pt color $color coords $coords"
				}

			}
		}

		method getsize {} {
			list $deskxmin $deskymin $deskxmax $deskymax
		}

		method getdim {} {
			list $xmin $xmax $ymin $ymax
		}

		method getcanv {} {
			return $can
		}
		
		method dim {args} {
			set zoomstack [list $args]
			$self dim_internal {*}$args
		}

		method dim_internal {x1 x2 y1 y2 xt yt} {
			#puts "Dimensioning $x1 $x2 $y1 $y2 $xt $yt"

			set xmin [expr {double($x1)}]
			set xmax [expr {double($x2)}]
			set ymin [expr {double($y1)}]
			set ymax [expr {double($y2)}]

			set xtics [expr {double($xt)}]
			set ytics [expr {double($yt)}]
			# force floating point for all arguments
			if {$logx} {
				# logarithmic scale -- xticmin is the power of 10
				lassign [$self log_widen $xmin $xmax] xmin xmax
				set xticmin [expr {log10($xmin)}]
				set xticmax [expr {log10($xmax)}]

			} else {
				# linear scale
				set xticmin [expr {int(floor($xmin/$xtics))}]
				set xticmax [expr {int(ceil($xmax/$xtics))}]
				set xmin [expr {$xticmin*$xtics}]
				set xmax [expr {$xticmax*$xtics}]
			}

			if {$logy} {
				# logarithmic scale -- yticmin is the power of 10
				lassign [$self log_widen $ymin $ymax] ymin ymax
				set yticmin [expr {log10($ymin)}]
				set yticmax [expr {log10($ymax)}]

			} else {
				# linear scale
				set yticmin [expr {int(floor($ymin/$ytics))}]
				set yticmax [expr {int(ceil($ymax/$ytics))}]
				set ymin [expr {$yticmin*$ytics}]
				set ymax [expr {$yticmax*$ytics}]
			}
			set dimensioned 1

			$self calcaddmul
			# calculate linear transform parameters
			$self empty
			$self drawcoordsys

			# Notify other elements about the redraw
			event generate $can <<BoxResize>> -when tail
		}
		
		method autodim {args} {
			# if called from outside, reset zoom stack
			set zoomstack [list $args]
			$self autodim_internal {*}$args
		}

		method autodim_internal {x1 x2 y1 y2} {
			# automagically calculate good values
			# for the tics increment

			if {$logx && ($x1<=0 || $x2<=0)} { error "x-range must be positive for logscale"}
			if {$logy && ($y1<=0 || $y2<=0)} { error "y-range must be positive for logscale"}
			
			if {0} {
				if {$x2==$x1} { error "Zero x-range" }
				if {$y2==$y1} { error "Zero y-range" }
			} else {
				# instead of erroring out, widen zero ranges
				if {$x2==$x1} {
					if {$logx} {
						set xm $x1
						set x1 [expr {$xm*0.999}]
						set x2 [expr {$xm*1.001}]
					} else {
						set xm $x1
						set x1 [expr {$xm-0.001}]
						set x2 [expr {$xm+0.001}]
					}
				}

				if {$y2==$y1} {
					if {$logy} {
						set ym $y1
						set y1 [expr {$ym*0.999}]
						set y2 [expr {$ym*1.001}]
					} else {
						set ym $y1
						set y1 [expr {$ym-0.001}]
						set y2 [expr {$ym+0.001}]
					}
				}
						
			}

			set xd [expr {log($x2 - $x1)/log(10)}]
			set yd [expr {log($y2 - $y1)/log(10)}]
			set xe [expr {pow(10, floor($xd)-1)}]
			set ye [expr {pow(10, floor($yd)-1)}]

			set xfrac [expr {fmod($xd, 1.0)}]
			set yfrac [expr {fmod($yd, 1.0)}]
			if {$xfrac < 0 } {set xfrac [expr {$xfrac+1.0}]}
			if {$yfrac < 0 } {set yfrac [expr {$yfrac+1.0}]}
			# Exponent und Bruchteil des Zehnerlogarithmus
			set xb 10
			if {$xfrac <= 0.70} { set xb 5}
			if {$xfrac <= 0.31} { set xb 2}

			set yb 10
			if {$yfrac <= 0.70} { set yb 5}
			if {$yfrac <= 0.31} { set yb 2}

			# gerundeter Tick-Wert = xb*xe, yb*ye
			$self dim_internal $x1 $x2 $y1 $y2 [expr {$xb*$xe}] [expr {$yb*$ye}]

		}

		method calcaddmul {} {
			if {$logx} {
				set xmul [expr ($deskxmax - $deskxmin)/(log($xmax) -log($xmin))]
				set xadd [expr $deskxmin-log($xmin)*$xmul]
			} else {
				set xmul [expr ($deskxmax - $deskxmin)/($xmax -$xmin)]
				set xadd [expr $deskxmin-$xmin*$xmul]
			}

			if {$logy} {
				set ymul [expr ($deskymax - $deskymin)/(log($ymax) -log($ymin))]
				set yadd [expr $deskymin-log($ymin)*$ymul]
			} else {
				set ymul [expr ($deskymax - $deskymin)/($ymax -$ymin)]
				set yadd [expr $deskymin-$ymin*$ymul]
			}
		}

		method drawxtic {xval} {
			set deskx [$self xToPix $xval]
			if {$xval<$xmin || $xval>$xmax} return
			if { $grid } { $can create line $deskx $deskymin $deskx $deskymax -fill gray -tag $selfns }
			$can create line $deskx $deskymin  $deskx [expr {$deskymin+$ticklength}] -tag $selfns
			$can create text $deskx [expr {$deskymin+$ticklength}] -anchor n -justify center -text [format $xaxisformat $xval] -font $axisfont -tag $selfns
		}

		method drawytic {yval} {
			set desky [$self yToPix $yval]
			if {$yval<$ymin || $yval>$ymax} return
			if { $grid } { $can create line $deskxmin $desky $deskxmax $desky -fill gray -tag $selfns }
			$can create line $deskxmin $desky  [expr {$deskxmin-$ticklength}] $desky -tag $selfns
			$can create text  [expr {$deskxmin-$ticklength}] $desky -anchor e -text [format $yaxisformat $yval] -font $axisfont -tag $selfns
		}

		method logticlist {min max} {
			# return a list of tics for logarithmic plotting
			# min & max are powers of ten
			set ticlevel [expr {$max-$min}]
			if {$ticlevel<=2} {
				return {1 2 3 4 5}
			}
			if {$ticlevel<=4} {
				return {1 2 5}
			}
			if {$ticlevel<=6} {
				return {1 5}
			}
			return 1
		}

		method log_widen {min max } {
		#	puts "log_widen $min $max"
			set tics [$self logticlist [expr {log10($min)}] [expr {log10($max)}]]
			set minexp [expr {pow(10, int(floor(log10($min))))}]
			set maxexp [expr {pow(10, int(floor(log10($max))))}]

			set wmin $minexp
			set wmax $maxexp
			
		#	puts "$wmin $wmax , increment $tics"
			foreach tic $tics {
				if {$minexp*$tic < $min} {
					set wmin [expr {$minexp*$tic}]
				}
			}
			
			lappend tics 10
			foreach tic $tics {
				if {$maxexp*$tic >= $max} {
					set wmax [expr {$maxexp*$tic}]
					break
				}
			}

			return [list $wmin $wmax]
		}
	
		method widen {min max} {
			set minv [expr {int(floor($min))}]
			set maxv [expr {int(ceil($max))}]
			return [list $minv $maxv]
		}

	
		method drawcoordsys {} {

			if {$logx} {
				# logarithmic scale
				# draw only 1, 2, 5 * 10^ticmark
				set xticlist [$self logticlist $xticmin $xticmax]
				lassign [$self widen $xticmin $xticmax] pmin pmax
				for {set xtic $pmin} {$xtic<=$pmax} {incr xtic} {
					set power [expr {pow(10,$xtic)}]
					foreach multiplier $xticlist {
						$self drawxtic [expr {$multiplier*$power}]
					}
				}
			} else {
				for {set xtic $xticmin} { $xtic <= $xticmax} { incr xtic } {
					$self drawxtic [expr {$xtics*$xtic}]
					# puts "$deskx $deskymin $xval"
				}
			}

			if {$logy} {
				# logarithmic scale
				# draw only 1, 2, 5 * 10^ticmark
				set yticlist [$self logticlist $yticmin $yticmax]
				lassign [$self widen $yticmin $yticmax] pmin pmax
				for {set ytic $pmin} {$ytic<=$pmax} {incr ytic} {
					set power [expr {pow(10,$ytic)}]
					foreach multiplier $yticlist {
						$self drawytic [expr {$multiplier*$power}]
					}
				}
			} else {
				for {set ytic $yticmin} { $ytic <= $yticmax} { incr ytic } {
					$self drawytic [expr $ytics*$ytic]
					# puts "$deskxmin $desky $yval"
				}
			}

			$can create rectangle $deskxmin $deskymin $deskxmax $deskymax -tag $selfns

			if { $options(-xlabel) != "" } {
				$can create text [expr {($deskxmin + $deskxmax) / 2}] [expr {$deskymin + $ticklength + 1.2 * $lineheight}] \
					-anchor n -text $options(-xlabel) -font $axisfont -tag $selfns
			}
			
			if { $options(-ylabel) != "" } {
				$can create text 0 [expr {($deskymin + $deskymax)/2}] \
					-anchor n -angle 90 -text $options(-ylabel) -font $axisfont -tag $selfns
			}

		}

		method xToPix {x} {
			if {$logx} {
				expr {($x<=0)? -Inf*$xmul : log($x)*$xmul+$xadd}
			} else {
				expr {$x*$xmul+$xadd}
			}
		}

		method yToPix {y} {
			if {$logy} {
				expr {($y<=0) ? -Inf*$ymul : log($y)*$ymul+$yadd}
			} else {
				expr {$y*$ymul+$yadd}
			}
		}

		method PixTox {x} {
			if {$logx}  {
				expr {exp(($x-$xadd)/$xmul)}
			} else {
				expr {($x-$xadd)/$xmul}
			}
		}

		method PixToy {y} {
			if {$logy}  {
				expr {exp(($y-$yadd)/$ymul)}
			} else {
				expr {($y-$yadd)/$ymul}
			}
		}

		method coordsToPixel {x y} {
			list [$self xToPix $x] [$self yToPix $y]
		}

		method pixelToCoords {x y} {
			list [$self PixTox $x] [$self PixToy $y]
		}

		proc calcminmax {data}  {
			if {[llength $data]<2} {
				error "Invalid data, <2 items"
			}
			
			set xmin ""
			set ymin ""

			while {![isfinite $xmin] || ![isfinite $ymin]} {
				set data [lassign $data xmin ymin]
				if {[llength $data]<2} { return [list 1.0 2.0 1.0 2.0] }
			}

			set xmax $xmin
			set ymax $ymin
			foreach {x y} $data {
				if {![isfinite $x] || ![isfinite $y]} { continue }
				if {$x<$xmin} { set xmin $x}
				if {$x>$xmax} { set xmax $x}
				if {$y<$ymin} { set ymin $y}
				if {$y>$ymax} { set ymax $y}
			}

			list $xmin $xmax $ymin $ymax
		}

		method connectpoints {coordlist color args} {
			# save this data for redraw purposes
			set cid [$self connectpoints_nosave $coordlist $color $args]
			incr datasetnr
			dict set linedata $datasetnr [list $coordlist $color $args $cid]
			return $datasetnr
		}

		method showpoints {coordlist color shape} {
			# save this data for redraw purposes
			set cid [$self showpoints_nosave $coordlist $color $shape]
			incr datasetnr
			dict set pointdata $datasetnr [list $coordlist $color $shape $cid]
			return $datasetnr
		}

		method showpoints_autodim {coordlist color shape} {
			$self autodim {*}[calcminmax $coordlist]
			$self showpoints $coordlist $color $shape
		}

		method connectpoints_autodim {coordlist color args} {
			$self autodim {*}[calcminmax $coordlist]
			$self connectpoints $coordlist $color {*}$args
		}

		method connectpoints_nosave {coordlist color extraargs {prefix {}} } {
			if {$prefix == {}} {
				incr pttagnr
				set prefix [format "l%d_" $pttagnr]
			}
			set ltag "$prefix$selfns"
			
			set dxmin [$self xToPix $xmin]
			set dxmax [$self xToPix $xmax]
			set dymin [$self yToPix $ymin]
			set dymax [$self yToPix $ymax]

			set piece {}
			set pieces {}
			foreach {x y} $coordlist {
				if {![isfinite $x] || ![isfinite $y]} { 
					# NaN value, start a new piece
					if {[llength $piece]>0} { 
						lappend pieces $piece
					}
					set piece {}
					continue
				}

				set x [$self xToPix $x]
				set y [$self yToPix $y]
				lappend piece $x $y
			}


			lappend pieces $piece

			foreach piece $pieces {
				if {[llength $piece]>=4} {
					set clipped [geometry::polylineclip $piece $dxmin $dxmax $dymin $dymax]
					foreach coord $clipped {
						if {[llength $coord]<4} {
							# error
							puts "Input coords: "
							puts "set piece [list $piece]"
							puts "ukaz::geometry::polylineclip {$piece} $dxmin $dxmax $dymin $dymax"
							error "polyline did wrong, look in console"
						}
						$can create line $coord {*}$extraargs -fill $color -tag [list $selfns $ltag]
					}
				}
			}

			return $prefix
		}

		method showpoints_nosave {coordlist color shape {prefix {}}} {
			switch $shape {
				circle { 
					set shapeproc circle
					set filled false
				}

				filled-circle {
					set shapeproc filled-circle
					set filled true
				}

				square {
					set shapeproc square
					set filled false
				}

				filled-square {
					set shapeproc filled-square
					set filled true
				}

				hex     -
				hexagon {
					set shapeproc hexagon
					set filled false
				}

				filled-hexagon {
					set shapeproc filled-hexagon
					set filled true
				}

				default {

					error "Shape must be either square, circle or hex(agon), got  '$shape'"
					return
				}
			}

			if {$prefix == {} } {
				incr pttagnr
				set prefix [format "o%d_" $pttagnr]
			}

			# on Mac OS X, right&middle buttons are swapped
			# X11/Mac does it right, though
			if {[tk windowingsystem]== "aqua"} {
				set secondclick <2>
			} else {
				set secondclick <3>
			}

			set itemnr 0
			foreach {x y} $coordlist {

				if {[isfinite $x] && ($x>=$xmin) && ($x<=$xmax) && ($y>=$ymin) && ($y<=$ymax)} {
					set deskx [$self xToPix $x]
					set desky [$self yToPix $y]
					# simple clipping, sufficient
					$self $shapeproc $deskx $desky $color [list "$prefix$itemnr$selfns" "$prefix$selfns" $selfns]
					$can bind "$prefix$itemnr$selfns" <1> [mymethod pointclick $itemnr $prefix]
					$can bind "$prefix$itemnr$selfns" $secondclick [mymethod pointrightclick $itemnr $prefix]
				}

				incr itemnr
			}
			return $prefix
		}

		method circle {x y color tag} {
			# additional fully transparent circle to make interior selectable
			$can create oval [expr {$x-5}] [expr {$y-5}] [expr {$x+5}] [expr {$y+5}] -outline "" -tag $tag
			$can create oval [expr {$x-5}] [expr {$y-5}] [expr {$x+5}] [expr {$y+5}] -outline $color -tag $tag
			# puts $tag
		}

		method square {x y color tag} {
			$can create rectangle  [expr {$x-5}] [expr {$y-5}] [expr {$x+5}] [expr {$y+5}] -outline $color -tag $tag
		}

		method hexagon {x y color tag} {
			set size 5
			set clist {1 -0.5 0 -1.12 -1 -0.5 -1 0.5 0 1.12 1 0.5}
			foreach {xc yc} $clist {
				lappend coord [expr {$xc*$size+$x}]
				lappend coord [expr {$yc*$size+$y}]
			}
			$can create polygon $coord -outline $color -fill "" -tag $tag
		}
		
		method filled-circle {x y color tag} {
			$can create oval [expr {$x-5}] [expr {$y-5}] [expr {$x+5}] [expr {$y+5}] -outline "" -fill $color -tag $tag
		}

		method filled-square {x y color tag} {
			$can create rectangle  [expr {$x-5}] [expr {$y-5}] [expr {$x+5}] [expr {$y+5}] -outline "" -fill $color -tag $tag
		}

		method filled-hexagon {x y color tag} {
			set size 5
			set clist {1 -0.5 0 -1.12 -1 -0.5 -1 0.5 0 1.12 1 0.5}
			foreach {xc yc} $clist {
				lappend coord [expr {$xc*$size+$x}]
				lappend coord [expr {$yc*$size+$y}]
			}
			$can create polygon $coord -outline "" -fill $color -tag $tag
		}

		method remove {itemlist} {
			foreach item $itemlist {
				if [dict exists $pointdata $item] {
					set ctag [lindex [dict get $pointdata $item] 3]
					$can delete "$ctag$selfns"
					dict unset pointdata $item
				}

				if [dict exists $linedata $item] {
					set ctag [lindex [dict get $linedata $item] 3]
					$can delete "$ctag$selfns"
					dict unset linedata $item
				}
			}

		}

		method highlight {tag nr color} {
			set ctag "$tag$nr$selfns"
			switch [string index $tag 0] {
				o {$can itemconf $ctag -outline $color -fill $color}
				f {$can itemconf $ctag -fill $color}
				default { return [error "Invalid pointset identifier"] }
			}
			$can raise $ctag
		}

		method unhighlight {tag nr color} {
			set ctag "$tag$nr$selfns"
			switch [string index $tag 0] {
				o {$can itemconf $ctag -outline $color -fill "" }
				f {$can itemconf $ctag -fill $color}
				default { return [error "Invalid pointset identifier"] }
			}
		}

		method clear {} {
			$self empty
			set linedata {}
			set pointdata {}
			set pttagnr 0

			if {$dimensioned} {
				# box has been dimensioned
				$self drawcoordsys
			}
		}

		method empty {} {
			$can delete $selfns
		}

		method bind {event handler} {
			variable pointclickhandler
			variable rightclickhandler
			# arrange for handle to be called, when a point is clicked
			switch $event {
				<1>  {
					set pointclickhandler $handler
				}
				<3>  {
					set rightclickhandler $handler
				}
				default {
					error "Event must be <1> or <3>"
				}
			}
		}

		method pointclick {nr tag} {
			variable pointclickhandler
			puts "Click on point $nr, tag $tag in $selfns"
			if {$pointclickhandler != {}} {
				uplevel [list $pointclickhandler $nr $tag $selfns]
			}
		}

		method pointrightclick {nr tag} {
			puts "Right click on point $nr, tag $tag in $selfns"
			if {$rightclickhandler != {}} {
				uplevel [list $rightclickhandler $nr $tag $selfns]
			}
		}

#		method CreateImage {} { return [image create photo -format window -data $can] }

		method MakePDF {fn} {
			set size [list [winfo width $can] [winfo height $can]]
			set pdf [pdf4tcl::new %AUTO% -paper $size -compress false]
			$pdf canvas $can
			$pdf write -file $fn
			$pdf destroy
		}

		method zoomstart {x y} {
			# check if we hit the background
			if {[$can find withtag current]=={}} {
				# test whether we are inside the plotting area
				if {$x > $deskxmin && $x < $deskxmax && $y > $deskymax && $y < $deskymin} {
					set zooming true
					$can create rectangle [list $x $y $x $y] -outline red -tag zoomrect
					set zoomstartpos [list $x $y]
				}
			}
		}

		method zoommove {x y} {
			if {$zooming} {
				$can coords zoomrect [concat $zoomstartpos [list $x $y]]
			}
		}

		method zoomend {x y} {
			if {$zooming} {
				set zooming false
				$can delete zoomrect
				lassign [$self pixelToCoords {*}$zoomstartpos] x1 y1
				set x2 [$self PixTox $x]
				set y2 [$self PixToy $y]

				if {$x1==$x2 || $y1==$y2} {
					# if zoomregion is empty, do nothing
					return
				}
				# exchange if needed
				if {$x1>$x2} {
					lassign [list $x1 $x2] x2 x1
				}
				
				if {$y1>$y2} {
					lassign [list $y1 $y2] y2 y1
				}

				lappend zoomstack [list $x1 $x2 $y1 $y2]
				$self MouseZoom $x1 $x2 $y1 $y2
			}

		}

		method zoomout {x y} {
			# check if we hit the background
			if {[$can find withtag current]=={}} {
				# determine size for all saved datapoints
				set data {}
				dict for  {ind d} $linedata {
					lappend data {*}[lindex $d 0]
				}
				dict for  {ind d} $pointdata {
					lappend data {*}[lindex $d 0]
				}

				if {[llength $zoomstack]>1} {
					set zoomstack [lrange $zoomstack 0 end-1]
				}
				set prevpos [lindex $zoomstack end]
				if {$prevpos == {}} {
					# never happens
					# zoom completely out
					set totalpos [calcminmax $data]
					#puts "Zoom completely out: $totalpos"
					# $self MouseZoomOut {*}$totalpos
				} else {
					#puts "Zoom back: {*}$prevpos"
					$self MouseZoomOut {*}$prevpos
				}

			}
		}


		# override these two for computed data
		method MouseZoom {x1 x2 y1 y2} {
				$self autodim_internal $x1 $x2 $y1 $y2
				$self autoresize
		}
		
		method MouseZoomOut {x1 x2 y1 y2} {
				$self autodim_internal $x1 $x2 $y1 $y2
				$self autoresize
		}

		proc isfinite {x} {
			# determine, whether x,y is a valid point
			expr {[string is double -strict $x] && $x < Inf && $x > -Inf}
		}

		proc isnan {x} {
			# determine, whether x is NaN
			expr {$x != $x}
		}
	}

	snit::type dragline {
		variable dragging

		option -command -default {}
		option -orient -default horizontal -configuremethod SetOrientation
		option -variable -default {} -configuremethod SetVariable
		
		variable pos
		variable canv
		variable plotbox
		variable itemnr
		variable x1
		variable x2
		variable y1
		variable y2

		variable loopescape
		variable commandescape
		constructor {box color args} {
			set loopescape false
			set plotbox $box
			set canv [$box getcanv]

			uevent::bind $plotbox Destroy [mymethod BoxDestroy]

			lassign [$box getsize] x1 y1 x2 y2
			set itemnr [$canv create line [list $x1 $y1 $x2 $y2] -fill $color -dash .]

			$self configurelist $args

			set posx [expr {($x1+$x2)/2}]
			set posy [expr {($y1+$y2)/2}]
			set commandescape true
			$self GotoPixel $posx $posy
			
			# Bindings for dragging
			$canv bind $itemnr <ButtonPress-1> [mymethod dragstart %x %y]
			$canv bind $itemnr <Motion> [mymethod dragmove %x %y]
			$canv bind $itemnr <ButtonRelease-1> [mymethod dragend %x %y]
			# Bindings for hovering - change cursor
			$canv bind $itemnr <Enter> [mymethod dragenter]
			$canv bind $itemnr <Leave> [mymethod dragleave]
			# Bindings for changing of the size
			bind $canv <<BoxResize>> +[mymethod resize]
			set dragging 0
		}

		destructor {
			$self untrace
			uevent::unbind [uevent::bind $plotbox Destroy [mymethod BoxDestroy]]
			if { [winfo exists $canv] && [info exists itemnr]} { $canv delete $itemnr }
		}

		method SetVariable {option varname} {
			$self untrace
			if {$varname != {}} {
				upvar #0 $varname v
				#if {![info exists v]} { set $v 1.0 }
				trace add variable v write [mymethod SetValue]
				set options(-variable) $varname
				$self SetValue
			}
		}

		method untrace {} {
			if {$options(-variable)!={} } {
				upvar #0 $options(-variable) v
				trace remove variable v write [mymethod SetValue]
				set options(-variable) {}
			}
		}
		
		method SetValue {args} {
			if {$loopescape} {
				set loopescape false
				return
			}
			set loopescape true
			upvar #0 $options(-variable) v
			if {[info exists v]} {
				$self gotoCoords $v $v
			}
		}

		method DoTraces {} {
			if {$loopescape} {
				set loopescape false
			} else {
				if {$options(-variable)!={}} {
					set loopescape true
					upvar #0 $options(-variable) v
					set v $pos
				}
			}

			if {$options(-command)!={}} {
				if {$commandescape} {
					set commandescape false
				} else {
					uplevel #0 [list $options(-command) $pos]
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
					
		method BoxDestroy { args } { $self destroy }

		method dragenter {} {
			if {!$dragging} {
				$canv configure -cursor hand2
			}
		}

		method dragleave {} {
			if {!$dragging} {
				$canv configure -cursor {}
			}
		}

		method dragstart {x y} {
			set dragging 1
		}

		method dragmove {x y} {
			if {$dragging} {
				$self GotoPixel $x $y
			}
		}

		method dragend {x y} {
			set dragging 0
		}

		method GotoPixel {x y} {
			lassign [$plotbox pixelToCoords $x $y] rx ry
			if {$options(-orient)=="horizontal"} {
				set pos $ry
				$canv coords $itemnr [list $x1 $y $x2 $y]
			} else {
				set pos $rx
				$canv coords $itemnr [list $x $y1 $x $y2]
			}
			$self DoTraces
		}

		method gotoCoords {x y} {
			lassign [$plotbox coordsToPixel $x $y] nx ny
			if {$options(-orient)=="horizontal"} {
				set pos $y
				$canv coords $itemnr [list $x1 $ny $x2 $ny]
			} else {
				set pos $x
				$canv coords $itemnr [list $nx $y1 $nx $y2]
			}
			$canv raise $itemnr
			$self DoTraces
		}

		method resize {} {
			# Binding invoked, when the underlying box changes its dimensions
			lassign [$plotbox getsize] x1 y1 x2 y2
			lassign [$plotbox coordsToPixel $pos $pos] px py
			if {$options(-orient)=="horizontal"} {
				$canv coords $itemnr [list $x1 $py $x2 $py]
			} else {
				$canv coords $itemnr [list $px $y1 $px $y2]
			}
		}

	}

}
