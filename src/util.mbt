// Top-level utilities: loading ATD data and sorting type definitions.

///|
fn default_warning_handler(msg : String) -> Unit {
  eprintln(msg)
}

///|
/// Read ATD data from UTF-8 bytes.
///
/// - `annot_schema`: check for misplaced annotations.
/// - `expand`: perform monomorphization (`atdcat -x`).
/// - `keep_builtins`: with `expand`, preserve the builtin parametrized types.
/// - `keep_poly`: with `expand`, keep parametrized definitions (`-xk`).
/// - `xdebug`: with `expand`, keep non-standard type names (`-xd`).
/// - `inherit_fields`: expand `inherit` statements in records (`-if`).
/// - `inherit_variants`: expand `inherit` statements in sums (`-iv`).
/// - `pos_fname`: file name used in error messages.
/// - `pos_lnum`: number of the first line.
/// - `on_warning`: what to do with warnings; they are printed on stderr by
///   default.
pub fn load_bytes(
  src : BytesView,
  annot_schema? : Schema,
  expand? : Bool = false,
  keep_builtins? : Bool = false,
  keep_poly? : Bool = false,
  xdebug? : Bool = false,
  inherit_fields? : Bool = false,
  inherit_variants? : Bool = false,
  pos_fname? : String = "",
  pos_lnum? : Int = 1,
  on_warning? : (String) -> Unit = default_warning_handler,
) -> Module raise AtdError {
  let module_ = parse_module(src, pos_fname~, pos_lnum~)
  check_module(module_)
  let locals = load_imports(module_.imports)
  check_type_refs(locals, module_.type_defs)
  for w in unused_import_warnings(locals, module_.type_defs) {
    on_warning(w)
  }
  let type_defs = if inherit_fields || inherit_variants {
    expand_inherit(module_.type_defs, inherit_fields~, inherit_variants~)
  } else {
    module_.type_defs
  }
  let type_defs = if expand {
    expand_type_defs(type_defs, keep_builtins~, keep_poly~, debug=xdebug)
  } else {
    type_defs
  }
  let module_ = { ..module_, type_defs, }
  match annot_schema {
    None => ()
    Some(schema) => annot_validate(schema, Module(module_))
  }
  module_
}

///|
/// Read ATD data from a string. See `load_bytes` for the options.
pub fn load_string(
  s : String,
  annot_schema? : Schema,
  expand? : Bool = false,
  keep_builtins? : Bool = false,
  keep_poly? : Bool = false,
  xdebug? : Bool = false,
  inherit_fields? : Bool = false,
  inherit_variants? : Bool = false,
  pos_fname? : String = "",
  pos_lnum? : Int = 1,
  on_warning? : (String) -> Unit = default_warning_handler,
) -> Module raise AtdError {
  load_bytes(
    @utf8.encode(s),
    annot_schema?,
    expand~,
    keep_builtins~,
    keep_poly~,
    xdebug~,
    inherit_fields~,
    inherit_variants~,
    pos_fname~,
    pos_lnum~,
    on_warning~,
  )
}

///|
let ignorable_type_names : Array[TypeName] = [
  TypeName::simple("unit"),
  TypeName::simple("bool"),
  TypeName::simple("int"),
  TypeName::simple("float"),
  TypeName::simple("string"),
  TypeName::simple("abstract"),
]

///|
/// Topological sort for dependency analysis: split definitions into
/// mutually-recursive groups, ordered such that each group may only depend
/// on type definitions of its own group or previous groups. The boolean
/// flags indicate groups of one or more mutually recursive definitions.
///
/// `all_rec` assumes all definitions are mutually dependent.
pub fn tsort(
  type_defs : Array[TypeDef],
  all_rec? : Bool = false,
) -> Array[(Bool, Array[TypeDef])] {
  if all_rec {
    [(true, type_defs)]
  } else {
    let l = type_defs.map(x => {
      (x, x.value.extract_type_names(ignorable=ignorable_type_names))
    })
    topological_sort(l, x => x.name).rev()
  }
}
