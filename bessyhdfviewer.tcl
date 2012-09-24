lappend auto_path 

package require hdfpp
package require ukaz

proc bessy_reshape {fn} {
	set hdf [HDFpp %AUTO% $fn]
	set hlist [$hdf dump]
	$hdf -delete
	foreach dataset $hlist {
		set dname [dict get $dataset name]
		dict unset dataset name
		if {[catch {dict get $dataset attrs Name} name]} {
			# there is no name - put it directly
			set key [list $dname]
		} else {
			# sub-name in the attrs - put it as a subdict
			dict unset dataset attrs Name
			set key [list $dname $name]
		}
		
		if {[llength [dict get $dataset data]]==0} {
			# key contains only attrs -- put it directly there
			set dataset [dict get $dataset attrs]
		} else {	
			# filter all data entries to the last occurence >= BESSY_INF
			set BESSY_INF 9.9e36
			set data [dict get $datast data]
			set index 0
			set lastindex end
			foreach v $data {
				if {abs($v) >= $BESSY_INF} {
					set lastindex $index
				}
				incr index
			}
			dict set dataset data [lrange $data 0 $lastindex]
		}

		dict set hdict {*}$key $dataset
	}
	return $hdict
}

proc bessy_class {data} {
	# classify dataset into Images, Plot and return plot axes
	set images [dict exists $data Detector Pilatus_Tiff]
	set motor {}
	catch {dict get $data Plot Motor} motor
	set detector {}
	catch {dict get $data Plot Detector} detector
	list $images $motor $detector
}


