// Translation of ATD to JSON Schema, a port of `jsonschema.ml`.
//
// The translation is done in two passes:
// 1. Translation to an AST that models the constructs of JSON Schema.
// 2. Translation of that AST to JSON.

///|
/// Supported versions of the JSON Schema standard.
pub(all) enum JsonschemaVersion {
  Draft_2019_09
  Draft_2020_12
} derive(Eq, Debug)

///|
/// The latest supported version.
pub let default_jsonschema_version : JsonschemaVersion = Draft_2020_12

///|
priv enum JsType {
  Ref(String)
  Null
  Boolean
  Integer
  Number
  JString
  JArray(JsType)
  JTuple(Array[JsType])
  Object(JsObject)
  JMap(JsType)
  Union(Array[JsType])
  JNullable(JsType)
  Const(@yojson.Value, Array[(String, @yojson.Value)])
  JAny
}

///|
priv struct JsObject {
  properties : Array[(String, JsType, Array[(String, @yojson.Value)])]
  required : Array[String]
  xprop : Bool
}

///|
priv struct JsDef {
  name : String
  description : String?
  type_expr : JsType
}

///|
fn make_id(type_name : TypeName) -> String {
  "#/definitions/" + type_name.to_string()
}

///|
fn trans_description_simple(loc : Loc, an : Annot) -> String? raise AtdError {
  match get_doc(loc, an) {
    None => None
    Some(blocks) => Some(print_doc_text(blocks))
  }
}

///|
fn trans_description(
  loc : Loc,
  an : Annot,
) -> Array[(String, @yojson.Value)] raise AtdError {
  match trans_description_simple(loc, an) {
    None => []
    Some(doc) => [("description", @yojson.Value::String(doc))]
  }
}

///|
fn trans_type_expr(xprop : Bool, x : TypeExpr) -> JsType raise AtdError {
  match x {
    Sum(_, vl, _) => {
      let cases = []
      for v in vl {
        match v {
          Variant(loc, name, an, opt_e) => {
            let json_name = get_json_cons(name, an)
            let descr = trans_description(loc, an)
            match opt_e {
              None => cases.push(Const(@yojson.Value::String(json_name), descr))
              Some(e) =>
                cases.push(
                  JTuple([
                    Const(@yojson.Value::String(json_name), descr),
                    trans_type_expr(xprop, e),
                  ]),
                )
            }
          }
          Inherit(_) => abort("assertion failed")
        }
      }
      Union(cases)
    }
    Record(_, fl, _) => {
      let properties = []
      let required = []
      for f in fl {
        match f {
          Field({ loc, name, kind, annot: an, expr: e, }) => {
            let json_name = get_json_fname(name, an)
            match kind {
              Required => required.push(json_name)
              Optional | WithDefault => ()
            }
            let unwrapped_e = match (kind, e) {
              (Optional, Option(_, e, _)) => e
              (_, e) => e
            }
            let descr = trans_description(loc, an)
            properties.push(
              (json_name, trans_type_expr(xprop, unwrapped_e), descr),
            )
          }
          Inherit(_) => abort("assertion failed")
        }
      }
      Object({ properties, required, xprop, })
    }
    Tuple(_, tl, _) => {
      let l = []
      for c in tl {
        l.push(trans_type_expr(xprop, c.expr))
      }
      JTuple(l)
    }
    List(loc, e, an) => {
      let json_repr = get_json_list(an)
      match (e, json_repr) {
        (_, Array) => JArray(trans_type_expr(xprop, e))
        (
          Tuple(
            _,
            [
              { expr: Name(_, { name: { path: ["string"], }, .. }, _), .. },
              { expr: value, .. },
            ],
            _
          ),
          Object,
        ) => JMap(trans_type_expr(xprop, value))
        (_, Object) =>
          error_at(
            loc, "This type expression is not of the form (string * _) list. It can't be represented as a JSON object.",
          )
      }
    }
    Option(loc, e, an) => {
      let transpiled = Sum(
        loc,
        [Variant(loc, "Some", [], Some(e)), Variant(loc, "None", [], None)],
        an,
      )
      trans_type_expr(xprop, transpiled)
    }
    Nullable(_, e, _) => JNullable(trans_type_expr(xprop, e))
    Shared(loc, _, _) => error_at(loc, "unsupported: shared")
    Wrap(_, e, _) => trans_type_expr(xprop, e)
    Tvar(loc, _) => error_at(loc, "unsupported: parametrized types")
    Name(_, { name, .. }, _) =>
      match name.path {
        ["unit"] => Null
        ["bool"] => Boolean
        ["int"] => Integer
        ["float"] => Number
        ["string"] => JString
        ["abstract"] => JAny
        _ => Ref(make_id(name))
      }
  }
}

///|
fn trans_def(xprop : Bool, x : TypeDef) -> JsDef raise AtdError {
  if !x.param.is_empty() {
    error_at(x.loc, "unsupported: parametrized types")
  }
  let description = trans_description_simple(x.loc, x.annot)
  {
    name: x.name.to_string(),
    description,
    type_expr: trans_type_expr(xprop, x.value),
  }
}

///|
fn make_type_property(
  is_nullable : Bool,
  name : String,
) -> (String, @yojson.Value) {
  if is_nullable {
    (
      "type",
      @yojson.Value::List([
        @yojson.Value::String(name),
        @yojson.Value::String("null"),
      ]),
    )
  } else {
    ("type", @yojson.Value::String(name))
  }
}

///|
fn assoc(l : Array[(String, @yojson.Value)]) -> @yojson.Value {
  Assoc(l)
}

