// The parser of format strings, a port of `fmt_ebb_of_string` in OCaml's
// `camlinternalFormat.ml`, in legacy mode (the default of the compiler).
//
// The structure of the OCaml parser is kept, down to the order of the
// recursive calls: the rest of a format is parsed before some checks of a
// conversion, which determines the error reported for a format with several
// errors.
//
// Copyright 1996 Institut National de Recherche en Informatique et en
// Automatique (OCaml), distributed under the terms of the GNU Lesser
// General Public License version 2.1, with the special exception on
// linking described in the file LICENSE.

///|
priv suberror FormatError {
  FormatError(String)
}

///|
priv struct FormatParser {
  str : String
}

///|
/// OCaml's `Sys.max_string_length` on 64-bit platforms: the limit of
/// widths and precisions.
let max_string_length : Int64 = 144115188075855863L

///|
fn FormatParser::char_at(self : FormatParser, i : Int) -> Char {
  self.str[i].unsafe_to_char()
}

///|
/// The position of an index in error messages: like in OCaml, it counts
/// the bytes of the UTF-8 encoding.
fn FormatParser::pos(self : FormatParser, i : Int) -> Int {
  utf8_length(self.str.view(end_offset=i))
}

///|
fn FormatParser::quoted(self : FormatParser) -> String {
  string_to_caml_string(self.str)
}

///|
fn FormatParser::invalid_format_message(
  self : FormatParser,
  str_ind : Int,
  msg : String,
) -> FormatError {
  FormatError(
    "invalid format \{self.quoted()}: at character number \{self.pos(str_ind)}, \{msg}",
  )
}

///|
fn FormatParser::unexpected_end_of_format(
  self : FormatParser,
  end_ind : Int,
) -> FormatError {
  self.invalid_format_message(end_ind, "unexpected end of format")
}

///|
fn FormatParser::expected_character(
  self : FormatParser,
  str_ind : Int,
  expected : String,
  read : Char,
) -> FormatError {
  self.invalid_format_message(
    str_ind,
    "\{expected} expected, read \{caml_char(read)}",
  )
}

///|
fn FormatParser::incompatible_flag(
  self : FormatParser,
  pct_ind : Int,
  str_ind : Int,
  symb : Char,
  option : String,
) -> FormatError {
  let subfmt = self.str
    .view(start_offset=pct_ind, end_offset=str_ind)
    .to_owned()
  FormatError(
    "invalid format \{self.quoted()}: at character number \{self.pos(pct_ind)}, \{option} is incompatible with '\{symb}' in sub-format \{string_to_caml_string(subfmt)}",
  )
}

///|
/// Parse the format from `beg_ind` (included) to `end_ind` (excluded).
fn FormatParser::parse(
  self : FormatParser,
  beg_ind : Int,
  end_ind : Int,
) -> @list.List[Item] raise FormatError {
  self.parse_literal(beg_ind, beg_ind, end_ind)
}

///|
/// Read literal characters up to '%' or '@' special characters.
fn FormatParser::parse_literal(
  self : FormatParser,
  lit_start : Int,
  str_ind : Int,
  end_ind : Int,
) -> @list.List[Item] raise FormatError {
  let mut str_ind = str_ind
  while str_ind < end_ind && !(self.char_at(str_ind) is ('%' | '@')) {
    str_ind += 1
  }
  if str_ind == end_ind {
    return self.add_literal(lit_start, str_ind, @list.empty())
  }
  let fmt_rest = if self.char_at(str_ind) == '%' {
    self.parse_format(str_ind, end_ind)
  } else {
    self.parse_after_at(str_ind + 1, end_ind)
  }
  self.add_literal(lit_start, str_ind, fmt_rest)
}

///|
/// Add a literal to a format from a literal character sub-sequence.
fn FormatParser::add_literal(
  self : FormatParser,
  lit_start : Int,
  str_ind : Int,
  fmt : @list.List[Item],
) -> @list.List[Item] {
  if str_ind == lit_start {
    fmt
  } else {
    fmt.prepend(
      Lit(self.str.view(start_offset=lit_start, end_offset=str_ind).to_owned()),
    )
  }
}

