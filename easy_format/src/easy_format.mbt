// A port of easy-format 1.3.4 (https://github.com/ocaml-community/easy-format),
// indentation made easy: pretty-printing of trees made of atoms, lists and
// labels, on top of bobzhang/format, a port of OCaml's Format.
//
// Copyright (c) 2008 Martin Jambon. Distributed under the terms of the BSD
// 3-clause license, see the file LICENSE.

///|
/// How the body of a list may be wrapped.
pub(all) enum Wrap {
  /// wrap if the list contains only atoms
  WrapAtoms
  /// always wrap when needed
  AlwaysWrap
  /// never wrap: the list is either horizontal or vertical
  NeverWrap
  /// align vertically: always break the line between list items and align
  /// the left edge of each item
  ForceBreaks
  /// like `ForceBreaks`, and turn the wrappable lists (`WrapAtoms` or
  /// `AlwaysWrap`) containing this one into `ForceBreaks` lists
  ForceBreaksRec
  /// align horizontally: never break the line between list items
  NoBreaks
} derive(Eq, Debug)

///|
pub extend Wrap with Eq::{equal, not_equal}

///|
pub extend Wrap with Debug::{to_repr}

///|
/// When to break the line after a label.
pub(all) enum LabelBreak {
  /// if there's not enough room
  Auto
  /// always
  Always
  /// always, and force breaks in the lists and labels containing this one
  /// (like `ForceBreaksRec` for lists)
  AlwaysRec
  /// never
  Never
} derive(Eq, Debug)

///|
pub extend LabelBreak with Eq::{equal, not_equal}

///|
pub extend LabelBreak with Debug::{to_repr}

///|
/// The markers printed around the text of a style: the opening and closing
/// markers of a semantic tag, which are not counted in the width of the
/// text.
pub(all) struct Style {
  tag_open : String
  tag_close : String
} derive(Eq, Debug)

///|
pub extend Style with Eq::{equal, not_equal}

///|
pub extend Style with Debug::{to_repr}

///|
/// Parameters of an atom.
pub(all) struct AtomParam {
  /// Default: `None`
  atom_style : String?
} derive(Eq, Debug)

///|
pub extend AtomParam with Eq::{equal, not_equal}

///|
pub extend AtomParam with Debug::{to_repr}

///|
/// The default parameters of atoms. Derive new parameters from it with
/// `{ ..atom, field: value }`.
pub let atom : AtomParam = { atom_style: None, }

///|
/// Parameters of a list.
pub(all) struct ListParam {
  /// Whether there must be some whitespace after the opening string.
  /// Default: `true`
  space_after_opening : Bool
  /// Whether there must be some whitespace after the item separators.
  /// Default: `true`
  space_after_separator : Bool
  /// Whether there must be some whitespace before the item separators.
  /// Default: `false`
  space_before_separator : Bool
  /// Whether the separators must stick to the item on the left.
  /// Default: `true`
  separators_stick_left : Bool
  /// Whether there must be some whitespace before the closing string.
  /// Default: `true`
  space_before_closing : Bool
  /// Whether the opening string should be fused with the preceding label.
  /// Default: `true`
  stick_to_label : Bool
  /// Whether the beginning of the closing string must be aligned with the
  /// beginning of the opening string (`stick_to_label = false`) or with the
  /// beginning of the label if any (`stick_to_label = true`).
  /// Default: `true`
  align_closing : Bool
  /// Under which conditions the list body may be wrapped, i.e. allow
  /// several lines and several list items per line. Default: `WrapAtoms`
  wrap_body : Wrap
  /// Extra indentation of the list body. Default: `2`
  indent_body : Int
  /// Default: `None`
  list_style : String?
  /// Default: `None`
  opening_style : String?
  /// Default: `None`
  body_style : String?
  /// Default: `None`
  separator_style : String?
  /// Default: `None`
  closing_style : String?
} derive(Eq, Debug)

///|
pub extend ListParam with Eq::{equal, not_equal}

///|
pub extend ListParam with Debug::{to_repr}

