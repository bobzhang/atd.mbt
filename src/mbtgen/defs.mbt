// Generation of MoonBit definitions for ATD type definitions.

///|
/// Doc comment lines (`/// ...`) from a `<doc text="...">` annotation.
fn doc_comment(
  loc : @atd.Loc,
  an : @atd.Annot,
  indent? : String = "",
) -> Array[String] raise @atd.AtdError {
  match @atd.get_doc(loc, an) {
    None => []
    Some(blocks) => {
      let lines = []
      for i, block in blocks {
        if i > 0 {
          lines.push(indent + "///")
        }
        match block {
          Paragraph(inlines) => {
            let text = inlines
              .map(x => {
                match x {
                  Text(s) => s
                  Code(s) => "`" + s + "`"
                }
              })
              .join("")
            for line in @atd.rewrap_paragraph(text, max_length=72) {
              lines.push(indent + "/// " + line)
            }
          }
          Pre(pre_lines) => {
            lines.push(indent + "/// ```text")
            for line in pre_lines {
              lines.push(
                if line == "" {
                  indent + "///"
                } else {
                  indent + "/// " + line
                },
              )
            }
            lines.push(indent + "/// ```")
          }
        }
      }
      lines
    }
  }
}

///|
/// The traits derived by a struct or enum: `<mbt derive="...">`, or
/// `Eq, Debug`, plus `Hash` for the types used as keys of maps.
fn Env::derived_traits(
  self : Env,
  d : @atd.TypeDef,
) -> Array[String] raise @atd.AtdError {
  match get_mbt_string(d.annot, "derive") {
    None =>
      if self.hash_types.contains(d.name.to_string()) {
        ["Eq", "Hash", "Debug"]
      } else {
        ["Eq", "Debug"]
      }
    Some(s) =>
      s.split(",").map(x => x.trim().to_owned()).filter(x => x != "").collect()
  }
}

///|
fn Env::derive_clause(
  self : Env,
  d : @atd.TypeDef,
) -> String raise @atd.AtdError {
  match self.derived_traits(d) {
    [] => ""
    l => " derive(\{l.join(", ")})"
  }
}

///|
/// The methods of the traits that MoonBit promotes to methods of the type.
fn trait_methods(t : String) -> Array[String]? {
  match t {
    "Eq" => Some(["equal", "not_equal"])
    "Hash" => Some(["hash", "hash_combine"])
    "Debug" => Some(["to_repr"])
    "Compare" => Some(["compare", "op_lt", "op_le", "op_ge", "op_gt"])
    "Default" => Some(["default"])
    "ToJson" => Some(["to_json"])
    _ => None
  }
}

///|
/// Make the methods of derived traits regular methods explicitly, as
/// required by MoonBit (warning `implicit_impl_as_method`).
fn extend_with(
  out : Array[String],
  type_name : String,
  traits : Array[String],
) -> Unit {
  for t in traits {
    match trait_methods(t) {
      Some(methods) => {
        out.push("///|")
        out.push("pub extend \{type_name} with \{t}::{\{methods.join(", ")}}")
        out.push("")
      }
      None => ()
    }
  }
}

///|
/// A field of a record, with all the information needed for code
/// generation.
priv struct FieldInfo {
  loc : @atd.Loc
  mbt_name : String
  json_name : String
  kind : @atd.FieldKind
  /// type of the MoonBit field, and of the JSON value when present
  value_type : @atd.TypeExpr
  /// MoonBit expression for the default value of `~` fields
  default : String?
  annot : @atd.Annot
}

