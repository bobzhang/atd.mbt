// Utilities for interpreting annotations of type `Annot`.

///|
/// Return all the fields named `field` found in the sections named
/// `section`, in order.
pub fn annot_fields(
  l : Annot,
  section~ : String,
  field~ : String,
) -> Array[(Loc, String?)] {
  let res = []
  for sec in l {
    if sec.name == section {
      for f in sec.fields {
        if f.name == field {
          res.push((f.loc, f.value))
        }
      }
    }
  }
  res
}

///|
/// Return the field `section.field` if it exists, failing if it occurs
/// more than once.
pub fn annot_field(
  l : Annot,
  section~ : String,
  field~ : String,
) -> (Loc, String?)? raise AtdError {
  match annot_fields(l, section~, field~) {
    [] => None
    [fieldmatch] => Some(fieldmatch)
    [(loc, _), .. others] => {
      let locs = others.iter().map(x => string_of_loc(x.0)).collect()
      error_at(
        loc,
        "Duplicate annotation \{section}.\{field} (also in:\n  \{locs.join(",\n  ")}\n)",
      )
    }
  }
}

///|
/// Test whether a section named `section` exists.
pub fn annot_has_section(l : Annot, section : String) -> Bool {
  l.iter().any(s => s.name == section)
}

///|
/// Test whether the field exists in one of the given sections.
pub fn annot_has_field(
  l : Annot,
  sections~ : Array[String],
  field~ : String,
) -> Bool raise AtdError {
  for section in sections {
    if annot_field(l, section~, field~) is Some(_) {
      return true
    }
  }
  false
}

///|
/// Look up a boolean flag such as `<json keep_nulls>` or
/// `<json keep_nulls="true">`. The default is `false`.
pub fn annot_get_flag(
  l : Annot,
  sections~ : Array[String],
  field~ : String,
) -> Bool raise AtdError {
  for section in sections {
    match annot_field(l, section~, field~) {
      None => continue
      Some((loc, o)) =>
        return match o {
          None | Some("true") => true
          Some("false") => false
          Some(s) =>
            error_at(
              loc,
              "Invalid value \{ocaml_quote(s)} for flag \{section}.\{field}",
            )
        }
    }
  }
  false
}

///|
/// Look up the value of a field and parse it.
pub fn[T] annot_get_field(
  l : Annot,
  parse~ : (String) -> T?,
  default~ : T,
  sections~ : Array[String],
  field~ : String,
) -> T raise AtdError {
  for section in sections {
    match annot_field(l, section~, field~) {
      None => continue
      Some((loc, Some(s))) =>
        match parse(s) {
          Some(y) => return y
          None =>
            error_at(
              loc,
              "Invalid annotation <\{section} \{field}=\{ocaml_quote(s)}>",
            )
        }
      Some((loc, None)) =>
        error_at(loc, "Missing value for annotation \{section}.\{field}")
    }
  }
  default
}

///|
/// Look up all the values of a field in the first section.
pub fn[T] annot_get_fields(
  l : Annot,
  parse~ : (String) -> T?,
  sections~ : Array[String],
  field~ : String,
) -> Array[T] raise AtdError {
  guard sections is [section, ..] else { return [] }
  let res = []
  for x in annot_fields(l, section~, field~) {
    match x {
      (loc, None) =>
        error_at(loc, "Missing value for annotation \{section}.\{field}")
      (loc, Some(s)) =>
        match parse(s) {
          None =>
            error_at(
              loc,
              "Invalid annotation <\{section} \{field}=\{ocaml_quote(s)}>",
            )
          Some(v) => res.push(v)
        }
    }
  }
  res
}

///|
/// Look up the optional value of a field and parse it.
pub fn[T] annot_get_opt_field(
  l : Annot,
  parse~ : (String) -> T?,
  sections~ : Array[String],
  field~ : String,
) -> T? raise AtdError {
  annot_get_field(
    l,
    parse=s => {
      match parse(s) {
        None => None
        Some(v) => Some(Some(v))
      }
    },
    default=None,
    sections~,
    field~,
  )
}

///|
/// Look up a string-valued field.
pub fn annot_get_string(
  l : Annot,
  sections~ : Array[String],
  field~ : String,
) -> String? raise AtdError {
  annot_get_opt_field(l, parse=s => Some(s), sections~, field~)
}

///|
/// Set the value of a field, replacing the first existing occurrence if
/// any.
pub fn annot_set_field(
  l : Annot,
  loc~ : Loc,
  section~ : String,
  field~ : String,
  value : String?,
) -> Annot {
  match l.search_by(s => s.name == section) {
    None => {
      let res = [
        { name: section, loc, fields: [{ name: field, loc, value, }], },
      ]
      res.append(l)
      res
    }
    Some(i) => {
      let sec = l[i]
      let fields = match sec.fields.search_by(f => f.name == field) {
        None => {
          let fields = [{ name: field, loc, value, }]
          fields.append(sec.fields)
          fields
        }
        Some(j) => {
          let fields = sec.fields.copy()
          fields[j] = { name: field, loc, value, }
          fields
        }
      }
      let res = l.copy()
      res[i] = { ..sec, fields, }
      res
    }
  }
}

///|
/// Return the location of the first occurrence of a field.
pub fn annot_get_loc(
  l : Annot,
  sections~ : Array[String],
  field~ : String,
) -> Loc? raise AtdError {
  for section in sections {
    match annot_field(l, section~, field~) {
      None => continue
      Some((loc, _)) => return Some(loc)
    }
  }
  None
}

///|
/// Merge sections of the same name and fields of the same name, the first
/// occurrence taking precedence.
pub fn annot_merge(l : Annot) -> Annot {
  let res : Array[AnnotSection] = []
  for sec in l {
    match res.search_by(s => s.name == sec.name) {
      None => res.push(sec)
      Some(i) => {
        let fields = res[i].fields.copy()
        fields.append(sec.fields)
        res[i] = { ..res[i], fields: collapse_fields(fields), }
      }
    }
  }
  res
}

///|
fn collapse_fields(l : Array[AnnotField]) -> Array[AnnotField] {
  let res : Array[AnnotField] = []
  for f in l {
    if !res.iter().any(x => x.name == f.name) {
      res.push(f)
    }
  }
  res
}

///|
let id_counter : Ref[Int] = { val: -1, }

///|
/// Create a unique identifier (used for `shared` types).
pub fn annot_create_id() -> String {
  id_counter.val += 1
  id_counter.val.to_string()
}

///|
/// A section of an annotation schema: the fields allowed in the section,
/// with the kind of node where they may occur.
pub(all) struct SchemaSection {
  section : String
  fields : Array[(NodeKind, String)]
} derive(Debug)

///|
/// A schema for checking the placement of annotations.
pub type Schema = Array[SchemaSection]

///|
fn validate_section(sec : SchemaSection, root : Any) -> Unit raise AtdError {
  iter_annot(root, (kind, an) => {
    for s in an {
      if s.name == sec.section {
        for f in s.fields {
          if !sec.fields.iter().any(x => x.0 == kind && x.1 == f.name) {
            error_at(
              f.loc,
              "Invalid or misplaced annotation <\{s.name} ... \{f.name}... >",
            )
          }
        }
      }
    }
  })
}

///|
/// Check that all the annotations of the sections described by the schema
/// are valid and properly placed.
pub fn annot_validate(schema : Schema, root : Any) -> Unit raise AtdError {
  for sec in schema {
    validate_section(sec, root)
  }
}