///|
/// The default parameters of lists. Derive new parameters from it with
/// `{ ..list, field: value }`.
pub let list : ListParam = {
  space_after_opening: true,
  space_after_separator: true,
  space_before_separator: false,
  separators_stick_left: true,
  space_before_closing: true,
  stick_to_label: true,
  align_closing: true,
  wrap_body: WrapAtoms,
  indent_body: 2,
  list_style: None,
  opening_style: None,
  body_style: None,
  separator_style: None,
  closing_style: None,
}

///|
/// Parameters of a label.
pub(all) struct LabelParam {
  /// Whether to break the line after the label. Default: `Auto`
  label_break : LabelBreak
  /// Whether there must be some whitespace after the label. Default: `true`
  space_after_label : Bool
  /// Extra indentation before the item that comes after a label.
  /// Default: `2`
  indent_after_label : Int
  /// Default: `None`
  label_style : String?
} derive(Eq, Debug)

///|
pub extend LabelParam with Eq::{equal, not_equal}

///|
pub extend LabelParam with Debug::{to_repr}

///|
/// The default parameters of labels. Derive new parameters from it with
/// `{ ..label, field: value }`.
pub let label : LabelParam = {
  label_break: Auto,
  space_after_label: true,
  indent_after_label: 2,
  label_style: None,
}

///|
/// A tree to be pretty-printed.
pub(all) enum T {
  /// Plain string normally without line breaks.
  Atom(String, AtomParam)
  /// `List((opening, separator, closing, param), nodes)`: a sequence of
  /// nodes, e.g. `List(("[", ",", "]", list), ...)`.
  List((String, String, String, ListParam), Array[T])
  /// `Label((label, param), node)`: a node with a label, such as `x:`,
  /// `let x =` or `int main()`.
  Label((T, LabelParam), T)
  /// Printing with the formatter directly; the function is responsible for
  /// leaving the formatter in a clean state.
  Custom((@format.Formatter) -> Unit)
}

///|
/// How to escape the text, but not the markers of the styles.
pub(all) enum Escape {
  /// no escaping
  NoEscape
  /// `Escape(f)`: `f(print, s)` prints the text `s` escaped with `print`
  Escape(((StringView) -> Unit, StringView) -> Unit)
  /// escape the strings with a function
  EscapeString((String) -> String)
}

///|
/// Transform a tree starting from the leaves, propagating and merging
/// accumulators until reaching the root.
fn[A] propagate_from_leaf_to_root(
  x : T,
  init_acc~ : (T) -> A,
  merge_acc~ : (A, A) -> A,
  map_node~ : (T, A) -> (T, A),
) -> (T, A) {
  fn aux(x : T) -> (T, A) {
    match x {
      Atom(_, _) | Custom(_) => map_node(x, init_acc(x))
      List(param, children) => {
        let new_children = []
        let mut acc = init_acc(x)
        for child in children {
          let (new_child, child_acc) = aux(child)
          new_children.push(new_child)
          acc = merge_acc(acc, child_acc)
        }
        map_node(List(param, new_children), acc)
      }
      Label((x1, param), x2) => {
        let acc0 = init_acc(x)
        let (new_x1, acc1) = aux(x1)
        let (new_x2, acc2) = aux(x2)
        let acc = merge_acc(merge_acc(acc0, acc1), acc2)
        map_node(Label((new_x1, param), new_x2), acc)
      }
    }
  }

  aux(x)
}

///|
/// Convert wrappable lists into vertical lists if any of their descendants
/// has the attribute `wrap_body = ForceBreaksRec` (and likewise for labels
/// with `label_break = AlwaysRec`).
fn propagate_forced_breaks(x : T) -> T {
  // acc = whether to force breaks in wrappable lists or labels
  let init_acc = (x : T) => {
    match x {
      List((_, _, _, { wrap_body: ForceBreaksRec, .. }), _)
      | Label((_, { label_break: AlwaysRec, .. }), _) => true
      Atom(_, _) | Label(_, _) | Custom(_) | List(_, _) => false
    }
  }
  let map_node = (x : T, force_breaks : Bool) => {
    match x {
      List((_, _, _, { wrap_body: ForceBreaksRec, .. }), _) => (x, true)
      List((_, _, _, { wrap_body: ForceBreaks, .. }), _) => (x, force_breaks)
      List(
        (op, sep, cl, { wrap_body: WrapAtoms | NeverWrap | AlwaysWrap, .. } as p
        ),
        children
      ) =>
        if force_breaks {
          (
            List((op, sep, cl, { ..p, wrap_body: ForceBreaks, }), children),
            true,
          )
        } else {
          (x, false)
        }
      Label((a, { label_break: Auto, .. } as lp), b) =>
        if force_breaks {
          (Label((a, { ..lp, label_break: Always, }), b), true)
        } else {
          (x, false)
        }
      List((_, _, _, { wrap_body: NoBreaks, .. }), _)
      | Label((_, { label_break: Always | AlwaysRec | Never, .. }), _)
      | Atom(_, _)
      | Custom(_) => (x, force_breaks)
    }
  }
  propagate_from_leaf_to_root(
    x,
    init_acc~,
    merge_acc=(a, b) => a || b,
    map_node~,
  ).0
}

