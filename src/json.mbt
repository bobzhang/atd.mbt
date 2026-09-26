// Mapping from ATD to JSON: interpretation of `<json ...>` annotations.

///|
/// JSON representation of an ATD `int`.
pub(all) enum JsonInt {
  Int
  String
} derive(Eq, Debug)

///|
/// JSON representation of an ATD `float`.
pub(all) enum JsonFloat {
  /// Number with an optional maximum number of decimal places
  Float(Int?)
  Int
} derive(Eq, Debug)

///|
/// OCaml-specific JSON adapter.
pub(all) struct OcamlAdapter {
  normalize : String
  restore : String
} derive(Eq, Debug)

///|
/// JSON adapters for various target languages.
pub(all) struct JsonAdapter {
  ocaml_adapter : OcamlAdapter?
  java_adapter : String?
} derive(Eq, Debug)

///|
/// JSON representation of lists: JSON arrays, or JSON objects for lists of
/// pairs whose first element is a string.
pub(all) enum JsonList {
  Array
  Object
} derive(Eq, Debug)

///|
/// Representation of the variants of a sum type with a payload:
/// `["Cons", payload]` (Array, default) or `{"Cons": payload}` (Object).
pub(all) enum JsonSumRepr {
  Array
  Object
} derive(Eq, Debug)

///|
/// Record options.
pub(all) struct JsonRecord {
  json_keep_nulls : Bool
  json_record_adapter : JsonAdapter
} derive(Eq, Debug)

///|
/// Sum type options.
pub(all) struct JsonSum {
  json_sum_adapter : JsonAdapter
  json_open_enum : Bool
  json_lowercase_tags : Bool
  json_sum_repr : JsonSumRepr
} derive(Eq, Debug)

///|
/// All the valid annotations of the form `<json ...>`.
pub let json_annot_schema : Schema = [
  {
    section: "json",
    fields: [
      (TypeExpr, "adapter.ocaml"),
      (TypeExpr, "adapter.to_ocaml"),
      (TypeExpr, "adapter.from_ocaml"),
      (TypeExpr, "keep_nulls"),
      (TypeExpr, "open_enum"),
      (TypeExpr, "precision"),
      (TypeExpr, "repr"),
      (Variant, "name"),
      (Field, "name"),
      (Field, "tag_field"),
    ],
  },
  {
    section: "ocaml_json",
    fields: [
      (TypeDef, "from"),
      (TypeDef, "module"),
      (TypeDef, "predef"),
      (TypeDef, "t"),
    ],
  },
]

///|
/// Representation of an `int`: `<json repr="int|string">`.
pub fn get_json_int(an : Annot) -> JsonInt raise AtdError {
  annot_get_field(
    an,
    parse=s => {
      match s {
        "int" => Some(JsonInt::Int)
        "string" => Some(JsonInt::String)
        _ => None
      }
    },
    default=JsonInt::Int,
    sections=["json"],
    field="repr",
  )
}

///|
/// `<json precision="N">`
pub fn get_json_precision(an : Annot) -> Int? raise AtdError {
  annot_get_opt_field(
    an,
    parse=s => {
      try @string.parse_int(s) catch {
        _ => None
      } noraise {
        n => Some(n)
      }
    },
    sections=["json"],
    field="precision",
  )
}

///|
/// Representation of a `float`: `<json repr="float|int">`.
pub fn get_json_float(an : Annot) -> JsonFloat raise AtdError {
  let is_float = annot_get_field(
    an,
    parse=s => {
      match s {
        "float" => Some(true)
        "int" => Some(false)
        _ => None
      }
    },
    default=true,
    sections=["json"],
    field="repr",
  )
  if is_float {
    Float(get_json_precision(an))
  } else {
    Int
  }
}

///|
/// Representation of a list: `<json repr="array|object">`.
pub fn get_json_list(an : Annot) -> JsonList raise AtdError {
  annot_get_field(
    an,
    parse=s => {
      match s {
        "array" => Some(JsonList::Array)
        "object" => Some(JsonList::Object)
        _ => None
      }
    },
    default=JsonList::Array,
    sections=["json"],
    field="repr",
  )
}

