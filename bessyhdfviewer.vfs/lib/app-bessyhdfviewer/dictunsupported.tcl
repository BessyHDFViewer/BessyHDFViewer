namespace eval DictUnsupported { 
   package require Tcl 8.6 
   ######################### 
   ## dict format dict 
   # 
   # convert dictionary value dict into string 
   # hereby insert newlines and spaces to make 
   # a nicely formatted ascii output 
   # The output is a valid dict and can be read/used 
   # just like the original dict 
   ############################# 


   proc dict_format {dict} { 
      dictformat_rec $dict "" "\t" 
   } 


   proc isdict {v} { 
      string match "value is a dict *" [::tcl::unsupported::representation $v] 
   } 


   ## helper function - do the real work recursively 
   # use accumulator for indentation 
   proc dictformat_rec {dict indent indentstring} {
      # unpack this dimension
	  set result {}
      dict for {key value} $dict { 
         if {[isdict $value]} { 
            append result "$indent[list $key]\n$indent\{\n" 
            append result "[dictformat_rec $value "$indentstring$indent" $indentstring]\n" 
            append result "$indent\}\n" 
         } else { 
            append result "$indent[list $key] [list $value]\n" 
         }
      }

      return $result 
   }

   namespace ensemble configure dict -map \
       [linsert [namespace ensemble configure dict -map] end format [namespace current]::dict_format]
}