///|
/// Parse a format after '%'.
fn FormatParser::parse_format(
  self : FormatParser,
  pct_ind : Int,
  end_ind : Int,
) -> @list.List[Item] raise FormatError {
  let str_ind = pct_ind + 1
  if str_ind == end_ind {
    raise self.unexpected_end_of_format(end_ind)
  }
  if self.char_at(str_ind) == '_' {
    self.parse_flags(pct_ind, str_ind + 1, end_ind, true)
  } else {
    self.parse_flags(pct_ind, str_ind, end_ind, false)
  }
}

///|
fn FormatParser::parse_flags(
  self : FormatParser,
  pct_ind : Int,
  str_ind : Int,
  end_ind : Int,
  ign : Bool,
) -> @list.List[Item] raise FormatError {
  // in legacy mode, duplicate flags are accepted
  let mut zero = false
  let mut minus = false
  let mut plus = false
  let mut space = false
  let mut hash = false
  let mut str_ind = str_ind
  for ;; {
    if str_ind == end_ind {
      raise self.unexpected_end_of_format(end_ind)
    }
    match self.char_at(str_ind) {
      '0' => zero = true
      '-' => minus = true
      '+' => plus = true
      '#' => hash = true
      ' ' => space = true
      _ => break
    }
    str_ind += 1
  }
  self.parse_padding(
    pct_ind, str_ind, end_ind, zero, minus, plus, hash, space, ign,
  )
}

///|
/// Try to read a digital or a '*' padding.
fn FormatParser::parse_padding(
  self : FormatParser,
  pct_ind : Int,
  str_ind : Int,
  end_ind : Int,
  zero : Bool,
  minus : Bool,
  plus : Bool,
  hash : Bool,
  space : Bool,
  ign : Bool,
) -> @list.List[Item] raise FormatError {
  if str_ind == end_ind {
    raise self.unexpected_end_of_format(end_ind)
  }
  let padty : PadTy = match (zero, minus) {
    (false, false) => Right
    (false, true) => Left
    (true, false) => Zeros
    (true, true) => Left // legacy
  }
  match self.char_at(str_ind) {
    '0'..='9' => {
      let (new_ind, width) = self.parse_positive(str_ind, end_ind)
      self.parse_after_padding(
        pct_ind,
        new_ind,
        end_ind,
        minus,
        plus,
        hash,
        space,
        ign,
        LitPad(padty, width),
      )
    }
    '*' =>
      self.parse_after_padding(
        pct_ind,
        str_ind + 1,
        end_ind,
        minus,
        plus,
        hash,
        space,
        ign,
        ArgPad(padty),
      )
    _ => {
      let pad = match padty {
        Left => NoPad // legacy
        // a '0' padding indication not followed by anything is a Right
        // padding of width 0 (used by the scanning conversions %0s, %0c)
        Zeros => LitPad(Right, 0)
        Right => NoPad
      }
      self.parse_after_padding(
        pct_ind, str_ind, end_ind, minus, plus, hash, space, ign, pad,
      )
    }
  }
}

///|
/// Is precision defined?
fn FormatParser::parse_after_padding(
  self : FormatParser,
  pct_ind : Int,
  str_ind : Int,
  end_ind : Int,
  minus : Bool,
  plus : Bool,
  hash : Bool,
  space : Bool,
  ign : Bool,
  pad : Pad,
) -> @list.List[Item] raise FormatError {
  if str_ind == end_ind {
    raise self.unexpected_end_of_format(end_ind)
  }
  match self.char_at(str_ind) {
    '.' =>
      self.parse_precision(
        pct_ind,
        str_ind + 1,
        end_ind,
        minus,
        plus,
        hash,
        space,
        ign,
        pad,
      )
    symb =>
      self.parse_conversion(
        pct_ind,
        str_ind + 1,
        end_ind,
        plus,
        hash,
        space,
        ign,
        pad,
        NoPrec,
        pad,
        symb,
      )
  }
}

