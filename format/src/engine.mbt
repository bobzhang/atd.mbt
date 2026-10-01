// The pretty-printing engine, a port of OCaml's `format.ml` (OCaml 4.14).
//
// Copyright 1996 Institut National de Recherche en Informatique et en
// Automatique (OCaml), distributed under the terms of the GNU Lesser
// General Public License version 2.1, with the special exception on
// linking described in the file LICENSE.
//
// The algorithm is unchanged. Text widths are measured in UTF-8 bytes,
// like OCaml's `String.length` on UTF-8 strings, so that the output is
// identical to OCaml's for the same text; `print_as` gives an explicit
// width.

///|
/// The kinds of pretty-printing boxes.
priv enum BoxType {
  /// horizontal box: no line splitting
  HBox
  /// vertical box: every break hint splits the line
  VBox
  /// horizontal/vertical box: horizontal if it fits on the line, otherwise
  /// vertical
  HVBox
  /// horizontal or vertical compacting box: as much material as possible
  /// on each line
  HOVBox
  /// compacting box with enhanced box structure: break hints split the
  /// line if that moves to the left
  Box
  /// internal: a box whose contents fit on the line
  Fits
}

///|
/// A semantic tag.
pub(all) enum Stag {
  /// The tags of `open_tag` and of `@{<tag>` in format strings
  StringTag(String)
  /// Other tags, identified by a name; the default tag functions ignore
  /// them
  OtherTag(String)
} derive(Eq, Debug)

///|
pub extend Stag with Eq::{equal, not_equal}

///|
pub extend Stag with Debug::{to_repr}

///|
/// A tabulation box: the sorted list of tabulation stops.
priv struct TBox {
  mut tabs : @list.List[Int64]
}

///|
/// The tokens of the pretty-printer queue: text to print or elements that
/// drive indentation and line splitting.
priv enum Token {
  Text(String)
  Break(fits~ : (String, Int, String), breaks~ : (String, Int, String))
  TBreak(Int, Int)
  STab
  Begin(Int, BoxType)
  End
  TBegin(TBox)
  TEnd
  Newline
  IfNewline
  OpenTag(Stag)
  CloseTag
}

///|
/// An element of the queue: the declared length of the token, and its
/// size, set when the size of the box is known (negative if unknown).
priv struct QueueElem {
  mut size : Int64
  token : Token
  length : Int64
}

///|
priv struct ScanElem {
  /// value of left_total when the element was enqueued
  left_total : Int64
  queue_elem : QueueElem
}

///|
/// An element of the formatting stack: an active box.
priv struct FormatElem {
  box_type : BoxType
  width : Int64
}

///|
/// Large value for default tokens size.
let pp_infinity : Int64 = 1000000010

///|
let size_unknown : Int64 = -1

///|
/// Output functions of a formatter.
pub(all) struct OutFunctions {
  /// Output a string
  out_string : (StringView) -> Unit
  /// Flush the output device
  out_flush : () -> Unit
  /// Output a newline
  out_newline : () -> Unit
  /// Output `n` spaces (when a break hint does not split the line)
  out_spaces : (Int) -> Unit
  /// Output `n` spaces of indentation (after a newline)
  out_indent : (Int) -> Unit
}

///|
/// Functions handling semantic tags.
pub(all) struct StagFunctions {
  /// The marker output when a tag is opened, if tags are marked
  mark_open_stag : (Stag) -> String
  /// The marker output when a tag is closed, if tags are marked
  mark_close_stag : (Stag) -> String
  /// Called when a tag is opened, if tags are printed
  print_open_stag : (Stag) -> Unit
  /// Called when a tag is closed, if tags are printed
  print_close_stag : (Stag) -> Unit
}

