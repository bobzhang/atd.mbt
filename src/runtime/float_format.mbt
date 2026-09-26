// Exact formatting of floating-point numbers like C's printf("%.*g").

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
/// Round a digit string to `n` digits, rounding half to even.
/// Return the rounded digits (exactly `n` of them) and whether the rounding
/// carried into a new leading digit.
fn round_digits(digits : String, n : Int) -> (Array[Int], Bool) {
  let d = digits.iter().map(c => c.to_int() - '0'.to_int()).collect()
  if d.length() <= n {
    while d.length() < n {
      d.push(0)
    }
    return (d, false)
  }
  let kept = d[0:n].to_owned()
  let next = d[n]
  let rest_nonzero = d[n + 1:].iter().any(x => x != 0)
  let round_up = next > 5 ||
    (next == 5 && (rest_nonzero || (n > 0 && kept[n - 1] % 2 == 1)))
  if !round_up {
    return (kept, false)
  }
  let mut i = n - 1
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
    // carry: 99.. -> 100..
    let res = [1]
    for _ in 1..<n {
      res.push(0)
    }
    (res, true)
  } else {
    (kept, false)
  }
}

///|
/// Format a finite number like C's `printf("%.<precision>g", x)`.
pub fn format_float_g(x : Double, precision : Int) -> String {
  let p = if precision <= 0 { 1 } else { precision }
  let negative = x < 0.0 || (x == 0.0 && 1.0 / x < 0.0)
  let sign = if negative { "-" } else { "" }
  let (digits, exp10) = exact_decimal(x.abs())
  if digits == "" {
    return sign + "0"
  }
  let (d, carried) = round_digits(digits, p)
  // decimal exponent of the first significant digit, as in %e
  let x_exp = if carried { exp10 } else { exp10 - 1 }
  // remove trailing zeros
  let mut len = d.length()
  while len > 1 && d[len - 1] == 0 {
    len -= 1
  }
  let ds = d[0:len]
    .iter()
    .map(i => (i + '0'.to_int()).unsafe_to_char())
    .collect()
  let buf = StringBuilder()
  buf.write_string(sign)
  if x_exp < -4 || x_exp >= p {
    // scientific notation
    buf.write_char(ds[0])
    if len > 1 {
      buf.write_char('.')
      for c in ds[1:] {
        buf.write_char(c)
      }
    }
    buf.write_char('e')
    buf.write_char(if x_exp < 0 { '-' } else { '+' })
    let e = x_exp.abs()
    if e < 10 {
      buf.write_char('0')
    }
    buf.write_string(e.to_string())
  } else if x_exp < 0 {
    buf.write_string("0.")
    for _ in 0..<(-x_exp - 1) {
      buf.write_char('0')
    }
    for c in ds {
      buf.write_char(c)
    }
  } else {
    // x_exp + 1 digits before the point
    for i in 0..<=x_exp {
      buf.write_char(if i < len { ds[i] } else { '0' })
    }
    if len > x_exp + 1 {
      buf.write_char('.')
      for c in ds[x_exp + 1:] {
        buf.write_char(c)
      }
    }
  }
  buf.to_string()
}
