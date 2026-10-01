// Formatters and their public API, a port of OCaml's `format.ml`.
//
// Copyright 1996 Institut National de Recherche en Informatique et en
// Automatique (OCaml), distributed under the terms of the GNU Lesser
// General Public License version 2.1, with the special exception on
// linking described in the file LICENSE.

///|
/// Length of a string in UTF-8 bytes, which is its width for the
/// pretty-printer, like OCaml's `String.length` on UTF-8 strings.
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
fn default_mark_open_stag(tag : Stag) -> String {
  match tag {
    StringTag(s) => "<" + s + ">"
    OtherTag(_) => ""
  }
}

///|
fn default_mark_close_stag(tag : Stag) -> String {
  match tag {
    StringTag(s) => "</" + s + ">"
    OtherTag(_) => ""
  }
}

///|
/// The default tag functions: string tags are marked as `<tag>` and
/// `</tag>`, nothing is printed.
pub let default_stag_functions : StagFunctions = {
  mark_open_stag: default_mark_open_stag,
  mark_close_stag: default_mark_close_stag,
  print_open_stag: _ => (),
  print_close_stag: _ => (),
}

///|
/// Create a formatter from its output functions, like OCaml's
/// `formatter_of_out_functions`.
pub fn Formatter::of_out_functions(out : OutFunctions) -> Formatter {
  // The initial state of the formatter contains a dummy box.
  let queue = @deque.Deque([])
  let sys_tok = { size: size_unknown, token: Begin(0, HOVBox), length: 0, }
  queue.push_back(sys_tok)
  let scan_stack = []
  initialize_scan_stack(scan_stack)
  scan_stack.push({ left_total: 1, queue_elem: sys_tok, })
  let margin = 78L
  let min_space_left = 10L
  {
    scan_stack,
    format_stack: [],
    tbox_stack: [],
    tag_stack: [],
    mark_stack: [],
    margin,
    min_space_left,
    max_indent: margin - min_space_left,
    space_left: margin,
    current_indent: 0,
    is_new_line: true,
    left_total: 1,
    right_total: 1,
    curr_depth: 1,
    max_boxes: 2147483647,
    ellipsis: ".",
    out,
    print_tags: false,
    mark_tags: false,
    stag_functions: default_stag_functions,
    queue,
  }
}

///|
let blank_line : String = String::make(80, ' ')

///|
/// Output `n` spaces with an output function, 80 at a time, like OCaml's
/// `display_blanks`.
fn display_blanks(out_string : (StringView) -> Unit, n : Int) -> Unit {
  let mut n = n
  while n > 0 {
    if n <= 80 {
      out_string(blank_line.view(end_offset=n))
      n = 0
    } else {
      out_string(blank_line)
      n -= 80
    }
  }
}

///|
/// Create a formatter that outputs with `output` and flushes with `flush`;
/// newlines and spaces are output with `output` too. Like OCaml's
/// `make_formatter`.
pub fn Formatter::Formatter(
  output : (StringView) -> Unit,
  flush? : () -> Unit = () => (),
) -> Formatter {
  Formatter::of_out_functions({
    out_string: output,
    out_flush: flush,
    out_newline: () => output("\n"),
    out_spaces: n => display_blanks(output, n),
    out_indent: n => display_blanks(output, n),
  })
}

///|
/// Create a formatter writing to a string builder, like OCaml's
/// `formatter_of_buffer`.
pub fn Formatter::of_buffer(buf : StringBuilder) -> Formatter {
  Formatter(s => buf.write_view(s))
}

// Formatting functions

///|
/// Print a string, pretending that its width is `size`.
pub fn Formatter::print_as(self : Formatter, size : Int, s : String) -> Unit {
  if self.curr_depth < self.max_boxes {
    self.enqueue_string_as(size.to_int64(), s)
  }
}

