// Lexer for the ATD language, a hand-written port of `lexer.mll`.
// It operates on the UTF-8 bytes of the input, following ocamllex's
// longest-match semantics.

///|
priv enum Token {
  OpParen
  ClParen
  OpBrack
  ClBrack
  OpCurl
  ClCurl
  Lt
  Gt
  Semicolon
  Comma
  Colon
  Star
  Bar
  EqTok
  Question
  Tilde
  Dot
  From
  ImportKw
  As
  TypeKw
  Of
  InheritKw
  Lident(String)
  Uident(String)
  Tident(String)
  StringLit(String)
  Eof
} derive(Eq)

///|
priv struct Lexer {
  src : Bytes
  fname : String
  mut pos : Int
  mut lnum : Int
  mut bol : Int
  /// Start of the current lexeme
  mut start : Pos
}

///|
fn Lexer::Lexer(src : Bytes, fname~ : String, lnum~ : Int) -> Lexer {
  {
    src,
    fname,
    pos: 0,
    lnum,
    bol: 0,
    start: { fname, lnum, bol: 0, cnum: 0, },
  }
}

///|
fn Lexer::curr_pos(self : Lexer) -> Pos {
  { fname: self.fname, lnum: self.lnum, bol: self.bol, cnum: self.pos, }
}

///|
fn Lexer::peek(self : Lexer, offset : Int) -> Int {
  let i = self.pos + offset
  if i < self.src.length() {
    self.src[i].to_int()
  } else {
    -1
  }
}

///|
fn Lexer::newline(self : Lexer) -> Unit {
  self.lnum += 1
  self.bol = self.pos
}

///|
fn[T] Lexer::error(self : Lexer, msg : String) -> T raise AtdError {
  let loc = Loc(self.start, self.curr_pos())
  error(string_of_loc(loc) + "\n" + msg)
}

///|
fn is_upper(c : Int) -> Bool {
  c >= 'A' && c <= 'Z'
}

///|
fn is_lower(c : Int) -> Bool {
  c >= 'a' && c <= 'z'
}

///|
fn is_digit(c : Int) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_identchar(c : Int) -> Bool {
  is_upper(c) || is_lower(c) || is_digit(c) || c == '_' || c == '\''
}

