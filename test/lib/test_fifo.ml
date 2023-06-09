(* Tests for the [Fifo] module. We speak about a [classic] and [showahead] fifo which
   differ in when the output data appears. In classic mode it is 1 cycle after a read,
   while in showahead mode it is valid along with the empty flags deassertion. *)

open! Import
open Hardcaml_waveterm_kernel

module I = struct
  type 'a t =
    { clock : 'a
    ; clear : 'a
    ; wr : 'a
    ; d : 'a [@bits 32]
    ; rd : 'a
    }
  [@@deriving sexp_of, hardcaml]
end

let used_bits = 3

module O = struct
  type 'a t =
    { q : 'a [@bits 32]
    ; full : 'a
    ; empty : 'a
    ; nearly_full : 'a
    ; nearly_empty : 'a
    ; used : 'a [@bits used_bits]
    }
  [@@deriving sexp_of, hardcaml]
end

open Hardcaml

let wrap ?(capacity = 4) ~create_fn (i : _ I.t) =
  let open Signal in
  assert (num_bits_to_represent capacity <= used_bits);
  let { Fifo.q; full; empty; nearly_full; nearly_empty; used } =
    create_fn ~capacity ~clock:i.clock ~clear:i.clear ~wr:i.wr ~d:i.d ~rd:i.rd
  in
  let o =
    { O.q; full; empty; nearly_full; nearly_empty; used = uresize used used_bits }
  in
  o
;;

let display_rules =
  Display_rule.(
    [ I.map I.port_names ~f:(port_name_is ~wave_format:(Bit_or Unsigned_int)) |> I.to_list
    ; O.map O.port_names ~f:(port_name_is ~wave_format:(Bit_or Unsigned_int)) |> O.to_list
    ; [ port_name_matches Re.Posix.(re ".*" |> compile) ~wave_format:(Bit_or Unsigned_int)
      ]
    ]
    |> List.concat)
;;

let fill_then_empty ?(wave_width = 1) (waves, sim) =
  let inputs : _ I.t = Cyclesim.inputs sim in
  let outputs : _ O.t = Cyclesim.outputs sim in
  inputs.clear := Bits.vdd;
  Cyclesim.cycle sim;
  inputs.clear := Bits.gnd;
  inputs.wr := Bits.vdd;
  let rec write i =
    if not (Bits.to_bool !(outputs.full))
    then (
      inputs.d := Bits.of_int ~width:32 ((i + 1) * 10);
      Cyclesim.cycle sim;
      write (i + 1))
    else i
  in
  let wr_count = write 0 in
  inputs.wr := Bits.gnd;
  inputs.d := Bits.of_int ~width:32 0;
  Cyclesim.cycle sim;
  inputs.rd := Bits.vdd;
  let rd_count = ref 0 in
  let timeout = ref 100 in
  while !rd_count <> wr_count && !timeout <> 0 do
    if Bits.is_gnd !(outputs.empty) then Int.incr rd_count;
    Cyclesim.cycle sim;
    Int.decr timeout
  done;
  inputs.rd := Bits.gnd;
  Cyclesim.cycle sim;
  Cyclesim.cycle sim;
  Waveform.print ~display_width:87 ~display_height:27 ~wave_width ~display_rules waves
;;

let%expect_test "classic" =
  let module Sim = Cyclesim.With_interface (I) (O) in
  wrap ~create_fn:(Fifo.create ~showahead:false ())
  |> Sim.create
  |> Waveform.create
  |> fill_then_empty;
  [%expect
    {|
    ┌Signals───────────┐┌Waves────────────────────────────────────────────────────────────┐
    │clock             ││┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌│
    │                  ││  └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘│
    │clear             ││────┐                                                            │
    │                  ││    └───────────────────────────────────────────                 │
    │wr                ││    ┌───────────────┐                                            │
    │                  ││────┘               └───────────────────────────                 │
    │                  ││────┬───┬───┬───┬───┬───────────────────────────                 │
    │d                 ││ 0  │10 │20 │30 │40 │0                                           │
    │                  ││────┴───┴───┴───┴───┴───────────────────────────                 │
    │rd                ││                        ┌───────────────┐                        │
    │                  ││────────────────────────┘               └───────                 │
    │                  ││────────────────────────────┬───┬───┬───┬───────                 │
    │q                 ││ 0                          │10 │20 │30 │40                      │
    │                  ││────────────────────────────┴───┴───┴───┴───────                 │
    │full              ││                    ┌───────┐                                    │
    │                  ││────────────────────┘       └───────────────────                 │
    │empty             ││    ┌───┐                               ┌───────                 │
    │                  ││────┘   └───────────────────────────────┘                        │
    │nearly_full       ││                ┌───────────────┐                                │
    │                  ││────────────────┘               └───────────────                 │
    │nearly_empty      ││    ┌───────┐                       ┌───────────                 │
    │                  ││────┘       └───────────────────────┘                            │
    │                  ││────────┬───┬───┬───┬───────┬───┬───┬───┬───────                 │
    │used              ││ 0      │1  │2  │3  │4      │3  │2  │1  │0                       │
    │                  ││────────┴───┴───┴───┴───────┴───┴───┴───┴───────                 │
    └──────────────────┘└─────────────────────────────────────────────────────────────────┘ |}]
