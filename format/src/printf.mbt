// printf-like functions: format strings with conversions (`%d`, `%s`,
// ...) and pretty-printing directives (`@[`, `@]`, `@ `, ...), a port of
// OCaml's `Format.fprintf` & co and of the format string parser of
// `camlinternalFormat.ml` (in the default, legacy mode used by the OCaml
// compiler).
//
// Since MoonBit has no typed format strings, the format is parsed at run
// time and the arguments are given as an array of `Arg`. Invalid formats
// and arguments that don't match the format are programming errors, like
// type errors in OCaml: they abort.
//
// Copyright 1996 Institut National de Recherche en Informatique et en
// Automatique (OCaml), distributed under the terms of the GNU Lesser
// General Public License version 2.1, with the special exception on
// linking described in the file LICENSE.

///|
/// An argument of a printf-like function.
pub(all) enum Arg {
  /// `%d`, `%i`, `%u`, `%x`, `%X`, `%o` (with OCaml's 63-bit `int`
  /// semantics for unsigned conversions of negative numbers), widths and
  /// precisions given by `*`, and `%N`, `%l`, `%n`, `%L` used alone
  Int(Int)
  /// `%ld`, `%li`, ... (32-bit integers)
  Int32(Int)
  /// `%Ld`, `%nd`, ... (64-bit integers)
  Int64(Int64)
  /// `%f`, `%e`, `%E`, `%g`, `%G`, `%F`, `%h`, `%H`
  Float(Double)
  /// `%s`, `%S`
  String(String)
  /// `%c`, `%C`
  Char(Char)
  /// `%b`, `%B`
  Bool(Bool)
  /// `%a` and `%t`: a function printing on the formatter (OCaml's `%a`
  /// takes a printer and a value; here, the printer is already applied to
  /// its value)
  Print((Formatter) -> Unit)
  /// `%{ fmt %}` and `%( fmt %)`: a format string
  Format(String)
}

///|
priv enum Pad {
  NoPad
  LitPad(PadTy, Int)
  ArgPad(PadTy)
}

///|
priv enum Prec {
  NoPrec
  LitPrec(Int)
  ArgPrec
}

///|
priv enum FloatKind {
  /// `%f`, `%e`, `%E`, `%g`, `%G`
  FC(Char)
  /// `%F`
  FF
  /// `%#F`
  FCF
  /// `%h`
  FH
  /// `%H`
  FHU
}

///|
priv enum Conv {
  CChar
  CCamlChar
  CString
  CCamlString
  CInt(IntSize, Char, Bool, Bool, Bool, Bool) // size, conv, plus, space, alt, group
  CFloat(Char, FloatKind) // sign flag, kind
  CBool
  CAlpha
  CTheta
}

///|
priv enum FmtLit {
  CloseBox
  CloseTag
  BreakHint(Int, Int)
  FFlush
  ForceNewline
  FlushNewline
  MagicSize(Int)
  EscapedAt
  EscapedPercent
  ScanIndic(Char)
}

///|
priv enum Item {
  Lit(String)
  Conversion(Conv, Pad, Prec)
  Flush
  Formatting(FmtLit)
  OpenBoxGen(Array[Item])
  OpenTagGen(Array[Item])
  /// `%{ fmt %}`: consumes a format, prints the signature of `fmt`
  FormatArg(String)
  /// `%( fmt %)`: consumes a format and prints it with the next arguments
  /// (the signature of `fmt`)
  FormatSubst(String)
  /// `%N`, `%l`, `%n`, `%L` alone: consumes an int, prints it as `%u`
  ScanCounter
  /// `%_d`, `%[...]`, `%r`...: an error when output (the message, and the
  /// signature of the item)
  Invalid(String, String)
}

///|
/// OCaml's `%S`: a string in OCaml syntax.
fn string_to_caml_string(s : String) -> String {
  "\"" + string_escaped(s) + "\""
}

///|
/// OCaml's `%C`: a character in OCaml syntax.
fn caml_char(c : Char) -> String {
  "'" + char_escaped(c) + "'"
}

