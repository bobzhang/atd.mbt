// A port of the `easy-format` OCaml library (pretty-printing of trees made
// of atoms, lists and labels) on top of the `format` package.
// Styles, escaping and custom nodes are not supported.

///|
/// How the body of a list may be wrapped.
pub(all) enum Wrap {
  WrapAtoms
  AlwaysWrap
  NeverWrap
  ForceBreaks
  ForceBreaksRec
  NoBreaks
} derive(Eq, Debug)

///|
/// When to break a line after a label.
pub(all) enum LabelBreak {
  Auto
  Always
  AlwaysRec
  Never
} derive(Eq, Debug)

///|
/// Parameters of a list node.
pub(all) struct ListParam {
  space_after_opening : Bool
  space_after_separator : Bool
  space_before_separator : Bool
  separators_stick_left : Bool
  space_before_closing : Bool
  stick_to_label : Bool
  align_closing : Bool
  wrap_body : Wrap
  indent_body : Int
} derive(Eq, Debug)

///|
/// Default list parameters, as `Easy_format.list`.
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
}

///|
/// Parameters of a label node.
pub(all) struct LabelParam {
  label_break : LabelBreak
  space_after_label : Bool
  indent_after_label : Int
} derive(Eq, Debug)

///|
/// Default label parameters, as `Easy_format.label`.
pub let label : LabelParam = {
  label_break: Auto,
  space_after_label: true,
  indent_after_label: 2,
}

///|
/// A tree to be pretty-printed.
pub(all) enum T {
  Atom(String)
  List((String, String, String, ListParam), Array[T])
  Label((T, LabelParam), T)
} derive(Debug)

///|
/// Convert wrappable lists into vertical lists if any of their descendants
/// has the attribute `wrap_body = ForceBreaksRec`.
fn propagate_forced_breaks(x : T) -> T {
  fn init_acc(x : T) -> Bool {
    match x {
      List((_, _, _, { wrap_body: ForceBreaksRec, .. }), _) => true
      Label((_, { label_break: AlwaysRec, .. }), _) => true
      _ => false
    }
  }

  fn map_node(x : T, force_breaks : Bool) -> (T, Bool) {
    match x {
      List((_, _, _, { wrap_body: ForceBreaksRec, .. }), _) => (x, true)
      List((_, _, _, { wrap_body: ForceBreaks, .. }), _) => (x, force_breaks)
      List(
        (op, sep, cl, { wrap_body: WrapAtoms | NeverWrap | AlwaysWrap, .. } as p
        ),
        children
      ) =>
        if force_breaks {
          let p = { ..p, wrap_body: ForceBreaks, }
          (List((op, sep, cl, p), children), true)
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
      | Atom(_) => (x, force_breaks)
    }
  }

  fn aux(x : T) -> (T, Bool) {
    match x {
      Atom(_) => map_node(x, init_acc(x))
      List(param, children) => {
        let mut acc = init_acc(x)
        let new_children = []
        for child in children {
          let (c, a) = aux(child)
          new_children.push(c)
          acc = acc || a
        }
        map_node(List(param, new_children), acc)
      }
      Label((x1, param), x2) => {
        let acc0 = init_acc(x)
        let (new_x1, acc1) = aux(x1)
        let (new_x2, acc2) = aux(x2)
        map_node(Label((new_x1, param), new_x2), acc0 || acc1 || acc2)
      }
    }
  }

  aux(x).0
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
fn all_atoms(l : Array[T]) -> Bool {
  l.iter().all(x => x is Atom(_))
}

///|
fn extra_box(p : ListParam, l : Array[T]) -> Bool {
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
  l : Array[T],
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
fn fprint_t(fmt : @format.Formatter, x : T) -> Unit {
  match x {
    Atom(s) => fmt.print_string(s)
    List((_, _, _, p) as param, l) =>
      if p.align_closing {
        fprint_list(fmt, None, param, l)
      } else {
        fprint_list2(fmt, param, l)
      }
    Label(label, x) => fprint_pair(fmt, label, x)
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
  fprint_t(fmt, hd)
  for x in tl {
    if p.space_before_separator {
      fmt.print_string(" ")
    }
    fmt.print_string(sep)
    if p.space_after_separator {
      fmt.print_space()
    } else {
      fmt.print_cut()
    }
    fprint_t(fmt, x)
  }
}

///|
fn fprint_list_body_stick_right(
  fmt : @format.Formatter,
  p : ListParam,
  sep : String,
  hd : T,
  tl : ArrayView[T],
) -> Unit {
  fprint_t(fmt, hd)
  for x in tl {
    if p.space_before_separator {
      fmt.print_space()
    } else {
      fmt.print_cut()
    }
    fmt.print_string(sep)
    if p.space_after_separator {
      fmt.print_string(" ")
    }
    fprint_t(fmt, x)
  }
}

///|
fn fprint_opt_label(fmt : @format.Formatter, label : (T, LabelParam)?) -> Unit {
  match label {
    None => ()
    Some((lab, lp)) => {
      fprint_t(fmt, lab)
      if lp.space_after_label {
        fmt.print_string(" ")
      }
    }
  }
}

///|
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
      fmt.print_string(op)
      if p.space_after_opening || p.space_before_closing {
        fmt.print_string(" ")
      }
      fmt.print_string(cl)
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
  fmt.print_string(op)
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
  fmt.print_string(cl)
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
  let sep_indent = @format.utf8_length(sep) +
    (if p.space_after_separator { 1 } else { 0 })
  let indent = base_indent + sep_indent
  pp_open_xbox(fmt, p, indent)
  fprint_opt_label(fmt, label)
  fmt.print_string(op)
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
    fmt.print_string(sep)
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
  fmt.print_string(cl)
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
      fmt.print_string(op)
      if p.space_after_opening || p.space_before_closing {
        fmt.print_string(" ")
      }
      fmt.print_string(cl)
    }
    [hd, .. tl] => {
      fmt.print_string(op)
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
      fmt.print_string(cl)
    }
  }
}

///|
/// Printing a label:value pair.
fn fprint_pair(fmt : @format.Formatter, label : (T, LabelParam), x : T) -> Unit {
  let (lab, lp) = label
  match x {
    List((op, sep, cl, p), l) if p.stick_to_label && p.align_closing =>
      fprint_list(fmt, Some(label), (op, sep, cl, p), l)
    _ => {
      let indent = lp.indent_after_label
      fmt.open_hvbox(0)
      fprint_t(fmt, lab)
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
/// Print a tree into a formatter and flush it.
pub fn to_formatter(fmt : @format.Formatter, x : T) -> Unit {
  let x = propagate_forced_breaks(x)
  fprint_t(fmt, x)
  fmt.print_flush()
}

///|
/// Pretty-print a tree into a string, like `Easy_format.Pretty.to_string`.
pub fn to_string(x : T) -> String {
  let buf = StringBuilder()
  to_formatter(@format.Formatter::of_buffer(buf), x)
  buf.to_string()
}