///|
fn Env::field_infos(
  self : Env,
  fields : Array[@atd.Field],
) -> Array[FieldInfo] raise @atd.AtdError {
  let names = member_names(mbt_keywords)
  let res = []
  for f in fields {
    match f {
      Inherit(loc, _) => @atd.error_at(loc, "inherit should have been expanded")
      Field({ loc, name, kind, annot, expr, }) => {
        let mbt_name = match get_mbt_string(annot, "name") {
          Some(n) => {
            if !is_lowercase_ident(n) || mbt_keywords.contains(n) {
              @atd.error_at(
                loc,
                "invalid MoonBit field name \{mbt_string_literal(n)}",
              )
            }
            names.translate(name, preferred_translation=n)
          }
          None => names.translate(name, preferred_translation=sanitize(name))
        }
        let value_type = self.unwrap_field_type(loc, name, kind, expr)
        let default = match kind {
          WithDefault =>
            match get_mbt_string(annot, "default") {
              Some(d) => Some(d)
              None =>
                match self.default_value(value_type, []) {
                  Some(d) => Some(d)
                  None =>
                    @atd.error_at(
                      loc, "a default field value must be specified with <mbt default=\"...\">",
                    )
                }
            }
          Required | Optional => None
        }
        res.push({
          loc,
          mbt_name,
          json_name: @atd.get_json_fname(name, annot),
          kind,
          value_type,
          default,
          annot,
        })
      }
    }
  }
  res
}

///|
/// A variant of a sum type.
priv struct CaseInfo {
  loc : @atd.Loc
  mbt_name : String
  json_name : String
  /// payload type
  payload : @atd.TypeExpr?
  /// MoonBit types of the constructor arguments (a tuple payload is
  /// flattened into several arguments)
  arg_types : Array[String]
  annot : @atd.Annot
}

///|
fn Env::case_infos(
  self : Env,
  variants : Array[@atd.Variant],
) -> Array[CaseInfo] raise @atd.AtdError {
  let names = member_names(mbt_reserved_constructors)
  let res = []
  for v in variants {
    match v {
      Inherit(loc, _) => @atd.error_at(loc, "inherit should have been expanded")
      Variant(loc, name, annot, payload) => {
        let preferred = match get_mbt_string(annot, "name") {
          Some(n) => {
            if !is_uppercase_ident(n) {
              @atd.error_at(
                loc,
                "invalid MoonBit constructor name \{mbt_string_literal(n)}",
              )
            }
            n
          }
          None => sanitize(name)
        }
        let mbt_name = names.translate(name, preferred_translation=preferred)
        let arg_types = match payload {
          None => []
          Some(e) =>
            match unwrap(e) {
              Tuple(_, cells, _) if cells.length() >= 2 => {
                let l = []
                for c in cells {
                  l.push(self.type_of_expr(c.expr))
                }
                l
              }
              _ => [self.type_of_expr(e)]
            }
        }
        res.push({
          loc,
          mbt_name,
          json_name: @atd.get_json_cons(name, annot),
          payload,
          arg_types,
          annot,
        })
      }
    }
  }
  res
}