///|
/// Print a string in the current box. Its width is its length in UTF-8
/// bytes.
pub fn Formatter::print_string(self : Formatter, s : String) -> Unit {
  self.print_as(utf8_length(s), s)
}

///|
/// Print an integer.
pub fn Formatter::print_int(self : Formatter, i : Int) -> Unit {
  self.print_string(i.to_string())
}

///|
/// Print a floating-point number in OCaml's syntax, like OCaml's
/// `string_of_float` (12 significant digits).
pub fn Formatter::print_float(self : Formatter, f : Double) -> Unit {
  self.print_string(string_of_float(f))
}

///|
/// Print a boolean.
pub fn Formatter::print_bool(self : Formatter, b : Bool) -> Unit {
  self.print_string(if b { "true" } else { "false" })
}

///|
/// Print a character. Its width is 1.
pub fn Formatter::print_char(self : Formatter, c : Char) -> Unit {
  self.print_as(1, c.to_string())
}

///|
/// Print nothing.
pub fn Formatter::print_nothing(_self : Formatter) -> Unit {

}

// Boxes

///|
/// Open a horizontal box: break hints never split the line.
pub fn Formatter::open_hbox(self : Formatter) -> Unit {
  self.open_box_gen(0, HBox)
}

///|
/// Open a vertical box: every break hint splits the line; `indent` is
/// added to the current indentation.
pub fn Formatter::open_vbox(self : Formatter, indent : Int) -> Unit {
  self.open_box_gen(indent, VBox)
}

///|
/// Open a horizontal/vertical box: horizontal if it fits on the line,
/// otherwise vertical.
pub fn Formatter::open_hvbox(self : Formatter, indent : Int) -> Unit {
  self.open_box_gen(indent, HVBox)
}

///|
/// Open a horizontal-or-vertical compacting box: break hints split the line
/// only when the material doesn't fit on it.
pub fn Formatter::open_hovbox(self : Formatter, indent : Int) -> Unit {
  self.open_box_gen(indent, HOVBox)
}

///|
/// Open a structural compacting box: like `open_hovbox`, but break hints
/// also split the line if that reduces the indentation.
pub fn Formatter::open_box(self : Formatter, indent : Int) -> Unit {
  self.open_box_gen(indent, Box)
}

// Break hints

///|
/// Generalized break hint: `fits` = (before, width, after) is printed if
/// the line is not split, `breaks` = (before, offset, after) if it is.
pub fn Formatter::print_custom_break(
  self : Formatter,
  fits~ : (String, Int, String),
  breaks~ : (String, Int, String),
) -> Unit {
  let (before, width, after) = fits
  if self.curr_depth < self.max_boxes {
    let size = -self.right_total
    let token = Break(fits~, breaks~)
    let length = (utf8_length(before) + width + utf8_length(after)).to_int64()
    self.scan_push(true, { size, token, length, })
  }
}

///|
/// Break hint: print `width` spaces if the line is not split, otherwise
/// split the line and add `offset` to the indentation.
pub fn Formatter::print_break(
  self : Formatter,
  width : Int,
  offset : Int,
) -> Unit {
  self.print_custom_break(fits=("", width, ""), breaks=("", offset, ""))
}

///|
/// Break hint printing a space if the line is not split (`@ `).
pub fn Formatter::print_space(self : Formatter) -> Unit {
  self.print_break(1, 0)
}

///|
/// Break hint printing nothing if the line is not split (`@,`).
pub fn Formatter::print_cut(self : Formatter) -> Unit {
  self.print_break(0, 0)
}

///|
/// Force a new line in the current box. Not the normal way of
/// pretty-printing: prefer break hints within vertical boxes.
pub fn Formatter::force_newline(self : Formatter) -> Unit {
  if self.curr_depth < self.max_boxes {
    self.enqueue_advance({ size: 0, token: Newline, length: 0, })
  }
}

