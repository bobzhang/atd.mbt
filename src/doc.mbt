// Documentation in ATD's own "text" format, used in `<doc text="...">`.
// A port of `doc.ml` and `doc_lexer.mll`.

///|
/// Inline element of a paragraph.
pub(all) enum DocInline {
  Text(String)
  Code(String)
} derive(Eq, Debug)

///|
/// Block of documentation.
pub(all) enum DocBlock {
  Paragraph(Array[DocInline])
  Pre(Array[String])
} derive(Eq, Debug)

///|
/// Documentation: a list of blocks.
pub type Doc = Array[DocBlock]

///|
priv suberror DocFailure {
  DocFailure(String)
}

///|
fn is_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r' || c == '\n'
}

///|
fn is_space_no_nl(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r'
}

///|
fn is_par_not_special(c : Char) -> Bool {
  !(c == '\\' || c == '{' || c == '}' || is_space(c))
}

///|
fn is_verb_not_special(c : Char) -> Bool {
  !(c == '\\' || c == '}' || is_space(c))
}

///|
priv struct DocLexer {
  s : Array[Char]
  mut pos : Int
}

///|
fn DocLexer::at(self : DocLexer, i : Int) -> Char? {
  if i < self.s.length() {
    Some(self.s[i])
  } else {
    None
  }
}

///|
fn DocLexer::has_prefix(self : DocLexer, i : Int, p : String) -> Bool {
  let mut j = i
  for c in p {
    if self.at(j) != Some(c) {
      return false
    }
    j += 1
  }
  true
}

///|
fn DocLexer::count(self : DocLexer, i : Int, pred : (Char) -> Bool) -> Int {
  let mut j = i
  while self.at(j) is Some(c) && pred(c) {
    j += 1
  }
  j - i
}

///|
fn DocLexer::sub(self : DocLexer, i : Int, n : Int) -> String {
  String::from_array(self.s[i:i + n].to_owned())
}

///|
/// Length of a match of `line_break` ('\r'? '\n') at position i, or -1.
fn DocLexer::line_break(self : DocLexer, i : Int) -> Int {
  if self.at(i) == Some('\n') {
    1
  } else if self.at(i) == Some('\r') && self.at(i + 1) == Some('\n') {
    2
  } else {
    -1
  }
}

///|
/// Pick the longest match; ties are resolved in favor of the first rule.
/// `candidates` holds the match length of each rule, -1 for no match.
fn longest(candidates : Array[Int]) -> (Int, Int) {
  let mut best = -1
  let mut best_len = -1
  for i, len in candidates {
    if len > best_len {
      best = i
      best_len = len
    }
  }
  (best, best_len)
}

///|
fn close_paragraph(
  a1 : Array[DocBlock],
  a2 : Array[DocInline],
  a3 : Array[String],
) -> Unit {
  let s = a3.join("")
  if s != "" {
    a2.push(Text(s))
  }
  if !a2.is_empty() {
    a1.push(Paragraph(a2.copy()))
  }
  a2.clear()
  a3.clear()
}