///|
/// A pretty-printer: the pretty-printing engine and its state.
pub struct Formatter {
  priv scan_stack : Array[ScanElem]
  priv format_stack : Array[FormatElem]
  priv tbox_stack : Array[TBox]
  priv tag_stack : Array[Stag]
  priv mark_stack : Array[Stag]
  // The sizes are 64-bit integers, like OCaml's (63-bit) integers on 64-bit
  // platforms: texts of unknown size count for `pp_infinity`, which would
  // overflow 32-bit integers.
  priv mut margin : Int64
  priv mut min_space_left : Int64
  /// maximum value of indentation: no box can be opened further
  priv mut max_indent : Int64
  priv mut space_left : Int64
  priv mut current_indent : Int64
  priv mut is_new_line : Bool
  priv mut left_total : Int64
  priv mut right_total : Int64
  priv mut curr_depth : Int
  priv mut max_boxes : Int
  priv mut ellipsis : String
  priv mut out : OutFunctions
  priv mut print_tags : Bool
  priv mut mark_tags : Bool
  priv mut stag_functions : StagFunctions
  priv queue : @deque.Deque[QueueElem]
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
fn Formatter::output_string(self : Formatter, s : StringView) -> Unit {
  (self.out.out_string)(s)
}

///|
fn Formatter::output_newline(self : Formatter) -> Unit {
  (self.out.out_newline)()
}

///|
fn Formatter::output_spaces(self : Formatter, n : Int) -> Unit {
  (self.out.out_spaces)(n)
}

///|
fn Formatter::output_indent(self : Formatter, n : Int) -> Unit {
  (self.out.out_indent)(n)
}

///|
fn Formatter::format_pp_text(
  self : Formatter,
  size : Int64,
  text : String,
) -> Unit {
  self.space_left = self.space_left - size
  self.output_string(text)
  self.is_new_line = false
}

///|
fn Formatter::format_string(self : Formatter, s : String) -> Unit {
  if s != "" {
    self.format_pp_text(utf8_length(s).to_int64(), s)
  }
}

///|
fn Formatter::break_new_line(
  self : Formatter,
  breaks : (String, Int, String),
  width : Int64,
) -> Unit {
  let (before, offset, after) = breaks
  self.format_string(before)
  self.output_newline()
  self.is_new_line = true
  let indent = self.margin - width + offset.to_int64()
  let real_indent = if self.max_indent < indent {
    self.max_indent
  } else {
    indent
  }
  self.current_indent = real_indent
  self.space_left = self.margin - self.current_indent
  self.output_indent(self.current_indent.to_int())
  self.format_string(after)
}

///|
fn Formatter::break_line(self : Formatter, width : Int64) -> Unit {
  self.break_new_line(("", 0, ""), width)
}

///|
fn Formatter::break_same_line(
  self : Formatter,
  fits : (String, Int, String),
) -> Unit {
  let (before, width, after) = fits
  self.format_string(before)
  self.space_left = self.space_left - width.to_int64()
  self.output_spaces(width)
  self.format_string(after)
}

///|
/// To indent no more than max_indent: if one tries to open a box beyond
/// max_indent, then the box is rejected on the left by simulating a break.
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
fn Formatter::skip_token(self : Formatter) -> Unit {
  match self.queue.pop_front() {
    None => () // print_if_newline must have been the last printing command
    Some({ size, length, .. }) => {
      self.left_total = self.left_total - length
      self.space_left = self.space_left + size
    }
  }
}

///|
fn Formatter::format_pp_token(
  self : Formatter,
  size : Int64,
  token : Token,
) -> Unit {
  match token {
    Text(s) => self.format_pp_text(size, s)
    Begin(off, ty) => {
      let insertion_point = self.margin - self.space_left
      if insertion_point > self.max_indent {
        self.force_break_line()
      }
      let width = self.space_left - off.to_int64()
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
    TBegin(tbox) => self.tbox_stack.push(tbox)
    TEnd => ignore(self.tbox_stack.pop())
    STab =>
      match self.tbox_stack.last() {
        None => () // no open tabulation box
        Some(tbox) => {
          fn add_tab(n : Int64, l : @list.List[Int64]) -> @list.List[Int64] {
            match l {
              Empty => @list.singleton(n)
              More(x, tail=rest) =>
                if n < x {
                  @list.cons(n, l)
                } else {
                  @list.cons(x, add_tab(n, rest))
                }
            }
          }

          tbox.tabs = add_tab(self.margin - self.space_left, tbox.tabs)
        }
      }
    TBreak(n, off) => {
      let insertion_point = self.margin - self.space_left
      match self.tbox_stack.last() {
        None => () // no open tabulation box
        Some(tbox) => {
          let tab = match tbox.tabs {
            Empty => insertion_point
            More(first, ..) as tabs => {
              let mut found = first
              for head in tabs {
                if head >= insertion_point {
                  found = head
                  break
                }
              }
              found
            }
          }
          let offset = tab - insertion_point
          if offset >= 0 {
            self.break_same_line(("", (offset + n.to_int64()).to_int(), ""))
          } else {
            self.break_new_line(
              ("", (tab + off.to_int64()).to_int(), ""),
              self.margin,
            )
          }
        }
      }
    }
    Newline =>
      match self.format_stack.last() {
        None => self.output_newline() // no open box
        Some({ width, .. }) => self.break_line(width)
      }
    IfNewline =>
      if self.current_indent != self.margin - self.space_left {
        self.skip_token()
      }
    Break(fits~, breaks~) => {
      let (before, off, _) = breaks
      match self.format_stack.last() {
        None => () // no open box
        Some({ box_type, width, }) =>
          match box_type {
            HOVBox =>
              if size + utf8_length(before).to_int64() > self.space_left {
                self.break_new_line(breaks, width)
              } else {
                self.break_same_line(fits)
              }
            Box =>
              if self.is_new_line {
                self.break_same_line(fits)
              } else if size + utf8_length(before).to_int64() > self.space_left {
                self.break_new_line(breaks, width)
              } else if self.current_indent >
                self.margin - width + off.to_int64() {
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
    OpenTag(tag_name) => {
      let marker = (self.stag_functions.mark_open_stag)(tag_name)
      self.output_string(marker)
      self.mark_stack.push(tag_name)
    }
    CloseTag =>
      match self.mark_stack.pop() {
        None => () // no more tag to close
        Some(tag_name) => {
          let marker = (self.stag_functions.mark_close_stag)(tag_name)
          self.output_string(marker)
        }
      }
  }
}

///|
/// Print if the token size is known, else printing is delayed. Printing is
/// delayed when the text waiting in the queue requires more room to format
/// than exists on the current line.
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
fn Formatter::enqueue_string_as(
  self : Formatter,
  size : Int64,
  s : String,
) -> Unit {
  self.enqueue_advance({ size, token: Text(s), length: size, })
}

///|
fn Formatter::enqueue_string(self : Formatter, s : String) -> Unit {
  self.enqueue_string_as(utf8_length(s).to_int64(), s)
}

///|
/// The scan stack is never empty.
fn initialize_scan_stack(stack : Array[ScanElem]) -> Unit {
  stack.clear()
  let queue_elem = { size: size_unknown, token: Text(""), length: 0, }
  stack.push({ left_total: -1, queue_elem, })
}

///|
/// Set the size of the element on top of the scan stack: the size of a
/// break if `ty` is true, else the size of a box; pop the scan stack.
fn Formatter::set_size(self : Formatter, ty : Bool) -> Unit {
  match self.scan_stack.last() {
    None => () // the scan stack is never empty
    Some({ left_total, queue_elem, }) => {
      let size = queue_elem.size
      // test if the scan stack contains any data that is not obsolete
      if left_total < self.left_total {
        initialize_scan_stack(self.scan_stack)
      } else {
        match queue_elem.token {
          Break(..) | TBreak(_, _) =>
            if ty {
              queue_elem.size = self.right_total + size
              ignore(self.scan_stack.pop())
            }
          Begin(_, _) =>
            if !ty {
              queue_elem.size = self.right_total + size
              ignore(self.scan_stack.pop())
            }
          Text(_)
          | STab
          | TBegin(_)
          | TEnd
          | End
          | Newline
          | IfNewline
          | OpenTag(_)
          | CloseTag => () // scan_push is only used for breaks and boxes
        }
      }
    }
  }
}

///|
/// Push a token on the scanning stack; if `b` is true, set_size is called.
fn Formatter::scan_push(self : Formatter, b : Bool, token : QueueElem) -> Unit {
  self.enqueue(token)
  if b {
    self.set_size(true)
  }
  self.scan_stack.push({ left_total: self.right_total, queue_elem: token, })
}

///|
/// Open a new box. Text nested deeper than `max_boxes` is printed as the
/// ellipsis string.
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
  } else if self.curr_depth == self.max_boxes {
    self.enqueue_string(self.ellipsis)
  }
}

///|
/// The box which is always open.
fn Formatter::open_sys_box(self : Formatter) -> Unit {
  self.open_box_gen(0, HOVBox)
}

///|
/// Close the most recently opened pretty-printing box.
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
/// Open a semantic tag.
pub fn Formatter::open_stag(self : Formatter, tag : Stag) -> Unit {
  if self.print_tags {
    self.tag_stack.push(tag)
    (self.stag_functions.print_open_stag)(tag)
  }
  if self.mark_tags {
    self.enqueue({ size: 0, token: OpenTag(tag), length: 0, })
  }
}

///|
/// Close the most recently opened semantic tag.
pub fn Formatter::close_stag(self : Formatter) -> Unit {
  if self.mark_tags {
    self.enqueue({ size: 0, token: CloseTag, length: 0, })
  }
  if self.print_tags {
    match self.tag_stack.pop() {
      None => () // no more tag to close
      Some(tag) => (self.stag_functions.print_close_stag)(tag)
    }
  }
}

///|
/// Open a string tag (`open_stag(StringTag(s))`).
pub fn Formatter::open_tag(self : Formatter, s : String) -> Unit {
  self.open_stag(StringTag(s))
}

///|
/// Close the most recently opened tag.
pub fn Formatter::close_tag(self : Formatter) -> Unit {
  self.close_stag()
}

///|
/// Initialize the pretty-printer.
fn Formatter::rinit(self : Formatter) -> Unit {
  self.clear_queue()
  initialize_scan_stack(self.scan_stack)
  self.format_stack.clear()
  self.tbox_stack.clear()
  self.tag_stack.clear()
  self.mark_stack.clear()
  self.current_indent = 0
  self.curr_depth = 0
  self.space_left = self.margin
  self.open_sys_box()
}

///|
fn Formatter::clear_tag_stack(self : Formatter) -> Unit {
  for _ in self.tag_stack.copy() {
    self.close_tag()
  }
}

///|
/// Flush the pretty-printer queue.
fn Formatter::flush_queue(self : Formatter, b : Bool) -> Unit {
  self.clear_tag_stack()
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
