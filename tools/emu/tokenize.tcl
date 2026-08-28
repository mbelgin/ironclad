# Load each ASCII .BAS in the disk directory and save it back tokenised (same name).
# openmsx -machine Sony_HB-F1XD -diska <dir> -script tools/emu/tokenize.tcl   (env FILES="A.BAS B.BAS")
set throttle off
set files [split $env(FILES) " "]
set t 10
foreach f $files {
  after time $t "type \"LOAD\\\"$f\\\"\r\""
  set t [expr {$t + 400}]
  after time $t "type \"SAVE\\\"$f\\\"\r\""
  set t [expr {$t + 40}]
}
after time [expr {$t + 20}] { exit }
