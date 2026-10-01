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
/// A JSON value like Yojson's: objects are association lists, which
/// preserve the order and the duplicates of their keys.
pub(all) enum Value {
  Null
  Bool(Bool)
  Int(Int64)
  Float(Double)
  String(String)
  List(Array[Value])
  Assoc(Array[(String, Value)])
} derive(Eq, Debug)

///|
/// Convert from MoonBit's `Json`.
pub fn Value::of_json(x : Json) -> Value {
  match x {
    Null => Null
    True => Bool(true)
    False => Bool(false)
    Number(n, repr=Some(r)) =>
      // keep the exact representation of integers
      if r.iter().all(c => (c >= '0' && c <= '9') || c == '-') &&
        n == n.floor() &&
        n.abs() < 9.0e18 {
        Int(n.to_int64())
      } else {
        Float(n)
      }
    Number(n, repr=None) =>
      if n == n.floor() && n.abs() < 1.0e15 {
        Int(n.to_int64())
      } else {
        Float(n)
      }
    String(s) => String(s)
    Array(l) => List(l.map(Value::of_json))
    Object(m) =>
      Assoc(m.iter().map(kv => (kv.0, Value::of_json(kv.1))).collect())
  }
}

///|
/// Convert to MoonBit's `Json`. Duplicate keys of objects are lost: the
/// last value is kept.
pub fn Value::to_json(self : Value) -> Json {
  match self {
    Null => Json::null()
    Bool(b) => Json::boolean(b)
    Int(n) => Json::number(n.to_double(), repr=n.to_string())
    Float(x) => Json::number(x)
    String(s) => Json::string(s)
    List(l) => Json::array(l.map(Value::to_json))
    Assoc(l) => {
      let m : Map[String, Json] = Map([])
      for kv in l {
        m[kv.0] = kv.1.to_json()
      }
      Json::object(m)
    }
  }
}

///|
fn is_atom(x : Value) -> Bool {
  match x {
    Null | Bool(_) | Int(_) | Float(_) | String(_) => true
    List(l) => l.is_empty()
    Assoc(l) => l.is_empty()
  }
}

///|
fn pp_list(
  out : @format.Formatter,
  l : ArrayView[Value],
  f : (Value) -> Unit,
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
fn format(out : @format.Formatter, inside_box : Bool, x : Value) -> Unit {
  match x {
    Null => out.print_string("null")
    Bool(b) => out.print_string(if b { "true" } else { "false" })
    Int(n) => out.print_string(n.to_string())
    Float(x) => out.print_string(json_string_of_number(x, None))
    String(s) => out.print_string(json_string_of_string(s))
    List([]) => out.print_string("[]")
    List(l) => {
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
    Assoc([]) => out.print_string("{}")
    Assoc(l) => {
      if !inside_box {
        out.open_hvbox(2)
      }
      out.print_string("{")
      out.print_break(1, 0)
      for i, kv in l {
        if i > 0 {
          out.print_string(",")
          out.print_space()
        }
        out.open_hvbox(2)
        out.print_string(json_string_of_string(kv.0))
        out.print_string(": ")
        format(out, true, kv.1)
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
pub fn pretty_to_string(x : Value) -> String {
  let buf = StringBuilder()
  let out = @format.Formatter::of_buffer(buf)
  out.open_hvbox(2)
  format(out, true, x)
  out.close_box()
  out.print_flush()
  buf.to_string()
}

///|
/// Pretty-print MoonBit's `Json` like `Yojson.Safe.pretty_to_string`.
pub fn pretty_json_to_string(x : Json) -> String {
  pretty_to_string(Value::of_json(x))
}
