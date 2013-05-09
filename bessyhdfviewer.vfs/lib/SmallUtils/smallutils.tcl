package provide SmallUtils 1.0

namespace eval SmallUtils {
	variable ns [namespace current]
	variable Requests {}
	

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

}