///|
/// Parse a box description such as `<hov 2>`, like OCaml's
/// `open_box_of_string` (the angle brackets are already removed).
fn open_box_of_string(str : String) -> (Int, BoxType) raise FormatError {
  if str == "" {
    return (0, Box)
  }
  let len = str.length()
  let invalid_box = () => {
    FormatError("invalid box description \{string_to_caml_string(str)}")
  }
  let mut i = 0
  while i < len && (str[i] == ' ' || str[i] == '\t') {
    i += 1
  }
  let wstart = i
  while i < len && str[i] >= 'a' && str[i] <= 'z' {
    i += 1
  }
  let box_name = str.view(start_offset=wstart, end_offset=i).to_owned()
  while i < len && (str[i] == ' ' || str[i] == '\t') {
    i += 1
  }
  let nstart = i
  while i < len && ((str[i] >= '0' && str[i] <= '9') || str[i] == '-') {
    i += 1
  }
  let indent = if nstart == i {
    0
  } else {
    // OCaml's integers have 63 bits
    let n = @string.parse_int64(str.view(start_offset=nstart, end_offset=i)) catch {
      _ => raise invalid_box()
    }
    if n > 0x7FFFFFFFL {
      0x7FFFFFFF
    } else if n < -0x80000000L {
      -0x80000000
    } else {
      n.to_int()
    }
  }
  while i < len && (str[i] == ' ' || str[i] == '\t') {
    i += 1
  }
  if i != len {
    raise invalid_box()
  }
  let box_type = match box_name {
    "" | "b" => Box
    "h" => HBox
    "v" => VBox
    "hv" => HVBox
    "hov" => HOVBox
    _ => raise invalid_box()
  }
  (indent, box_type)
}

// Execution

///|
priv struct Printer {
  args : ArrayView[Arg]
  mut next : Int
  /// size given by `@<n>` for the next string or character
  mut magic_size : Int?
}

///|
fn arg_name(a : Arg) -> String {
  match a {
    Int(_) => "Int"
    Int32(_) => "Int32"
    Int64(_) => "Int64"
    Float(_) => "Float"
    String(_) => "String"
    Char(_) => "Char"
    Bool(_) => "Bool"
    Print(_) => "Print"
    Format(_) => "Format"
  }
}

///|
fn Printer::take(self : Printer, expected : String) -> Arg raise FormatError {
  if self.next >= self.args.length() {
    raise FormatError(
      "Format: missing argument \{self.next + 1}, expected \{expected}",
    )
  }
  let a = self.args[self.next]
  self.next += 1
  a
}

///|
fn Printer::mismatch(self : Printer, a : Arg, expected : String) -> FormatError {
  FormatError(
    "Format: argument \{self.next} is \{arg_name(a)}, expected \{expected}",
  )
}

///|
fn Printer::take_int(self : Printer) -> Int raise FormatError {
  match self.take("Int") {
    Int(n) => n
    a => raise self.mismatch(a, "Int")
  }
}

///|
fn Printer::pad_width(
  self : Printer,
  pad : Pad,
) -> (PadTy, Int)? raise FormatError {
  match pad {
    NoPad => None
    LitPad(t, w) => Some((t, w))
    ArgPad(t) => Some((t, self.take_int()))
  }
}

///|
fn Printer::precision(self : Printer, prec : Prec) -> Int? raise FormatError {
  match prec {
    NoPrec => None
    LitPrec(p) => Some(p)
    ArgPrec => Some(self.take_int())
  }
}

///|
fn apply_pad(p : (PadTy, Int)?, s : String) -> String {
  match p {
    None => s
    Some((t, w)) => fix_padding(t, w, s)
  }
}

///|
/// Output a string, with the size given by `@<n>` if any.
fn Printer::output_string(self : Printer, ppf : Formatter, s : String) -> Unit {
  match self.magic_size {
    Some(size) => {
      self.magic_size = None
      ppf.print_as(size, s)
    }
    None => ppf.print_string(s)
  }
}

///|
fn Printer::output_char(self : Printer, ppf : Formatter, c : Char) -> Unit {
  match self.magic_size {
    Some(size) => {
      self.magic_size = None
      ppf.print_as(size, c.to_string())
    }
    None => ppf.print_char(c)
  }
}

