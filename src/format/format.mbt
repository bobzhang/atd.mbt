// A port of the core pretty-printing engine of OCaml's `Format` module
// (OCaml 4.14), restricted to what is needed by Easy_format and Yojson:
// boxes, break hints, forced newlines and flushing. Tags, tabulation boxes
// and ellipsis handling are not supported.
//
// Text widths are measured in UTF-8 bytes, like OCaml's `String.length`,
// so that line breaking decisions are identical to the OCaml
// implementation.

///|
/// Kinds of pretty-printing boxes.
priv enum BoxType {
  HBox
  VBox
  HVBox
  HOVBox
  Box
  Fits
}

///|
priv enum Token {
  Text(String)
  Break(fits~ : (String, Int, String), breaks~ : (String, Int, String))
  Begin(Int, BoxType)
  End
  Newline
}

///|
priv struct QueueElem {
  mut size : Int
  token : Token
  length : Int
}

///|
priv struct ScanElem {
  left_total : Int
  queue_elem : QueueElem
}

///|
priv struct FormatElem {
  box_type : BoxType
  width : Int
}

///|
let pp_infinity : Int = 1000000010

///|
let size_unknown : Int = -1

///|
/// A pretty-printer writing into an internal buffer.
struct Formatter {
  scan_stack : Array[ScanElem]
  format_stack : Array[FormatElem]
  mut margin : Int
  mut min_space_left : Int
  mut max_indent : Int
  mut space_left : Int
  mut current_indent : Int
  mut is_new_line : Bool
  mut left_total : Int
  mut right_total : Int
  mut curr_depth : Int
  max_boxes : Int
  queue : @deque.Deque[QueueElem]
  out : StringBuilder
}

///|
/// Length of a string in UTF-8 bytes, matching OCaml's `String.length`.
pub fn utf8_length(s : StringView) -> Int {
  let mut n = 0
  for c in s {
    let code = c.to_int()
    n += if code < 0x80 {
      1
    } else if code < 0x800 {
      2
    } else if code < 0x10000 {
      3
    } else {
      4
    }
  }
  n
}

///|
fn initialize_scan_stack(stack : Array[ScanElem]) -> Unit {
  stack.clear()
  let queue_elem = { size: size_unknown, token: Text(""), length: 0, }
  stack.push({ left_total: -1, queue_elem, })
}

///|
/// Create a new formatter with the default OCaml settings
/// (margin 78, minimum space left 10).
pub fn Formatter::new(margin? : Int = 78) -> Formatter {
  let queue = @deque.Deque([])
  let sys_tok = { size: size_unknown, token: Begin(0, HOVBox), length: 0, }
  queue.push_back(sys_tok)
  let scan_stack = []
  initialize_scan_stack(scan_stack)
  scan_stack.push({ left_total: 1, queue_elem: sys_tok, })
  let min_space_left = 10
  let f = {
    scan_stack,
    format_stack: [],
    margin: 78,
    min_space_left,
    max_indent: 78 - min_space_left,
    space_left: 78,
    current_indent: 0,
    is_new_line: true,
    left_total: 1,
    right_total: 1,
    curr_depth: 1,
    max_boxes: 2147483647,
    queue,
    out: StringBuilder(),
  }
  if margin != 78 {
    f.set_margin(margin)
  }
  f
}

///|
fn pp_limit(n : Int) -> Int {
  if n < pp_infinity {
    n
  } else {
    pp_infinity - 1
  }
}

///|
fn Formatter::set_min_space_left(self : Formatter, n : Int) -> Unit {
  if n >= 1 {
    let n = pp_limit(n)
    self.min_space_left = n
    self.max_indent = self.margin - self.min_space_left
    self.rinit()
  }
}

///|
fn Formatter::set_max_indent(self : Formatter, n : Int) -> Unit {
  if n > 1 {
    self.set_min_space_left(self.margin - n)
  }
}

///|
/// Set the right margin, like OCaml's `Format.pp_set_margin`.
pub fn Formatter::set_margin(self : Formatter, n : Int) -> Unit {
  if n >= 1 {
    let n = pp_limit(n)
    self.margin = n
    let new_max_indent = if self.max_indent <= self.margin {
      self.max_indent
    } else {
      let a = self.margin - self.min_space_left
      let b = self.margin / 2
      let m = if a > b { a } else { b }
      if m > 1 {
        m
      } else {
        1
      }
    }
    self.set_max_indent(new_max_indent)
  }
}

///|
fn Formatter::output_string(self : Formatter, s : String) -> Unit {
  self.out.write_string(s)
}

///|
fn Formatter::output_newline(self : Formatter) -> Unit {
  self.out.write_char('\n')
}

///|
fn Formatter::output_spaces(self : Formatter, n : Int) -> Unit {
  for _ in 0..<n {
    self.out.write_char(' ')
  }
}

///|
fn Formatter::enqueue(self : Formatter, token : QueueElem) -> Unit {
  self.right_total = self.right_total + token.length
  self.queue.push_back(token)
}