///|
/// Execute the next formatting command only if the preceding line has just
/// been split; otherwise, ignore it.
pub fn Formatter::print_if_newline(self : Formatter) -> Unit {
  if self.curr_depth < self.max_boxes {
    self.enqueue_advance({ size: 0, token: IfNewline, length: 0, })
  }
}

///|
/// Close all the opened boxes and print all the pending text, then flush
/// the output device.
pub fn Formatter::print_flush(self : Formatter) -> Unit {
  self.flush_queue(false)
  (self.out.out_flush)()
}

///|
/// Like `print_flush`, followed by a newline.
pub fn Formatter::print_newline(self : Formatter) -> Unit {
  self.flush_queue(true)
  (self.out.out_flush)()
}

// Tabulation boxes

///|
/// Open a tabulation box.
pub fn Formatter::open_tbox(self : Formatter) -> Unit {
  self.curr_depth = self.curr_depth + 1
  if self.curr_depth < self.max_boxes {
    self.enqueue_advance({
      size: 0,
      token: TBegin({ tabs: @list.empty(), }),
      length: 0,
    })
  }
}

///|
/// Close the most recently opened tabulation box.
pub fn Formatter::close_tbox(self : Formatter) -> Unit {
  if self.curr_depth > 1 {
    if self.curr_depth < self.max_boxes {
      self.enqueue_advance({ size: 0, token: TEnd, length: 0, })
      self.curr_depth = self.curr_depth - 1
    }
  }
}

///|
/// Break hint in a tabulation box: move to the next tabulation stop, then
/// print `width` spaces; if there is no room, split the line and add
/// `offset` to the indentation.
pub fn Formatter::print_tbreak(
  self : Formatter,
  width : Int,
  offset : Int,
) -> Unit {
  if self.curr_depth < self.max_boxes {
    let size = -self.right_total
    self.scan_push(true, {
      size,
      token: TBreak(width, offset),
      length: width.to_int64(),
    })
  }
}

///|
/// Move to the next tabulation stop (`print_tbreak(0, 0)`).
pub fn Formatter::print_tab(self : Formatter) -> Unit {
  self.print_tbreak(0, 0)
}

///|
/// Set a tabulation stop at the current insertion point.
pub fn Formatter::set_tab(self : Formatter) -> Unit {
  if self.curr_depth < self.max_boxes {
    self.enqueue_advance({ size: 0, token: STab, length: 0, })
  }
}

// Maximum number of boxes

///|
/// Set the maximum number of simultaneously opened boxes (must be > 1);
/// material in deeper boxes is printed as the ellipsis.
pub fn Formatter::set_max_boxes(self : Formatter, n : Int) -> Unit {
  if n > 1 {
    self.max_boxes = n
  }
}

///|
/// The maximum number of simultaneously opened boxes.
pub fn Formatter::get_max_boxes(self : Formatter) -> Int {
  self.max_boxes
}

///|
/// Whether the maximum number of opened boxes is reached.
pub fn Formatter::over_max_boxes(self : Formatter) -> Bool {
  self.curr_depth == self.max_boxes
}

///|
/// Set the text printed for boxes beyond the maximum (`.` by default).
pub fn Formatter::set_ellipsis_text(self : Formatter, s : String) -> Unit {
  self.ellipsis = s
}

///|
/// The text printed for boxes beyond the maximum.
pub fn Formatter::get_ellipsis_text(self : Formatter) -> String {
  self.ellipsis
}

// Geometry

///|
fn pp_limit(n : Int64) -> Int64 {
  if n < pp_infinity {
    n
  } else {
    pp_infinity - 1
  }
}

///|
fn Formatter::set_min_space_left(self : Formatter, n : Int64) -> Unit {
  if n >= 1 {
    let n = pp_limit(n)
    self.min_space_left = n
    self.max_indent = self.margin - self.min_space_left
    self.rinit()
  }
}