///|
/// Read the digital or '*' precision.
fn FormatParser::parse_precision(
  self : FormatParser,
  pct_ind : Int,
  str_ind : Int,
  end_ind : Int,
  minus : Bool,
  plus : Bool,
  hash : Bool,
  space : Bool,
  ign : Bool,
  pad : Pad,
) -> @list.List[Item] raise FormatError {
  if str_ind == end_ind {
    raise self.unexpected_end_of_format(end_ind)
  }
  let parse_literal = (minus : Bool, str_ind : Int) => {
    let (new_ind, prec) = self.parse_positive(str_ind, end_ind)
    self.parse_after_precision(
      pct_ind,
      new_ind,
      end_ind,
      minus,
      plus,
      hash,
      space,
      ign,
      pad,
      LitPrec(prec),
    )
  }
  match self.char_at(str_ind) {
    '0'..='9' => parse_literal(minus, str_ind)
    // legacy: '+' or '-' before the precision is accepted and ignored
    '+' | '-' as symb => parse_literal(minus || symb == '-', str_ind + 1)
    '*' =>
      self.parse_after_precision(
        pct_ind,
        str_ind + 1,
        end_ind,
        minus,
        plus,
        hash,
        space,
        ign,
        pad,
        ArgPrec,
      )
    // legacy: '.' without a number means '.0'
    _ =>
      self.parse_after_precision(
        pct_ind,
        str_ind,
        end_ind,
        minus,
        plus,
        hash,
        space,
        ign,
        pad,
        LitPrec(0),
      )
  }
}

///|
/// Try to read the conversion.
fn FormatParser::parse_after_precision(
  self : FormatParser,
  pct_ind : Int,
  str_ind : Int,
  end_ind : Int,
  minus : Bool,
  plus : Bool,
  hash : Bool,
  space : Bool,
  ign : Bool,
  pad : Pad,
  prec : Prec,
) -> @list.List[Item] raise FormatError {
  if str_ind == end_ind {
    raise self.unexpected_end_of_format(end_ind)
  }
  // in legacy mode, %s and %S accept a mix of padding and precision, merged
  // as a single padding: %.10s is %10s, and %-.3s and %.-3s are %-3s
  let padprec = match pad {
    NoPad =>
      match (minus, prec) {
        (_, NoPrec) => NoPad
        (false, LitPrec(n)) => LitPad(Right, n)
        (true, LitPrec(n)) => LitPad(Left, n)
        (false, ArgPrec) => ArgPad(Right)
        (true, ArgPrec) => ArgPad(Left)
      }
    pad => pad
  }
  self.parse_conversion(
    pct_ind,
    str_ind + 1,
    end_ind,
    plus,
    hash,
    space,
    ign,
    pad,
    prec,
    padprec,
    self.char_at(str_ind),
  )
}