///|
fn type_expr_to_assoc(
  x : JsType,
  version : JsonschemaVersion,
  is_nullable? : Bool = false,
) -> Array[(String, @yojson.Value)] {
  match x {
    Ref(s) => [("$ref", @yojson.Value::String(s))]
    Null => [make_type_property(false, "null")]
    Boolean => [make_type_property(is_nullable, "boolean")]
    Integer => [make_type_property(is_nullable, "integer")]
    Number => [make_type_property(is_nullable, "number")]
    JString => [make_type_property(is_nullable, "string")]
    JAny => []
    JArray(x) =>
      [
        make_type_property(is_nullable, "array"),
        ("items", type_expr_to_json(x, version)),
      ]
    JTuple(xs) => {
      let res = [
        make_type_property(is_nullable, "array"),
        ("minItems", @yojson.Value::Int(xs.length().to_int64())),
      ]
      let items = @yojson.Value::List(
        xs.map(x => type_expr_to_json(x, version)),
      )
      match version {
        Draft_2020_12 => {
          res.push(("items", @yojson.Value::Bool(false)))
          res.push(("prefixItems", items))
        }
        Draft_2019_09 => {
          res.push(("additionalItems", @yojson.Value::Bool(false)))
          res.push(("items", items))
        }
      }
      res
    }
    Object(x) => {
      let properties = x.properties.map(p => {
        (p.0, type_expr_to_json(p.1, version, descr=p.2))
      })
      let res = [
        make_type_property(is_nullable, "object"),
        (
          "required",
          @yojson.Value::List(x.required.map(s => @yojson.Value::String(s))),
        ),
      ]
      if !x.xprop {
        res.push(("additionalProperties", @yojson.Value::Bool(false)))
      }
      res.push(("properties", assoc(properties)))
      res
    }
    JMap(x) =>
      [
        make_type_property(is_nullable, "object"),
        ("additionalProperties", type_expr_to_json(x, version)),
      ]
    Union(xs) =>
      [
        (
          "oneOf",
          @yojson.Value::List(
            xs.map(x => type_expr_to_json(x, version, is_nullable~)),
          ),
        ),
      ]
    JNullable(x) => type_expr_to_assoc(x, version, is_nullable=true)
    Const(json, descr) => {
      let res = descr.copy()
      res.push(("const", json))
      res
    }
  }
}

///|
fn type_expr_to_json(
  x : JsType,
  version : JsonschemaVersion,
  is_nullable? : Bool = false,
  descr? : Array[(String, @yojson.Value)] = [],
) -> @yojson.Value {
  let l = descr.copy()
  l.append(type_expr_to_assoc(x, version, is_nullable~))
  assoc(l)
}

///|
fn def_to_assoc(
  x : JsDef,
  version : JsonschemaVersion,
) -> Array[(String, @yojson.Value)] {
  let l = match x.description {
    None => []
    Some(d) => [("description", @yojson.Value::String(d))]
  }
  l.append(type_expr_to_assoc(x.type_expr, version))
  l
}

///|
/// All the annotations understood by the JSON Schema translator.
pub let jsonschema_annot_schema : Schema = [
  ..json_annot_schema, ..doc_annot_schema,
]

///|
/// Translate an ATD module to JSON Schema.
///
/// - `src_name`: name of the source, mentioned in the description.
/// - `root_type`: name of the type that describes the root JSON value.
/// - `xprop`: whether to allow extra properties in JSON objects.
///
/// `inherit` statements are expanded if needed. The result is a Yojson-like
/// value, whose objects preserve the order and duplicates of their keys;
/// convert it with `@yojson.Value::to_json` if needed.
pub fn jsonschema_of_module(
  module_ : Module,
  src_name~ : String,
  root_type~ : String,
  version? : JsonschemaVersion = default_jsonschema_version,
  xprop? : Bool = true,
) -> @yojson.Value raise AtdError {
  let defs = []
  for d in expand_inherit(module_.type_defs) {
    defs.push(trans_def(xprop, d))
  }
  let root_defs = defs.filter(x => x.name == root_type)
  let defs = defs.filter(x => x.name != root_type)
  let root_def = match root_defs {
    [x] => x
    [] =>
      error("Cannot find definition for the requested root type '\{root_type}'")
    _ => error("Found multiple definitions for type '\{root_type}'")
  }
  let (loc, an) = module_.head
  let description = [
      Some("Translated by atdcat from \{src_name}."),
      trans_description_simple(loc, an),
      root_def.description,
    ]
    .filter_map(x => x)
    .join("\n\n")
  let root_def = { ..root_def, description: Some(description), }
  let version_url = match version {
    Draft_2019_09 => "https://json-schema.org/draft/2019-09/schema"
    Draft_2020_12 => "https://json-schema.org/draft/2020-12/schema"
  }
  let fields = [
    ("$schema", @yojson.Value::String(version_url)),
    ("title", @yojson.Value::String(root_def.name)),
  ]
  fields.append(def_to_assoc(root_def, version))
  fields.push(
    (
      "definitions",
      assoc(defs.map(x => (x.name, assoc(def_to_assoc(x, version))))),
    ),
  )
  assoc(fields)
}

///|
/// Translate an ATD module to JSON Schema, pretty-printed like `atdcat`.
pub fn print_jsonschema(
  module_ : Module,
  src_name~ : String,
  root_type~ : String,
  version? : JsonschemaVersion = default_jsonschema_version,
  xprop? : Bool = true,
) -> String raise AtdError {
  let json = jsonschema_of_module(
    module_,
    src_name~,
    root_type~,
    version~,
    xprop~,
  )
  @yojson.pretty_to_string(json) + "\n"
}
