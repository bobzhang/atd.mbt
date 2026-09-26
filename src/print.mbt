// Pretty-printing of ATD trees in ATD syntax, a port of `print.ml`.

///|
let rlist : @easy_format.ListParam = {
  ..@easy_format.list,
  wrap_body: ForceBreaks,
  indent_body: 0,
  align_closing: false,
  space_after_opening: false,
  space_before_closing: false,
}

///|
let plist : @easy_format.ListParam = {
  ..@easy_format.list,
  align_closing: false,
  space_after_opening: false,
  space_before_closing: false,
}

///|
let hlist : @easy_format.ListParam = {
  ..@easy_format.list,
  wrap_body: NoBreaks,
}

///|
let shlist : @easy_format.ListParam = {
  ..hlist,
  stick_to_label: false,
  space_after_opening: false,
  space_before_closing: false,
}

///|
let shlist0 : @easy_format.ListParam = {
  ..shlist,
  space_after_separator: false,
}

///|
let llist : @easy_format.ListParam = {
  ..@easy_format.list,
  separators_stick_left: false,
  space_before_separator: true,
  space_after_separator: true,
}

///|
let lplist : @easy_format.ListParam = {
  ..llist,
  space_after_opening: false,
  space_before_closing: false,
}

///|
let label0 : @easy_format.LabelParam = {
  ..@easy_format.label,
  space_after_label: false,
}

///|
fn make_atom(s : String) -> @easy_format.T {
  Atom(s)
}

///|
fn horizontal_sequence(l : Array[@easy_format.T]) -> @easy_format.T {
  List(("", "", "", shlist), l)
}

///|
fn horizontal_sequence0(l : Array[@easy_format.T]) -> @easy_format.T {
  List(("", "", "", shlist0), l)
}

///|
fn format_prop(f : AnnotField) -> @easy_format.T {
  match f.value {
    None => make_atom(f.name)
    Some(s) =>
      Label((make_atom(f.name + "="), label0), make_atom(ocaml_quote(s)))
  }
}

///|
/// The default way of formatting an annotation section.
pub fn default_format_annot(s : AnnotSection) -> @easy_format.T {
  match s.fields {
    [] => make_atom("<" + s.name + ">")
    l =>
      List(("<", "", ">", plist), [
        Label(
          (make_atom(s.name), @easy_format.label),
          List(("", "", "", plist), l.map(format_prop)),
        ),
      ])
  }
}

///|
fn string_of_field(k : String, fk : FieldKind) -> String {
  match fk {
    Required => k
    Optional => "?" + k
    WithDefault => "~" + k
  }
}

///|
priv struct Printer {
  format_annot : (AnnotSection) -> @easy_format.T
}

///|
fn Printer::append_annots(
  self : Printer,
  l : Annot,
  x : @easy_format.T,
) -> @easy_format.T {
  match l {
    [] => x
    _ =>
      Label(
        (x, @easy_format.label),
        List(("", "", "", plist), l.map(self.format_annot)),
      )
  }
}

///|
fn Printer::prepend_colon_annots(
  self : Printer,
  l : Annot,
  x : @easy_format.T,
) -> @easy_format.T {
  match l {
    [] => x
    _ =>
      Label(
        (
          Label(
            (List(("", "", "", plist), l.map(self.format_annot)), label0),
            make_atom(":"),
          ),
          @easy_format.label,
        ),
        x,
      )
  }
}

///|
fn prepend_type_param(
  l : Array[String],
  tl : Array[@easy_format.T],
) -> Array[@easy_format.T] {
  match l {
    [] => tl
    _ => {
      let make_var = s => make_atom("'" + s)
      let x = match l {
        [s] => make_var(s)
        l => List(("(", ",", ")", plist), l.map(make_var))
      }
      [x, ..tl]
    }
  }
}

///|
fn Printer::prepend_type_args(
  self : Printer,
  l : Array[TypeExpr],
  tl : Array[@easy_format.T],
) -> Array[@easy_format.T] {
  match l {
    [] => tl
    [t] => [self.format_type_expr(t), ..tl]
    l =>
      [List(("(", ",", ")", plist), l.map(t => self.format_type_expr(t))), ..tl]
  }
}

///|
fn Printer::format_type_expr(self : Printer, x : TypeExpr) -> @easy_format.T {
  match x {
    Sum(_, l, a) =>
      self.append_annots(
        a,
        List(("[", "|", "]", llist), l.map(v => self.format_variant(v))),
      )
    Record(_, l, a) =>
      self.append_annots(
        a,
        List(
          ("{", ";", "}", @easy_format.list),
          l.map(f => self.format_field(f)),
        ),
      )
    Tuple(_, l, a) =>
      self.append_annots(
        a,
        List(("(", "*", ")", lplist), l.map(c => self.format_cell(c))),
      )
    List(_, t, a) => self.format_type_name("list", [t], a)
    Option(_, t, a) => self.format_type_name("option", [t], a)
    Nullable(_, t, a) => self.format_type_name("nullable", [t], a)
    Shared(_, t, a) => self.format_type_name("shared", [t], a)
    Wrap(_, t, a) => self.format_type_name("wrap", [t], a)
    Name(_, inst, a) =>
      self.format_type_name(inst.name.to_string(), inst.args, a)
    Tvar(_, name) => make_atom("'" + name)
  }
}