///|
fn is_hex(c : Int) -> Bool {
  is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
fn int_of_hex(c : Int) -> Int {
  if is_digit(c) {
    c - 48
  } else if c >= 'a' && c <= 'f' {
    c - 87
  } else {
    c - 55
  }
}

///|
/// Decode bytes as UTF-8, replacing invalid sequences.
fn decode_utf8(b : BytesView) -> String {
  @utf8.decode_lossy(b)
}

///|
/// Length of an lident starting at offset `i` (0 if none).
fn Lexer::lident_length(self : Lexer, i : Int) -> Int {
  let c = self.peek(i)
  let mut n = if is_lower(c) {
    1
  } else if c == '_' && is_identchar(self.peek(i + 1)) {
    2
  } else {
    return 0
  }
  while is_identchar(self.peek(i + n)) {
    n += 1
  }
  n
}

///|
fn Lexer::substring(self : Lexer, start : Int, end_ : Int) -> String {
  decode_utf8(self.src[start:end_])
}

///|
fn keyword_or_lident(s : String) -> Token {
  match s {
    "from" => From
    "import" => ImportKw
    "as" => As
    "type" => TypeKw
    "of" => Of
    "inherit" => InheritKw
    _ => Lident(s)
  }
}

///|
/// Return the next token with its location.
fn Lexer::token(self : Lexer) -> (Token, Loc) raise AtdError {
  for ;; {
    self.start = self.curr_pos()
    let c = self.peek(0)
    let simple = match c {
      '(' => if self.peek(1) == '*' { None } else { Some(OpParen) }
      ')' => Some(ClParen)
      '[' => Some(OpBrack)
      ']' => Some(ClBrack)
      '{' => Some(OpCurl)
      '}' => Some(ClCurl)
      '<' => Some(Lt)
      '>' => Some(Gt)
      ';' => Some(Semicolon)
      ',' => Some(Comma)
      ':' => Some(Colon)
      '*' => Some(Star)
      '|' => Some(Bar)
      '=' => Some(EqTok)
      '?' => Some(Question)
      '~' => Some(Tilde)
      '.' => Some(Dot)
      _ => None
    }
    match simple {
      Some(tok) => {
        self.pos += 1
        return (tok, Loc(self.start, self.curr_pos()))
      }
      None => ()
    }
    if c == -1 {
      return (Eof, Loc(self.start, self.curr_pos()))
    }
    if c == '(' {
      // "(*"
      self.pos += 2
      self.comment(1)
      continue
    }
    if c == '\n' || (c == '\r' && self.peek(1) == '\n') {
      self.pos += if c == '\r' { 2 } else { 1 }
      self.newline()
      continue
    }
    if c == ' ' || c == '\t' {
      while self.peek(0) == ' ' || self.peek(0) == '\t' {
        self.pos += 1
      }
      continue
    }
    let n = self.lident_length(0)
    if n > 0 {
      let s = self.substring(self.pos, self.pos + n)
      self.pos += n
      return (keyword_or_lident(s), Loc(self.start, self.curr_pos()))
    }
    if is_upper(c) {
      let mut n = 1
      while is_identchar(self.peek(n)) {
        n += 1
      }
      let s = self.substring(self.pos, self.pos + n)
      self.pos += n
      return (Uident(s), Loc(self.start, self.curr_pos()))
    }
    if c == '\'' {
      let n = self.lident_length(1)
      if n > 0 {
        let s = self.substring(self.pos + 1, self.pos + 1 + n)
        self.pos += 1 + n
        return (Tident(s), Loc(self.start, self.curr_pos()))
      }
      self.pos += 1
      let s = self.string(false)
      // like ocamllex, the start of the token is the start of the last
      // lexeme matched by the string rule, i.e. the closing quote
      return (StringLit(s), Loc(self.start, self.curr_pos()))
    }
    if c == '"' {
      self.pos += 1
      let s = self.string(true)
      return (StringLit(s), Loc(self.start, self.curr_pos()))
    }
    self.pos += 1
    let bytes = Bytes::from_array([c.to_byte()])
    let s = ocaml_escaped_bytes(bytes)
    self.error("Illegal character \"\{s}\"")
  }
}

///|
/// OCaml's `String.escaped` applied to raw bytes.
fn ocaml_escaped_bytes(b : BytesView) -> String {
  let buf = StringBuilder()
  for byte in b {
    let b = byte.to_int()
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
  }
  buf.to_string()
}

///|
/// Lex the contents of a string literal, after the opening quote.
fn Lexer::string(self : Lexer, double_quoted : Bool) -> String raise AtdError {
  let buf = @buffer.Buffer()
  for ;; {
    self.start = self.curr_pos()
    let c = self.peek(0)
    match c {
      -1 => self.error("Unterminated string")
      '"' => {
        self.pos += 1
        if double_quoted {
          break
        }
        buf.write_byte(b'"')
      }
      '\'' => {
        self.pos += 1
        if !double_quoted {
          break
        }
        buf.write_byte(b'\'')
      }
      '\\' => {
        let c1 = self.peek(1)
        match c1 {
          '\\' | '"' | '\'' => {
            buf.write_byte(c1.to_byte())
            self.pos += 2
          }
          'x' if is_hex(self.peek(2)) && is_hex(self.peek(3)) => {
            let b = int_of_hex(self.peek(2)) * 16 + int_of_hex(self.peek(3))
            buf.write_byte(b.to_byte())
            self.pos += 4
          }
          _ if is_digit(c1) && is_digit(self.peek(2)) && is_digit(self.peek(3)) => {
            let x = (c1 - 48) * 100 +
              (self.peek(2) - 48) * 10 +
              self.peek(3) -
              48
            self.pos += 4
            if x > 255 {
              self.error("Invalid escape sequence")
            }
            buf.write_byte(x.to_byte())
          }
          'n' => {
            buf.write_byte(b'\n')
            self.pos += 2
          }
          'r' => {
            buf.write_byte(b'\r')
            self.pos += 2
          }
          't' => {
            buf.write_byte(b'\t')
            self.pos += 2
          }
          'b' => {
            buf.write_byte(b'\b')
            self.pos += 2
          }
          '\n' => {
            self.pos += 2
            self.newline()
            while self.peek(0) == ' ' || self.peek(0) == '\t' {
              self.pos += 1
            }
          }
          '\r' if self.peek(2) == '\n' => {
            self.pos += 3
            self.newline()
            while self.peek(0) == ' ' || self.peek(0) == '\t' {
              self.pos += 1
            }
          }
          _ => {
            self.pos += 1
            self.error("Invalid escape sequence")
          }
        }
      }
      '\n' => {
        self.pos += 1
        self.newline()
        buf.write_byte(b'\n')
      }
      _ => {
        buf.write_byte(c.to_byte())
        self.pos += 1
      }
    }
  }
  decode_utf8(buf.contents())
}

///|
/// Skip a comment, after the opening `(*`.
fn Lexer::comment(self : Lexer, depth : Int) -> Unit raise AtdError {
  let mut depth = depth
  for ;; {
    self.start = self.curr_pos()
    let c = self.peek(0)
    if c == -1 {
      self.error("Unterminated comment")
    } else if c == '*' && self.peek(1) == ')' {
      self.pos += 2
      if depth > 1 {
        depth -= 1
      } else {
        break
      }
    } else if c == '(' && self.peek(1) == '*' {
      self.pos += 2
      depth += 1
    } else if c == '"' {
      self.pos += 1
      ignore(self.string(true))
    } else if c == '\n' || (c == '\r' && self.peek(1) == '\n') {
      self.pos += if c == '\r' { 2 } else { 1 }
      self.newline()
    } else {
      self.pos += 1
    }
  }
}