///|
/// Case analysis on conversion.
fn FormatParser::parse_conversion(
  self : FormatParser,
  pct_ind : Int,
  str_ind : Int,
  end_ind : Int,
  plus : Bool,
  hash : Bool,
  space : Bool,
  ign : Bool,
  pad : Pad,
  prec : Prec,
  padprec : Pad,
  symb : Char,
) -> @list.List[Item] raise FormatError {
  // the '_' flag must be used by the conversion
  let mut ign_used = false
  let get_ign = () => {
    ign_used = true
    ign
  }
  // padding as an option: '*' is not accepted
  let opt_of_pad = (c : Char, pad : Pad) => {
    match pad {
      NoPad => None
      LitPad(_, width) => Some(width)
      ArgPad(_) => raise self.incompatible_flag(pct_ind, str_ind, c, "'*'")
    }
  }
  let get_pad_opt = (c : Char) => opt_of_pad(c, pad)
  let get_padprec_opt = (c : Char) => opt_of_pad(c, padprec)
  let get_prec_opt = () => {
    match prec {
      NoPrec => None
      LitPrec(ndec) => Some(ndec)
      ArgPrec => raise self.incompatible_flag(pct_ind, str_ind, '_', "'*'")
    }
  }
  // legacy: a '0' padding is a right padding for integers with a
  // precision, and for strings and booleans
  let check_no_0 = (pad : Pad) => {
    match pad {
      LitPad(Zeros, width) => LitPad(Right, width)
      ArgPad(Zeros) => ArgPad(Right)
      pad => pad
    }
  }
  let get_int_pad = () => {
    match (pad, prec) {
      (pad, NoPrec) => pad
      (NoPad, _) => NoPad
      (pad, _) => check_no_0(pad)
    }
  }
  // the item of an ignored conversion: an error when printing
  let ignored = (sig : String) => {
    Item::Invalid("Printf: bad conversion %_", sig)
  }
  let fmt_result = match symb {
    ',' => self.parse(str_ind, end_ind)
    'c' => {
      let fmt_rest = self.parse(str_ind, end_ind)
      // %0c (which reads the next character in scanf) and the widths of
      // %c (ignored in legacy mode) print a character
      ignore(get_pad_opt('c'))
      fmt_rest.prepend(
        if get_ign() {
          ignored("")
        } else {
          Conversion(CChar, NoPad, NoPrec)
        },
      )
    }
    'C' => {
      let fmt_rest = self.parse(str_ind, end_ind)
      fmt_rest.prepend(
        if get_ign() {
          ignored("")
        } else {
          Conversion(CCamlChar, NoPad, NoPrec)
        },
      )
    }
    's' | 'S' => {
      let pad = check_no_0(padprec)
      let fmt_rest = self.parse(str_ind, end_ind)
      fmt_rest.prepend(
        if get_ign() {
          ignore(get_padprec_opt('_'))
          ignored("")
        } else {
          let conv = if symb == 's' { CString } else { CCamlString }
          Conversion(conv, pad, NoPrec)
        },
      )
    }
    'd' | 'i' | 'x' | 'X' | 'o' | 'u' => {
      let iconv = int_conv(plus, hash, space, symb)
      let fmt_rest = self.parse(str_ind, end_ind)
      fmt_rest.prepend(
        if get_ign() {
          ignore(get_pad_opt('_'))
          ignored("")
        } else {
          Conversion(make_int_conv(OInt, symb, iconv), get_int_pad(), prec)
        },
      )
    }
    'N' => {
      let fmt_rest = self.parse(str_ind, end_ind)
      fmt_rest.prepend(if get_ign() { ignored("") } else { ScanCounter })
    }
    'l' | 'n' | 'L' if str_ind == end_ind || !is_int_base(self.char_at(str_ind)) => {
      let fmt_rest = self.parse(str_ind, end_ind)
      fmt_rest.prepend(if get_ign() { ignored("") } else { ScanCounter })
    }
    'l' | 'n' | 'L' => {
      let c = self.char_at(str_ind)
      let iconv = int_conv(plus, hash, space, c)
      let fmt_rest = self.parse(str_ind + 1, end_ind)
      let size = match symb {
        'l' => I32
        'n' => Native
        _ => I64
      }
      fmt_rest.prepend(
        if get_ign() {
          ignore(get_pad_opt('_'))
          ignored("")
        } else {
          Conversion(make_int_conv(size, c, iconv), get_int_pad(), prec)
        },
      )
    }
    'f' | 'e' | 'E' | 'g' | 'G' | 'F' | 'h' | 'H' => {
      // legacy: '+' wins over ' '
      let flag = if plus { '+' } else if space { ' ' } else { '-' }
      let kind = match symb {
        'F' => if hash { FCF } else { FF }
        'h' => FH
        'H' => FHU
        c => FC(c)
      }
      let fmt_rest = self.parse(str_ind, end_ind)
      fmt_rest.prepend(
        if get_ign() {
          // the arguments of a constructor are evaluated from right to left
          ignore(get_prec_opt())
          ignore(get_pad_opt('_'))
          ignored("")
        } else {
          Conversion(CFloat(flag, kind), pad, prec)
        },
      )
    }
    'b' | 'B' => {
      let pad = check_no_0(padprec)
      let fmt_rest = self.parse(str_ind, end_ind)
      fmt_rest.prepend(
        if get_ign() {
          ignore(get_padprec_opt('_'))
          ignored("")
        } else {
          Conversion(CBool, pad, NoPrec)
        },
      )
    }
    'a' =>
      self.parse(str_ind, end_ind).prepend(Conversion(CAlpha, NoPad, NoPrec))
    't' =>
      self.parse(str_ind, end_ind).prepend(Conversion(CTheta, NoPad, NoPrec))
    'r' => {
      let fmt_rest = self.parse(str_ind, end_ind)
      // %r (a reader, for scanf) is impossible with printf by typing
      fmt_rest.prepend(
        if get_ign() {
          Invalid(
            "Printf: %_r is not supported by printf-like functions", "%_r",
          )
        } else {
          Invalid("Printf: %r is not supported by printf-like functions", "%r")
        },
      )
    }
    '!' => self.parse(str_ind, end_ind).prepend(Flush)
    '%' | '@' => self.parse(str_ind, end_ind).prepend(Lit(symb.to_string()))
    '{' => {
      let sub_end = self.search_subformat_end(str_ind, end_ind, '}')
      let sub_fmt = self.parse(str_ind, sub_end)
      let fmt_rest = self.parse(sub_end + 2, end_ind)
      let sub_fmtty = signature(sub_fmt)
      fmt_rest.prepend(
        if get_ign() {
          ignore(get_pad_opt('_'))
          ignored("")
        } else {
          ignore(get_pad_opt('{'))
          FormatArg(sub_fmtty)
        },
      )
    }
    '(' => {
      let sub_end = self.search_subformat_end(str_ind, end_ind, ')')
      let fmt_rest = self.parse(sub_end + 2, end_ind)
      let sub_fmt = self.parse(str_ind, sub_end)
      let sub_fmtty = signature(sub_fmt)
      fmt_rest.prepend(
        if get_ign() {
          ignore(get_pad_opt('_'))
          // `%_( fmt %)` takes the arguments of `fmt`
          ignored(sub_fmtty)
        } else {
          ignore(get_pad_opt('('))
          FormatSubst(sub_fmtty)
        },
      )
    }
    '[' => {
      let next_ind = self.parse_char_set(str_ind, end_ind)
      let fmt_rest = self.parse(next_ind, end_ind)
      fmt_rest.prepend(
        if get_ign() {
          ignore(get_pad_opt('_'))
          ignored("")
        } else {
          ignore(get_pad_opt('['))
          Invalid("Printf: bad conversion %[", "%s")
        },
      )
    }
    '-' | '+' | '#' | ' ' | '_' =>
      raise FormatError(
        "invalid format \{self.quoted()}: at character number \{self.pos(pct_ind)}, flag \{caml_char(symb)} is only allowed after the '%', before padding and precision",
      )
    _ =>
      raise self.invalid_format_message(
        str_ind - 1,
        "invalid conversion \"%\{symb}\"",
      )
  }
  // this check is not disabled in legacy mode, since ignoring it would
  // result in a different typing (argument-less formats can be ignored)
  if !ign_used && ign && !(symb is ('@' | '%' | '!' | ',')) {
    raise self.incompatible_flag(pct_ind, str_ind, symb, "'_'")
  }
  fmt_result
}

