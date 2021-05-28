open! Core

let () =
  Command_unix.run
  @@ Command.group
       ~summary:"Hardcaml Synthesis reports"
       [ "clz", Count_leading_zeros.command ]
;;