// The regular pretty-printing functions (`Easy_format.Pretty`)

///|
/// Escape the text output by the formatter, but not the markers of the
/// tags. This relies on the fact that `mark_open_stag` and
/// `mark_close_stag` are called exactly once before the marker is output.
fn set_escape(
  fmt : @format.Formatter,
  escape : ((StringView) -> Unit, StringView) -> Unit,
) -> Unit {
  let (print0, flush0) = fmt.get_output_functions()
  let tagf0 = fmt.get_stag_functions()
  let mut is_tag = false
  let mot = tag => {
    is_tag = true
    (tagf0.mark_open_stag)(tag)
  }
  let mct = tag => {
    is_tag = true
    (tagf0.mark_close_stag)(tag)
  }
  let print = (s : StringView) => {
    if is_tag {
      print0(s)
      is_tag = false
    } else {
      escape(print0, s)
    }
  }
  fmt.set_output_functions(print, flush0)
  fmt.set_stag_functions({ ..tagf0, mark_open_stag: mot, mark_close_stag: mct, })
}

///|
fn set_escape_string(fmt : @format.Formatter, esc : (String) -> String) -> Unit {
  set_escape(fmt, (print, s) => print(esc(s.to_owned())))
}

///|
/// Prepare a formatter for printing with styles (the markers of the styles
/// are printed with semantic tags) and escaping. `Pretty.define_styles` in
/// OCaml.
pub fn define_styles(
  fmt : @format.Formatter,
  escape : Escape,
  styles : ArrayView[(String, Style)],
) -> Unit {
  if styles.length() > 0 {
    fmt.set_tags(true)
    let tbl1 : Map[String, String] = Map([])
    let tbl2 : Map[String, String] = Map([])
    for style in styles {
      let (style_name, style) = style
      tbl1[style_name] = style.tag_open
      tbl2[style_name] = style.tag_close
    }
    let mark_open_tag = (tag : @format.Stag) => {
      match tag {
        StringTag(style_name) => tbl1.get(style_name).unwrap_or("")
        OtherTag(_) => ""
      }
    }
    let mark_close_tag = (tag : @format.Stag) => {
      match tag {
        StringTag(style_name) => tbl2.get(style_name).unwrap_or("")
        OtherTag(_) => ""
      }
    }
    fmt.set_stag_functions({
      ..fmt.get_stag_functions(),
      mark_open_stag: mark_open_tag,
      mark_close_stag: mark_close_tag,
    })
  }
  match escape {
    NoEscape => ()
    Escape(esc) => set_escape(fmt, esc)
    EscapeString(esc) => set_escape_string(fmt, esc)
  }
}

///|
fn pp_open_xbox(fmt : @format.Formatter, p : ListParam, indent : Int) -> Unit {
  match p.wrap_body {
    AlwaysWrap | NeverWrap | WrapAtoms => fmt.open_hvbox(indent)
    ForceBreaks | ForceBreaksRec => fmt.open_vbox(indent)
    NoBreaks => fmt.open_hbox()
  }
}

///|
fn all_atoms(l : ArrayView[T]) -> Bool {
  l.iter().all(x => x is Atom(_, _))
}

///|
/// Whether the body of a list is printed in an extra box.
fn extra_box(p : ListParam, l : ArrayView[T]) -> Bool {
  match p.wrap_body {
    AlwaysWrap => true
    NeverWrap | ForceBreaks | ForceBreaksRec | NoBreaks => false
    WrapAtoms => all_atoms(l)
  }
}