///|
/// Parse formatting information (after '@').
fn FormatParser::parse_after_at(
  self : FormatParser,
  str_ind : Int,
  end_ind : Int,
) -> @list.List[Item] raise FormatError {
  if str_ind == end_ind {
    return @list.singleton(Lit("@"))
  }
  let lit = (lit : FmtLit) => {
    self.parse(str_ind + 1, end_ind).prepend(Formatting(lit))
  }
  match self.char_at(str_ind) {
    '[' => self.parse_tag(false, str_ind + 1, end_ind)
    ']' => lit(CloseBox)
    '{' => self.parse_tag(true, str_ind + 1, end_ind)
    '}' => lit(CloseTag)
    ',' => lit(BreakHint(0, 0))
    ' ' => lit(BreakHint(1, 0))
    ';' => self.parse_good_break(str_ind + 1, end_ind)
    '?' => lit(FFlush)
    '\n' => lit(ForceNewline)
    '.' => lit(FlushNewline)
    '<' => self.parse_magic_size(str_ind + 1, end_ind)
    '@' => lit(EscapedAt)
    '%' if str_ind + 1 < end_ind && self.char_at(str_ind + 1) == '%' =>
      self.parse(str_ind + 2, end_ind).prepend(Formatting(EscapedPercent))
    '%' => self.parse(str_ind, end_ind).prepend(Lit("@"))
    c => lit(ScanIndic(c))
  }
}

///|
/// Try to read the optional <name> after "@{" or "@[".
fn FormatParser::parse_tag(
  self : FormatParser,
  is_open_tag : Bool,
  str_ind : Int,
  end_ind : Int,
) -> @list.List[Item] raise FormatError {
  let make = (sub : @list.List[Item]) => {
    if is_open_tag {
      OpenTagGen(sub.to_array())
    } else {
      OpenBoxGen(sub.to_array())
    }
  }
  if str_ind < end_ind && self.char_at(str_ind) == '<' {
    // the closing '>' is searched in the whole string
    let mut ind = str_ind + 1
    while ind < self.str.length() && self.char_at(ind) != '>' {
      ind += 1
    }
    if ind < end_ind {
      let fmt_rest = self.parse(ind + 1, end_ind)
      let sub_fmt = self.parse(str_ind, ind + 1)
      return fmt_rest.prepend(make(sub_fmt))
    }
  }
  self.parse(str_ind, end_ind).prepend(make(@list.empty()))
}