///|
/// Set the maximum indentation: boxes opened beyond it are rejected to the
/// left. Ignored if `n <= 1`.
pub fn Formatter::set_max_indent(self : Formatter, n : Int) -> Unit {
  self.set_max_indent64(n.to_int64())
}

///|
fn Formatter::set_max_indent64(self : Formatter, n : Int64) -> Unit {
  if n > 1 {
    self.set_min_space_left(self.margin - n)
  }
}

///|
/// The maximum indentation.
pub fn Formatter::get_max_indent(self : Formatter) -> Int {
  self.max_indent.to_int()
}

///|
/// Set the right margin (78 by default). Ignored if `n < 1`.
pub fn Formatter::set_margin(self : Formatter, n : Int) -> Unit {
  if n >= 1 {
    let n = pp_limit(n.to_int64())
    self.margin = n
    let new_max_indent = if self.max_indent <= self.margin {
      // try to maintain max_indent to its actual value
      self.max_indent
    } else {
      // if possible maintain min_space_left to its actual value; if this
      // leads to a too small max_indent, take half of the new margin, if
      // it is greater than 1
      let a = self.margin - self.min_space_left
      let b = self.margin / 2
      let m = if a > b { a } else { b }
      if m > 1 {
        m
      } else {
        1
      }
    }
    // rebuild invariants
    self.set_max_indent64(new_max_indent)
  }
}

///|
/// The right margin.
pub fn Formatter::get_margin(self : Formatter) -> Int {
  self.margin.to_int()
}

///|
/// The geometry of a formatter.
pub(all) struct Geometry {
  max_indent : Int
  margin : Int
} derive(Eq, Debug)

///|
pub extend Geometry with Eq::{equal, not_equal}

///|
pub extend Geometry with Debug::{to_repr}

///|
/// Error raised by functions given invalid arguments.
pub(all) suberror InvalidArgument {
  InvalidArgument(String)
} derive(Eq, Debug)

///|
pub extend InvalidArgument with Eq::{equal, not_equal}

///|
pub extend InvalidArgument with Debug::{to_repr}

///|
fn validate_geometry(g : Geometry) -> String? {
  if g.max_indent < 2 {
    Some("max_indent < 2")
  } else if g.margin <= g.max_indent {
    Some("margin <= max_indent")
  } else {
    None
  }
}

///|
/// Whether a geometry is valid: `max_indent >= 2` and
/// `margin > max_indent`.
pub fn check_geometry(g : Geometry) -> Bool {
  validate_geometry(g) is None
}

///|
fn Formatter::set_full_geometry(self : Formatter, g : Geometry) -> Unit {
  self.set_margin(g.margin)
  self.set_max_indent(g.max_indent)
}

///|
/// Set the margin and the maximum indentation, which must form a valid
/// geometry.
pub fn Formatter::set_geometry(
  self : Formatter,
  max_indent~ : Int,
  margin~ : Int,
) -> Unit raise InvalidArgument {
  let g = { max_indent, margin, }
  match validate_geometry(g) {
    Some(msg) => raise InvalidArgument("Format.pp_set_geometry: " + msg)
    None => self.set_full_geometry(g)
  }
}

///|
/// Like `set_geometry`, but does nothing if the geometry is invalid.
pub fn Formatter::safe_set_geometry(
  self : Formatter,
  max_indent~ : Int,
  margin~ : Int,
) -> Unit {
  let g = { max_indent, margin, }
  if validate_geometry(g) is None {
    self.set_full_geometry(g)
  }
}

///|
/// The geometry of the formatter.
pub fn Formatter::get_geometry(self : Formatter) -> Geometry {
  { margin: self.margin.to_int(), max_indent: self.max_indent.to_int(), }
}

///|
/// Update the geometry of the formatter.
pub fn Formatter::update_geometry(
  self : Formatter,
  update : (Geometry) -> Geometry,
) -> Unit {
  self.set_full_geometry(update(self.get_geometry()))
}

