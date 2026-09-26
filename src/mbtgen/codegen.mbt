// MoonBit code generation for JSON support, the MoonBit counterpart of
// atdts and atdpy.
//
// For each ATD type `foo`, the generated code defines:
//
// - a MoonBit type `Foo`: a struct for records, an enum for sum types,
//   and a type alias otherwise;
// - `write_foo(x : Foo) -> Json` and
//   `read_foo(x : Json, path : @atd_runtime.Path) -> Foo raise ...`,
//   the composable JSON writer and reader;
// - `foo_of_json`, `foo_of_string` and `string_of_foo` for convenience;
// - an implementation of `ToJson` for structs and enums;
// - `Foo::new(...)` for records, with labelled arguments and defaults.
//
// The generated code depends on the package `bobzhang/atd/runtime`,
// imported with the alias `@atd_runtime`.

///|
let rt : String = "@atd_runtime"

///|
/// Where a type definition's name comes from and what it maps to.
priv struct Env {
  /// ATD type name -> MoonBit type name
  type_names : @atd.UniqueNames
  imports : @atd.Imports
  /// Local definitions, for resolving aliases (default values, recursion)
  defs : Map[String, @atd.TypeDef]
  /// Parametrized abstract types, which translate to `Json`
  abstract_poly : Array[String]
}

///|
fn[T] not_implemented(loc : @atd.Loc, msg : String) -> T raise @atd.AtdError {
  @atd.error_at(loc, "not implemented in atdmbt: " + msg)
}

///|
fn Env::type_name(self : Env, atd_name : String) -> String {
  self.type_names.translate(
    atd_name,
    preferred_translation=to_camel_case(sanitize(atd_name)),
  )
}

///|
fn fun_suffix(atd_name : String) -> String {
  sanitize(atd_name)
}

///|
fn reader_name(atd_name : String) -> String {
  "read_" + fun_suffix(atd_name)
}

///|
fn writer_name(atd_name : String) -> String {
  "write_" + fun_suffix(atd_name)
}

///|
/// Package alias of an imported ATD module: `<mbt name="...">` or its local
/// name.
fn package_alias(x : @atd.Import) -> String raise @atd.AtdError {
  match get_mbt_string(x.annot, "name") {
    Some(name) => name
    None => sanitize(x.name)
  }
}

///|
/// Resolve a type name: `Some((package_alias, base_name))` for imported
/// types, `None` for local ones.
fn Env::resolve(
  self : Env,
  loc : @atd.Loc,
  name : @atd.TypeName,
) -> (String?, String) raise @atd.AtdError {
  match @atd.resolve_import(self.imports, loc, name) {
    (None, base_name) => (None, base_name)
    (Some((import_, _)), base_name) => (Some(package_alias(import_)), base_name)
  }
}

///|
/// Representations of ATD type `(k * v) list`, depending on the JSON and
/// MoonBit annotations.
priv enum AssocKind {
  /// default representation; possibly not even a list of pairs
  ArrayArray
  /// JSON array of pairs, MoonBit map
  ArrayMap(@atd.TypeExpr, @atd.TypeExpr)
  /// JSON object, MoonBit map with string keys
  ObjectMap(@atd.TypeExpr)
  /// JSON object, MoonBit array of pairs
  ObjectArray(@atd.TypeExpr)
}

///|
fn is_string_type(e : @atd.TypeExpr) -> Bool {
  e is Name(_, { name: { path: ["string"], }, args: [], .. }, _)
}

///|
fn assoc_kind(
  loc : @atd.Loc,
  e : @atd.TypeExpr,
  an : @atd.Annot,
) -> AssocKind raise @atd.AtdError {
  let json_repr = @atd.get_json_list(an)
  let mbt_repr = get_list_repr(an)
  match (e, json_repr, mbt_repr) {
    (Tuple(_, [{ expr: key, .. }, { expr: value, .. }], _), Array, ReprMap) =>
      ArrayMap(key, value)
    (Tuple(_, [{ expr: key, .. }, { expr: value, .. }], _), Object, ReprMap) if is_string_type(
        key,
      ) => ObjectMap(value)
    (Tuple(_, [{ expr: key, .. }, { expr: value, .. }], _), Object, ReprArray) if is_string_type(
        key,
      ) => ObjectArray(value)
    (_, Array, ReprArray) => ArrayArray
    (_, Object, _) => @atd.error_at(loc, "not a (string * _) list")
    (_, Array, ReprMap) => @atd.error_at(loc, "not a (_ * _) list")
  }
}