///|
fn convert_float(
  kind : FloatKind,
  flag : Char,
  prec : Int,
  x : Double,
) -> String {
  let hex = () => hexstring_of_float(x, prec, flag)
  let caml_special_val = (s : String) => {
    if x.is_nan() {
      "nan"
    } else if x.is_inf() {
      if x < 0.0 {
        "neg_infinity"
      } else {
        "infinity"
      }
    } else {
      s
    }
  }
  match kind {
    FH => hex()
    FHU => hex().to_upper()
    FCF => caml_special_val(hex())
    FF => {
      let s = format_float_c(x, 'g', prec.abs(), sign=flag)
      let s = if s.iter().any(c => c == '.' || c == 'e' || c == 'E') {
        s
      } else {
        s + "."
      }
      caml_special_val(s)
    }
    FC(c) => format_float_c(x, c, prec.abs(), sign=flag)
  }
}

///|
fn Printer::run(
  self : Printer,
  ppf : Formatter,
  items : Array[Item],
) -> Unit raise FormatError {
  for item in items {
    match item {
      Lit(s) => self.output_string(ppf, s)
      Conversion(conv, pad, prec) => {
        let p = self.pad_width(pad)
        let pr = self.precision(prec)
        match conv {
          CChar =>
            match self.take("Char") {
              Char(c) => self.output_char(ppf, c)
              a => raise self.mismatch(a, "Char")
            }
          CCamlChar =>
            match self.take("Char") {
              Char(c) => self.output_string(ppf, caml_char(c))
              a => raise self.mismatch(a, "Char")
            }
          CString =>
            match self.take("String") {
              String(s) => self.output_string(ppf, apply_pad(p, s))
              a => raise self.mismatch(a, "String")
            }
          CCamlString =>
            match self.take("String") {
              String(s) =>
                self.output_string(ppf, apply_pad(p, string_to_caml_string(s)))
              a => raise self.mismatch(a, "String")
            }
          CBool =>
            match self.take("Bool") {
              Bool(b) =>
                self.output_string(
                  ppf,
                  apply_pad(p, if b { "true" } else { "false" }),
                )
              a => raise self.mismatch(a, "Bool")
            }
          CInt(size, c, plus, space, alt, group) => {
            let expected = match size {
              OInt => "Int"
              I32 => "Int32"
              I64 | Native => "Int64"
            }
            let n = match (size, self.take(expected)) {
              (OInt, Int(n)) => n.to_int64()
              (I32, Int32(n)) => n.to_int64()
              (I64 | Native, Int64(n)) => n
              (_, a) => raise self.mismatch(a, expected)
            }
            let s = format_int_c(n, size, c, plus~, space~, alt~)
            let s = if group { group_digits(s) } else { s }
            let s = match pr {
              Some(prec) => fix_int_precision(prec, s)
              None => s
            }
            self.output_string(ppf, apply_pad(p, s))
          }
          CFloat(flag, kind) => {
            let x = match self.take("Float") {
              Float(x) => x
              a => raise self.mismatch(a, "Float")
            }
            let prec = match pr {
              Some(prec) => prec
              None => if kind is FF { 12 } else { -6 }
            }
            self.output_string(
              ppf,
              apply_pad(p, convert_float(kind, flag, prec, x)),
            )
          }
          CAlpha | CTheta => {
            self.magic_size = None
            match self.take("Print") {
              Print(f) => f(ppf)
              a => raise self.mismatch(a, "Print")
            }
          }
        }
      }
      Flush => {
        self.magic_size = None
        ppf.print_flush()
      }
      Formatting(lit) => {
        self.magic_size = None
        match lit {
          CloseBox => ppf.close_box()
          CloseTag => ppf.close_tag()
          BreakHint(width, offset) => ppf.print_break(width, offset)
          FFlush => ppf.print_flush()
          ForceNewline => ppf.force_newline()
          FlushNewline => ppf.print_newline()
          MagicSize(size) => self.magic_size = Some(size)
          EscapedAt => ppf.print_char('@')
          EscapedPercent => ppf.print_char('%')
          ScanIndic(c) => {
            ppf.print_char('@')
            ppf.print_char(c)
          }
        }
      }
      OpenTagGen(sub) => {
        self.magic_size = None
        let tag = self.compute_tag(sub)
        ppf.open_stag(StringTag(tag))
      }
      OpenBoxGen(sub) => {
        self.magic_size = None
        let (indent, bty) = open_box_of_string(self.compute_tag(sub))
        ppf.open_box_gen(indent, bty)
      }
      FormatArg(sig) =>
        match self.take("Format") {
          Format(_) => self.output_string(ppf, sig)
          a => raise self.mismatch(a, "Format")
        }
      FormatSubst(sub_fmtty) =>
        match self.take("Format") {
          Format(s) => {
            let p : FormatParser = { str: s, }
            let fmt = p.parse(0, s.length())
            // the format must have the type of the sub-format
            if signature(fmt) != sub_fmtty {
              raise FormatError("CamlinternalFormat.Type_mismatch")
            }
            self.run(ppf, fmt.to_array())
          }
          a => raise self.mismatch(a, "Format")
        }
      ScanCounter => {
        let n = self.take_int()
        self.output_string(
          ppf,
          format_int_c(
            n.to_int64(),
            OInt,
            'u',
            plus=false,
            space=false,
            alt=false,
          ),
        )
      }
      Invalid(msg, _) => raise FormatError(msg)
    }
  }
}