///|
fn Env::gen_record(
  self : Env,
  out : Array[String],
  d : @atd.TypeDef,
  fields : Array[@atd.Field],
  an : @atd.Annot,
) -> Unit raise @atd.AtdError {
  let atd_name = d.name.to_string()
  let type_name = self.type_name(atd_name)
  let infos = self.field_infos(fields)
  check_duplicate_json_names(infos.map(f => (f.loc, f.json_name)), "field")
  let keep_nulls = @atd.get_json_keep_nulls(an)
  // type definition
  out.push("///|")
  out.append(doc_comment(d.loc, d.annot))
  out.push("pub(all) struct \{type_name} {")
  for f in infos {
    out.append(doc_comment(f.loc, f.annot, indent="  "))
    let t = self.type_of_expr(f.value_type)
    let t = match f.kind {
      Optional => t + "?"
      _ => t
    }
    out.push("  \{f.mbt_name} : \{t}")
  }
  out.push("}\{self.derive_clause(d)}")
  out.push("")
  extend_with(out, type_name, self.derived_traits(d))
  // constructor
  out.push("///|")
  out.push("/// Create a value of type `\{type_name}`.")
  out.push("#alias(new, deprecated=\"Use `\{type_name}(...)` instead\")")
  if infos.is_empty() {
    out.push("pub fn \{type_name}::\{type_name}() -> \{type_name} {")
  } else {
    out.push("pub fn \{type_name}::\{type_name}(")
    for f in infos {
      let t = self.type_of_expr(f.value_type)
      match f.kind {
        Required => out.push("  \{f.mbt_name}~ : \{t},")
        Optional => out.push("  \{f.mbt_name}? : \{t},")
        WithDefault =>
          out.push("  \{f.mbt_name}? : \{t} = \{f.default.unwrap()},")
      }
    }
    out.push(") -> \{type_name} {")
  }
  out.push("  \{type_name}::{ \{infos.map(f => f.mbt_name).join(", ")} }")
  out.push("}")
  out.push("")
  // writer
  out.push("///|")
  out.push("pub fn \{self.writer_name(atd_name)}(x : \{type_name}) -> Json {")
  if infos.is_empty() {
    out.push("  ignore(x)")
  }
  out.push("  let o : Map[String, Json] = Map([])")
  for f in infos {
    let key = mbt_string_literal(f.json_name)
    match f.kind {
      Required | WithDefault =>
        out.push(
          "  o[\{key}] = \{self.write_expr(f.value_type, "x." + f.mbt_name)}",
        )
      Optional => {
        out.push("  match x.\{f.mbt_name} {")
        out.push(
          "    Some(v) => o[\{key}] = \{self.write_expr(f.value_type, "v")}",
        )
        out.push("    None => ()")
        out.push("  }")
      }
    }
  }
  out.push("  Json::object(o)")
  out.push("}")
  out.push("")
  // reader
  let type_lit = mbt_string_literal(atd_name)
  out.push("///|")
  out.push(
    "pub fn \{self.reader_name(atd_name)}(x : Json, path : \{rt}.Path) -> \{type_name} raise \{rt}.JsonError {",
  )
  let o = if infos.is_empty() { "_" } else { "o" }
  out.push("  let \{o} = \{rt}.read_object(x, path, \{type_lit})")
  out.push("  \{type_name}::{")
  let kn = if keep_nulls { ", keep_nulls=true" } else { "" }
  for f in infos {
    let key = mbt_string_literal(f.json_name)
    let r = self.reader(f.value_type)
    match f.kind {
      Required =>
        out.push(
          "    \{f.mbt_name}: \{rt}.read_required_field(o, \{type_lit}, \{key}, \{r}, path),",
        )
      Optional =>
        out.push(
          "    \{f.mbt_name}: \{rt}.read_optional_field(o, \{key}, \{r}, path\{kn}),",
        )
      WithDefault => {
        out.push("    \{f.mbt_name}: match \{rt}.get_field(o, \{key}\{kn}) {")
        out.push(
          "      Some(v) => \{self.read_expr(f.value_type, "v", "path.key(" + key + ")")}",
        )
        out.push("      None => \{f.default.unwrap()}")
        out.push("    },")
      }
    }
  }
  out.push("  }")
  out.push("}")
  out.push("")
}