// Output functions

///|
/// Set the output functions of the formatter.
pub fn Formatter::set_out_functions(
  self : Formatter,
  out : OutFunctions,
) -> Unit {
  self.out = out
}

///|
/// The output functions of the formatter.
pub fn Formatter::get_out_functions(self : Formatter) -> OutFunctions {
  self.out
}

// Tags

///|
/// Set the tag functions of the formatter.
pub fn Formatter::set_stag_functions(
  self : Formatter,
  funs : StagFunctions,
) -> Unit {
  self.stag_functions = funs
}

///|
/// The tag functions of the formatter.
pub fn Formatter::get_stag_functions(self : Formatter) -> StagFunctions {
  self.stag_functions
}

///|
/// Whether to call the `print_*_stag` functions on tags.
pub fn Formatter::set_print_tags(self : Formatter, b : Bool) -> Unit {
  self.print_tags = b
}

///|
/// Whether to output the `mark_*_stag` markers of tags.
pub fn Formatter::set_mark_tags(self : Formatter, b : Bool) -> Unit {
  self.mark_tags = b
}

///|
/// Whether the `print_*_stag` functions are called on tags.
pub fn Formatter::get_print_tags(self : Formatter) -> Bool {
  self.print_tags
}

///|
/// Whether the `mark_*_stag` markers of tags are output.
pub fn Formatter::get_mark_tags(self : Formatter) -> Bool {
  self.mark_tags
}

///|
/// Set both `print_tags` and `mark_tags`.
pub fn Formatter::set_tags(self : Formatter, b : Bool) -> Unit {
  self.set_print_tags(b)
  self.set_mark_tags(b)
}

// Symbolic output

///|
/// An item of symbolic output.
pub(all) enum SymbolicOutputItem {
  OutputFlush
  OutputNewline
  OutputString(String)
  OutputSpaces(Int)
  OutputIndent(Int)
} derive(Eq, Debug)

///|
pub extend SymbolicOutputItem with Eq::{equal, not_equal}

///|
pub extend SymbolicOutputItem with Debug::{to_repr}

///|
/// A buffer of symbolic output: pretty-printing with no low-level output,
/// so that the output can be post-processed.
pub struct SymbolicOutputBuffer {
  priv items : Array[SymbolicOutputItem]
}

///|
/// Create a buffer of symbolic output.
pub fn SymbolicOutputBuffer::SymbolicOutputBuffer() -> SymbolicOutputBuffer {
  { items: [], }
}

///|
/// Remove the contents of the buffer.
pub fn SymbolicOutputBuffer::clear(self : SymbolicOutputBuffer) -> Unit {
  self.items.clear()
}

///|
/// The contents of the buffer.
pub fn SymbolicOutputBuffer::get(
  self : SymbolicOutputBuffer,
) -> Array[SymbolicOutputItem] {
  self.items.copy()
}

///|
/// Return the contents of the buffer and clear it.
pub fn SymbolicOutputBuffer::flush(
  self : SymbolicOutputBuffer,
) -> Array[SymbolicOutputItem] {
  let items = self.items.copy()
  self.items.clear()
  items
}

///|
/// Add an item to the buffer.
pub fn SymbolicOutputBuffer::add(
  self : SymbolicOutputBuffer,
  item : SymbolicOutputItem,
) -> Unit {
  self.items.push(item)
}

///|
/// Create a formatter whose output is stored in a symbolic output buffer.
pub fn Formatter::of_symbolic_output_buffer(
  sob : SymbolicOutputBuffer,
) -> Formatter {
  Formatter::of_out_functions({
    out_string: s => sob.add(OutputString(s.to_owned())),
    out_flush: () => sob.add(OutputFlush),
    out_newline: () => sob.add(OutputNewline),
    out_spaces: n => sob.add(OutputSpaces(n)),
    out_indent: n => sob.add(OutputIndent(n)),
  })
}