///|
fn Formatter::clear_queue(self : Formatter) -> Unit {
  self.left_total = 1
  self.right_total = 1
  self.queue.clear()
}

///|
fn Formatter::format_pp_text(
  self : Formatter,
  size : Int,
  text : String,
) -> Unit {
  self.space_left = self.space_left - size
  self.output_string(text)
  self.is_new_line = false
}

///|
fn Formatter::format_string(self : Formatter, s : String) -> Unit {
  if s != "" {
    self.format_pp_text(utf8_length(s), s)
  }
}

///|
fn Formatter::break_new_line(
  self : Formatter,
  breaks : (String, Int, String),
  width : Int,
) -> Unit {
  let (before, offset, after) = breaks
  self.format_string(before)
  self.output_newline()
  self.is_new_line = true
  let indent = self.margin - width + offset
  let real_indent = if self.max_indent < indent {
    self.max_indent
  } else {
    indent
  }
  self.current_indent = real_indent
  self.space_left = self.margin - self.current_indent
  self.output_spaces(self.current_indent)
  self.format_string(after)
}

///|
fn Formatter::break_line(self : Formatter, width : Int) -> Unit {
  self.break_new_line(("", 0, ""), width)
}

///|
fn Formatter::break_same_line(
  self : Formatter,
  fits : (String, Int, String),
) -> Unit {
  let (before, width, after) = fits
  self.format_string(before)
  self.space_left = self.space_left - width
  self.output_spaces(width)
  self.format_string(after)
}

///|
fn Formatter::force_break_line(self : Formatter) -> Unit {
  match self.format_stack.last() {
    None => self.output_newline()
    Some({ box_type, width, }) =>
      if width > self.space_left {
        match box_type {
          Fits | HBox => ()
          VBox | HVBox | HOVBox | Box => self.break_line(width)
        }
      }
  }
}

///|
fn Formatter::format_pp_token(
  self : Formatter,
  size : Int,
  token : Token,
) -> Unit {
  match token {
    Text(s) => self.format_pp_text(size, s)
    Begin(off, ty) => {
      let insertion_point = self.margin - self.space_left
      if insertion_point > self.max_indent {
        self.force_break_line()
      }
      let width = self.space_left - off
      let box_type = match ty {
        VBox => VBox
        HBox | HVBox | HOVBox | Box | Fits =>
          if size > self.space_left {
            ty
          } else {
            Fits
          }
      }
      self.format_stack.push({ box_type, width, })
    }
    End => ignore(self.format_stack.pop())
    Newline =>
      match self.format_stack.last() {
        None => self.output_newline()
        Some({ width, .. }) => self.break_line(width)
      }
    Break(fits~, breaks~) => {
      let (before, off, _) = breaks
      match self.format_stack.last() {
        None => ()
        Some({ box_type, width, }) =>
          match box_type {
            HOVBox =>
              if size + utf8_length(before) > self.space_left {
                self.break_new_line(breaks, width)
              } else {
                self.break_same_line(fits)
              }
            Box =>
              if self.is_new_line {
                self.break_same_line(fits)
              } else if size + utf8_length(before) > self.space_left {
                self.break_new_line(breaks, width)
              } else if self.current_indent > self.margin - width + off {
                self.break_new_line(breaks, width)
              } else {
                self.break_same_line(fits)
              }
            HVBox => self.break_new_line(breaks, width)
            Fits => self.break_same_line(fits)
            VBox => self.break_new_line(breaks, width)
            HBox => self.break_same_line(fits)
          }
      }
    }
  }
}

///|
fn Formatter::advance_left(self : Formatter) -> Unit {
  while self.queue.front() is Some({ size, token, length, }) {
    let pending_count = self.right_total - self.left_total
    if size >= 0 || pending_count >= self.space_left {
      ignore(self.queue.pop_front())
      let size = if size >= 0 { size } else { pp_infinity }
      self.format_pp_token(size, token)
      self.left_total = length + self.left_total
    } else {
      break
    }
  }
}

///|
fn Formatter::enqueue_advance(self : Formatter, tok : QueueElem) -> Unit {
  self.enqueue(tok)
  self.advance_left()
}

///|
fn Formatter::set_size(self : Formatter, ty : Bool) -> Unit {
  match self.scan_stack.last() {
    None => ()
    Some({ left_total, queue_elem, }) => {
      let size = queue_elem.size
      if left_total < self.left_total {
        initialize_scan_stack(self.scan_stack)
      } else {
        match queue_elem.token {
          Break(..) =>
            if ty {
              queue_elem.size = self.right_total + size
              ignore(self.scan_stack.pop())
            }
          Begin(_, _) =>
            if !ty {
              queue_elem.size = self.right_total + size
              ignore(self.scan_stack.pop())
            }
          Text(_) | End | Newline => ()
        }
      }
    }
  }
}