///|
fn DocLexer::paragraph(self : DocLexer) -> Array[DocBlock] raise DocFailure {
  let a1 : Array[DocBlock] = []
  let a2 : Array[DocInline] = []
  let a3 : Array[String] = []
  for ;; {
    let i = self.pos
    let at_eof = i >= self.s.length()
    // R1: '\\' ('\\' | "{{" | "{{{")
    let r1 = if self.at(i) == Some('\\') {
      if self.has_prefix(i + 1, "{{{") {
        4
      } else if self.has_prefix(i + 1, "{{") {
        3
      } else if self.at(i + 1) == Some('\\') {
        2
      } else {
        -1
      }
    } else {
      -1
    }
    // R2: "{{"
    let r2 = if self.has_prefix(i, "{{") { 2 } else { -1 }
    // R3: space* "{{{" line_break?
    let sp = self.count(i, is_space)
    let r3 = if self.has_prefix(i + sp, "{{{") {
      let lb = self.line_break(i + sp + 3)
      sp + 3 + (if lb > 0 { lb } else { 0 })
    } else {
      -1
    }
    // R4: par_not_special+
    let n4 = self.count(i, is_par_not_special)
    let r4 = if n4 > 0 { n4 } else { -1 }
    // R5: space'* "\n"? space'*
    let s1 = self.count(i, is_space_no_nl)
    let r5 = if self.at(i + s1) == Some('\n') {
      s1 + 1 + self.count(i + s1 + 1, is_space_no_nl)
    } else {
      s1
    }
    // R6: space'* "\n" (space'* "\n")+ space'*
    let r6 = {
      let mut j = i + self.count(i, is_space_no_nl)
      let mut newlines = 0
      let mut last_end = -1
      while self.at(j) == Some('\n') {
        j += 1
        newlines += 1
        last_end = j
        j += self.count(j, is_space_no_nl)
      }
      if newlines >= 2 {
        last_end - i + self.count(last_end, is_space_no_nl)
      } else {
        -1
      }
    }
    // R7: space* eof (the eof pseudo-character counts as one more char)
    let r7 = if i + sp >= self.s.length() { sp + 1 } else { -1 }
    // R8: any char
    let r8 = if at_eof { -1 } else { 1 }
    let (rule, len) = longest([r1, r2, r3, r4, r5, r6, r7, r8])
    match rule {
      0 => {
        a3.push(self.sub(i + 1, len - 1))
        self.pos += len
      }
      1 => {
        self.pos += len
        let code = self.inline_verbatim()
        let s = a3.join("")
        if s != "" {
          a2.push(Text(s))
        }
        a3.clear()
        a2.push(Code(code))
      }
      2 => {
        self.pos += len
        let pre = self.verbatim()
        close_paragraph(a1, a2, a3)
        a1.push(Pre(pre))
      }
      3 => {
        a3.push(self.sub(i, len))
        self.pos += len
      }
      4 => {
        a3.push(" ")
        self.pos += len
      }
      5 => {
        close_paragraph(a1, a2, a3)
        self.pos += len
      }
      6 => {
        close_paragraph(a1, a2, a3)
        return a1
      }
      _ => {
        a3.push(self.sub(i, 1))
        self.pos += 1
      }
    }
  }
}

///|
fn DocLexer::inline_verbatim(self : DocLexer) -> String raise DocFailure {
  let accu = []
  for ;; {
    let i = self.pos
    let v1 = if self.has_prefix(i, "\\\\") { 2 } else { -1 }
    let v2 = if self.has_prefix(i, "\\}}") { 3 } else { -1 }
    let n3 = self.count(i, is_space)
    let v3 = if n3 > 0 { n3 } else { -1 }
    let n4 = self.count(i, is_verb_not_special)
    let v4 = if n4 > 0 { n4 } else { -1 }
    let v5 = if i < self.s.length() { 1 } else { -1 }
    let v6 = if self.has_prefix(i + n3, "}}") { n3 + 2 } else { -1 }
    let v7 = if i >= self.s.length() { 1 } else { -1 }
    let (rule, len) = longest([v1, v2, v3, v4, v5, v6, v7])
    match rule {
      0 => accu.push("\\")
      1 => accu.push("}}")
      2 => accu.push(" ")
      3 => accu.push(self.sub(i, len))
      4 => accu.push(self.sub(i, 1))
      5 => {
        self.pos += len
        return accu.join("")
      }
      _ => raise DocFailure("Missing `}}'")
    }
    self.pos += len
  }
}

///|
fn count_leading_spaces(line : String) -> Int {
  let mut n = 0
  for c in line {
    if c == ' ' {
      n += 1
    } else {
      return n
    }
  }
  // blank line = infinite indentation
  2147483647
}

///|
/// Remove as many leading spaces as possible while maintaining the
/// relative visual positioning of the text.
fn trim_indentation(lines : Array[String]) -> Array[String] {
  match lines {
    [] => []
    _ => {
      let mut removable = 2147483647
      for line in lines {
        let n = count_leading_spaces(line)
        if n < removable {
          removable = n
        }
      }
      lines.map(str => {
        let chars = str.to_array()
        if removable <= chars.length() {
          String::from_array(chars[removable:].to_owned())
        } else {
          ""
        }
      })
    }
  }
}