///|
/// Remove the outer `wrap` constructs that have no `<mbt ...>` annotation.
fn unwrap(e : @atd.TypeExpr) -> @atd.TypeExpr {
  match e {
    Wrap(_, e, an) if is_transparent_wrap(an) => unwrap(e)
    e => e
  }
}

///|
/// The MoonBit type of a type expression.
fn Env::type_of_expr(
  self : Env,
  e : @atd.TypeExpr,
) -> String raise @atd.AtdError {
  match e {
    Sum(loc, _, _) => not_implemented(loc, "inline sum types")
    Record(loc, _, _) => not_implemented(loc, "inline records")
    Tuple(_, cells, _) =>
      match cells {
        [] => "Unit"
        [c] => self.type_of_expr(c.expr)
        _ => {
          let l = []
          for c in cells {
            l.push(self.type_of_expr(c.expr))
          }
          "(" + l.join(", ") + ")"
        }
      }
    List(loc, e, an) =>
      match assoc_kind(loc, e, an) {
        ArrayArray => "Array[\{self.type_of_expr(e)}]"
        ObjectArray(value) => "Array[(String, \{self.type_of_expr(value)})]"
        ArrayMap(key, value) =>
          "Map[\{self.type_of_expr(key)}, \{self.type_of_expr(value)}]"
        ObjectMap(value) => "Map[String, \{self.type_of_expr(value)}]"
      }
    Option(_, e, _) | Nullable(_, e, _) => self.type_of_expr(e) + "?"
    Shared(loc, _, _) => not_implemented(loc, "shared")
    Wrap(_, e, an) =>
      match get_mbt_string(an, "t") {
        Some(t) => t
        None => self.type_of_expr(e)
      }
    Name(loc, { name, args, .. }, an) =>
      match self.resolve(loc, name) {
        (Some(alias_), base_name) => {
          if !args.is_empty() {
            not_implemented(loc, "parametrized imported types")
          }
          "@\{alias_}.\{to_camel_case(sanitize(base_name))}"
        }
        (None, base_name) => {
          if self.abstract_poly.contains(base_name) {
            return "Json"
          }
          if !args.is_empty() {
            not_implemented(loc, "parametrized types")
          }
          match base_name {
            "unit" => "Unit"
            "bool" => "Bool"
            "int" => if get_int64_repr(an) { "Int64" } else { "Int" }
            "float" => "Double"
            "string" => "String"
            "abstract" => "Json"
            _ => self.type_name(base_name)
          }
        }
      }
    Tvar(loc, _) => not_implemented(loc, "type variables")
  }
}

///|
/// Apply a function expression to arguments, parenthesizing it if needed.
fn apply(f : String, args : String) -> String {
  let simple = f
    .iter()
    .all(c => {
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '.' ||
      c == '@' ||
      c == ':'
    })
  if simple {
    f + "(" + args + ")"
  } else {
    "(" + f + ")(" + args + ")"
  }
}

///|
/// An expression of type `(Json, @atd_runtime.Path) -> T raise
/// @atd_runtime.JsonError` reading a value of the given type.
fn Env::reader(self : Env, e : @atd.TypeExpr) -> String raise @atd.AtdError {
  match e {
    Sum(loc, _, _) => not_implemented(loc, "inline sum types")
    Record(loc, _, _) => not_implemented(loc, "inline records")
    Tuple(_, cells, _) => self.tuple_reader(cells)
    List(loc, e, an) =>
      match assoc_kind(loc, e, an) {
        ArrayArray => "\{rt}.read_list(\{self.reader(e)})"
        ObjectArray(value) =>
          "\{rt}.read_assoc_object_into_array(\{self.reader(value)})"
        ArrayMap(key, value) =>
          "\{rt}.read_assoc_array_into_map(\{self.reader(key)}, \{self.reader(value)})"
        ObjectMap(value) =>
          "\{rt}.read_assoc_object_into_map(\{self.reader(value)})"
      }
    Option(_, e, _) => "\{rt}.read_option(\{self.reader(e)})"
    Nullable(_, e, _) => "\{rt}.read_nullable(\{self.reader(e)})"
    Shared(loc, _, _) => not_implemented(loc, "shared")
    Wrap(_, e, an) =>
      match get_mbt_string(an, "t") {
        None => self.reader(e)
        Some(_) => {
          let wrap = match get_mbt_string(an, "wrap") {
            Some(f) => f
            None =>
              @atd.error_at(
                e.loc(),
                "missing annotation <mbt wrap=\"...\"> for a wrap type with <mbt t=\"...\">",
              )
          }
          "(x, path) => \{apply(wrap, apply(self.reader(e), "x, path"))}"
        }
      }
    Name(loc, { name, .. }, an) =>
      match self.resolve(loc, name) {
        (Some(alias_), base_name) => "@\{alias_}.\{reader_name(base_name)}"
        (None, base_name) => {
          if self.abstract_poly.contains(base_name) {
            return "\{rt}.read_json"
          }
          match base_name {
            "unit" => "\{rt}.read_unit"
            "bool" => "\{rt}.read_bool"
            "int" => {
              let int64 = get_int64_repr(an)
              match @atd.get_json_int(an) {
                Int => if int64 { "\{rt}.read_int64" } else { "\{rt}.read_int" }
                String =>
                  if int64 {
                    "\{rt}.read_int64_of_string"
                  } else {
                    "\{rt}.read_int_of_string"
                  }
              }
            }
            "float" => "\{rt}.read_float"
            "string" => "\{rt}.read_string"
            "abstract" => "\{rt}.read_json"
            _ => reader_name(base_name)
          }
        }
      }
    Tvar(loc, _) => not_implemented(loc, "type variables")
  }
}

