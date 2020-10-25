# Copyright (c) 2012 Christian Gollwitzer, Bundesanstalt für Materialforschung und -prüfung (BAM)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
# of the Software, and to permit persons to whom the Software is furnished to do
# so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

package require snit
package provide numeric_entry 0.9

snit::widgetadaptor numeric_entry {
	# ttk::entry which displays nicely rounded values, but uses
	# internal full precision until the user edits the values

	option -format -default "%.6g"
	option -epsilon -default 0
	option -default -default {}
	option -min -default {}
	option -max -default {}
	option -strict -default false
	option -variable -default {} -configuremethod SetVar

	delegate option * to hull except -validate except -validatecommand except -invalidcommand except -textvariable
	delegate method * to hull

	variable displayvar
	variable loopescape
	variable modified

	constructor {args} {
		installhull using ttk::entry -validate all -validatecommand [mymethod validator %d %S %s %P %V] -textvariable [myvar displayvar]
		set loopescape false
		set modified false

		# move the -variable option to the end of the list
		if {[dict exists $args -variable]} {
			set thevar [dict get $args -variable]
			dict unset args -variable
			dict set args -variable $thevar
		}
		$self configurelist $args
	}

	destructor {
		$self untrace
	}

	method untrace {} {
		if {$options(-variable)!= {}} {
			upvar #0 $options(-variable) v
			trace remove variable v write [mymethod SetVal]
			set options(-variable) {}
		}

	}

	method SetVar {option varname} {
		$self untrace
		if {$varname != {} } {
			upvar #0 $varname v
			if {![info exists v]} {
				set v $options(-default)
			}
			trace add variable v write [mymethod SetVal]
			set options(-variable) $varname
			$self SetVal
		}
	}

	method SetVal {args} {
		# the linked variable has been set
		# reset modified flag and format number
		if {$loopescape} {
			set loopescape false
			return
		}

		set modified false
		$self FormatVal
	}

	method FormatVal {} {
		upvar #0 $options(-variable) thevar

		if {$thevar=={}} {
			set displayvar {}
			return
		}
		if {abs($thevar)<$options(-epsilon)} {
			set displayvar 0
		} else {
			set displayvar [format $options(-format) $thevar]
		}
	}

	method validator {mode key oldx newx event} {
		upvar #0 $options(-variable) thevar

		# check the new value for anything looking remotely like exponential notation
		# replace comma with decimal point
		regsub , $newx . newx
		switch $mode {
			1 {
				# inserting
				if { [regexp {^\s*[+-]?\d*(\.\d*)?([eE][+-]?\d*)?\s*$} $newx] } {
					# loopescape stops SetVar from updating displayvar
					set loopescape true
					set thevar $newx
					set modified true
					event generate $win <<ModifiedInsert>> -when head
					return true
				} else {
					return false
				}
			}
			0 {
				# delete
				# accept in any case: Don't annoy user to reject anything
				set loopescape true
				set thevar $newx
				set modified true

				event generate $win <<ModifiedDelete>> -when head
				return true
			}
			-1 {
				# revalidation
				# if there is no modification, just accept
				if {!$modified} {
					return true
				} else {
					# whether we need to change the value inside here
					set valuechanged false

					if {![string is double $newx]} {
						# try to make a double from this corrupted string
						if {[scan $newx %f temp]} {
							set newx $temp
							set valuechanged true
						} else {
							# can't convert to double in any reasonable fashion
							set newx $options(-default)
							set valuechanged true
						}
					}

					# check again with -strict, to disallow empty input
					if {$options(-strict) && ![string is double -strict $newx]} {
						set newx $options(-default)
						set valuechanged true
					}

					# check for min and max values
					if {!$valuechanged && [string is double -strict $options(-min)] && $newx<$options(-min)} {
						set newx $options(-min)
						set valuechanged true
					}

					if {!$valuechanged && [string is double -strict $options(-max)] && $newx>$options(-max)} {
						set newx $options(-max)
						set valuechanged true
					}

					# newx is determined, now set the linked variable
					# inhibit trace
					set loopescape true
					set thevar $newx
					if {$valuechanged} {
						# the value has been changed by the validator
						# reformat the display
						$self FormatVal
					}
					if {$valuechanged || ($event=="focusout" && $modified)} {
						event generate $win <<Modified>> -when head
					}
					return true
				}
			}
			default {
				error "Unknown validation condition $mode"
			}
		}

	}

	method IsModified {} {
		return $modified
	}

	method ResetModified {} {
		set modified false
	}
}
