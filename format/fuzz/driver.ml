(* Reference driver for the differential fuzzing of bobzhang/format: run a
   script of pretty-printing operations (read on stdin) with OCaml's Format
   and print the result.

   Build: ocamlfind ocamlopt driver.ml -o driver.exe

   The script has one operation per line, see README.md. Strings are
   hex-encoded ("-" for the empty string). *)

open CamlinternalFormatBasics

let unhex s =
  if s = "-" then ""
  else
    String.init (String.length s / 2) (fun i ->
        Char.chr (int_of_string ("0x" ^ String.sub s (2 * i) 2)))

let format_of_string_exn s : (Obj.t, Format.formatter, unit) format =
  let (CamlinternalFormat.Fmt_EBB fmt) =
    CamlinternalFormat.fmt_ebb_of_string ~legacy_behavior:true s
  in
  Obj.magic (Format (fmt, s))

let alpha ppf s = Format.fprintf ppf "@[<1>%s@ %s@]" s s
let theta s ppf = Format.fprintf ppf "@[<hov 2>%s@,%s@]" s s

(* The OCaml values of an argument (two for %a). *)
let arg a : Obj.t list =
  let tag = a.[0] and v = String.sub a 2 (String.length a - 2) in
  match tag with
  | 'i' -> [ Obj.repr (int_of_string v) ]
  | 'l' -> [ Obj.repr (Int32.of_string v) ]
  | 'L' -> [ Obj.repr (Int64.of_string v) ]
  | 'n' -> [ Obj.repr (Nativeint.of_string v) ]
  | 'f' -> [ Obj.repr (Int64.float_of_bits (Int64.of_string ("0x" ^ v))) ]
  | 's' -> [ Obj.repr (unhex v) ]
  | 'c' -> [ Obj.repr (Char.chr (int_of_string v)) ]
  | 'b' -> [ Obj.repr (v = "1") ]
  | 'a' -> [ Obj.repr alpha; Obj.repr (unhex v) ]
  | 't' -> [ Obj.repr (theta (unhex v)) ]
  | 'F' | 'P' -> [ Obj.repr (format_of_string_exn (unhex v)) ]
  | _ -> failwith ("bad argument " ^ a)

let printf ppf fmt args =
  let f = Format.fprintf ppf (format_of_string_exn fmt) in
  let args = List.concat_map arg args in
  ignore
    (List.fold_left (fun f a -> (Obj.magic f : Obj.t -> Obj.t) a) f args)

let box ppf kind n =
  match kind with
  | "b" -> Format.pp_open_box ppf n
  | "h" -> Format.pp_open_hbox ppf ()
  | "v" -> Format.pp_open_vbox ppf n
  | "hv" -> Format.pp_open_hvbox ppf n
  | "hov" -> Format.pp_open_hovbox ppf n
  | _ -> failwith ("bad box " ^ kind)

let run ppf line =
  let i = int_of_string in
  match String.split_on_char ' ' line with
  | [ "" ] -> ()
  | [ "margin"; n ] -> Format.pp_set_margin ppf (i n)
  | [ "max_indent"; n ] -> Format.pp_set_max_indent ppf (i n)
  | [ "max_boxes"; n ] -> Format.pp_set_max_boxes ppf (i n)
  | [ "ellipsis"; s ] -> Format.pp_set_ellipsis_text ppf (unhex s)
  | [ "mark_tags"; b ] -> Format.pp_set_mark_tags ppf (b = "1")
  | [ "box"; k; n ] -> box ppf k (i n)
  | [ "close" ] -> Format.pp_close_box ppf ()
  | [ "str"; s ] -> Format.pp_print_string ppf (unhex s)
  | [ "as"; n; s ] -> Format.pp_print_as ppf (i n) (unhex s)
  | [ "int"; n ] -> Format.pp_print_int ppf (i n)
  | [ "char"; n ] -> Format.pp_print_char ppf (Char.chr (i n))
  | [ "bool"; b ] -> Format.pp_print_bool ppf (b = "1")
  | [ "float"; f ] ->
      Format.pp_print_float ppf (Int64.float_of_bits (Int64.of_string ("0x" ^ f)))
  | [ "break"; w; o ] -> Format.pp_print_break ppf (i w) (i o)
  | [ "custom"; s1; w; s2; s3; o; s4 ] ->
      Format.pp_print_custom_break ppf
        ~fits:(unhex s1, i w, unhex s2)
        ~breaks:(unhex s3, i o, unhex s4)
  | [ "space" ] -> Format.pp_print_space ppf ()
  | [ "cut" ] -> Format.pp_print_cut ppf ()
  | [ "force_newline" ] -> Format.pp_force_newline ppf ()
  | [ "if_newline" ] -> Format.pp_print_if_newline ppf ()
  | [ "flush" ] -> Format.pp_print_flush ppf ()
  | [ "newline" ] -> Format.pp_print_newline ppf ()
  | [ "tbox" ] -> Format.pp_open_tbox ppf ()
  | [ "tclose" ] -> Format.pp_close_tbox ppf ()
  | [ "set_tab" ] -> Format.pp_set_tab ppf ()
  | [ "tab" ] -> Format.pp_print_tab ppf ()
  | [ "tbreak"; w; o ] -> Format.pp_print_tbreak ppf (i w) (i o)
  | [ "tag"; s ] -> Format.pp_open_stag ppf (Format.String_tag (unhex s))
  | [ "ctag" ] -> Format.pp_close_stag ppf ()
  | [ "text"; s ] -> Format.pp_print_text ppf (unhex s)
  | [ "check"; fmt ] ->
      let msg =
        match
          CamlinternalFormat.fmt_ebb_of_string ~legacy_behavior:true (unhex fmt)
        with
        | _ -> "ok"
        | exception Failure msg -> msg
      in
      Format.pp_print_string ppf msg;
      Format.pp_force_newline ppf ()
  | "printf" :: fmt :: args -> printf ppf (unhex fmt) args
  | _ -> failwith ("bad operation " ^ line)

let () =
  let buf = Buffer.create 1024 in
  let ppf = Format.formatter_of_buffer buf in
  (try
     while true do
       run ppf (input_line stdin)
     done
   with End_of_file -> ());
  Format.pp_print_flush ppf ();
  print_string (Buffer.contents buf)