///|
/// JSON adapters: `<json adapter.ocaml="...">` etc.
pub fn get_json_adapter(an : Annot) -> JsonAdapter raise AtdError {
  let get_field = field => annot_get_string(an, sections=["json"], field~)
  let get_loc = field => {
    match annot_get_loc(an, sections=["json"], field~) {
      Some(loc) => loc
      None => dummy_loc
    }
  }
  let field_module = "adapter.ocaml"
  let field_normalize = "adapter.to_ocaml"
  let field_restore = "adapter.from_ocaml"
  let ocaml_adapter = match
    (
      get_field(field_module),
      get_field(field_normalize),
      get_field(field_restore),
    ) {
    (None, None, None) => None
    (Some(m), None, None) =>
      Some({ normalize: m + ".normalize", restore: m + ".restore", })
    (None, Some(normalize), Some(restore)) =>
      Some({ normalize: "(" + normalize + ")", restore: "(" + restore + ")", })
    (Some(_), _, _) =>
      error_at(
        get_loc(field_module),
        "Cannot use \{ocaml_quote(field_module)} field together with \{ocaml_quote(field_normalize)} or \{ocaml_quote(field_restore)}",
      )
    (None, Some(_), None) =>
      error_at(
        get_loc(field_normalize),
        "\{ocaml_quote(field_normalize)} is used without required counterpart \{ocaml_quote(field_restore)}",
      )
    (None, None, Some(_)) =>
      error_at(
        get_loc(field_restore),
        "\{ocaml_quote(field_restore)} is used without required counterpart \{ocaml_quote(field_normalize)}",
      )
  }
  let java_adapter = get_field("adapter.java")
  { ocaml_adapter, java_adapter, }
}

///|
/// `<json open_enum>`
pub fn get_json_open_enum(an : Annot) -> Bool raise AtdError {
  annot_get_flag(an, sections=["json"], field="open_enum")
}

///|
/// `<json lowercase_tags>`
pub fn get_json_lowercase_tags(an : Annot) -> Bool raise AtdError {
  annot_get_flag(an, sections=["json"], field="lowercase_tags")
}

///|
/// Representation of sum types: `<json repr="object">`.
pub fn get_json_sum_repr(an : Annot) -> JsonSumRepr raise AtdError {
  annot_get_field(
    an,
    parse=s => {
      match s {
        "object" => Some(JsonSumRepr::Object)
        _ => None
      }
    },
    default=JsonSumRepr::Array,
    sections=["json"],
    field="repr",
  )
}

///|
/// All the options of a sum type.
pub fn get_json_sum(an : Annot) -> JsonSum raise AtdError {
  {
    json_sum_adapter: get_json_adapter(an),
    json_open_enum: get_json_open_enum(an),
    json_lowercase_tags: get_json_lowercase_tags(an),
    json_sum_repr: get_json_sum_repr(an),
  }
}

///|
/// JSON name of a variant: `<json name="...">`.
pub fn get_json_cons(default : String, an : Annot) -> String raise AtdError {
  annot_get_field(
    an,
    parse=s => Some(s),
    default~,
    sections=["json"],
    field="name",
  )
}

///|
/// JSON name of a field: `<json name="...">`.
pub fn get_json_fname(default : String, an : Annot) -> String raise AtdError {
  annot_get_field(
    an,
    parse=s => Some(s),
    default~,
    sections=["json"],
    field="name",
  )
}

///|
/// `<json keep_nulls>`
pub fn get_json_keep_nulls(an : Annot) -> Bool raise AtdError {
  annot_get_flag(an, sections=["json"], field="keep_nulls")
}

///|
/// All the options of a record type.
pub fn get_json_record(an : Annot) -> JsonRecord raise AtdError {
  {
    json_keep_nulls: get_json_keep_nulls(an),
    json_record_adapter: get_json_adapter(an),
  }
}
