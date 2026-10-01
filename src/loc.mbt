// Source locations, modeled after OCaml's `Lexing.position`.
// All offsets are byte offsets into the UTF-8 encoded source, so that
// error messages report the same columns as the OCaml implementation.

///|
/// A position in a source file.
pub(all) struct Pos {
  /// File name, used in error messages.
  fname : String
  /// Line number, starting from 1.
  lnum : Int
  /// Byte offset of the beginning of the line.
  bol : Int
  /// Byte offset of the position.
  cnum : Int
} derive(Eq, Debug)

///|
/// A region in a source file.
pub(all) struct Loc {
  start : Pos
  end_ : Pos
} derive(Eq, Debug)

///|
/// The dummy position, as OCaml's `Lexing.dummy_pos`.
pub let dummy_pos : Pos = { fname: "", lnum: 0, bol: 0, cnum: -1, }

///|
/// Dummy value for predefined constructs that are not associated with a
/// useful source location.
pub let dummy_loc : Loc = { start: dummy_pos, end_: dummy_pos, }

///|
/// Build a location from two positions.
#alias(new, deprecated="Use `Loc(...)` instead")
pub fn Loc::Loc(start : Pos, end_ : Pos) -> Loc {
  { start, end_, }
}

///|
fn compare_pos(a : Pos, b : Pos) -> Int {
  let c = compare_strings(a.fname, b.fname)
  if c != 0 {
    c
  } else {
    a.cnum.compare(b.cnum)
  }
}

///|
/// Compare two locations so as to sort them by file path, then start
/// position, then end position.
pub fn Loc::compare(a : Loc, b : Loc) -> Int {
  let c = compare_pos(a.start, b.start)
  if c != 0 {
    c
  } else {
    compare_pos(a.end_, b.end_)
  }
}

///|
/// Convert a location into a human-readable string such as
/// `File "foo.atd", line 123, characters 40-45`.
pub fn string_of_loc(loc : Loc) -> String {
  let pos1 = loc.start
  let pos2 = loc.end_
  let start1 = pos1.bol
  "File \{ocaml_quote(pos1.fname)}, line \{pos1.lnum}, characters \{pos1.cnum - start1}-\{pos2.cnum - start1}"
}
