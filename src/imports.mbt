// Management of external definitions via 'from ... import' statements.

///|
/// Map from local module name to import.
pub type Imports = Map[String, Import]

///|
/// Load and validate the import declarations.
pub fn load_imports(imports : ArrayView[Import]) -> Imports raise AtdError {
  let globals : Map[Array[String], Unit] = Map([])
  let locals : Imports = Map([])
  for x in imports {
    let name = x.name
    if locals.contains(name) {
      error_at(
        x.loc,
        (
          $|Local module name '\{name}' is already used by another import.
          $|Consider using 'as' to give it a non-conflicting name.
        ),
      )
    } else if globals.contains(x.path) {
      error_at(x.loc, "Module '\{x.path.join(".")}' is imported twice.")
    } else {
      let seen_types : Map[String, Unit] = Map([])
      for it in x.types {
        if seen_types.contains(it.name) {
          error_at(
            x.loc,
            "Type '\{it.name}' appears more than once in the import of module '\{x.path.join(".")}'.",
          )
        }
        seen_types[it.name] = ()
      }
      locals[name] = x
      globals[x.path] = ()
    }
  }
  locals
}

///|
/// Resolve a qualified or unqualified type name.
/// Returns `(Some((import, imported_type)), base_name)` for qualified names,
/// or `(None, base_name)` for unqualified names.
pub fn resolve_import(
  locals : Imports,
  loc : Loc,
  x : TypeName,
) -> ((Import, ImportedType?)?, String) raise AtdError {
  match x.split() {
    (None, base_name) => (None, base_name)
    (Some(module_name), base_name) =>
      match locals.get(module_name) {
        None =>
          error_at(
            loc,
            (
              $|Unknown module name '\{module_name}'.
              $|Hint: add 'from \{module_name} import \{base_name}' at the top of the file.
            ),
          )
        Some(import_) => {
          let it_opt = import_.types
            .iter()
            .find_first(it => it.name == base_name)
          (Some((import_, it_opt)), base_name)
        }
      }
  }
}

///|
/// Collect the warnings about imported type names that are never
/// referenced in any type expression, sorted by source position.
pub fn unused_import_warnings(
  locals : Imports,
  type_defs : ArrayView[TypeDef],
) -> Array[String] raise AtdError {
  let used : Map[(String, String), Unit] = Map([])
  for def in type_defs {
    def.value.fold((), (type_expr, _) => {
      match type_expr {
        Name(_, inst, _) =>
          match inst.name.split() {
            (None, _) => ()
            (Some(module_name), base_name) =>
              used[(module_name, base_name)] = ()
          }
        _ => ()
      }
    })
  }
  let warnings : Array[(Loc, String, String)] = []
  for _, import_ in locals {
    for it in import_.types {
      if !used.contains((import_.name, it.name)) {
        warnings.push((import_.loc, it.name, import_.path.join(".")))
      }
    }
  }
  warnings.sort_by((a, b) => {
    let c = a.0.compare(b.0)
    if c != 0 {
      c
    } else {
      compare_strings(a.1, b.1)
    }
  })
  warnings.map(w => {
    let (loc, type_name, module_path) = w
    "\{string_of_loc(loc)}:\nWarning: Type '\{type_name}' was imported from module '\{module_path}' but is never used."
  })
}

///|
/// Walk all type expressions and verify that every qualified type reference
/// `a.b` refers to an imported module `a` that lists type `b` with the
/// right arity.
pub fn check_type_refs(
  locals : Imports,
  type_defs : ArrayView[TypeDef],
) -> Unit raise AtdError {
  for def in type_defs {
    def.value.fold((), (type_expr, _) => {
      match type_expr {
        Name(loc, inst, _) =>
          match inst.name.split() {
            (None, _) => ()
            (Some(module_name), base_name) =>
              match locals.get(module_name) {
                None =>
                  error_at(
                    loc,
                    (
                      $|Unknown module name '\{module_name}'.
                      $|Hint: add 'from \{module_name} import \{base_name}' at the top of the file.
                    ),
                  )
                Some(import_) =>
                  match
                    import_.types.iter().find_first(it => it.name == base_name) {
                    None =>
                      error_at(
                        loc,
                        (
                          $|Type '\{base_name}' was not imported from module '\{module_name}'.
                          $|Hint: add '\{base_name}' to the import list: from \{import_.path.join(".")} import ..., \{base_name}
                        ),
                      )
                    Some(it) => {
                      let declared_arity = it.params.length()
                      let used_arity = inst.args.length()
                      if declared_arity != used_arity {
                        error_at(
                          loc,
                          "Type '\{module_name}.\{base_name}' was imported with arity \{declared_arity} but used with arity \{used_arity}.",
                        )
                      }
                    }
                  }
              }
          }
        _ => ()
      }
    })
  }
}
