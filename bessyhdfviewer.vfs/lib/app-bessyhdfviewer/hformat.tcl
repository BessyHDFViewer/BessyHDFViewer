namespace eval HFormat {
	package require Tcl 8.6
	#########################
	##
	# convert nested list/dictionary value dict into string
	# hereby insert newlines and spaces to make
	# a nicely formatted ascii output
	# The output is a valid dict/list and can be read/used
	# just like the original dict/list
	#############################

	proc hformat {value} {
		hformat_rec $value "" "\t"
	}

	proc gettype {v} {
		if {![regexp {value is a (\w+)} [tcl::unsupported::representation $v] -> type]} {
			error "Failure to parse representation. Incompatible Tcl version?"
		}
		return $type
	}

		
	proc isstructured {v} {
		set type [gettype $v]
		expr {$type in {dict list}}
	}

	proc isempty {v} {
		switch [gettype $v] {
			list { 
				return [expr {[llength $v]==0}]
			}

			dict {
				return [expr {[dict size $v]==0}]
			}

			default {
				return [expr {$v == ""}]
			}
		}
	}

	## helper function - do the real work recursively
	# use accumulator for indentation
	proc hformat_rec {structure indent indentstring} {
		# check for type of this level
		set type [gettype $structure]
		# unpack this dimension
		switch $type {
			dict {
				if {[dict size $structure] == 0} { 
					return "$indent{}"
				}
				dict for {key value} $structure {
					if {[isstructured $value]} {
						if {[isempty $value]} {
							append result "$indent[list $key] {}\n"
						} else {
							append result "$indent[list $key]\n$indent\{\n"
							append result "[hformat_rec $value "$indentstring$indent" $indentstring]\n"
							append result "$indent\}\n"
						}
					} else {
						append result "$indent[list $key] [list $value]\n" 
					}
				}
				return $result
			}

			list {
				if {[llength $structure] == 0} { 
					return "{}"
				}
				foreach {value} $structure {
					if {[isstructured $value]} {
						if {[isempty $value]} {
							append result "$indent{}\n"
						} else {
							append result "$indent\{\n"
							append result "[hformat_rec $value "$indentstring$indent" $indentstring]\n"
							append result "$indent\}\n"
						}
					} else {
						append result "$indent[list $value]\n"
					}
				}
				return $result
			}

			default {
				return [list $structure]
			}
		}
	}

	interp alias {} hformat {} HFormat::hformat
}