///|
fn DocLexer::verbatim(self : DocLexer) -> Array[String] raise DocFailure {
  let lines = []
  let line = []
  for ;; {
    let i = self.pos
    let w1 = if self.has_prefix(i, "\\\\") { 2 } else { -1 }
    let w2 = if self.has_prefix(i, "\\}}}") { 4 } else { -1 }
    let w3 = if self.at(i) == Some('\t') { 1 } else { -1 }
    let w4 = self.line_break(i)
    let n5 = self.count(i, is_verb_not_special)
    let w5 = if n5 > 0 { n5 } else { -1 }
    let w6 = if i < self.s.length() { 1 } else { -1 }
    let lb = self.line_break(i)
    let lb = if lb > 0 { lb } else { 0 }
    let w7 = if self.has_prefix(i + lb, "}}}") { lb + 3 } else { -1 }
    let w8 = if i >= self.s.length() { 1 } else { -1 }
    let (rule, len) = longest([w1, w2, w3, w4, w5, w6, w7, w8])
    match rule {
      0 => line.push("\\")
      1 => line.push("}}}")
      2 => line.push("        ")
      3 => {
        lines.push(line.join(""))
        line.clear()
      }
      4 => line.push(self.sub(i, len))
      5 => line.push(self.sub(i, 1))
      6 => {
        self.pos += len
        lines.push(line.join(""))
        return trim_indentation(lines)
      }
      _ => raise DocFailure("Missing `}}}'")
    }
    self.pos += len
  }
}

///|
/// Parse documentation in ATD's text format.
pub fn parse_doc_text(loc : Loc, s : String) -> Doc raise AtdError {
  let lexer : DocLexer = { s: s.to_array(), pos: 0, }
  lexer.paragraph() catch {
    DocFailure(msg) =>
      error(
        "\{string_of_loc(loc)}:\nInvalid format for doc.text \{ocaml_quote(s)}:\nFailure(\{ocaml_quote(msg)})",
      )
  }
}

///|
/// Replace each match of one of the patterns (tried in order at each
/// position) by its replacement.
fn substitute(s : String, rules : Array[(String, String)]) -> String {
  let buf = StringBuilder()
  let chars = s.to_array()
  let mut i = 0
  while i < chars.length() {
    let mut matched = false
    for rule in rules {
      let (pat, repl) = rule
      let pc = pat.to_array()
      let mut ok = i + pc.length() <= chars.length()
      if ok {
        for k, c in pc {
          if chars[i + k] != c {
            ok = false
            break
          }
        }
      }
      if ok {
        buf.write_string(repl)
        i += pc.length()
        matched = true
        break
      }
    }
    if !matched {
      buf.write_char(chars[i])
      i += 1
    }
  }
  buf.to_string()
}

///|
fn escape_text(s : String) -> String {
  substitute(s, [("{{", "\\{\\{"), ("\\", "\\\\")])
}

///|
fn escape_code(s : String) -> String {
  substitute(s, [("}}", "\\}\\}"), ("\\", "\\\\")])
}

///|
fn escape_pre_line(s : String) -> String {
  substitute(s, [("}}}", "\\}\\}\\}"), ("\\", "\\\\")])
}

///|
/// OCaml's `String.trim`.
fn ocaml_trim(s : String) -> String {
  let is_ws = (c : Char) => {
    c == ' ' || c == '\u{0C}' || c == '\n' || c == '\r' || c == '\t'
  }
  let chars = s.to_array()
  let mut i = 0
  let mut j = chars.length()
  while i < j && is_ws(chars[i]) {
    i += 1
  }
  while j > i && is_ws(chars[j - 1]) {
    j -= 1
  }
  String::from_array(chars[i:j].to_owned())
}

///|
/// Replicates the upstream regexp `(?: \t\r\n)+`, which matches repeated
/// occurrences of the exact 4-character sequence " \t\r\n".
fn compact_whitespace(s : String) -> String {
  let chars = s.to_array()
  let buf = StringBuilder()
  let mut i = 0
  let is_seq = (i : Int) => {
    i + 4 <= chars.length() &&
    chars[i] == ' ' &&
    chars[i + 1] == '\t' &&
    chars[i + 2] == '\r' &&
    chars[i + 3] == '\n'
  }
  while i < chars.length() {
    if is_seq(i) {
      while is_seq(i) {
        i += 4
      }
      buf.write_char(' ')
    } else {
      buf.write_char(chars[i])
      i += 1
    }
  }
  buf.to_string()
}

///|
fn normalize_inline(s : String) -> String {
  compact_whitespace(ocaml_trim(s))
}

