// Conversions of numbers, characters and strings to text, reproducing the
// C `printf` conversions used by OCaml's runtime (`caml_format_int`,
// `caml_format_float`, `caml_hexstring_of_float`) and the helpers of
// `camlinternalFormat.ml`.
//
// Copyright 1996 Institut National de Recherche en Informatique et en
// Automatique (OCaml), distributed under the terms of the GNU Lesser
// General Public License version 2.1, with the special exception on
// linking described in the file LICENSE.

// Floating-point numbers

///|
/// The exact decimal expansion of a finite, non-negative double:
/// `(digits, exponent)` such that the value is `0.digits * 10^exponent`,
/// with no leading zero in `digits` (empty for zero).
fn exact_decimal(x : Double) -> (String, Int) {
  let bits = x.reinterpret_as_uint64()
  let biased = ((bits >> 52) & 0x7FF).to_int()
  let fraction = bits & 0xFFFFFFFFFFFFF
  let (mantissa, e) = if biased == 0 {
    (fraction, -1074)
  } else {
    (fraction | 0x10000000000000, biased - 1075)
  }
  if mantissa == 0 {
    return ("", 0)
  }
  let m = @bigint.BigInt::from_uint64(mantissa)
  if e >= 0 {
    let n = m * @bigint.BigInt::from_int(2).pow(@bigint.BigInt::from_int(e))
    let digits = n.to_string()
    (digits, digits.length())
  } else {
    // m * 2^e = m * 5^-e / 10^-e
    let n = m * @bigint.BigInt::from_int(5).pow(@bigint.BigInt::from_int(-e))
    let digits = n.to_string()
    (digits, digits.length() + e)
  }
}

///|
/// Round the decimal number `0.digits * 10^exp` to `n` digits after its
/// first digit position... more precisely: keep the digits of indices
/// `< keep` (which may be negative or exceed the number of digits), rounding
/// half to even on the exact value. Return the kept digits (exactly
/// `max(keep, 0)` of them, padded with zeros) and whether the rounding
/// carried into a new leading digit.
fn round_digits_at(digits : String, keep : Int) -> (Array[Int], Bool) {
  let d = digits.iter().map(c => c.to_int() - '0'.to_int()).collect()
  if keep < 0 {
    return ([], false)
  }
  if d.length() <= keep {
    while d.length() < keep {
      d.push(0)
    }
    return (d, false)
  }
  let kept = d[0:keep].to_owned()
  let next = d[keep]
  let rest_nonzero = d[keep + 1:].iter().any(x => x != 0)
  let round_up = next > 5 ||
    (next == 5 && (rest_nonzero || (keep > 0 && kept[keep - 1] % 2 == 1)))
  if !round_up {
    return (kept, false)
  }
  let mut i = keep - 1
  while i >= 0 {
    if kept[i] == 9 {
      kept[i] = 0
      i -= 1
    } else {
      kept[i] += 1
      break
    }
  }
  if i < 0 {
    // carry: 99.. -> 100.., one more digit
    (Array::makei(keep + 1, j => if j == 0 { 1 } else { 0 }), true)
  } else {
    (kept, false)
  }
}

///|
fn digits_string(d : ArrayView[Int]) -> String {
  let buf = StringBuilder()
  for x in d {
    buf.write_char((x + '0'.to_int()).unsafe_to_char())
  }
  buf.to_string()
}

///|
/// The digits of a number in scientific notation with `prec` digits after
/// the point: the `prec + 1` significant digits and the decimal exponent.
fn scientific_digits(x : Double, prec : Int) -> (Array[Int], Int) {
  let (digits, exp10) = exact_decimal(x)
  if digits == "" {
    return (Array::make(prec + 1, 0), 0)
  }
  let (d, carried) = round_digits_at(digits, prec + 1)
  if carried {
    (d[0:prec + 1].to_owned(), exp10)
  } else {
    (d, exp10 - 1)
  }
}