///|
fn pp_open_nonaligned_box(
  fmt : @format.Formatter,
  p : ListParam,
  indent : Int,
  l : ArrayView[T],
) -> Unit {
  match p.wrap_body {
    AlwaysWrap => fmt.open_hovbox(indent)
    NeverWrap => fmt.open_hvbox(indent)
    WrapAtoms =>
      if all_atoms(l) {
        fmt.open_hovbox(indent)
      } else {
        fmt.open_hvbox(indent)
      }
    ForceBreaks | ForceBreaksRec => fmt.open_vbox(indent)
    NoBreaks => fmt.open_hbox()
  }
}

///|
fn open_tag(fmt : @format.Formatter, style : String?) -> Unit {
  if style is Some(s) {
    fmt.open_stag(StringTag(s))
  }
}

///|
fn close_tag(fmt : @format.Formatter, style : String?) -> Unit {
  if style is Some(_) {
    fmt.close_stag()
  }
}

///|
fn tag_string(fmt : @format.Formatter, style : String?, s : String) -> Unit {
  match style {
    None => fmt.print_string(s)
    Some(tag) => {
      fmt.open_stag(StringTag(tag))
      fmt.print_string(s)
      fmt.close_stag()
    }
  }
}

///|
fn fprint_t(fmt : @format.Formatter, x : T) -> Unit {
  match x {
    Atom(s, p) => tag_string(fmt, p.atom_style, s)
    List((_, _, _, p) as param, l) => {
      open_tag(fmt, p.list_style)
      if p.align_closing {
        fprint_list(fmt, None, param, l)
      } else {
        fprint_list2(fmt, param, l)
      }
      close_tag(fmt, p.list_style)
    }
    Label(label, x) => fprint_pair(fmt, label, x)
    Custom(f) => f(fmt)
  }
}

///|
fn fprint_list_body_stick_left(
  fmt : @format.Formatter,
  p : ListParam,
  sep : String,
  hd : T,
  tl : ArrayView[T],
) -> Unit {
  open_tag(fmt, p.body_style)
  fprint_t(fmt, hd)
  for x in tl {
    if p.space_before_separator {
      fmt.print_string(" ")
    }
    tag_string(fmt, p.separator_style, sep)
    if p.space_after_separator {
      fmt.print_space()
    } else {
      fmt.print_cut()
    }
    fprint_t(fmt, x)
  }
  close_tag(fmt, p.body_style)
}

///|
fn fprint_list_body_stick_right(
  fmt : @format.Formatter,
  p : ListParam,
  sep : String,
  hd : T,
  tl : ArrayView[T],
) -> Unit {
  open_tag(fmt, p.body_style)
  fprint_t(fmt, hd)
  for x in tl {
    if p.space_before_separator {
      fmt.print_space()
    } else {
      fmt.print_cut()
    }
    tag_string(fmt, p.separator_style, sep)
    if p.space_after_separator {
      fmt.print_string(" ")
    }
    fprint_t(fmt, x)
  }
  close_tag(fmt, p.body_style)
}

///|
fn fprint_opt_label(fmt : @format.Formatter, label : (T, LabelParam)?) -> Unit {
  if label is Some((lab, lp)) {
    open_tag(fmt, lp.label_style)
    fprint_t(fmt, lab)
    close_tag(fmt, lp.label_style)
    if lp.space_after_label {
      fmt.print_string(" ")
    }
  }
}

///|
/// Either horizontal or vertical list.
fn fprint_list(
  fmt : @format.Formatter,
  label : (T, LabelParam)?,
  param : (String, String, String, ListParam),
  l : Array[T],
) -> Unit {
  let (op, _, cl, p) = param
  match l {
    [] => {
      fprint_opt_label(fmt, label)
      tag_string(fmt, p.opening_style, op)
      if p.space_after_opening || p.space_before_closing {
        fmt.print_string(" ")
      }
      tag_string(fmt, p.closing_style, cl)
    }
    [hd, .. tl] =>
      if tl.length() == 0 || p.separators_stick_left {
        fprint_list_stick_left(fmt, label, param, hd, tl, l)
      } else {
        fprint_list_stick_right(fmt, label, param, hd, tl, l)
      }
  }
}