;;

let%expect_test "showahead" =
  let module Sim = Cyclesim.With_interface (I) (O) in
  wrap ~create_fn:(Fifo.create ~showahead:true ())
  |> Sim.create
  |> Waveform.create
  |> fill_then_empty;
  [%expect
    {|
    ┌Signals───────────┐┌Waves────────────────────────────────────────────────────────────┐
    │clock             ││┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌│
    │                  ││  └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘│
    │clear             ││────┐                                                            │
    │                  ││    └───────────────────────────────────────────────────         │
    │wr                ││    ┌───────────────────┐                                        │
    │                  ││────┘                   └───────────────────────────────         │
    │                  ││────┬───┬───┬───┬───┬───┬───────────────────────────────         │
    │d                 ││ 0  │10 │20 │30 │40 │50 │0                                       │
    │                  ││────┴───┴───┴───┴───┴───┴───────────────────────────────         │
    │rd                ││                            ┌───────────────────┐                │
    │                  ││────────────────────────────┘                   └───────         │
    │                  ││────────┬───────────────────────┬───┬───┬───┬───┬───────         │
    │q                 ││ 0      │10                     │20 │30 │40 │50 │20              │
    │                  ││────────┴───────────────────────┴───┴───┴───┴───┴───────         │
    │full              ││                        ┌───────┐                                │
    │                  ││────────────────────────┘       └───────────────────────         │
    │empty             ││    ┌───┐                                       ┌───────         │
    │                  ││────┘   └───────────────────────────────────────┘                │
    │nearly_full       ││                    ┌───────────────┐                            │
    │                  ││────────────────────┘               └───────────────────         │
    │nearly_empty      ││    ┌───────┐                               ┌───────────         │
    │                  ││────┘       └───────────────────────────────┘                    │
    │                  ││────────┬───┬───┬───┬───┬───────┬───┬───┬───┬───┬───────         │
    │used              ││ 0      │1  │2  │3  │4  │5      │4  │3  │2  │1  │0               │
    │                  ││────────┴───┴───┴───┴───┴───────┴───┴───┴───┴───┴───────         │
    └──────────────────┘└─────────────────────────────────────────────────────────────────┘ |}]
;;

let%expect_test "classic with reg" =
  let module Sim = Cyclesim.With_interface (I) (O) in
  wrap ~create_fn:(Fifo.create_classic_with_extra_reg ())
  |> Sim.create
  |> Waveform.create
  |> fill_then_empty;
  [%expect
    {|
    ┌Signals───────────┐┌Waves────────────────────────────────────────────────────────────┐
    │clock             ││┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌│
    │                  ││  └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘│
    │clear             ││────┐                                                            │
    │                  ││    └─────────────────────────────────────────────────────────── │
    │wr                ││    ┌───────────────────────┐                                    │
    │                  ││────┘                       └─────────────────────────────────── │
    │                  ││────┬───┬───┬───┬───┬───┬───┬─────────────────────────────────── │
    │d                 ││ 0  │10 │20 │30 │40 │50 │60 │0                                   │
    │                  ││────┴───┴───┴───┴───┴───┴───┴─────────────────────────────────── │
    │rd                ││                                ┌───────────────────────┐        │
    │                  ││────────────────────────────────┘                       └─────── │
    │                  ││────────────────────────────────────┬───┬───┬───┬───┬───┬─────── │
    │q                 ││ 0                                  │10 │20 │30 │40 │50 │60      │
    │                  ││────────────────────────────────────┴───┴───┴───┴───┴───┴─────── │
    │full              ││                            ┌───────────┐                        │
    │                  ││────────────────────────────┘           └─────────────────────── │
    │empty             ││────────────┐                                           ┌─────── │
    │                  ││            └───────────────────────────────────────────┘        │
    │nearly_full       ││                        ┌───────────────────┐                    │
    │                  ││────────────────────────┘                   └─────────────────── │
    │nearly_empty      ││    ┌───────────────┐                           ┌─────────────── │
    │                  ││────┘               └───────────────────────────┘                │
    │                  ││────────┬───────────┬───┬───┬───────────┬───┬───┬───┬─────────── │
    │used              ││ 0      │1          │2  │3  │4          │3  │2  │1  │0           │
    │                  ││────────┴───────────┴───┴───┴───────────┴───┴───┴───┴─────────── │
    └──────────────────┘└─────────────────────────────────────────────────────────────────┘ |}]
