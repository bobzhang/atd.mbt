// A JSON parser that keeps the exact text of every number (in
// `Json::Number(_, repr=Some(text))`), so that readers can check that a
// number is an integer and read 64-bit integers without loss.

///|
priv struct JsonParser {
  s : StringView
  mut i : Int
  mut depth : Int
}

///|
let max_nesting_depth : Int = 1024

///|
fn[T] JsonParser::fail(self : JsonParser, msg : String) -> T raise JsonError {
  // compute the line and column of the current position
  let mut line = 1
  let mut col = 1
  for k in 0..<self.i {
    if k < self.s.length() && self.s[k] == '\n' {
      line += 1
      col = 1
    } else {
      col += 1
    }
  }
  let msg = if self.i >= self.s.length() {
    "unexpected end of input"
  } else {
    msg
  }
  raise JsonError("invalid JSON: \{msg} at line \{line}, column \{col}")
}

///|
fn JsonParser::peek(self : JsonParser) -> Int {
  if self.i < self.s.length() {
    self.s[self.i].to_int()
  } else {
    -1
  }
}

///|
fn JsonParser::skip_blanks(self : JsonParser) -> Unit {
  while self.peek() is (' ' | '\t' | '\n' | '\r') {
    self.i += 1
  }
}

///|
fn JsonParser::expect_word(
  self : JsonParser,
  word : String,
  value : Json,
) -> Json raise JsonError {
  for c in word {
    if self.peek() != c.to_int() {
      self.fail("unexpected character")
    }
    self.i += 1
  }
  value
}

///|
fn JsonParser::value(self : JsonParser) -> Json raise JsonError {
  self.skip_blanks()
  match self.peek() {
    '{' => self.object()
    '[' => self.array()
    '"' => Json::string(self.string())
    't' => self.expect_word("true", Json::boolean(true))
    'f' => self.expect_word("false", Json::boolean(false))
    'n' => self.expect_word("null", Json::null())
    '-' | '0'..='9' => self.number()
    -1 => self.fail("unexpected end of input")
    _ => self.fail("unexpected character")
  }
}

///|
fn JsonParser::enter(self : JsonParser) -> Unit raise JsonError {
  self.depth += 1
  if self.depth > max_nesting_depth {
    self.fail("too deeply nested")
  }
}

///|
fn JsonParser::object(self : JsonParser) -> Json raise JsonError {
  self.enter()
  self.i += 1 // {
  let m : Map[String, Json] = Map([])
  self.skip_blanks()
  if self.peek() == '}' {
    self.i += 1
  } else {
    for ;; {
      self.skip_blanks()
      if self.peek() != '"' {
        self.fail("expected a string")
      }
      let key = self.string()
      self.skip_blanks()
      if self.peek() != ':' {
        self.fail("expected ':'")
      }
      self.i += 1
      m[key] = self.value()
      self.skip_blanks()
      match self.peek() {
        ',' => self.i += 1
        '}' => {
          self.i += 1
          break
        }
        _ => self.fail("expected ',' or '}'")
      }
    }
  }
  self.depth -= 1
  Json::object(m)
}

///|
fn JsonParser::array(self : JsonParser) -> Json raise JsonError {
  self.enter()
  self.i += 1 // [
  let l = []
  self.skip_blanks()
  if self.peek() == ']' {
    self.i += 1
  } else {
    for ;; {
      l.push(self.value())
      self.skip_blanks()
      match self.peek() {
        ',' => self.i += 1
        ']' => {
          self.i += 1
          break
        }
        _ => self.fail("expected ',' or ']'")
      }
    }
  }
  self.depth -= 1
  Json::array(l)
}

///|
fn hex_value(c : Int) -> Int {
  match c {
    '0'..='9' => c - '0'
    'a'..='f' => c - 'a' + 10
    'A'..='F' => c - 'A' + 10
    _ => -1
  }
}

///|
fn JsonParser::string(self : JsonParser) -> String raise JsonError {
  self.i += 1 // opening quote
  let buf = StringBuilder()
  for ;; {
    let c = self.peek()
    match c {
      -1 => self.fail("unterminated string")
      '"' => {
        self.i += 1
        break
      }
      '\\' => {
        self.i += 1
        let e = self.peek()
        self.i += 1
        match e {
          '"' => buf.write_char('"')
          '\\' => buf.write_char('\\')
          '/' => buf.write_char('/')
          'b' => buf.write_char('\b')
          'f' => buf.write_char('\u{0C}')
          'n' => buf.write_char('\n')
          'r' => buf.write_char('\r')
          't' => buf.write_char('\t')
          'u' => {
            let mut code = 0
            for _ in 0..<4 {
              let h = hex_value(self.peek())
              if h < 0 {
                self.fail("invalid \\u escape")
              }
              code = code * 16 + h
              self.i += 1
            }
            // UTF-16 code units are copied as they are, which handles
            // surrogate pairs
            buf.write_char(code.unsafe_to_char())
          }
          _ => self.fail("invalid escape sequence")
        }
      }
      c if c < 0x20 => self.fail("control character in string")
      _ => {
        buf.write_char(c.unsafe_to_char())
        self.i += 1
      }
    }
  }
  buf.to_string()
}

///|
fn JsonParser::digits(self : JsonParser) -> Int {
  let start = self.i
  while self.peek() is ('0'..='9') {
    self.i += 1
  }
  self.i - start
}

///|
fn JsonParser::number(self : JsonParser) -> Json raise JsonError {
  let start = self.i
  if self.peek() == '-' {
    self.i += 1
  }
  match self.peek() {
    '0' => self.i += 1
    '1'..='9' => ignore(self.digits())
    _ => self.fail("invalid number")
  }
  if self.peek() == '.' {
    self.i += 1
    if self.digits() == 0 {
      self.fail("invalid number")
    }
  }
  if self.peek() is ('e' | 'E') {
    self.i += 1
    if self.peek() is ('+' | '-') {
      self.i += 1
    }
    if self.digits() == 0 {
      self.fail("invalid number")
    }
  }
  let text = self.s[start:self.i].to_owned()
  let value = @string.parse_double(text) catch {
    _ => self.fail("invalid number")
  }
  Json::number(value, repr=text)
}

///|
/// Parse a JSON string. Unlike `@json.parse`, the exact text of every
/// number is kept in `Json::Number(_, repr=Some(text))`, which lets the
/// readers of integers reject non-integers such as `1.5` or `1.0` and read
/// 64-bit integers without loss of precision.
pub fn parse(s : StringView) -> Json raise JsonError {
  let p : JsonParser = { s, i: 0, depth: 0, }
  let v = p.value()
  p.skip_blanks()
  if p.i < s.length() {
    p.fail("unexpected data after the JSON value")
  }
  v
}