///|
fn fprint_list_stick_left(
  fmt : @format.Formatter,
  label : (T, LabelParam)?,
  param : (String, String, String, ListParam),
  hd : T,
  tl : ArrayView[T],
  l : Array[T],
) -> Unit {
  let (op, sep, cl, p) = param
  let indent = p.indent_body
  pp_open_xbox(fmt, p, indent)
  fprint_opt_label(fmt, label)
  tag_string(fmt, p.opening_style, op)
  if p.space_after_opening {
    fmt.print_space()
  } else {
    fmt.print_cut()
  }
  let extra = extra_box(p, l)
  if extra {
    fmt.open_hovbox(0)
  }
  fprint_list_body_stick_left(fmt, p, sep, hd, tl)
  if extra {
    fmt.close_box()
  }
  if p.space_before_closing {
    fmt.print_break(1, -indent)
  } else {
    fmt.print_break(0, -indent)
  }
  tag_string(fmt, p.closing_style, cl)
  fmt.close_box()
}

///|
fn fprint_list_stick_right(
  fmt : @format.Formatter,
  label : (T, LabelParam)?,
  param : (String, String, String, ListParam),
  hd : T,
  tl : ArrayView[T],
  l : Array[T],
) -> Unit {
  let (op, sep, cl, p) = param
  let base_indent = p.indent_body
  // OCaml's `String.length`: the length in bytes
  let sep_indent = @format.utf8_length(sep) +
    (if p.space_after_separator { 1 } else { 0 })
  let indent = base_indent + sep_indent
  pp_open_xbox(fmt, p, indent)
  fprint_opt_label(fmt, label)
  tag_string(fmt, p.opening_style, op)
  if p.space_after_opening {
    fmt.print_space()
  } else {
    fmt.print_cut()
  }
  let extra = extra_box(p, l)
  if extra {
    fmt.open_hovbox(0)
  }
  fprint_t(fmt, hd)
  for x in tl {
    if p.space_before_separator {
      fmt.print_break(1, -sep_indent)
    } else {
      fmt.print_break(0, -sep_indent)
    }
    tag_string(fmt, p.separator_style, sep)
    if p.space_after_separator {
      fmt.print_string(" ")
    }
    fprint_t(fmt, x)
  }
  if extra {
    fmt.close_box()
  }
  if p.space_before_closing {
    fmt.print_break(1, -indent)
  } else {
    fmt.print_break(0, -indent)
  }
  tag_string(fmt, p.closing_style, cl)
  fmt.close_box()
}

///|
/// Lists with `align_closing = false`.
fn fprint_list2(
  fmt : @format.Formatter,
  param : (String, String, String, ListParam),
  l : Array[T],
) -> Unit {
  let (op, sep, cl, p) = param
  match l {
    [] => {
      tag_string(fmt, p.opening_style, op)
      if p.space_after_opening || p.space_before_closing {
        fmt.print_string(" ")
      }
      tag_string(fmt, p.closing_style, cl)
    }
    [hd, .. tl] => {
      tag_string(fmt, p.opening_style, op)
      if p.space_after_opening {
        fmt.print_string(" ")
      }
      pp_open_nonaligned_box(fmt, p, 0, l)
      if p.separators_stick_left {
        fprint_list_body_stick_left(fmt, p, sep, hd, tl)
      } else {
        fprint_list_body_stick_right(fmt, p, sep, hd, tl)
      }
      fmt.close_box()
      if p.space_before_closing {
        fmt.print_string(" ")
      }
      tag_string(fmt, p.closing_style, cl)
    }
  }
}

///|
/// Printing a label:value pair.
///
/// The opening bracket stays on the same line as the key, no matter what,
/// and the closing bracket is either on the same line or vertically aligned
/// with the beginning of the key.
fn fprint_pair(fmt : @format.Formatter, label : (T, LabelParam), x : T) -> Unit {
  let (lab, lp) = label
  match x {
    List((op, sep, cl, p), l) if p.stick_to_label && p.align_closing =>
      fprint_list(fmt, Some(label), (op, sep, cl, p), l)
    _ => {
      let indent = lp.indent_after_label
      fmt.open_hvbox(0)
      open_tag(fmt, lp.label_style)
      fprint_t(fmt, lab)
      close_tag(fmt, lp.label_style)
      match lp.label_break {
        Auto =>
          if lp.space_after_label {
            fmt.print_break(1, indent)
          } else {
            fmt.print_break(0, indent)
          }
        Always | AlwaysRec => {
          fmt.force_newline()
          fmt.print_string(String::make(indent, ' '))
        }
        Never => if lp.space_after_label { fmt.print_char(' ') }
      }
      fprint_t(fmt, x)
      fmt.close_box()
    }
  }
}

