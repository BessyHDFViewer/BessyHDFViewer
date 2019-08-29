package provide SmallUtils 1.0

namespace eval SmallUtils {
	variable ns [namespace current]
	variable Requests {}

	namespace export defer autovar autofd enumerate dict_getdefault dict_assign

	proc defer {cmd} {
		# defer cmd to idle time. Multiple requests are merged
		variable ns
		variable Requests
		if {[dict size $Requests] == 0} {
			after idle ${ns}::doRequests
		}

		dict set Requests $cmd 1
	}

	proc doRequests {} {
		variable Requests

		# first clear Requests, so that new requests are only recorded
		# during execution and do not interfere with the execution
		set ReqCopy $Requests
		set Requests {}
		dict for {cmd val} $ReqCopy {
			uplevel #0 $cmd
		}
	}

	proc TablelistMakeTree {tbl tree {valuedict {}}} {
		foreach line $tree {
			TablelistMakeTree_rec root $line
		}
		# now insert rest as unsorted group
		if {[dict size $valuedict] != 0} {
			set node [$tbl insertchild root end "Unsorted"]
			dict for {key value} $valuedict {
				lappend childlist [list $key {*}$value]
			}
			$tbl insertchildlist $node end $childlist
		}
	}

	proc TablelistMakeTree_rec {node tree} {
		upvar 1 valuedict valuedict
		upvar 1 tbl tbl
		set tree [lassign $tree type]
		switch -nocase $type {
			GROUP {
				# a group of items with a list of trees in values
				lassign $tree name values
				set childnode [$tbl insertchild $node end [list $name]]
				if {$node != "root"} {
					$tbl collapse $childnode
				}
				$tbl rowconfigure $childnode -selectable 0
				foreach value $values {
					TablelistMakeTree_rec $childnode $value
				}
			}

			LIST {
				# a list of items
				lassign $tree values
				# zip up contents of valuedict with these items
				set childlist {}
				foreach name $values {
					if {[dict exists $valuedict $name]} {
						lappend childlist [list $name {*}[dict get $valuedict $name]]
						dict unset valuedict $name
					} else {
						lappend childlist [list $name]
					}
				}
				$tbl insertchildlist $node end $childlist
			}

			default {
				error "Unknown element in tree: $type. Should be GROUP or LIST"
			}
		}

	}

	proc file_common_dir {flist} {
		# find common directory for files in flist
		set flistabs {}
		foreach fn $flist {
			lappend flistabs [file dirname [file normalize $fn]]
		}
		set ancestor [file split [lindex $flistabs 0]]
		foreach fn $flistabs {
			set fnsplit [file split $fn]
			# shorten to common length
			set maxidx [expr {max([llength $fnsplit],[llength $ancestor])-1}]
			set fnsplit [lrange $fnsplit 0 $maxidx]
			set ancestor [lrange $ancestor 0 $maxidx]
			# trim from back until we are equal
			while {$fnsplit!=$ancestor} {
				set fnsplit [lrange $fnsplit 0 end-1]
				set ancestor [lrange $ancestor 0 end-1]
			}
		}

		if {$ancestor == ""} { return "/" }
		file join {*}$ancestor
	}

	proc autovar {var args} {
		variable ns
		upvar 1 $var v
		set v [uplevel 1 $args]
		trace add variable v unset [list ${ns}::autodestroy $v]
	}

	proc autodestroy {cmd args} {
		# puts "RAII destructing $cmd"
		rename $cmd ""
	}

	proc autofd {var args} {
		variable ns
		upvar 1 $var fd
		catch {unset fd}
		set fd [uplevel 1 [list open {*}$args]]
		trace add variable fd unset [list ${ns}::autoclose $fd]
	}

	proc autoclose {fd args} {
		# puts "RAII destructing $cmd"
		catch {close $fd}
	}

	proc dict_getdefault {dict args} {
		set default [lindex $args end]
		set keys [lrange $args 0 end-1]
		if {[dict exists $dict {*}$keys]} {
			return [dict get $dict {*}$keys]
		} else {
			return $default
		}
	}
	
	proc dict_assign {dictvalue args} {
		# extract variables from dict
		# unset -> unset
		foreach var $args {
			upvar $var v 
			if {[catch {dict get $dictvalue $var} v]} {
				unset v
			}
		}
	}

	proc enumerate {list} {
		set result {}
		for {set ind 0} {$ind < [llength $list]} {incr ind} {
			lappend result $ind [lindex $list $ind]
		}
		return $result
	}

	# functions to create a diff
	# shamelessly ripped from https://wiki.tcl-lang.org/page/diff+in+Tcl

	# McIlroy --
	#
	#	from: https://wiki.tcl-lang.org/page/diff+in+Tcl
	#
	#	Copyright (c) 2003 by Kevin B. Kenny.  All rights reserved.
	#
	#       Computes the longest common subsequence of two lists.
	#
	# Parameters:
	#       sequence1, sequence2 -- Two lists to compare.
	#
	# Results:
	#       Returns a list of two lists of equal length.
	#       The first sublist is of indices into sequence1, and the
	#       second sublist is of indices into sequence2.  Each corresponding
	#       pair of indices corresponds to equal elements in the sequences;
	#       the sequence returned is the longest possible.
	#
	# Side effects:
	#       None.