///|
fn print_doc_inline(x : DocInline) -> String {
  match x {
    Text(s) => escape_text(normalize_inline(s))
    Code(s) =>
      match escape_code(normalize_inline(s)) {
        "" => ""
        s => {
          let first_space = if s.has_prefix("{") { " " } else { "" }
          let last_space = if s.has_suffix("}") { " " } else { "" }
          "{{" + first_space + s + last_space + "}}"
        }
      }
  }
}

///|
fn print_doc_block(x : DocBlock) -> String {
  match x {
    Paragraph(xs) => xs.map(print_doc_inline).filter(s => s != "").join(" ")
    Pre(lines) => {
      let content = lines.map(escape_pre_line).join("\n")
      match content {
        "" => ""
        s => {
          let first_newline = if s.has_prefix("\n") { "" } else { "\n" }
          let last_newline = if s.has_suffix("\n") { "" } else { "\n" }
          "{{{" + first_newline + s + last_newline + "}}}"
        }
      }
    }
  }
}

///|
/// Print documentation in ATD's text format.
pub fn print_doc_text(blocks : Doc) -> String {
  blocks.map(print_doc_block).join("\n\n")
}

///|
/// All the valid annotations of the form `<doc ...>`.
pub let doc_annot_schema : Schema = [
  {
    section: "doc",
    fields: [
      (ModuleHead, "text"),
      (TypeDef, "text"),
      (Variant, "text"),
      (Field, "text"),
    ],
  },
]

///|
/// Extract and parse the documentation from an annotation.
pub fn get_doc(loc : Loc, an : Annot) -> Doc? raise AtdError {
  let mut err : AtdError? = None
  let res = annot_get_opt_field(
    an,
    parse=s => {
      Some(
        parse_doc_text(loc, s) catch {
          e => {
            err = Some(e)
            []
          }
        },
      )
    },
    sections=["doc"],
    field="text",
  )
  match err {
    Some(e) => raise e
    None => res
  }
}

///|
fn html_escape(buf : StringBuilder, s : String) -> Unit {
  for c in s {
    match c {
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      '&' => buf.write_string("&amp;")
      '"' => buf.write_string("&quot;")
      c => buf.write_char(c)
    }
  }
}

///|
/// Convert documentation to HTML.
pub fn html_of_doc(blocks : Doc) -> String {
  let buf = StringBuilder()
  buf.write_string("\n<div class=\"atd-doc\">\n")
  for block in blocks {
    match block {
      Paragraph(l) => {
        buf.write_string("<p>\n")
        for x in l {
          match x {
            Text(s) => html_escape(buf, s)
            Code(s) => {
              buf.write_string("<code>")
              html_escape(buf, s)
              buf.write_string("</code>")
            }
          }
        }
        buf.write_string("\n</p>\n")
      }
      Pre(lines) => {
        buf.write_string("<pre>\n")
        for line in lines {
          html_escape(buf, line)
          buf.write_char('\n')
        }
        buf.write_string("</pre>\n")
      }
    }
  }
  buf.write_string("\n</div>\n")
  buf.to_string()
}

///|
/// Split a string on sequences of blanks, ignoring leading and trailing
/// blanks.
pub fn split_on_blank(str : String) -> Array[String] {
  let res = []
  let cur = StringBuilder()
  for c in str {
    if is_space(c) {
      if cur.to_string() != "" {
        res.push(cur.to_string())
        cur.reset()
      }
    } else {
      cur.write_char(c)
    }
  }
  if cur.to_string() != "" {
    res.push(cur.to_string())
  }
  res
}

///|
/// Concatenate words into lines of at most `max_length` bytes, if
/// possible.
pub fn concatenate_into_lines(
  words : Array[String],
  max_length~ : Int,
) -> Array[String] {
  let max_length = if max_length < 0 { 0 } else { max_length }
  let lines = []
  let buf = StringBuilder()
  let mut len = 0
  for word in words {
    let word_len = @format.utf8_length(word)
    if len == 0 {
      buf.write_string(word)
      len = word_len
    } else if len + 1 + word_len <= max_length {
      buf.write_char(' ')
      buf.write_string(word)
      len = len + 1 + word_len
    } else {
      lines.push(buf.to_string())
      buf.reset()
      buf.write_string(word)
      len = word_len
    }
  }
  lines.push(buf.to_string())
  lines
}

///|
/// Rewrap a paragraph into lines of at most `max_length` bytes.
pub fn rewrap_paragraph(str : String, max_length~ : Int) -> Array[String] {
  concatenate_into_lines(split_on_blank(str), max_length~)
}
