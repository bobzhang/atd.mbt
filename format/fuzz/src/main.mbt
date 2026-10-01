// Driver for the differential fuzzing of bobzhang/format: run a script of
// pretty-printing operations (read on stdin) and print the result. This is
// the MoonBit counterpart of `driver.ml`, see README.md.

///|
fn unhex(s : String) -> String {
  if s == "-" {
    return ""
  }
  let bytes = FixedArray::make(s.length() / 2, b'\x00')
  for i in 0..<bytes.length() {
    let byte = @string.parse_int(
      s.view(start_offset=2 * i, end_offset=2 * i + 2),
      base=16,
    ) catch {
      _ => abort("bad hex string \{s}")
    }
    bytes[i] = byte.to_byte()
  }
  @utf8.decode(Bytes::from_array(bytes)) catch {
    _ => abort("invalid UTF-8 in \{s}")
  }
}

///|
fn int(s : String) -> Int {
  @string.parse_int(s) catch {
    _ => abort("bad integer \{s}")
  }
}

///|
fn int64(s : String) -> Int64 {
  @string.parse_int64(s) catch {
    _ => abort("bad integer \{s}")
  }
}

///|
fn float_of_bits(s : String) -> Double {
  let bits = @string.parse_uint64(s, base=16) catch {
    _ => abort("bad float \{s}")
  }
  bits.reinterpret_as_double()
}

///|
/// The arguments of `%a` and `%t`, like in `driver.ml`.
fn alpha(s : String) -> @format.Arg {
  Print(ppf => ppf.printf("@[<1>%s@ %s@]", [String(s), String(s)]))
}

///|
fn theta(s : String) -> @format.Arg {
  Print(ppf => ppf.printf("@[<hov 2>%s@,%s@]", [String(s), String(s)]))
}

///|
fn arg(a : String) -> @format.Arg {
  let v = a.view(start_offset=2).to_owned()
  match a[0] {
    'i' => Int(int(v))
    'l' => Int32(int(v))
    'L' | 'n' => Int64(int64(v))
    'f' => Float(float_of_bits(v))
    's' => String(unhex(v))
    'c' => Char(int(v).unsafe_to_char())
    'b' => Bool(v == "1")
    'a' => alpha(unhex(v))
    't' => theta(unhex(v))
    'F' | 'P' => Format(unhex(v))
    _ => abort("bad argument \{a}")
  }
}

///|
fn run(ppf : @format.Formatter, line : String) -> Unit {
  let words = line.split(" ").map(w => w.to_owned()).collect()
  match words {
    [""] => ()
    ["margin", n] => ppf.set_margin(int(n))
    ["max_indent", n] => ppf.set_max_indent(int(n))
    ["max_boxes", n] => ppf.set_max_boxes(int(n))
    ["ellipsis", s] => ppf.set_ellipsis_text(unhex(s))
    ["mark_tags", b] => ppf.set_mark_tags(b == "1")
    ["box", "b", n] => ppf.open_box(int(n))
    ["box", "h", _] => ppf.open_hbox()
    ["box", "v", n] => ppf.open_vbox(int(n))
    ["box", "hv", n] => ppf.open_hvbox(int(n))
    ["box", "hov", n] => ppf.open_hovbox(int(n))
    ["close"] => ppf.close_box()
    ["str", s] => ppf.print_string(unhex(s))
    ["as", n, s] => ppf.print_as(int(n), unhex(s))
    ["int", n] => ppf.print_int(int(n))
    ["char", n] => ppf.print_char(int(n).unsafe_to_char())
    ["bool", b] => ppf.print_bool(b == "1")
    ["float", f] => ppf.print_float(float_of_bits(f))
    ["break", w, o] => ppf.print_break(int(w), int(o))
    ["custom", s1, w, s2, s3, o, s4] =>
      ppf.print_custom_break(
        fits=(unhex(s1), int(w), unhex(s2)),
        breaks=(unhex(s3), int(o), unhex(s4)),
      )
    ["space"] => ppf.print_space()
    ["cut"] => ppf.print_cut()
    ["force_newline"] => ppf.force_newline()
    ["if_newline"] => ppf.print_if_newline()
    ["flush"] => ppf.print_flush()
    ["newline"] => ppf.print_newline()
    ["tbox"] => ppf.open_tbox()
    ["tclose"] => ppf.close_tbox()
    ["set_tab"] => ppf.set_tab()
    ["tab"] => ppf.print_tab()
    ["tbreak", w, o] => ppf.print_tbreak(int(w), int(o))
    ["tag", s] => ppf.open_stag(StringTag(unhex(s)))
    ["ctag"] => ppf.close_stag()
    ["text", s] => ppf.print_text(unhex(s))
    ["check", fmt] => {
      let msg = try {
        @format.check_format(unhex(fmt))
        "ok"
      } catch {
        Failure(msg) => msg
      }
      ppf.print_string(msg)
      ppf.force_newline()
    }
    ["printf", fmt, .. args] =>
      ppf.printf(unhex(fmt), args.iter().map(arg).collect())
    _ => abort("bad operation \{line}")
  }
}

///|
async fn main {
  let script = @stdio.stdin.read_all().binary()
  let script = String::from_array(script.iter().map(b => b.to_char()).collect())
  let buf = StringBuilder()
  let ppf = @format.Formatter::of_buffer(buf)
  for line in script.split("\n") {
    run(ppf, line.to_owned())
  }
  ppf.print_flush()
  @stdio.stdout.write(buf.to_string())
}