///|
fn Env::gen_sum(
  self : Env,
  out : Array[String],
  d : @atd.TypeDef,
  variants : Array[@atd.Variant],
  an : @atd.Annot,
) -> Unit raise @atd.AtdError {
  let atd_name = d.name.to_string()
  let type_name = self.type_name(atd_name)
  let cases = self.case_infos(variants)
  let json_sum = @atd.get_json_sum(an)
  let object_repr = json_sum.json_sum_repr is Object
  // with <json open_enum>, the variant with a string payload receives the
  // unknown tags and is written as a plain string
  let mut open_case : String? = None
  if json_sum.json_open_enum {
    // same rules and messages as atdgen
    let sum_loc = unwrap(d.value).loc()
    match cases.filter(c => c.payload is Some(_)) {
      [] =>
        @atd.error_at(
          sum_loc, "Missing catch-all case of the form `| Other of string`, required by <json open_enum>.",
        )
      [c] =>
        match c.payload {
          Some(e) if self.deref(e)
            is Name(_, { name: { path: ["string"], }, args: [], .. }, _) =>
            open_case = Some(c.mbt_name)
          Some(e) =>
            @atd.error_at(
              e.loc(),
              "The argument of this variant must be of type string as imposed by <json open_enum>.",
            )
          None => ()
        }
      _ =>
        @atd.error_at(
          sum_loc, "Multiple variants have arguments, which doesn't make sense when combined with <json open_enum>.",
        )
    }
  }
  check_duplicate_json_names(cases.map(c => (c.loc, c.json_name)), "variant")
  // type definition
  out.push("///|")
  out.append(doc_comment(d.loc, d.annot))
  out.push("pub(all) enum \{type_name} {")
  for c in cases {
    out.append(doc_comment(c.loc, c.annot, indent="  "))
    if c.json_name != c.mbt_name {
      out.push("  // JSON: \{mbt_string_literal(c.json_name)}")
    }
    match c.arg_types {
      [] => out.push("  \{c.mbt_name}")
      l => out.push("  \{c.mbt_name}(\{l.join(", ")})")
    }
  }
  out.push("}\{self.derive_clause(d)}")
  out.push("")
  extend_with(out, type_name, self.derived_traits(d))
  // writer
  out.push("///|")
  out.push("pub fn \{self.writer_name(atd_name)}(x : \{type_name}) -> Json {")
  if cases.is_empty() {
    out.push("  ignore(x)")
    out.push("  abort(\"impossible: empty type\")")
  } else {
    out.push("  match x {")
    for c in cases {
      let tag = "Json::string(\{mbt_string_literal(c.json_name)})"
      match c.payload {
        None => out.push("    \{type_name}::\{c.mbt_name} => \{tag}")
        Some(e) => {
          let n = c.arg_types.length()
          let vars = Array::makei(n, i => "v\{i}")
          let payload = match unwrap(e) {
            Tuple(_, cells, _) if n >= 2 => self.write_tuple_vars(cells, vars)
            _ => self.write_expr(e, "v0")
          }
          let json = if open_case == Some(c.mbt_name) {
            payload
          } else if object_repr {
            "Json::object(Map::from_array([(\{mbt_string_literal(c.json_name)}, \{payload})]))"
          } else {
            "Json::array([\{tag}, \{payload}])"
          }
          out.push(
            "    \{type_name}::\{c.mbt_name}(\{vars.join(", ")}) => \{json}",
          )
        }
      }
    }
    out.push("  }")
  }
  out.push("}")
  out.push("")
  // reader
  let type_lit = mbt_string_literal(atd_name)
  out.push("///|")
  out.push(
    "pub fn \{self.reader_name(atd_name)}(x : Json, path : \{rt}.Path) -> \{type_name} raise \{rt}.JsonError {",
  )
  out.push("  match x {")
  for c in cases {
    if c.payload is None {
      out.push(
        "    String(\{mbt_string_literal(c.json_name)}) => \{type_name}::\{c.mbt_name}",
      )
    }
  }
  fn make(c : CaseInfo, v : String, p : String) -> String raise @atd.AtdError {
    let e = c.payload.unwrap()
    let n = c.arg_types.length()
    match unwrap(e) {
      Tuple(_, cells, _) if n >= 2 => {
        let args = []
        for i, cell in cells {
          args.push(self.read_expr(cell.expr, "a[\{i}]", "p.index(\{i})"))
        }
        "{ let p = \{p}; let a = \{rt}.read_tuple(\{v}, p, \{n}); \{type_name}::\{c.mbt_name}(\{args.join(", ")}) }"
      }
      _ => "\{type_name}::\{c.mbt_name}(\{self.read_expr(e, v, p)})"
    }
  }

  let payload_cases = cases.filter(c => c.payload is Some(_))
  if !payload_cases.is_empty() {
    if object_repr {
      out.push("    Object(_) =>")
      out.push("      match \{rt}.read_single_field(x) {")
      for c in payload_cases {
        let key = mbt_string_literal(c.json_name)
        let r = make(c, "v", "path.key(\{key})")
        out.push("        Some((\{key}, v)) => \{r}")
      }
      out.push("        _ => \{rt}.bad_json(\{type_lit}, x, path)")
      out.push("      }")
    } else {
      for c in payload_cases {
        let key = mbt_string_literal(c.json_name)
        let r = make(c, "v", "path.index(1)")
        out.push("    Array([String(\{key}), v]) => \{r}")
      }
    }
  }
  match open_case {
    Some(c) => {
      let value = cases.iter().find_first(x => x.mbt_name == c).unwrap()
      out.push(
        "    String(_) => \{type_name}::\{c}(\{self.read_expr(value.payload.unwrap(), "x", "path")})",
      )
    }
    None => ()
  }
  out.push("    _ => \{rt}.bad_json(\{type_lit}, x, path)")
  out.push("  }")
  out.push("}")
  out.push("")
}