///|
/// The digits of a number in fixed notation with `prec` digits after the
/// point: the digits before and after the point.
fn fixed_digits(x : Double, prec : Int) -> (String, String) {
  let (digits, exp10) = exact_decimal(x)
  if digits == "" {
    return ("0", String::make(prec, '0'))
  }
  // keep the digits up to position exp10 + prec
  let keep = exp10 + prec
  let (d, _) = round_digits_at(digits, keep)
  let all = digits_string(d)
  let all = if all.length() < prec {
    String::make(prec - all.length(), '0') + all
  } else {
    all
  }
  let int_part = all.view(end_offset=all.length() - prec).to_owned()
  let frac_part = all.view(start_offset=all.length() - prec).to_owned()
  let int_part = if int_part == "" {
    "0"
  } else {
    // remove leading zeros
    let mut i = 0
    while i < int_part.length() - 1 && int_part[i] == '0' {
      i += 1
    }
    int_part.view(start_offset=i).to_owned()
  }
  (int_part, frac_part)
}

///|
fn exponent_string(e : Int, upper : Bool) -> String {
  let buf = StringBuilder()
  buf.write_char(if upper { 'E' } else { 'e' })
  buf.write_char(if e < 0 { '-' } else { '+' })
  let a = e.abs()
  if a < 10 {
    buf.write_char('0')
  }
  buf.write_string(a.to_string())
  buf.to_string()
}

///|
fn is_negative(x : Double) -> Bool {
  x < 0.0 || (x == 0.0 && 1.0 / x < 0.0)
}

///|
/// Format a number like C's `printf` with conversion `conv` (one of
/// `f`, `e`, `E`, `g`, `G`), precision `prec` and sign flag `sign`
/// (`'+'`, `' '`, or `'-'` for none). `alt` is the `#` flag.
pub fn format_float_c(
  x : Double,
  conv : Char,
  prec : Int,
  sign? : Char = '-',
  alt? : Bool = false,
) -> String {
  let upper = conv == 'E' || conv == 'G' || conv == 'F'
  let neg = is_negative(x)
  let sign_str = if neg && !x.is_nan() {
    "-"
  } else {
    match sign {
      '+' => "+"
      ' ' => " "
      _ => ""
    }
  }
  if x.is_nan() {
    return sign_str + (if upper { "NAN" } else { "nan" })
  }
  if x.is_inf() {
    return sign_str + (if upper { "INF" } else { "inf" })
  }
  let a = x.abs()
  let body = match conv {
    'f' | 'F' => {
      let (i, f) = fixed_digits(a, prec)
      if prec > 0 || alt {
        i + "." + f
      } else {
        i
      }
    }
    'e' | 'E' => {
      let (d, e) = scientific_digits(a, prec)
      let s = digits_string(d)
      let mantissa = if prec > 0 || alt {
        s.view(end_offset=1).to_owned() +
        "." +
        s.view(start_offset=1).to_owned()
      } else {
        s
      }
      mantissa + exponent_string(e, upper)
    }
    _ => {
      // g, G
      let p = if prec == 0 { 1 } else { prec }
      let (d, e) = scientific_digits(a, p - 1)
      if e < -4 || e >= p {
        // scientific notation with p - 1 digits after the point
        let s = digits_string(d)
        let mut frac = s.view(start_offset=1).to_owned()
        if !alt {
          frac = strip_trailing_zeros(frac)
        }
        let mantissa = if frac != "" || alt {
          s.view(end_offset=1).to_owned() + "." + frac
        } else {
          s.view(end_offset=1).to_owned()
        }
        mantissa + exponent_string(e, upper)
      } else {
        // fixed notation with p - 1 - e digits after the point
        let (i, f) = fixed_digits(a, p - 1 - e)
        let f = if alt { f } else { strip_trailing_zeros(f) }
        if f != "" || alt {
          i + "." + f
        } else {
          i
        }
      }
    }
  }
  sign_str + body
}

///|
fn strip_trailing_zeros(s : String) -> String {
  let mut n = s.length()
  while n > 0 && s[n - 1] == '0' {
    n -= 1
  }
  s.view(end_offset=n).to_owned()
}