///|
/// Try to read the optional <width offset> after "@;".
fn FormatParser::parse_good_break(
  self : FormatParser,
  str_ind : Int,
  end_ind : Int,
) -> @list.List[Item] raise FormatError {
  let attempt = () => {
    if str_ind == end_ind || self.char_at(str_ind) != '<' {
      return None
    }
    let str_ind_1 = self.parse_spaces(str_ind + 1, end_ind)
    match self.char_at(str_ind_1) {
      '0'..='9' | '-' => {
        let (str_ind_2, width) = self.parse_integer(str_ind_1, end_ind)
        let str_ind_3 = self.parse_spaces(str_ind_2, end_ind)
        match self.char_at(str_ind_3) {
          '>' => Some((str_ind_3 + 1, BreakHint(width, 0)))
          '0'..='9' | '-' => {
            let (str_ind_4, offset) = self.parse_integer(str_ind_3, end_ind)
            let str_ind_5 = self.parse_spaces(str_ind_4, end_ind)
            if self.char_at(str_ind_5) != '>' {
              None
            } else {
              Some((str_ind_5 + 1, BreakHint(width, offset)))
            }
          }
          _ => None
        }
      }
      _ => None
    }
  }
  let (next_ind, formatting_lit) = match (attempt() catch { _ => None }) {
    Some(res) => res
    None => (str_ind, BreakHint(1, 0))
  }
  self.parse(next_ind, end_ind).prepend(Formatting(formatting_lit))
}

///|
/// Parse the size in a <n>.
fn FormatParser::parse_magic_size(
  self : FormatParser,
  str_ind : Int,
  end_ind : Int,
) -> @list.List[Item] raise FormatError {
  let attempt = () => {
    let str_ind_1 = self.parse_spaces(str_ind, end_ind)
    match self.char_at(str_ind_1) {
      '0'..='9' | '-' => {
        let (str_ind_2, size) = self.parse_integer(str_ind_1, end_ind)
        let str_ind_3 = self.parse_spaces(str_ind_2, end_ind)
        if self.char_at(str_ind_3) != '>' {
          None
        } else {
          Some((str_ind_3 + 1, size))
        }
      }
      _ => None
    }
  }
  match (attempt() catch { _ => None }) {
    Some((next_ind, size)) =>
      self.parse(next_ind, end_ind).prepend(Formatting(MagicSize(size)))
    None => self.parse(str_ind, end_ind).prepend(Formatting(ScanIndic('<')))
  }
}

///|
/// Parse a char set (of scanf's %[...]); return the index after it.
fn FormatParser::parse_char_set(
  self : FormatParser,
  str_ind : Int,
  end_ind : Int,
) -> Int raise FormatError {
  if str_ind == end_ind {
    raise self.unexpected_end_of_format(end_ind)
  }
  let fail_single_percent = (str_ind : Int) => {
    FormatError(
      "invalid format \{self.quoted()}: '%' alone is not accepted in character sets, use %% instead at position \{self.pos(str_ind)}.",
    )
  }
  // the states of the parser of the content: the first character, a
  // character, after a character c, after c-
  let str_ind = if self.char_at(str_ind) == '^' { str_ind + 1 } else { str_ind }
  // parse the first character
  if str_ind == end_ind {
    raise self.unexpected_end_of_format(end_ind)
  }
  let mut c = self.char_at(str_ind)
  let mut i = str_ind + 1
  // after a character `c`
  for ;; {
    if i == end_ind {
      raise self.unexpected_end_of_format(end_ind)
    }
    match self.char_at(i) {
      ']' => return i + 1
      '-' => {
        // after `c-`
        let i1 = i + 1
        if i1 == end_ind {
          raise self.unexpected_end_of_format(end_ind)
        }
        match self.char_at(i1) {
          ']' => return i1 + 1
          '%' => {
            if i1 + 1 == end_ind {
              raise self.unexpected_end_of_format(end_ind)
            }
            if !(self.char_at(i1 + 1) is ('%' | '@')) {
              raise fail_single_percent(i1)
            }
            i = i1 + 2
          }
          _ => i = i1 + 1
        }
        // the content, until the first ']'
        for ;; {
          if i == end_ind {
            raise self.unexpected_end_of_format(end_ind)
          }
          match self.char_at(i) {
            ']' => return i + 1
            '-' => i += 1
            ch => {
              c = ch
              i += 1
              break
            }
          }
        }
      }
      '%' | '@' as c2 if c == '%' => {
        ignore(c2)
        i += 1
        // the content, until the first ']'
        for ;; {
          if i == end_ind {
            raise self.unexpected_end_of_format(end_ind)
          }
          match self.char_at(i) {
            ']' => return i + 1
            '-' => i += 1
            ch => {
              c = ch
              i += 1
              break
            }
          }
        }
      }
      c2 => {
        if c == '%' {
          raise fail_single_percent(i)
        }
        c = c2
        i += 1
      }
    }
  }
}

