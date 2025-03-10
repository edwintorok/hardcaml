open! Import
open Signal

let rtl_write_null outputs = Rtl.print Verilog (Circuit.create_exn ~name:"test" outputs)

let%expect_test "Port names must be unique" =
  require_does_raise [%here] (fun () -> rtl_write_null [ output "a" (input "a" 1) ]);
  [%expect
    {|
    ("Port names are not unique" (circuit_name test) (input_and_output_names (a))) |}]
;;

let%expect_test "Port names must be legal" =
  require_does_raise [%here] (fun () -> rtl_write_null [ output "a" (input "1^7" 1) ]);
  [%expect
    {|
    ("Error while writing circuit"
      (circuit_name test)
      (hierarchy_path (test))
      (output ((language Verilog) (mode (To_channel <stdout>))))
      (exn (
        "illegal port name"
        (name       1^7)
        (legal_name _1_7)
        (note       "Hardcaml will not change ports names.")
        (port (
          wire
          (names (1^7))
          (width   1)
          (data_in empty)))))) |}]
;;

let%expect_test "Port name clashes with reserved name" =
  require_does_raise [%here] (fun () -> rtl_write_null [ output "module" (input "x" 1) ]);
  [%expect
    {|
    ("Error while writing circuit"
      (circuit_name test)
      (hierarchy_path (test))
      (output ((language Verilog) (mode (To_channel <stdout>))))
      (exn (
        "port name has already been defined or matches a reserved identifier"
        (port (
          wire
          (names (module))
          (width   1)
          (data_in x)))))) |}]
;;

let%expect_test "output wire is width 0 (or empty)" =
  (* The exception is raised by the [output] function. *)
  require_does_raise [%here] (fun () -> rtl_write_null [ output "x" (empty +: empty) ]);
  [%expect
    {|
    ("width of wire was specified as 0" (
      wire (
        wire
        (width   0)
        (data_in empty)))) |}]
;;

let%expect_test "instantiation input is empty" =
  require_does_raise [%here] (fun () ->
    let a = Signal.empty in
    let inst =
      Instantiation.create () ~name:"example" ~inputs:[ "a", a ] ~outputs:[ "b", 1 ]
    in
    Circuit.create_exn ~name:"example" [ Signal.output "b" (Map.find_exn inst "b") ]
    |> Rtl.print Verilog);
  [%expect
    {|
    module example (
        b
    );

        output b;

        /* signal declarations */
        wire _4;
        wire _1;

        /* logic */
        example
            the_example
    ("Error while writing circuit"
      (circuit_name example)
      (hierarchy_path (example))
      (output ((language Verilog) (mode (To_channel <stdout>))))
      (exn (
        "failed to connect instantiation port"
        (inst_name the_example)
        (port_name a)
        (signal    empty)
        (indexes ())
        (exn (
          "[Rtl.SignalNameManager] internal error while looking up signal name"
          (index      0)
          (for_signal empty)))))) |}]
;;
