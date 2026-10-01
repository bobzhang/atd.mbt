// Convenience printers, a port of OCaml's `Format.pp_print_list` & co.
//
// Copyright 1996 Institut National de Recherche en Informatique et en
// Automatique (OCaml), distributed under the terms of the GNU Lesser
// General Public License version 2.1, with the special exception on
// linking described in the file LICENSE.

///|
/// The default separator of `print_list`, `print_iter` and `print_array`:
/// a cut break hint.
fn default_sep(ppf : Formatter) -> Unit {
  ppf.print_cut()
}

///|
/// Print the elements of a list with `pp_v`, separated by `pp_sep` (a cut
/// by default), like OCaml's `pp_print_list`.
pub fn[T] Formatter::print_list(
  self : Formatter,
  pp_sep? : (Formatter) -> Unit = default_sep,
  pp_v : (Formatter, T) -> Unit,
  l : @list.List[T],
) -> Unit {
  let mut first = true
  for v in l {
    if !first {
      pp_sep(self)
    }
    first = false
    pp_v(self, v)
  }
}

///|
/// Print the elements of an array, like `print_list`.
pub fn[T] Formatter::print_array(
  self : Formatter,
  pp_sep? : (Formatter) -> Unit = default_sep,
  pp_v : (Formatter, T) -> Unit,
  a : ArrayView[T],
) -> Unit {
  for i, v in a {
    if i > 0 {
      pp_sep(self)
    }
    pp_v(self, v)
  }
}

///|
/// Print the elements of an iterator, like OCaml's `pp_print_seq`.
pub fn[T] Formatter::print_iter(
  self : Formatter,
  pp_sep? : (Formatter) -> Unit = default_sep,
  pp_v : (Formatter, T) -> Unit,
  seq : Iter[T],
) -> Unit {
  let mut first = true
  for v in seq {
    if !first {
      pp_sep(self)
    }
    first = false
    pp_v(self, v)
  }
}

///|
/// Print free-flowing text, like OCaml's `pp_print_text`: spaces are
/// break hints and newlines are forced newlines.
pub fn Formatter::print_text(self : Formatter, s : String) -> Unit {
  let len = s.length()
  let mut left = 0
  let mut right = 0
  let flush = () => {
    self.print_string(s.view(start_offset=left, end_offset=right).to_owned())
    right += 1
    left = right
  }
  while right != len {
    match s[right] {
      '\n' => {
        flush()
        self.force_newline()
      }
      ' ' => {
        flush()
        self.print_space()
      }
      // there is no specific support for '\t' as it is unclear what a
      // right semantics would be
      _ => right += 1
    }
  }
  if left != len {
    flush()
  }
}

///|
/// Print an optional value with `pp_v`; `None` is printed with `none`,
/// which prints nothing by default, like OCaml's `pp_print_option`.
pub fn[T] Formatter::print_option(
  self : Formatter,
  none? : (Formatter) -> Unit = Formatter::print_nothing,
  pp_v : (Formatter, T) -> Unit,
  o : T?,
) -> Unit {
  match o {
    None => none(self)
    Some(v) => pp_v(self, v)
  }
}

///|
/// Print a result with `ok` or `error`, like OCaml's `pp_print_result`.
pub fn[T, E] Formatter::print_result(
  self : Formatter,
  ok~ : (Formatter, T) -> Unit,
  error~ : (Formatter, E) -> Unit,
  r : Result[T, E],
) -> Unit {
  match r {
    Ok(v) => ok(self, v)
    Err(e) => error(self, e)
  }
}