///|
/// Consume all next spaces, raise an error if end_ind is reached.
fn FormatParser::parse_spaces(
  self : FormatParser,
  str_ind : Int,
  end_ind : Int,
) -> Int raise FormatError {
  let mut str_ind = str_ind
  for ;; {
    if str_ind == end_ind {
      raise self.unexpected_end_of_format(end_ind)
    }
    if self.char_at(str_ind) != ' ' {
      return str_ind
    }
    str_ind += 1
  }
}

///|
/// Read a positive integer, raise an error if end_ind is reached.
fn FormatParser::parse_positive(
  self : FormatParser,
  str_ind : Int,
  end_ind : Int,
) -> (Int, Int) raise FormatError {
  let mut str_ind = str_ind
  let mut acc = 0L
  for ;; {
    if str_ind == end_ind {
      raise self.unexpected_end_of_format(end_ind)
    }
    match self.char_at(str_ind) {
      '0'..='9' as c => {
        acc = acc * 10 + (c.to_int() - '0'.to_int()).to_int64()
        if acc > max_string_length {
          raise FormatError(
            "invalid format \{self.quoted()}: integer \{acc} is greater than the limit \{max_string_length}",
          )
        }
        str_ind += 1
      }
      _ => break
    }
  }
  // such widths can't be printed anyway
  (str_ind, if acc > 0x7FFFFFFFL { 0x7FFFFFFF } else { acc.to_int() })
}

///|
/// Read a positive or negative integer, raise an error if end_ind is
/// reached.
fn FormatParser::parse_integer(
  self : FormatParser,
  str_ind : Int,
  end_ind : Int,
) -> (Int, Int) raise FormatError {
  if str_ind == end_ind {
    raise self.unexpected_end_of_format(end_ind)
  }
  match self.char_at(str_ind) {
    '0'..='9' => self.parse_positive(str_ind, end_ind)
    '-' => {
      if str_ind + 1 == end_ind {
        raise self.unexpected_end_of_format(end_ind)
      }
      match self.char_at(str_ind + 1) {
        '0'..='9' => {
          let (next_ind, n) = self.parse_positive(str_ind + 1, end_ind)
          (next_ind, -n)
        }
        c => raise self.expected_character(str_ind + 1, "digit", c)
      }
    }
    _ => abort("parse_integer")
  }
}

///|
/// Search the end of the current sub-format (the corresponding "%}" or
/// "%)").
fn FormatParser::search_subformat_end(
  self : FormatParser,
  str_ind : Int,
  end_ind : Int,
  c : Char,
) -> Int raise FormatError {
  let mut str_ind = str_ind
  for ;; {
    if str_ind == end_ind {
      raise FormatError(
        "invalid format \{self.quoted()}: unclosed sub-format, expected \"%\{c}\" at character number \{self.pos(end_ind)}",
      )
    }
    if self.char_at(str_ind) != '%' {
      str_ind += 1
      continue
    }
    if str_ind + 1 == end_ind {
      raise self.unexpected_end_of_format(end_ind)
    }
    let c1 = self.char_at(str_ind + 1)
    if c1 == c {
      // end of format found
      return str_ind
    }
    match c1 {
      '_' => {
        // search for "%_(" or "%_{"
        if str_ind + 2 == end_ind {
          raise self.unexpected_end_of_format(end_ind)
        }
        match self.char_at(str_ind + 2) {
          '{' =>
            str_ind = self.search_subformat_end(str_ind + 3, end_ind, '}') + 2
          '(' =>
            str_ind = self.search_subformat_end(str_ind + 3, end_ind, ')') + 2
          _ => str_ind += 3
        }
      }
      '{' => str_ind = self.search_subformat_end(str_ind + 2, end_ind, '}') + 2
      '(' => str_ind = self.search_subformat_end(str_ind + 2, end_ind, ')') + 2
      '}' => raise self.expected_character(str_ind + 1, "character ')'", '}')
      ')' => raise self.expected_character(str_ind + 1, "character '}'", ')')
      _ => str_ind += 2
    }
  }
}