///|
fn Printer::format_type_name(
  self : Printer,
  name : String,
  args : Array[TypeExpr],
  a : Annot,
) -> @easy_format.T {
  self.append_annots(
    a,
    horizontal_sequence(self.prepend_type_args(args, [make_atom(name)])),
  )
}

///|
fn Printer::format_inherit(self : Printer, t : TypeExpr) -> @easy_format.T {
  horizontal_sequence([make_atom("inherit"), self.format_type_expr(t)])
}

///|
fn Printer::format_cell(self : Printer, c : Cell) -> @easy_format.T {
  self.prepend_colon_annots(c.annot, self.format_type_expr(c.expr))
}

///|
fn Printer::format_field(self : Printer, x : Field) -> @easy_format.T {
  match x {
    Field(f) =>
      Label(
        (
          horizontal_sequence0([
            self.append_annots(
              f.annot,
              make_atom(string_of_field(f.name, f.kind)),
            ),
            make_atom(":"),
          ]),
          @easy_format.label,
        ),
        self.format_type_expr(f.expr),
      )
    Inherit(_, t) => self.format_inherit(t)
  }
}

///|
fn Printer::format_variant(self : Printer, x : Variant) -> @easy_format.T {
  match x {
    Variant(_, k, a, opt) => {
      let cons = self.append_annots(a, make_atom(k))
      match opt {
        None => cons
        Some(t) =>
          Label(
            (cons, @easy_format.label),
            Label(
              (make_atom("of"), @easy_format.label),
              self.format_type_expr(t),
            ),
          )
      }
    }
    Inherit(_, t) => self.format_inherit(t)
  }
}

///|
fn Printer::format_imported_type(
  self : Printer,
  it : ImportedType,
) -> @easy_format.T {
  let name_atom = match it.params {
    [] => make_atom(it.name)
    [p] => horizontal_sequence([make_atom("'" + p), make_atom(it.name)])
    ps => {
      let params : @easy_format.T = List(
        ("(", ",", ")", plist),
        ps.map(p => make_atom("'" + p)),
      )
      horizontal_sequence([params, make_atom(it.name)])
    }
  }
  if it.annot.is_empty() {
    name_atom
  } else {
    self.append_annots(it.annot, name_atom)
  }
}

///|
fn Printer::format_import(self : Printer, x : Import) -> @easy_format.T {
  let type_list : @easy_format.T = List(
    ("", ",", "", lplist),
    x.types.map(it => self.format_imported_type(it)),
  )
  let l = [
    make_atom("from"),
    self.append_annots(x.annot, make_atom(x.path.join("."))),
  ]
  match x.alias_ {
    None => ()
    Some(local_name) => l.push(make_atom("as " + local_name))
  }
  l.push(make_atom("import"))
  l.push(type_list)
  horizontal_sequence(l)
}

///|
fn Printer::format_type_def(self : Printer, x : TypeDef) -> @easy_format.T {
  let left = if x.annot.is_empty() {
    horizontal_sequence(
      [
        make_atom("type"),
        ..prepend_type_param(x.param, [make_atom(x.name.to_string() + " =")]),
      ],
    )
  } else {
    let l = [
      make_atom("type"),
      ..prepend_type_param(x.param, [make_atom(x.name.to_string())]),
    ]
    let x = self.append_annots(x.annot, horizontal_sequence(l))
    horizontal_sequence([x, make_atom("=")])
  }
  Label((left, @easy_format.label), self.format_type_expr(x.value))
}

///|
fn Printer::format_module(self : Printer, x : Module) -> @easy_format.T {
  let l = x.head.1.map(self.format_annot)
  for i in x.imports {
    l.push(self.format_import(i))
  }
  for d in x.type_defs {
    l.push(self.format_type_def(d))
  }
  List(("", "", "", rlist), l)
}

///|
/// Convert any node into an Easy_format tree.
pub fn format(
  x : Any,
  format_annot? : (AnnotSection) -> @easy_format.T = default_format_annot,
) -> @easy_format.T {
  let p : Printer = { format_annot, }
  match x {
    Module(x) => p.format_module(x)
    Import(x) => p.format_import(x)
    ImportedType(x) => p.format_imported_type(x)
    TypeDef(x) => p.format_type_def(x)
    TypeExpr(x) => p.format_type_expr(x)
    Variant(x) => p.format_variant(x)
    Cell(x) => p.format_cell(x)
    Field(x) => p.format_field(x)
  }
}

///|
/// Pretty-print any node in ATD syntax.
pub fn to_string(
  x : Any,
  format_annot? : (AnnotSection) -> @easy_format.T = default_format_annot,
) -> String {
  @easy_format.to_string(format(x, format_annot~))
}

///|
/// Pretty-print a type name applied to arguments, with annotations.
pub fn string_of_type_inst(
  name : TypeName,
  args : Array[TypeExpr],
  an : Annot,
) -> String {
  let loc = dummy_loc
  to_string(TypeExpr(Name(loc, { loc, name, args, }, an)))
}
