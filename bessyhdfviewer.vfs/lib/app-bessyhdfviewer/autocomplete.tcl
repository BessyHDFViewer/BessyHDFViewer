package require snit

snit::widgetadaptor AutoComplete {
	# dialog for choosing and sorting a subset of a large list

	variable suggind
	variable matches
	variable front
	variable tail
	variable singlevar
	variable formula


	option -aclist -default {Energy Keithley4 Keithley1 Sample-X Det.-X}

	delegate option * to hull
	delegate method * to hull

	
	constructor {args} {
		installhull $win
		bind $win <Key> [mymethod InvalidateAutoComplete]
		# unspecific key binding
		bind $win <Tab> [mymethod AutoComplete]
		$self configurelist $args
		$self InvalidateAutoComplete
	}

	method AutoComplete {} {

		set ACavailable false
		if {[llength $matches] == 0} {
			set insertpos [$hull index insert]
			set input [$hull get]
			set head [string range $input 0 $insertpos-1]
			set tail [string range $input $insertpos end]

			#puts "Cursor: $head|$tail"

			# match for either: something ${varname tail}
			# or whitespace + something
			# complicated because of non-canonical variable names
			# like Sample-X, which must be ${Sample-X} or Det.-X

			set formula [regexp {^(.*)(\$)(\{?)(.+)$} $head -> front dollar brace varhead]
			if {$formula} {
				set singlevar false
			} else {
				set singlevar [regexp {^([[:space:]]*)(.+)$} $head -> space varhead]
				set front {}
			}
			
			if {$formula || $singlevar} {
				# look for possible matches of varhead in autocomplete list
				set matches {}
				foreach varname $options(-aclist) {
					if {[string match -nocase "$varhead*" $varname]} {
						lappend matches $varname
					}
				}
				set matches [lsort -nocase $matches]
				lappend matches $varhead

				#puts "Possible matches [join $matches ,]"

				set suggind 0
				set ACavailable true
			}

		} else {
			set ACavailable true

		}
		
		if {$ACavailable} {
			set suggestion [lindex $matches $suggind]
			# replace by suggestion
			set output $front

			if {$singlevar} {
				# single variable - just insert it
				set output $suggestion
			} else {
				# formula - $ and brace suggestion
				if {[regexp {^[[:alpha:]][[:alnum:]]*$} $suggestion]} {
					# only alphanumeric - don't use braces
					append output "\$$suggestion"
				} else {
					# insert braces for safety
					append output "\$\{$suggestion\}"
				}
			}
			set insertpos [string length $output]
			append output $tail
			
			# insert text and 
			# move cursor to end of inserted text
			$hull delete 0 end
			$hull insert 0 $output
			$hull icursor $insertpos
			
			# cycle through suggestions
			incr suggind
			if {$suggind >= [llength $matches]} { set suggind 0 }
		}
		return -code break
	}

	method InvalidateAutoComplete {} {
		set matches {}
		#puts "AC invalidated"
	}

}