	proc McIlroy {sequence1 sequence2} {
		# Construct a set of equivalence classes of lines in set 2

		set index 0
		foreach string $sequence2 {
			lappend eqv($string) $index
			incr index
		}

		# K holds descriptions of the common subsequences.
		# Initially, there is one common subsequence of length 0,
		# with a fence saying that it includes line -1 of both files.
		# The maximum subsequence length is 0; position 0 of
		# K holds a fence carrying the line following the end
		# of both files.

		lappend K [::list -1 -1 {}]
		lappend K [::list [llength $sequence1] [llength $sequence2] {}]
		set k 0

		# Walk through the first file, letting i be the index of the line and
		# string be the line itself.

		set i 0
		foreach string $sequence1 {
			# Consider each possible corresponding index j in the second file.

			if { [info exists eqv($string)] } {

				# c is the candidate match most recently found, and r is the
				# length of the corresponding subsequence.

				set r 0
				set c [lindex $K 0]

				foreach j $eqv($string) {
					# Perform a binary search to find a candidate common
					# subsequence to which may be appended this match.

					set max $k
					set min $r
					set s [expr { $k + 1 }]
					while { $max >= $min } {
						set mid [expr { ( $max + $min ) / 2 }]
						set bmid [lindex [lindex $K $mid] 1]
						if { $j == $bmid } {
							break
						} elseif { $j < $bmid } {
							set max [expr {$mid - 1}]
						} else {
							set s $mid
							set min [expr { $mid + 1 }]
						}
					}

					# Go to the next match point if there is no suitable
					# candidate.

					if { $j == [lindex [lindex $K $mid] 1] || $s > $k} {
						continue
					}

					# s is the sequence length of the longest sequence
					# to which this match point may be appended. Make
					# a new candidate match and store the old one in K
					# Set r to the length of the new candidate match.

					set newc [::list $i $j [lindex $K $s]]
					if { $r >= 0 } {
						lset K $r $c
					}
					set c $newc
					set r [expr { $s + 1 }]

					# If we've extended the length of the longest match,
					# we're done; move the fence.

					if { $s >= $k } {
						lappend K [lindex $K end]
						incr k
						break
					}
				}

				# Put the last candidate into the array

				lset K $r $c
			}

			incr i
		}

		# Package the common subsequence in a convenient form

		set seta {}
		set setb {}
		set q [lindex $K $k]

		for { set i 0 } { $i < $k } {incr i } {
			lappend seta {}
			lappend setb {}
		}
		while { [lindex $q 0] >= 0 } {
			incr k -1
			lset seta $k [lindex $q 0]
			lset setb $k [lindex $q 1]
			set q [lindex $q 2]
		}

		return [::list $seta $setb]
	}
	# write the hunk similar to standard diff
	#
	proc formatHunk {p q i j leftdiff rightdiff} {
		set result {}
		set nleftdiff [llength $leftdiff]
		set nrightdiff [llength $rightdiff]

		if {$nleftdiff > 0 || $nrightdiff > 0} {
			# found a difference
			append result "diff: $i,$p $j,$q\n"
			if {$nleftdiff > 0} {
				append result "[join [lmap line $leftdiff  { string cat "< " $line }] \n]\n"
			}
			if {$nleftdiff > 0 && $nrightdiff > 0} {
				append result "---\n"
			}
			if {$nrightdiff > 0} {
				append result "[join [lmap line $rightdiff  { string cat "> " $line }] \n]\n"
			}
		}

		return $result
	}

	# split the two strings at newline and diff them
	proc difftext {text1 text2} {

		set lines1 [split $text1 \n]
		set lines2 [split $text2 \n]

		set i 0
		set j 0
		set p 0
		set q 0
		set leftdiff {}
		set rightdiff {}

		lassign [McIlroy $lines1 $lines2] x1 x2

		foreach p $x1 q $x2 {
			set leftdiff {}
			set rightdiff {}
			set istart $i
			set jstart $j

			while { $i < $p } {
				set l [lindex $lines1 $i]
				incr i
				lappend leftdiff $l
			}
			while { $j < $q } {
				set m [lindex $lines2 $j]
				incr j
				lappend rightdiff $m
			}

			append result [formatHunk $p $q $istart $jstart $leftdiff $rightdiff]

			set l [lindex $lines1 $i]
			incr i
			incr j
		}

		set istart $i
		set jstart $j
		while { $i < [llength $lines1] } {
			set l [lindex $lines1 $i]
			incr i
			lappend leftdiff $l
		}
		while { $j < [llength $lines2] } {
			set m [lindex $lines2 $j]
			incr j
			lappend rightdiff $m
		}

		append result [formatHunk $p $q $istart $jstart $leftdiff $rightdiff]

		return $result
	}

}
