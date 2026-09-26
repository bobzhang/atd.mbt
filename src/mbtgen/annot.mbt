// ATD annotations interpreted specifically by atdmbt: `<mbt ...>`.
// atdmbt also honors the JSON-related annotations `<json ...>`.

///|
/// All the valid `<mbt ...>` annotations.
pub let mbt_annot_schema_section : @atd.SchemaSection = {
  section: "mbt",
  fields: [
    // package alias for an imported ATD module
    (Import, "name"),
    // MoonBit name of an imported type
    (ImportedType, "name"),
    // traits to derive for records and sum types, e.g. "Eq, Debug"
    (TypeDef, "derive"),
    // alternative representations: "map" for lists, "int64" for int
    (TypeExpr, "repr"),
    // MoonBit type for a `wrap` construct and conversion functions
    (TypeExpr, "t"),
    (TypeExpr, "wrap"),
    (TypeExpr, "unwrap"),
    // default value of an optional field `~foo`, as a MoonBit expression
    (Field, "default"),
    // MoonBit field name
    (Field, "name"),
    // MoonBit constructor name
    (Variant, "name"),
  ],
}

///|
/// The annotation schema of atdmbt: `<mbt ...>`, `<json ...>` and
/// `<doc ...>` annotations.
pub let annot_schema : @atd.Schema = [
  mbt_annot_schema_section, ..@atd.json_annot_schema, ..@atd.doc_annot_schema,
]

///|
fn get_mbt_string(
  an : @atd.Annot,
  field : String,
) -> String? raise @atd.AtdError {
  @atd.annot_get_string(an, sections=["mbt"], field~)
}

///|
priv enum ListRepr {
  ReprArray
  ReprMap
}

///|
fn get_list_repr(an : @atd.Annot) -> ListRepr raise @atd.AtdError {
  @atd.annot_get_field(
    an,
    parse=s => {
      match s {
        "array" => Some(ReprArray)
        "map" => Some(ReprMap)
        _ => None
      }
    },
    default=ReprArray,
    sections=["mbt"],
    field="repr",
  )
}

///|
fn get_int64_repr(an : @atd.Annot) -> Bool raise @atd.AtdError {
  @atd.annot_get_field(
    an,
    parse=s => {
      match s {
        "int" => Some(false)
        "int64" => Some(true)
        _ => None
      }
    },
    default=false,
    sections=["mbt"],
    field="repr",
  )
}