///|
fn Env::gen_alias(
  self : Env,
  out : Array[String],
  d : @atd.TypeDef,
  e : @atd.TypeExpr,
) -> Unit raise @atd.AtdError {
  let atd_name = d.name.to_string()
  let type_name = self.type_name(atd_name)
  let target = self.type_of_expr(e)
  // `type foo = ... wrap <mbt t="Foo">` refers to an existing type `Foo`
  if target != type_name {
    out.push("///|")
    out.append(doc_comment(d.loc, d.annot))
    out.push("pub type \{type_name} = \{target}")
    out.push("")
  }
  out.push("///|")
  out.push("pub fn \{self.writer_name(atd_name)}(x : \{type_name}) -> Json {")
  out.push("  \{self.write_expr(e, "x")}")
  out.push("}")
  out.push("")
  out.push("///|")
  out.push(
    "pub fn \{self.reader_name(atd_name)}(x : Json, path : \{rt}.Path) -> \{type_name} raise \{rt}.JsonError {",
  )
  out.push("  \{self.read_expr(e, "x", "path")}")
  out.push("}")
  out.push("")
}

///|
fn Env::gen_helpers(
  self : Env,
  out : Array[String],
  d : @atd.TypeDef,
  nominal : Bool,
) -> Unit {
  let atd_name = d.name.to_string()
  let type_name = self.type_name(atd_name)
  let s = self.fun_base(atd_name)
  out.push("///|")
  out.push("/// Convert a JSON value into a value of type `\{type_name}`.")
  out.push(
    "pub fn \{s}_of_json(x : Json) -> \{type_name} raise \{rt}.JsonError {",
  )
  out.push("  \{self.reader_name(atd_name)}(x, \{rt}.Path::Root)")
  out.push("}")
  out.push("")
  out.push("///|")
  out.push("/// Parse a JSON string into a value of type `\{type_name}`.")
  out.push(
    "pub fn \{s}_of_string(s : StringView) -> \{type_name} raise \{rt}.JsonError {",
  )
  out.push("  \{self.reader_name(atd_name)}(\{rt}.parse(s), \{rt}.Path::Root)")
  out.push("}")
  out.push("")
  out.push("///|")
  out.push(
    "/// Serialize a value of type `\{type_name}` to JSON, compactly or with the",
  )
  out.push("/// given indentation.")
  out.push(
    "pub fn string_of_\{s}(x : \{type_name}, indent? : Int = 0) -> String {",
  )
  out.push("  \{rt}.stringify(\{self.writer_name(atd_name)}(x), indent~)")
  out.push("}")
  out.push("")
  if nominal {
    out.push("///|")
    out.push("pub impl ToJson for \{type_name} with to_json(self) {")
    out.push("  \{self.writer_name(atd_name)}(self)")
    out.push("}")
    out.push("")
    extend_with(out, type_name, ["ToJson"])
  }
}

///|
/// Two fields of a record, or two variants of a sum type, can't have the
/// same JSON name: one of them would be lost when writing JSON, and reading
/// would be ambiguous.
fn check_duplicate_json_names(
  names : Array[(@atd.Loc, String)],
  what : String,
) -> Unit raise @atd.AtdError {
  let seen : Map[String, @atd.Loc] = Map([])
  for x in names {
    let (loc, name) = x
    match seen.get(name) {
      Some(first) =>
        @atd.error_at(
          loc,
          "Duplicate JSON \{what} name \{mbt_string_literal(name)}, already used at \{@atd.string_of_loc(first)}",
        )
      None => seen[name] = loc
    }
  }
}