///|
/// Print the description of a box or tag into a string and remove its
/// first and last characters (the angle brackets), like OCaml's
/// `compute_tag`.
fn Printer::compute_tag(
  self : Printer,
  sub : Array[Item],
) -> String raise FormatError {
  let buf = StringBuilder()
  let ppf = Formatter::of_buffer(buf)
  self.run(ppf, sub)
  ppf.print_flush()
  let s = buf.to_string()
  if s.length() < 2 {
    s
  } else {
    s.view(start_offset=1, end_offset=s.length() - 1).to_owned()
  }
}

///|
/// Check that a format string is valid, like the OCaml compiler does for
/// format literals: printing with an invalid format aborts the program.
/// The error messages are OCaml's. Some errors (e.g. an invalid box
/// description) are only detected when printing, like in OCaml.
pub fn check_format(fmt : String) -> Unit raise Failure {
  let p : FormatParser = { str: fmt, }
  ignore(p.parse(0, fmt.length())) catch {
    FormatError(msg) => raise Failure(msg)
  }
}

///|
fn parse_format_string(fmt : String) -> Array[Item] {
  let p : FormatParser = { str: fmt, }
  p.parse(0, fmt.length()).to_array() catch {
    FormatError(msg) => abort(msg)
  }
}

///|
/// Print on the formatter according to a format string, like OCaml's
/// `Format.fprintf`. Conversions take their values from `args`, in order.
///
/// Invalid formats and arguments that don't match the format abort the
/// program, since they are programming errors (type errors in OCaml).
pub fn Formatter::printf(
  self : Formatter,
  fmt : String,
  args : ArrayView[Arg],
) -> Unit {
  let items = parse_format_string(fmt)
  let p : Printer = { args, next: 0, magic_size: None, }
  p.run(self, items) catch {
    FormatError(msg) => abort(msg)
  }
  if p.next < args.length() {
    abort("Format: too many arguments for format \{string_to_caml_string(fmt)}")
  }
}

///|
/// Like `printf`, then call `k` with the formatter, like OCaml's
/// `Format.kfprintf`.
pub fn[T] Formatter::kprintf(
  self : Formatter,
  k : (Formatter) -> T,
  fmt : String,
  args : ArrayView[Arg],
) -> T {
  self.printf(fmt, args)
  k(self)
}

///|
/// Like `asprintf`, then call `k` with the result, like OCaml's
/// `Format.kasprintf`.
pub fn[T] kasprintf(
  k : (String) -> T,
  fmt : String,
  args : ArrayView[Arg],
) -> T {
  k(asprintf(fmt, args))
}

///|
/// Format into a string, like OCaml's `Format.asprintf`: the material is
/// printed with a fresh formatter (margin 78) that is flushed at the end.
pub fn asprintf(fmt : String, args : ArrayView[Arg]) -> String {
  let buf = StringBuilder()
  let ppf = Formatter::of_buffer(buf)
  ppf.printf(fmt, args)
  ppf.flush_queue(false)
  buf.to_string()
}

///|
/// Format into a string, like OCaml's `Format.sprintf`. The functions of
/// `%a` and `%t` print on the formatter, as with `asprintf`.
pub fn sprintf(fmt : String, args : ArrayView[Arg]) -> String {
  asprintf(fmt, args)
}

///|
/// Delayed printing, like OCaml's `Format.dprintf`: the result prints on
/// the formatter it is given.
pub fn dprintf(fmt : String, args : ArrayView[Arg]) -> (Formatter) -> Unit {
  let args = args.to_owned()
  ppf => ppf.printf(fmt, args)
}