///|
/// Check if symb is a valid int conversion after "%l", "%n" or "%L".
fn is_int_base(c : Char) -> Bool {
  c is ('d' | 'i' | 'x' | 'X' | 'o' | 'u')
}

///|
/// Compute the flags of an integer conversion like OCaml's
/// `compute_int_conv` in legacy mode: (plus, space, alt, group).
fn int_conv(
  plus : Bool,
  hash : Bool,
  space : Bool,
  symb : Char,
) -> (Bool, Bool, Bool, Bool) {
  match (plus, hash, space, symb) {
    (false, false, false, _) => (false, false, false, false)
    (false, false, true, 'd' | 'i') => (false, true, false, false)
    (true, false, false, 'd' | 'i') => (true, false, false, false)
    (false, true, false, 'd' | 'i' | 'u') => (false, false, false, true)
    (false, true, false, 'x' | 'X' | 'o') => (false, false, true, false)
    // legacy: '#' wins for 'x', 'X' and 'o'
    (_, true, _, 'x' | 'X' | 'o') => (false, false, true, false)
    // legacy: '#' is ignored
    (_, true, _, 'd' | 'i' | 'u') => int_conv(plus, false, space, symb)
    // legacy: '+' wins over ' '
    (true, _, true, _) => int_conv(plus, hash, false, symb)
    // legacy: ' ' is ignored
    (false, _, true, _) => int_conv(plus, hash, false, symb)
    // legacy: '+' is ignored
    (true, _, false, _) => int_conv(false, hash, space, symb)
    // other conversions don't take flags
    (false, true, false, _) => (false, false, false, false)
  }
}

///|
fn make_int_conv(
  size : IntSize,
  symb : Char,
  flags : (Bool, Bool, Bool, Bool),
) -> Conv {
  let (plus, space, alt, group) = flags
  CInt(size, symb, plus, space, alt, group)
}

///|
/// The signature of a format: a canonical representation of its
/// conversions, like OCaml's `string_of_fmtty (fmtty_of_fmt fmt)`.
fn signature(items : @list.List[Item]) -> String {
  let buf = StringBuilder()
  fn pad_arg(p : Pad) -> Unit {
    if p is ArgPad(_) {
      buf.write_string("%i")
    }
  }

  fn prec_arg(p : Prec) -> Unit {
    if p is ArgPrec {
      buf.write_string("%i")
    }
  }

  fn go(items : Iter[Item]) -> Unit {
    for item in items {
      match item {
        Conversion(conv, pad, prec) => {
          match conv {
            CChar | CCamlChar | CAlpha | CTheta => ()
            CString | CCamlString | CBool => pad_arg(pad)
            CInt(_, _, _, _, _, _) | CFloat(_, _) => {
              pad_arg(pad)
              prec_arg(prec)
            }
          }
          buf.write_string(
            match conv {
              CChar | CCamlChar => "%c"
              CString | CCamlString => "%s"
              CInt(OInt, _, _, _, _, _) => "%i"
              CInt(I32, _, _, _, _, _) => "%li"
              CInt(I64, _, _, _, _, _) => "%Li"
              CInt(Native, _, _, _, _, _) => "%ni"
              CFloat(_, _) => "%f"
              CBool => "%B"
              CAlpha => "%a"
              CTheta => "%t"
            },
          )
        }
        OpenBoxGen(sub) | OpenTagGen(sub) => go(sub.iter())
        FormatArg(s) => buf.write_string("%{" + s + "%}")
        FormatSubst(s) => buf.write_string("%(" + s + "%)")
        ScanCounter => buf.write_string("%i")
        Invalid(_, s) => buf.write_string(s)
        Lit(_) | Flush | Formatting(_) => ()
      }
    }
  }

  go(items.iter())
  buf.to_string()
}