///|
/// Format a number in hexadecimal like OCaml's `caml_hexstring_of_float`
/// (`%h`): `prec` digits after the point, or as many as needed if `prec` is
/// negative.
pub fn hexstring_of_float(x : Double, prec : Int, sign : Char) -> String {
  let bits = x.reinterpret_as_uint64()
  let negative = bits >> 63 != 0
  let mut exp = ((bits >> 52) & 0x7FF).to_int()
  let mut m = bits & ((1UL << 52) - 1)
  let buf = StringBuilder()
  if negative {
    buf.write_char('-')
  } else {
    match sign {
      '+' => buf.write_char('+')
      ' ' => buf.write_char(' ')
      _ => ()
    }
  }
  if exp == 0x7FF {
    buf.write_string(if m == 0 { "infinity" } else { "nan" })
    return buf.to_string()
  }
  buf.write_string("0x")
  if exp == 0 {
    if m != 0 {
      exp = -1022 // denormal
    }
  } else {
    exp = exp - 1023
    m = m | (1UL << 52)
  }
  // if a precision is given, and is small, round the mantissa accordingly
  if prec >= 0 && prec < 13 {
    let i = 52 - prec * 4
    let unit = 1UL << i
    let half = unit >> 1
    let mask = unit - 1
    let frac = m & mask
    m = m & mask.lnot()
    // round to nearest, ties to even
    if frac > half || (frac == half && (m & unit) != 0) {
      m += unit
    }
  }
  let hex = "0123456789abcdef"
  let digit = (d : UInt64) => hex[d.to_int()].unsafe_to_char()
  // leading digit
  buf.write_char(digit(m >> 52))
  m = (m << 4) & ((1UL << 56) - 1)
  let mut p = prec
  if (if p >= 0 { p > 0 } else { m != 0 }) {
    buf.write_char('.')
    while (if p >= 0 { p > 0 } else { m != 0 }) {
      buf.write_char(digit(m >> 52))
      m = (m << 4) & ((1UL << 56) - 1)
      p -= 1
    }
  }
  buf.write_char('p')
  if exp >= 0 {
    buf.write_char('+')
  }
  buf.write_string(exp.to_string())
  buf.to_string()
}

///|
/// OCaml's `valid_float_lexem`: add a `.` to a number without one, so that
/// it reads as a float.
fn valid_float_lexem(s : String) -> String {
  if s.iter().all(c => (c >= '0' && c <= '9') || c == '-') {
    s + "."
  } else {
    s
  }
}

///|
/// OCaml's `string_of_float`: 12 significant digits, with a `.` if needed
/// (`1.`, `0.1`, `1e+20`, `inf`, `nan`).
pub fn string_of_float(f : Double) -> String {
  valid_float_lexem(format_float_c(f, 'g', 12))
}

// Integers

///|
/// Digits of an unsigned 64-bit integer in a base.
fn unsigned_digits(n : UInt64, base : Int, upper : Bool) -> String {
  if n == 0 {
    return "0"
  }
  let hex = if upper { "0123456789ABCDEF" } else { "0123456789abcdef" }
  let b = base.to_uint64()
  let chars = []
  let mut n = n
  while n > 0 {
    chars.push(hex[(n % b).to_int()].unsafe_to_char())
    n = n / b
  }
  String::from_array(chars.rev())
}

///|
/// The sizes of integers in format strings.
priv enum IntSize {
  /// OCaml's `int` (63 bits): `%d`
  OInt
  /// `int32`: `%ld`
  I32
  /// `int64`: `%Ld`
  I64
  /// `nativeint` (64 bits): `%nd`
  Native
}

///|
/// Format an integer like OCaml's `caml_format_int` & co: C's `printf` with
/// flags `+`, ` ` and `#` (for `x`, `X` and `o` only) and conversion `d`,
/// `i`, `u`, `x`, `X` or `o`. Unsigned conversions use the representation
/// of the value in the integer size.
fn format_int_c(
  n : Int64,
  size : IntSize,
  conv : Char,
  plus~ : Bool,
  space~ : Bool,
  alt~ : Bool,
) -> String {
  match conv {
    'd' | 'i' =>
      if n < 0L {
        "-" + unsigned_digits((0L - n).reinterpret_as_uint64(), 10, false)
      } else {
        let s = n.to_string()
        if plus {
          "+" + s
        } else if space {
          " " + s
        } else {
          s
        }
      }
    _ => {
      let u = match size {
        // OCaml's Unsigned_long_val: the 63 bits of the tagged value
        OInt => n.reinterpret_as_uint64() & 0x7FFFFFFFFFFFFFFFUL
        I32 => n.to_int().reinterpret_as_uint().to_uint64()
        I64 | Native => n.reinterpret_as_uint64()
      }
      match conv {
        'u' => unsigned_digits(u, 10, false)
        'x' => {
          let s = unsigned_digits(u, 16, false)
          if alt && u != 0 {
            "0x" + s
          } else {
            s
          }
        }
        'X' => {
          let s = unsigned_digits(u, 16, true)
          if alt && u != 0 {
            "0X" + s
          } else {
            s
          }
        }
        _ => {
          let s = unsigned_digits(u, 8, false)
          if alt && s[0] != '0' {
            "0" + s
          } else {
            s
          }
        }
      }
    }
  }
}

