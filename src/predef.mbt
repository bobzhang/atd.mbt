// Table of predefined types.

///|
fn predef_def(name : String, mk : (Loc, TypeExpr) -> TypeExpr) -> TypeDef {
  let loc = dummy_loc
  let d : TypeDef = {
    loc,
    name: TypeName::simple(name),
    param: ["a"],
    annot: [],
    value: mk(loc, Tvar(loc, "a")),
    orig: None,
  }
  { ..d, orig: Some(d), }
}

///|
/// The list of predefined types: name, arity, and definition if any.
pub let predef_list : Array[(TypeName, Int, TypeDef?)] = [
  (TypeName::simple("unit"), 0, None),
  (TypeName::simple("bool"), 0, None),
  (TypeName::simple("int"), 0, None),
  (TypeName::simple("float"), 0, None),
  (TypeName::simple("string"), 0, None),
  (TypeName::simple("abstract"), 0, None),
  (
    TypeName::simple("list"),
    1,
    Some(predef_def("list", (l, a) => List(l, a, []))),
  ),
  (
    TypeName::simple("option"),
    1,
    Some(predef_def("option", (l, a) => Option(l, a, []))),
  ),
  (
    TypeName::simple("nullable"),
    1,
    Some(predef_def("nullable", (l, a) => Nullable(l, a, []))),
  ),
  (
    TypeName::simple("shared"),
    1,
    Some(predef_def("shared", (l, a) => Shared(l, a, []))),
  ),
  (
    TypeName::simple("wrap"),
    1,
    Some(predef_def("wrap", (l, a) => Wrap(l, a, []))),
  ),
]

///|
/// A table mapping type names to their arity and definition.
pub type PredefTable = Map[TypeName, (Int, TypeDef?)]

///|
/// Build the table of predefined and user-defined types, checking for
/// duplicate definitions.
pub fn make_predef_table(
  user_defs : ArrayView[TypeDef],
) -> PredefTable raise AtdError {
  let predef : PredefTable = Map([])
  for x in predef_list {
    let (k, n, opt_t) = x
    predef[k] = (n, opt_t)
  }
  let tbl : PredefTable = Map([])
  for k, v in predef {
    tbl[k] = v
  }
  for x in user_defs {
    let name = x.name
    if tbl.contains(name) {
      if predef.contains(name) {
        error_at(x.loc, "\{name} is a predefined type, it cannot be redefined.")
      } else {
        error_at(x.loc, "Type \{name} is defined for the second time.")
      }
    }
    tbl[name] = (x.param.length(), Some(x))
  }
  tbl
}

///|
/// Follow aliases of the form `type t = u` down to the original definition.
pub fn get_original_definition(
  tbl : PredefTable,
  name : TypeName,
) -> (Int, TypeDef?)? {
  match tbl.get(name) {
    None => None
    Some((_, opt_def)) as res =>
      match opt_def {
        None => res
        Some(def) =>
          match def.value {
            Name(_, inst, _) =>
              match get_original_definition(tbl, inst.name) {
                None => res
                Some(_) as res => res
              }
            _ => res
          }
      }
  }
}

///|
/// Return the type construct that a type name stands for, if known.
pub fn get_construct(tbl : PredefTable, name : TypeName) -> (Int, TypeExpr)? {
  match get_original_definition(tbl, name) {
    None | Some((_, None)) => None
    Some((n, Some(def))) => Some((n, def.value))
  }
}

///|
/// Return the type construct of a type expression, looking up
/// parameterless type names.
pub fn get_construct_of_expr(tbl : PredefTable, x : TypeExpr) -> TypeExpr? {
  match x {
    Name(_, { name, args: [], .. }, _) =>
      match get_original_definition(tbl, name) {
        None => None
        Some((_, None)) => Some(x)
        Some((_, Some(def))) => Some(def.value)
      }
    construct => Some(construct)
  }
}