///|
fn Env::tuple_reader(
  self : Env,
  cells : Array[@atd.Cell],
) -> String raise @atd.AtdError {
  let n = cells.length()
  let items = []
  for i, c in cells {
    items.push(apply(self.reader(c.expr), "a[\{i}], path.index(\{i})"))
  }
  let value = match items {
    [] => "()"
    [x] => x
    _ => "(" + items.join(", ") + ")"
  }
  if n == 0 {
    "(x, path) => ignore(\{rt}.read_tuple(x, path, 0))"
  } else {
    "(x, path) => { let a = \{rt}.read_tuple(x, path, \{n}); \{value} }"
  }
}

///|
/// An expression of type `(T) -> Json` writing a value of the given type.
fn Env::writer(self : Env, e : @atd.TypeExpr) -> String raise @atd.AtdError {
  match e {
    Sum(loc, _, _) => not_implemented(loc, "inline sum types")
    Record(loc, _, _) => not_implemented(loc, "inline records")
    Tuple(_, cells, _) as e =>
      match cells {
        [] => "(_ : Unit) => Json::array([])"
        [c] => "x => Json::array([\{apply(self.writer(c.expr), "x")}])"
        _ => {
          let items = []
          for i, c in cells {
            items.push(apply(self.writer(c.expr), "x.\{i}"))
          }
          "(x : \{self.type_of_expr(e)}) => Json::array([\{items.join(", ")}])"
        }
      }
    List(loc, e, an) =>
      match assoc_kind(loc, e, an) {
        ArrayArray => "\{rt}.write_list(\{self.writer(e)})"
        ObjectArray(value) =>
          "\{rt}.write_assoc_array_to_object(\{self.writer(value)})"
        ArrayMap(key, value) =>
          "\{rt}.write_assoc_map_to_array(\{self.writer(key)}, \{self.writer(value)})"
        ObjectMap(value) =>
          "\{rt}.write_assoc_map_to_object(\{self.writer(value)})"
      }
    Option(_, e, _) => "\{rt}.write_option(\{self.writer(e)})"
    Nullable(_, e, _) => "\{rt}.write_nullable(\{self.writer(e)})"
    Shared(loc, _, _) => not_implemented(loc, "shared")
    Wrap(_, e, an) =>
      match get_mbt_string(an, "t") {
        None => self.writer(e)
        Some(_) => {
          let unwrap = match get_mbt_string(an, "unwrap") {
            Some(f) => f
            None =>
              @atd.error_at(
                e.loc(),
                "missing annotation <mbt unwrap=\"...\"> for a wrap type with <mbt t=\"...\">",
              )
          }
          "x => \{apply(self.writer(e), apply(unwrap, "x"))}"
        }
      }
    Name(loc, { name, .. }, an) =>
      match self.resolve(loc, name) {
        (Some(alias_), base_name) => "@\{alias_}.\{writer_name(base_name)}"
        (None, base_name) => {
          if self.abstract_poly.contains(base_name) {
            return "\{rt}.write_json"
          }
          match base_name {
            "unit" => "\{rt}.write_unit"
            "bool" => "\{rt}.write_bool"
            "int" => {
              let int64 = get_int64_repr(an)
              match @atd.get_json_int(an) {
                Int =>
                  if int64 {
                    "\{rt}.write_int64"
                  } else {
                    "\{rt}.write_int"
                  }
                String =>
                  if int64 {
                    "\{rt}.write_int64_to_string"
                  } else {
                    "\{rt}.write_int_to_string"
                  }
              }
            }
            "float" =>
              match @atd.get_json_float(an) {
                Int => "\{rt}.write_float_as_int"
                Float(None) => "\{rt}.write_float"
                Float(Some(n)) => "\{rt}.write_float_prec(\{n})"
              }
            "string" => "\{rt}.write_string"
            "abstract" => "\{rt}.write_json"
            _ => writer_name(base_name)
          }
        }
      }
    Tvar(loc, _) => not_implemented(loc, "type variables")
  }
}

