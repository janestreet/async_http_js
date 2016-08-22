open Core_kernel.Std
open Async_kernel.Std
open Js_of_ocaml
open Js_of_ocaml_async
open Async_http_js
open Virtual_dom.Std

let set ~key ~value =
  Deferred.map ~f:(fun res ->
    Sexp.of_string_conv_exn (Or_error.ok_exn res)
      Unit.t_of_sexp)
    (Http.get
      ~arguments:[("key", key); ("value", value)]
      "http://localhost:8000/set")
;;

let get k =
  Deferred.Result.map ~f:(fun s ->
    Sexp.of_string_conv_exn s (Option.t_of_sexp String.t_of_sexp))
    (Http.get
      ~arguments:[("key", k)]
      "http://localhost:8000/get")
;;

type state =
  { key   : string
  ; value : string
  }

type update =
  | New_value of string
  | Set_value

let style props =
  Vdom.Attr.create "style"
    (String.concat ~sep:";"
       (List.map ~f:(fun (n, v) -> sprintf "%s:%s" n v) props))
;;

let event_reader, event_writer = Pipe.create ()

module Event = Vdom.Event.Define
    (struct
      module Action = struct
        type t = update
      end

      let handle = Pipe.write_without_pushback event_writer
    end)

let inject = Event.inject

let view state =
  let open Vdom in
  Node.body []
    [ Node.div
        [ Attr.style [ "width", "100%"; "height", "100%" ]
        ; Attr.create "tabindex" "1"
        ]
        [ Node.h2 [] [Node.text "Value"]
        ; Node.input
            [ Attr.create "type" "text"
            ; Attr.create "value" state.value
            ; Attr.id "entry"
            ]
            []
        ; Node.button
            [ Attr.on_click (fun _e -> inject Set_value)
            ]
            [Node.text "set the value"]
        ]
    ]
;;

let update u state =
  match u with
  | New_value v ->
    { state with value = v }
  | Set_value ->
    Js.Opt.iter (Dom_html.(CoerceTo.input (getElementById "entry")))
      (fun input ->
         let value = Js.to_string input##.value in
         don't_wait_for (
           set ~key:state.key ~value
           >>| fun () ->
           Pipe.write_without_pushback event_writer (New_value value)
         )
      );
    state
;;

let run_app ~initial_state ~updates ~view =
  let state = ref initial_state in
  let vdom = ref (view initial_state) in
  let elt = ref (Vdom.Node.to_dom !vdom :> Dom.element Js.t) in
  Dom_html.document##.body := (Js.Unsafe.coerce !elt : Dom_html.bodyElement Js.t);
  Pipe.iter updates ~f:(fun u ->
    state := update u !state;
    let new_vdom = view !state in
    let module Patch = Vdom.Node.Patch in
    elt := Patch.apply (Patch.create ~previous:!vdom ~current:new_vdom) !elt;
    vdom := new_vdom;
    Deferred.unit
  ) |> don't_wait_for
;;

let () =
  Async_js.init ();
  Dom_html.window##.onload := Dom_html.handler (fun _ev ->
    don't_wait_for (
      get "value" >>= fun res ->
      let view, value_opt =
        match res with
        | Error e ->
          let open Vdom in
          ((fun _ ->
             Node.body [] [Node.text (Error.to_string_hum e)])
          , None)
        | Ok value_opt ->
          (view, value_opt)
      in
      run_app
        ~view
        ~updates:event_reader
        ~initial_state:
          { value = Option.value ~default:"" value_opt
          ; key = "value"
          };
      Deferred.unit
    );
    Js.bool true)
;;