///|
/// The `#` flag of `%d`, `%i` and `%u`: digits are grouped by three with
/// underscores, like OCaml's `transform_int_alt`.
fn group_digits(s : String) -> String {
  let mut digits = 0
  for c in s {
    if c >= '0' && c <= '9' {
      digits += 1
    }
  }
  let buf = StringBuilder()
  let mut left = (digits - 1) % 3 + 1
  for c in s {
    if c >= '0' && c <= '9' {
      if left == 0 {
        buf.write_char('_')
        left = 3
      }
      left -= 1
      buf.write_char(c)
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

// Padding

///|
/// Padding of a conversion.
priv enum PadTy {
  Left
  Right
  Zeros
}

///|
/// Add padding around a string, like OCaml's `fix_padding`.
fn fix_padding(padty : PadTy, width : Int, s : String) -> String {
  // the width is in bytes, like OCaml strings
  let len = utf8_length(s)
  let (width, padty) = (width.abs(), if width < 0 { Left } else { padty })
  if width <= len {
    return s
  }
  let fill = width - len
  match padty {
    Left => s + String::make(fill, ' ')
    Right => String::make(fill, ' ') + s
    Zeros =>
      if len > 0 && (s[0] == '+' || s[0] == '-' || s[0] == ' ') {
        s.view(end_offset=1).to_owned() +
        String::make(fill, '0') +
        s.view(start_offset=1).to_owned()
      } else if len > 1 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X') {
        s.view(end_offset=2).to_owned() +
        String::make(fill, '0') +
        s.view(start_offset=2).to_owned()
      } else {
        String::make(fill, '0') + s
      }
  }
}

///|
/// Add `0` padding to an integer, like OCaml's `fix_int_precision`.
fn fix_int_precision(prec : Int, s : String) -> String {
  let prec = prec.abs()
  let len = s.length()
  if len == 0 {
    return s
  }
  let c = s[0]
  if (c == '+' || c == '-' || c == ' ') && prec + 1 > len {
    s.view(end_offset=1).to_owned() +
    String::make(prec + 1 - len, '0') +
    s.view(start_offset=1).to_owned()
  } else if c == '0' &&
    prec + 2 > len &&
    len > 1 &&
    (s[1] == 'x' || s[1] == 'X') {
    s.view(end_offset=2).to_owned() +
    String::make(prec + 2 - len, '0') +
    s.view(start_offset=2).to_owned()
  } else if (
      (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
    ) &&
    prec > len {
    String::make(prec - len, '0') + s
  } else {
    s
  }
}

// Characters and strings

///|
/// Escape one byte like OCaml's `String.escaped` (`quote` tells whether to
/// escape `'`, as `Char.escaped` does).
fn escape_byte(buf : StringBuilder, b : Int, quote : Bool) -> Unit {
  match b {
    '"' => buf.write_string(if quote { "\"" } else { "\\\"" })
    '\'' => buf.write_string(if quote { "\\'" } else { "'" })
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
}

///|
/// Iterate over the UTF-8 encoding of a string.
fn utf8_iter(s : StringView, f : (Int) -> Unit) -> Unit {
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
/// OCaml's `String.escaped`, applied to the UTF-8 encoding of a string.
pub fn string_escaped(s : StringView) -> String {
  let buf = StringBuilder()
  utf8_iter(s, b => escape_byte(buf, b, false))
  buf.to_string()
}

///|
/// OCaml's `Char.escaped`, applied to the UTF-8 encoding of a character.
pub fn char_escaped(c : Char) -> String {
  let buf = StringBuilder()
  utf8_iter(c.to_string(), b => escape_byte(buf, b, true))
  buf.to_string()
}
