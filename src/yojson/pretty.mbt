// Pretty-printing of JSON data, reproducing the output of
// `Yojson.Safe.pretty_to_string` (Yojson 2.x):
//
// 1. What fits on one line stays on one line.
// 2. What doesn't fit on one line gets printed more vertically so as to not
//    exceed a reasonable page width, if possible.
//
// Arrays containing only atoms are wrapped like ordinary text.

///|
/// Escape a string as a JSON string literal, like Yojson.
pub fn json_string_of_string(s : String) -> String {
  let buf = StringBuilder()
  buf.write_char('"')
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\b' => buf.write_string("\\b")
      '\u{0C}' => buf.write_string("\\f")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\u{00}'..='\u{1F}' | '\u{7F}' => {
        let code = c.to_int()
        let hex = "0123456789abcdef"
        buf.write_string("\\u00")
        buf.write_char(hex[code >> 4].unsafe_to_char())
        buf.write_char(hex[code & 0xF].unsafe_to_char())
      }
      c => buf.write_char(c)
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
/// Print a number: integral values are printed as integers, other values
/// using their exact representation if available.
pub fn json_string_of_number(x : Double, repr : String?) -> String {
  match repr {
    Some(r) => r
    None =>
      if x == x.floor() && x.abs() < 1.0e15 {
        x.to_int64().to_string()
      } else {
        x.to_string()
      }
  }
}

///|
fn is_atom(x : Json) -> Bool {
  match x {
    Null | True | False | Number(_) | String(_) => true
    Array(l) => l.is_empty()
    Object(l) => l.is_empty()
  }
}

///|
fn pp_list(
  out : @format.Formatter,
  l : ArrayView[Json],
  f : (Json) -> Unit,
) -> Unit {
  for i, x in l {
    if i > 0 {
      out.print_string(",")
      out.print_space()
    }
    f(x)
  }
}

///|
fn format(out : @format.Formatter, inside_box : Bool, x : Json) -> Unit {
  match x {
    Null => out.print_string("null")
    True => out.print_string("true")
    False => out.print_string("false")
    Number(n, repr~) => out.print_string(json_string_of_number(n, repr))
    String(s) => out.print_string(json_string_of_string(s))
    Array([]) => out.print_string("[]")
    Array(l) => {
      if !inside_box {
        out.open_hvbox(2)
      }
      out.print_string("[")
      out.print_break(1, 0)
      if l.iter().all(is_atom) {
        out.open_hovbox(0)
      } else {
        out.open_hvbox(0)
      }
      pp_list(out, l, x => format(out, false, x))
      out.close_box()
      out.print_break(1, -2)
      out.print_string("]")
      if !inside_box {
        out.close_box()
      }
    }
    Object(l) =>
      if l.is_empty() {
        out.print_string("{}")
      } else {
        if !inside_box {
          out.open_hvbox(2)
        }
        out.print_string("{")
        out.print_break(1, 0)
        let mut first = true
        for k, v in l {
          if !first {
            out.print_string(",")
            out.print_space()
          }
          first = false
          out.open_hvbox(2)
          out.print_string(json_string_of_string(k))
          out.print_string(": ")
          format(out, true, v)
          out.close_box()
        }
        out.print_break(1, -2)
        out.print_string("}")
        if !inside_box {
          out.close_box()
        }
      }
  }
}

///|
/// Pretty-print JSON data like `Yojson.Safe.pretty_to_string`.
pub fn pretty_to_string(x : Json) -> String {
  let out = @format.Formatter::new()
  out.open_hvbox(2)
  format(out, true, x)
  out.close_box()
  out.print_flush()
  out.contents()
}
