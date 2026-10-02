// Conversion of an ATD tree to OCaml source code for that value
// (`atdcat -ml`), a port of `reflect.ml`.

///|
fn[T] r_list(
  buf : StringBuilder,
  l : Array[T],
  f : (StringBuilder, T) -> Unit,
) -> Unit {
  buf.write_string("[")
  for x in l {
    f(buf, x)
    buf.write_string(";\n")
  }
  buf.write_string("]")
}

///|
fn[T] r_opt(
  buf : StringBuilder,
  o : T?,
  f : (StringBuilder, T) -> Unit,
) -> Unit {
  match o {
    None => buf.write_string("None")
    Some(x) => {
      buf.write_string("Some (")
      f(buf, x)
      buf.write_string(")")
    }
  }
}

///|
fn r_qstring(buf : StringBuilder, s : String) -> Unit {
  buf.write_string(ocaml_quote(s))
}

///|
fn r_annot(buf : StringBuilder, l : Annot) -> Unit {
  r_list(buf, l, (buf, s) => {
    buf.write_string("(\{ocaml_quote(s.name)}, (loc, ")
    r_list(buf, s.fields, (buf, f) => {
      buf.write_string("(\{ocaml_quote(f.name)}, (loc, ")
      r_opt(buf, f.value, r_qstring)
      buf.write_string("))")
    })
    buf.write_string("))")
  })
}

///|
fn r_type_expr(buf : StringBuilder, x : TypeExpr) -> Unit {
  let unary = (name : String, t : TypeExpr, a : Annot) => {
    buf.write_string("\{name} (loc, ")
    r_type_expr(buf, t)
    buf.write_string(", ")
    r_annot(buf, a)
    buf.write_string(")")
  }
  match x {
    Sum(_, vl, a) => {
      buf.write_string("Sum (loc, ")
      r_list(buf, vl, r_variant)
      buf.write_string(", ")
      r_annot(buf, a)
      buf.write_string(")")
    }
    Record(_, fl, a) => {
      buf.write_string("Record (loc, ")
      r_list(buf, fl, r_field)
      buf.write_string(", ")
      r_annot(buf, a)
      buf.write_string(")")
    }
    Tuple(_, cl, a) => {
      buf.write_string("Tuple (loc, ")
      r_list(buf, cl, r_cell)
      buf.write_string(", ")
      r_annot(buf, a)
      buf.write_string(")")
    }
    List(_, t, a) => unary("List", t, a)
    Option(_, t, a) => unary("Option", t, a)
    Nullable(_, t, a) => unary("Nullable", t, a)
    Shared(_, t, a) => unary("Shared", t, a)
    Wrap(_, t, a) => unary("Wrap", t, a)
    Name(_, inst, a) => {
      buf.write_string("Name (loc, ")
      buf.write_string("(loc, \{ocaml_quote(inst.name.to_string())}, ")
      r_list(buf, inst.args, r_type_expr)
      buf.write_string("), ")
      r_annot(buf, a)
      buf.write_string(")")
    }
    Tvar(_, s) => buf.write_string("Tvar (loc, \{ocaml_quote(s)})")
  }
}

///|
fn r_cell(buf : StringBuilder, c : Cell) -> Unit {
  buf.write_string("(loc, ")
  r_type_expr(buf, c.expr)
  buf.write_string(", ")
  r_annot(buf, c.annot)
  buf.write_string(")")
}

///|
fn r_variant(buf : StringBuilder, x : Variant) -> Unit {
  match x {
    Variant(_, s, a, o) => {
      buf.write_string("Variant (loc, (\{ocaml_quote(s)}, ")
      r_annot(buf, a)
      buf.write_string("), ")
      r_opt(buf, o, r_type_expr)
      buf.write_string(")")
    }
    Inherit(_, x) => {
      buf.write_string("Inherit (loc, ")
      r_type_expr(buf, x)
      buf.write_string(")")
    }
  }
}

///|
fn r_field(buf : StringBuilder, x : Field) -> Unit {
  match x {
    Field(f) => {
      let kind = match f.kind {
        Required => "Required"
        Optional => "Optional"
        WithDefault => "With_default"
      }
      buf.write_string("Field (loc, (\{ocaml_quote(f.name)}, \{kind}, ")
      r_annot(buf, f.annot)
      buf.write_string("), ")
      r_type_expr(buf, f.expr)
      buf.write_string(")")
    }
    Inherit(_, x) => {
      buf.write_string("Inherit (loc, ")
      r_type_expr(buf, x)
      buf.write_string(")")
    }
  }
}

///|
fn r_imported_type(buf : StringBuilder, it : ImportedType) -> Unit {
  buf.write_string("{ it_params = ")
  r_list(buf, it.params, r_qstring)
  buf.write_string("; it_name = \{ocaml_quote(it.name)}; it_annot = ")
  r_annot(buf, it.annot)
  buf.write_string(" }")
}

///|
fn r_import(buf : StringBuilder, x : Import) -> Unit {
  buf.write_string("{ loc = loc; path = ")
  r_list(buf, x.path, r_qstring)
  buf.write_string("; annot = ")
  r_annot(buf, x.annot)
  buf.write_string("; alias = ")
  r_opt(buf, x.alias_, r_qstring)
  buf.write_string("; name = \{ocaml_quote(x.name)}; types = ")
  r_list(buf, x.types, r_imported_type)
  buf.write_string(" }")
}

///|
fn r_type_def(buf : StringBuilder, x : TypeDef) -> Unit {
  buf.write_string(
    "{ loc = loc; name = \{ocaml_quote(x.name.to_string())}; param = ",
  )
  r_list(buf, x.param, r_qstring)
  buf.write_string("; annot = ")
  r_annot(buf, x.annot)
  buf.write_string("; value = ")
  r_type_expr(buf, x.value)
  buf.write_string("; orig = ")
  r_opt(buf, x.orig, r_type_def)
  buf.write_string("; } ")
}

///|
fn[T] r_top_list(
  buf : StringBuilder,
  l : Array[T],
  f : (StringBuilder, T) -> Unit,
) -> Unit {
  buf.write_string("[\n")
  for x in l {
    f(buf, x)
    buf.write_string(";\n")
  }
  buf.write_string("]\n")
}

///|
/// Print the OCaml code of the AST of a module, like `atdcat -ml name`.
pub fn reflect_module(name : String, x : Module) -> String {
  let buf = StringBuilder()
  buf.write_string(
    "let \{name}_head : Ast.module_head =\n  let loc = Ast.dummy_loc in\n  (loc, ",
  )
  r_annot(buf, x.head.1)
  buf.write_string(")\n")
  buf.write_string(
    "let \{name}_imports : Ast.imports list =\n  let loc = Ast.dummy_loc in\n",
  )
  r_top_list(buf, x.imports, r_import)
  buf.write_string("\n")
  buf.write_string(
    "let \{name}_type_defs : Ast.type_defs list =\n  let loc = Ast.dummy_loc in\n",
  )
  r_top_list(buf, x.type_defs, r_type_def)
  buf.write_string("\n")
  buf.write_string(
    "let \{name}_full : Ast.module_ = {\n  module_head = \{name}_head;\n  imports = \{name}_imports;\n  type_defs = \{name}_type_defs;\n}\n",
  )
  buf.to_string()
}

///|
/// Version of the ATD library.
pub let version : String = "0.3.0"
