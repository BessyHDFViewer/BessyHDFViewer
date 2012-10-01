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
}

