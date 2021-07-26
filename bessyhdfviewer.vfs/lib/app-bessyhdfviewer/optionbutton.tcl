# Copyright (c) 2021 Christian Gollwitzer
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
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
 
package require Tk
package require snit

snit::widgetadaptor	optionbutton {
	# a toolbutton that opens a menu upon 
	# longer click
	delegate option * to hull except -command
	delegate method * to hull
	
	# delay before opening the options menu
	option -delay -default 500
	# values for display
	option -values -default {} -configuremethod setvalues
	option -headline -default {} -configuremethod setvalues
	
	# callback before menu opens
	option -optcallback -default {}
	
	# callback after press / select
	option -command -default {} 

	component optmenu

	variable afterid {}
	variable mouseoutside false

	constructor {args} {
		installhull using ttk::menubutton -style Toolbutton
		install optmenu using menu $win.m
		$hull configure -menu $optmenu

		$self configurelist $args
		
		# replace bindings
		bind $self <Button-1> [mymethod LeftBPress]
		bind $self <ButtonRelease-1> [mymethod LeftBRelease]
		bind $self <Button-3> [mymethod RightBPress]
		bind $self <Leave> [mymethod mouseleft]
		bind $self <Enter> [mymethod mouseenter]
	}

	destructor {
		if {$afterid ne {}} {
			catch [after cancel $afterid]
		}
	}


	method LeftBPress {} {
		$hull state pressed
		set afterid [after $options(-delay) [mymethod openmenu]]
		set mouseoutside false
		return -code break
	}

	method LeftBRelease {} {
		set problem 0
		if {$afterid ne {} || [llength $options(-values)] == 0} {
			# the delay for the popdown menu is not yet passed
			# or there is no list
			after cancel $afterid
			set afterid {}
			if {!$mouseoutside} {
				set problem [catch {uplevel #0 $options(-command)} result errdict]
			}
		}

		$hull state !pressed
		if {$problem} {
			return {*}$errdict $result
		}
		return -code break
	}

	method RightBPress {} {
		$self openmenu
		return -code break
	}

	method mouseleft {} {
		set mouseoutside true
	}

	method mouseenter {} {
		set mouseoutside false
	}

	method openmenu {} {
		set afterid {}
		uplevel #0 $options(-optcallback)
		if {[llength $options(-values)] > 0} { 
			$hull state !pressed
			ttk::menubutton::Popdown $win
		}
	}

	method selected {i} {
		set cmdlist [linsert $options(-command) end $i]
		uplevel #0 $cmdlist
	}

	method setvalues {opt val} {
		set options($opt) $val
		$optmenu delete 0 end

		if {$options(-headline) ne {}} {
			$optmenu add command -label $options(-headline) -state disabled
			$optmenu add separator
		}
		set i 0
		foreach lbl $options(-values) {
			$optmenu add command -label $lbl -command [mymethod selected $i]
			incr i
		}
	}
}
