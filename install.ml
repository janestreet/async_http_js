#use "topfind";;
#require "js-build-tools.oasis2opam_install";;

open Oasis2opam_install;;

generate ~package:"async_http_js"
  [ oasis_lib "async_http_js"
  ; file "META" ~section:"lib"
  ; file "_build/namespace_wrappers/js_of_ocaml.cmi" ~section:"lib"
  ]