///|
/// Pretty-print a tree with a formatter, and flush it.
/// `Pretty.to_formatter` in OCaml.
pub fn to_formatter(fmt : @format.Formatter, x : T) -> Unit {
  let x = propagate_forced_breaks(x)
  fprint_t(fmt, x)
  fmt.print_flush()
}

///|
/// Pretty-print a tree into a string builder, with a fresh formatter (whose
/// margin is 78). `Pretty.to_buffer` in OCaml.
pub fn to_buffer(
  buf : StringBuilder,
  x : T,
  escape? : Escape = NoEscape,
  styles? : ArrayView[(String, Style)] = [],
) -> Unit {
  let fmt = @format.Formatter::of_buffer(buf)
  define_styles(fmt, escape, styles)
  to_formatter(fmt, x)
}

///|
/// Pretty-print a tree into a string. `Pretty.to_string` in OCaml.
pub fn to_string(
  x : T,
  escape? : Escape = NoEscape,
  styles? : ArrayView[(String, Style)] = [],
) -> String {
  let buf = StringBuilder()
  to_buffer(buf, x, escape~, styles~)
  buf.to_string()
}

// Printing without spacing or newlines other than those in the input data
// or those produced by `Custom` printing (`Easy_format.Compact`)

///|
fn compact_fprint_t(buf : StringBuilder, x : T) -> Unit {
  match x {
    Atom(s, _) => buf.write_string(s)
    List((op, sep, cl, _), l) => {
      buf.write_string(op)
      for i, x in l {
        if i > 0 {
          buf.write_string(sep)
        }
        compact_fprint_t(buf, x)
      }
      buf.write_string(cl)
    }
    Label((label, _), x) => {
      compact_fprint_t(buf, label)
      compact_fprint_t(buf, x)
    }
    Custom(f) => {
      // will most likely not be compact
      let fmt = @format.Formatter::of_buffer(buf)
      f(fmt)
      fmt.print_flush()
    }
  }
}

///|
/// Print a tree into a string builder without spacing or newlines other
/// than those in the input data. `Compact.to_buffer` in OCaml.
pub fn compact_to_buffer(buf : StringBuilder, x : T) -> Unit {
  compact_fprint_t(buf, x)
}

///|
/// Print a tree into a string without spacing or newlines other than those
/// in the input data. `Compact.to_string` in OCaml.
pub fn compact_to_string(x : T) -> String {
  let buf = StringBuilder()
  compact_to_buffer(buf, x)
  buf.to_string()
}

///|
/// Print a tree with a formatter without spacing or newlines other than
/// those in the input data, and flush it. `Compact.to_formatter` in OCaml.
pub fn compact_to_formatter(fmt : @format.Formatter, x : T) -> Unit {
  fmt.print_string(compact_to_string(x))
  fmt.print_flush()
}

// Predefined sets of parameters (`Easy_format.Param`, deprecated)

///|
/// All the boolean fields set to true, `indent_body = 2`.
#deprecated("Derive the parameters from `list` instead")
pub let list_true : ListParam = { ..list, space_before_separator: true, }

///|
/// All the boolean fields set to false, `indent_body = 2`.
#deprecated("Derive the parameters from `list` instead")
pub let list_false : ListParam = {
  ..list,
  space_after_opening: false,
  space_after_separator: false,
  separators_stick_left: false,
  space_before_closing: false,
  stick_to_label: false,
  align_closing: false,
}

///|
/// All the boolean fields set to true, `indent_after_label = 2`.
#deprecated("Derive the parameters from `label` instead")
pub let label_true : LabelParam = label

///|
/// All the boolean fields set to false, `indent_after_label = 2`.
#deprecated("Derive the parameters from `label` instead")
pub let label_false : LabelParam = { ..label, space_after_label: false, }