;;

let%expect_test "showahead from classic" =
  let module Sim = Cyclesim.With_interface (I) (O) in
  wrap ~create_fn:(Fifo.create_showahead_from_classic ())
  |> Sim.create
  |> Waveform.create
  |> fill_then_empty;
  [%expect
    {|
    ┌Signals───────────┐┌Waves────────────────────────────────────────────────────────────┐
    │clock             ││┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌│
    │                  ││  └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘│
    │clear             ││────┐                                                            │
    │                  ││    └───────────────────────────────────────────────────         │
    │wr                ││    ┌───────────────────┐                                        │
    │                  ││────┘                   └───────────────────────────────         │
    │                  ││────┬───┬───┬───┬───┬───┬───────────────────────────────         │
    │d                 ││ 0  │10 │20 │30 │40 │50 │0                                       │
    │                  ││────┴───┴───┴───┴───┴───┴───────────────────────────────         │
    │rd                ││                            ┌───────────────────┐                │
    │                  ││────────────────────────────┘                   └───────         │
    │                  ││────────────┬───────────────────┬───┬───┬───┬───────────         │
    │q                 ││ 0          │10                 │20 │30 │40 │50                  │
    │                  ││────────────┴───────────────────┴───┴───┴───┴───────────         │
    │full              ││                        ┌───────┐                                │
    │                  ││────────────────────────┘       └───────────────────────         │
    │empty             ││────────────┐                                   ┌───────         │
    │                  ││            └───────────────────────────────────┘                │
    │nearly_full       ││                    ┌───────────────┐                            │
    │                  ││────────────────────┘               └───────────────────         │
    │nearly_empty      ││    ┌───────────┐                       ┌───────────────         │
    │                  ││────┘           └───────────────────────┘                        │
    │                  ││────────┬───────┬───┬───┬───────┬───┬───┬───┬───────────         │
    │used              ││ 0      │1      │2  │3  │4      │3  │2  │1  │0                   │
    │                  ││────────┴───────┴───┴───┴───────┴───┴───┴───┴───────────         │
    └──────────────────┘└─────────────────────────────────────────────────────────────────┘ |}]
;;

let%expect_test "showahead with extra reg" =
  let module Sim = Cyclesim.With_interface (I) (O) in
  wrap ~create_fn:(Fifo.create_showahead_with_extra_reg ())
  |> Sim.create
  |> Waveform.create
  |> fill_then_empty;
  [%expect
    {|
    ┌Signals───────────┐┌Waves────────────────────────────────────────────────────────────┐
    │clock             ││┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌│
    │                  ││  └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘│
    │clear             ││────┐                                                            │
    │                  ││    └────────────────────────────────────────────────────────────│
    │wr                ││    ┌───────────────────────────┐                                │
    │                  ││────┘                           └────────────────────────────────│
    │                  ││────┬───┬───┬───┬───┬───┬───┬───┬────────────────────────────────│
    │d                 ││ 0  │10 │20 │30 │40 │50 │60 │70 │0                               │
    │                  ││────┴───┴───┴───┴───┴───┴───┴───┴────────────────────────────────│
    │rd                ││                                    ┌───────────────────────────┐│
    │                  ││────────────────────────────────────┘                           └│
    │                  ││────────────────┬───────────────────────┬───┬───┬───┬───┬───┬────│
    │q                 ││ 0              │10                     │20 │30 │40 │50 │60 │70  │
    │                  ││────────────────┴───────────────────────┴───┴───┴───┴───┴───┴────│
    │full              ││                                ┌───────────┐                    │
    │                  ││────────────────────────────────┘           └────────────────────│
    │empty             ││────────────────┐                                               ┌│
    │                  ││                └───────────────────────────────────────────────┘│
    │nearly_full       ││                            ┌───────────────────┐                │
    │                  ││────────────────────────────┘                   └────────────────│
    │nearly_empty      ││    ┌───────────────────┐                           ┌────────────│
    │                  ││────┘                   └───────────────────────────┘            │
    │                  ││────────┬───────────────┬───┬───┬───────────┬───┬───┬───┬────────│
    │used              ││ 0      │1              │2  │3  │4          │3  │2  │1  │0       │
    │                  ││────────┴───────────────┴───┴───┴───────────┴───┴───┴───┴────────│
    └──────────────────┘└─────────────────────────────────────────────────────────────────┘ |}]
