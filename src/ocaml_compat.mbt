// Helpers reproducing the behavior of a few OCaml standard library
// functions whose exact output matters (error messages, printing).

///|
/// Iterate over the UTF-8 encoding of a string.
fn utf8_bytes(s : StringView, f : (Int) -> Unit) -> Unit {
  for c in s {
    let code = c.to_int()
    if code < 0x80 {
      f(code)
    } else if code < 0x800 {
      f(0xC0 | (code >> 6))
      f(0x80 | (code & 0x3F))
    } else if code < 0x10000 {
      f(0xE0 | (code >> 12))
      f(0x80 | ((code >> 6) & 0x3F))
      f(0x80 | (code & 0x3F))
    } else {
      f(0xF0 | (code >> 18))
      f(0x80 | ((code >> 12) & 0x3F))
      f(0x80 | ((code >> 6) & 0x3F))
      f(0x80 | (code & 0x3F))
    }
  }
}

///|
/// OCaml's `String.escaped`, applied to the UTF-8 encoding of `s`.
pub fn ocaml_escaped(s : StringView) -> String {
  let buf = StringBuilder()
  utf8_bytes(s, b => {
    match b {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\t' => buf.write_string("\\t")
      '\r' => buf.write_string("\\r")
      '\b' => buf.write_string("\\b")
      0x20..=0x7E => buf.write_char(b.unsafe_to_char())
      _ => {
        buf.write_char('\\')
        buf.write_char((b / 100 + 48).unsafe_to_char())
        buf.write_char((b / 10 % 10 + 48).unsafe_to_char())
        buf.write_char((b % 10 + 48).unsafe_to_char())
      }
    }
  })
  buf.to_string()
}

///|
/// OCaml's `Printf.sprintf "%S"`.
pub fn ocaml_quote(s : StringView) -> String {
  "\"" + ocaml_escaped(s) + "\""
}

///|
/// Compare strings like OCaml's `String.compare`, i.e. by UTF-8 bytes,
/// which is the same as comparing code points.
pub fn compare_strings(a : StringView, b : StringView) -> Int {
  let ia = a.iter()
  let ib = b.iter()
  for ;; {
    match (ia.next(), ib.next()) {
      (None, None) => break 0
      (None, Some(_)) => break -1
      (Some(_), None) => break 1
      (Some(x), Some(y)) => if x != y { break x.to_int().compare(y.to_int()) }
    }
  }
}

///|
/// Compare string lists like OCaml's polymorphic comparison.
pub fn compare_string_lists(
  a : ArrayView[String],
  b : ArrayView[String],
) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let c = compare_strings(a[i], b[i])
    if c != 0 {
      return c
    }
  }
  a.length().compare(b.length())
}