///|
fn Formatter::scan_push(self : Formatter, b : Bool, token : QueueElem) -> Unit {
  self.enqueue(token)
  if b {
    self.set_size(true)
  }
  self.scan_stack.push({ left_total: self.right_total, queue_elem: token, })
}

///|
fn Formatter::open_box_gen(
  self : Formatter,
  indent : Int,
  br_ty : BoxType,
) -> Unit {
  self.curr_depth = self.curr_depth + 1
  if self.curr_depth < self.max_boxes {
    let size = -self.right_total
    let elem = { size, token: Begin(indent, br_ty), length: 0, }
    self.scan_push(false, elem)
  }
}

///|
fn Formatter::open_sys_box(self : Formatter) -> Unit {
  self.open_box_gen(0, HOVBox)
}

///|
/// Close the most recently opened box.
pub fn Formatter::close_box(self : Formatter) -> Unit {
  if self.curr_depth > 1 {
    if self.curr_depth < self.max_boxes {
      self.enqueue({ size: 0, token: End, length: 0, })
      self.set_size(true)
      self.set_size(false)
    }
    self.curr_depth = self.curr_depth - 1
  }
}

///|
fn Formatter::rinit(self : Formatter) -> Unit {
  self.clear_queue()
  initialize_scan_stack(self.scan_stack)
  self.format_stack.clear()
  self.current_indent = 0
  self.curr_depth = 0
  self.space_left = self.margin
  self.open_sys_box()
}

///|
fn Formatter::flush_queue(self : Formatter, b : Bool) -> Unit {
  while self.curr_depth > 1 {
    self.close_box()
  }
  self.right_total = pp_infinity
  self.advance_left()
  if b {
    self.output_newline()
  }
  self.rinit()
}

///|
/// Print a string whose width is its UTF-8 byte length.
pub fn Formatter::print_string(self : Formatter, s : String) -> Unit {
  self.print_as(utf8_length(s), s)
}

///|
/// Print a string, pretending that its width is `size`.
pub fn Formatter::print_as(self : Formatter, size : Int, s : String) -> Unit {
  if self.curr_depth < self.max_boxes {
    self.enqueue_advance({ size, token: Text(s), length: size, })
  }
}

///|
/// Print a single character.
pub fn Formatter::print_char(self : Formatter, c : Char) -> Unit {
  self.print_string(c.to_string())
}

///|
/// Open a horizontal box.
pub fn Formatter::open_hbox(self : Formatter) -> Unit {
  self.open_box_gen(0, HBox)
}

///|
/// Open a vertical box.
pub fn Formatter::open_vbox(self : Formatter, indent : Int) -> Unit {
  self.open_box_gen(indent, VBox)
}

///|
/// Open a horizontal/vertical box.
pub fn Formatter::open_hvbox(self : Formatter, indent : Int) -> Unit {
  self.open_box_gen(indent, HVBox)
}

///|
/// Open a horizontal-or-vertical compacting box.
pub fn Formatter::open_hovbox(self : Formatter, indent : Int) -> Unit {
  self.open_box_gen(indent, HOVBox)
}

///|
/// Open a structural compacting box.
pub fn Formatter::open_box(self : Formatter, indent : Int) -> Unit {
  self.open_box_gen(indent, Box)
}

///|
/// Flush all pending material.
pub fn Formatter::print_flush(self : Formatter) -> Unit {
  self.flush_queue(false)
}

///|
/// Flush all pending material and print a newline.
pub fn Formatter::print_newline(self : Formatter) -> Unit {
  self.flush_queue(true)
}

///|
/// Force a newline in the current box.
pub fn Formatter::force_newline(self : Formatter) -> Unit {
  if self.curr_depth < self.max_boxes {
    self.enqueue_advance({ size: 0, token: Newline, length: 0, })
  }
}

///|
/// Generalized break hint.
pub fn Formatter::print_custom_break(
  self : Formatter,
  fits~ : (String, Int, String),
  breaks~ : (String, Int, String),
) -> Unit {
  let (before, width, after) = fits
  if self.curr_depth < self.max_boxes {
    let size = -self.right_total
    let token = Break(fits~, breaks~)
    let length = utf8_length(before) + width + utf8_length(after)
    self.scan_push(true, { size, token, length, })
  }
}

///|
/// Break hint: `width` spaces if the line is not split, otherwise a newline
/// with `offset` added to the indentation of the box.
pub fn Formatter::print_break(
  self : Formatter,
  width : Int,
  offset : Int,
) -> Unit {
  self.print_custom_break(fits=("", width, ""), breaks=("", offset, ""))
}

///|
/// Break hint printing a space if the line is not split.
pub fn Formatter::print_space(self : Formatter) -> Unit {
  self.print_break(1, 0)
}

///|
/// Break hint printing nothing if the line is not split.
pub fn Formatter::print_cut(self : Formatter) -> Unit {
  self.print_break(0, 0)
}

///|
/// Return the text printed so far (call `print_flush` first).
pub fn Formatter::contents(self : Formatter) -> String {
  self.out.to_string()
}