;;

let%expect_test "non-default nearly empty/full threshold values" =
  let module Sim = Cyclesim.With_interface (I) (O) in
  wrap ~create_fn:(Fifo.create ~showahead:true ~nearly_empty:2 ~nearly_full:1 ())
  |> Sim.create
  |> Waveform.create
  |> fill_then_empty;
  [%expect
    {|
    ┌Signals───────────┐┌Waves────────────────────────────────────────────────────────────┐
    │clock             ││┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌│
    │                  ││  └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘│
    │clear             ││────┐                                                            │
    │                  ││    └───────────────────────────────────────────────────         │
    │wr                ││    ┌───────────────────┐                                        │
    │                  ││────┘                   └───────────────────────────────         │
    │                  ││────┬───┬───┬───┬───┬───┬───────────────────────────────         │
    │d                 ││ 0  │10 │20 │30 │40 │50 │0                                       │
    │                  ││────┴───┴───┴───┴───┴───┴───────────────────────────────         │
    │rd                ││                            ┌───────────────────┐                │
    │                  ││────────────────────────────┘                   └───────         │
    │                  ││────────┬───────────────────────┬───┬───┬───┬───┬───────         │
    │q                 ││ 0      │10                     │20 │30 │40 │50 │20              │
    │                  ││────────┴───────────────────────┴───┴───┴───┴───┴───────         │
    │full              ││                        ┌───────┐                                │
    │                  ││────────────────────────┘       └───────────────────────         │
    │empty             ││    ┌───┐                                       ┌───────         │
    │                  ││────┘   └───────────────────────────────────────┘                │
    │nearly_full       ││        ┌───────────────────────────────────────┐                │
    │                  ││────────┘                                       └───────         │
    │nearly_empty      ││    ┌───────────┐                       ┌───────────────         │
    │                  ││────┘           └───────────────────────┘                        │
    │                  ││────────┬───┬───┬───┬───┬───────┬───┬───┬───┬───┬───────         │
    │used              ││ 0      │1  │2  │3  │4  │5      │4  │3  │2  │1  │0               │
    │                  ││────────┴───┴───┴───┴───┴───────┴───┴───┴───┴───┴───────         │
    └──────────────────┘└─────────────────────────────────────────────────────────────────┘ |}]
;;

let%expect_test "showahead with read_latency" =
  let module Sim = Cyclesim.With_interface (I) (O) in
  wrap ~capacity:3 ~create_fn:(Fifo.create_showahead_with_read_latency ~read_latency:5 ())
  |> Sim.create
  |> Waveform.create
  |> fill_then_empty ~wave_width:0;
  [%expect
    {|
    ┌Signals───────────┐┌Waves────────────────────────────────────────────────────────────┐
    │clock             ││┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌│
    │                  ││ └┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘│
    │clear             ││──┐                                                              │
    │                  ││  └───────────────────────────────────────────────────────       │
    │wr                ││  ┌───────┐                                                      │
    │                  ││──┘       └───────────────────────────────────────────────       │
    │                  ││──┬─┬─┬─┬─┬───────────────────────────────────────────────       │
    │d                 ││ 0│.│.│.│.│0                                                     │
    │                  ││──┴─┴─┴─┴─┴───────────────────────────────────────────────       │
    │rd                ││            ┌─────────────────────────────────────────┐          │
    │                  ││────────────┘                                         └───       │
    │                  ││────────────────┬───────────┬───────────┬───────────┬─────       │
    │q                 ││ 0              │10         │20         │30         │40          │
    │                  ││────────────────┴───────────┴───────────┴───────────┴─────       │
    │full              ││          ┌───────┐                                              │
    │                  ││──────────┘       └───────────────────────────────────────       │
    │empty             ││────────────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌───       │
    │                  ││                └─┘         └─┘         └─┘         └─┘          │
    │nearly_full       ││        ┌─────────────────────┐                                  │
    │                  ││────────┘                     └───────────────────────────       │
    │nearly_empty      ││  ┌─────┐                     ┌───────────────────────────       │
    │                  ││──┘     └─────────────────────┘                                  │
    │                  ││────┬─┬─┬─┬───────┬───────────┬───────────┬───────────┬───       │
    │used              ││ 0  │1│2│3│4      │3          │2          │1          │0         │
    │                  ││────┴─┴─┴─┴───────┴───────────┴───────────┴───────────┴───       │
    └──────────────────┘└─────────────────────────────────────────────────────────────────┘ |}]
;;