///|
/// An expression writing `arg`, a simple expression (evaluated several
/// times for tuples), as JSON.
fn Env::write_expr(
  self : Env,
  e : @atd.TypeExpr,
  arg : String,
) -> String raise @atd.AtdError {
  match e {
    Tuple(_, cells, _) if cells.length() >= 2 => {
      let items = []
      for i, c in cells {
        items.push(self.write_expr(c.expr, "\{arg}.\{i}"))
      }
      "Json::array([\{items.join(", ")}])"
    }
    Wrap(_, e, an) if is_transparent_wrap(an) => self.write_expr(e, arg)
    _ => apply(self.writer(e), arg)
  }
}

///|
/// Write the components of a tuple given as separate variables.
fn Env::write_tuple_vars(
  self : Env,
  cells : Array[@atd.Cell],
  vars : Array[String],
) -> String raise @atd.AtdError {
  let items = []
  for i, c in cells {
    items.push(self.write_expr(c.expr, vars[i]))
  }
  "Json::array([\{items.join(", ")}])"
}

///|
/// An expression reading the JSON value `x`, a variable, found at path
/// `path`, a simple expression.
fn Env::read_expr(
  self : Env,
  e : @atd.TypeExpr,
  x : String,
  path : String,
) -> String raise @atd.AtdError {
  match e {
    Wrap(_, e, an) if is_transparent_wrap(an) => self.read_expr(e, x, path)
    _ => apply(self.reader(e), "\{x}, \{path}")
  }
}

///|
/// The implicit default value of a type, if any.
fn Env::default_value(
  self : Env,
  e : @atd.TypeExpr,
  visited : Array[String],
) -> String? raise @atd.AtdError {
  match e {
    Sum(_) | Record(_) | Tuple(_) | Tvar(_) | Shared(_) => None
    List(loc, e, an) =>
      match assoc_kind(loc, e, an) {
        ArrayArray | ObjectArray(_) => Some("[]")
        ArrayMap(_) | ObjectMap(_) => Some("Map([])")
      }
    Option(_) | Nullable(_) => Some("None")
    Wrap(_, e, an) =>
      if get_mbt_string(an, "t") is Some(_) {
        None
      } else {
        self.default_value(e, visited)
      }
    Name(loc, { name, args: [], .. }, an) =>
      match self.resolve(loc, name) {
        (Some(_), _) => None
        (None, base_name) =>
          match base_name {
            "unit" => Some("()")
            "bool" => Some("false")
            "int" => if get_int64_repr(an) { Some("0L") } else { Some("0") }
            "float" => Some("0.0")
            "string" => Some("\"\"")
            "abstract" => Some("Json::null()")
            _ =>
              // follow type aliases
              match self.defs.get(base_name) {
                Some(d) if !visited.contains(base_name) =>
                  match unwrap(d.value) {
                    Sum(_) | Record(_) => None
                    v => self.default_value(v, [..visited, base_name])
                  }
                _ => None
              }
          }
      }
    Name(_) => None
  }
}

///|
/// If the field is `?foo: bar option`, its MoonBit type is `Bar?` and its
/// JSON value has type `bar` rather than `bar option`.
fn unwrap_field_type(
  loc : @atd.Loc,
  field_name : String,
  kind : @atd.FieldKind,
  e : @atd.TypeExpr,
) -> @atd.TypeExpr raise @atd.AtdError {
  match kind {
    Required | WithDefault => e
    Optional =>
      match e {
        Option(_, e, _) => e
        _ =>
          @atd.error_at(
            loc,
            "the type of optional field '\{field_name}' should be of the form 'xxx option'",
          )
      }
  }
}
