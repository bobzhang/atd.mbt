// Monomorphization of type expressions, a port of `expand.ml`.
//
// The goal is to inline each parametrized type definition as much as
// possible, allowing code generators to create more efficient code
// directly:
//
//   type ('a, 'b) t = [ Foo of 'a | Bar of 'b ]
//   type int_t = (int, int) t
//
// becomes:
//
//   type int_t = _1
//   type _1 = [ Foo of int | Bar of int ]
//
// A secondary goal is to factor out type subexpressions in order for the
// code generators to produce less code.

///|
/// Entry of the expansion table: order in the file, number of parameters,
/// original type definition, rewritten type definition.
priv struct ExpandEntry {
  seqnum : Int
  n_param : Int
  orig : TypeDef?
  rewritten : TypeDef?
}

///|
fn mapvar_expr(f : (String) -> String, x : TypeExpr) -> TypeExpr {
  match x {
    Sum(loc, vl, a) =>
      Sum(
        loc,
        vl.map(v => {
          match v {
            Variant(loc, k, a, opt_t) =>
              Variant(loc, k, a, opt_t.map(t => mapvar_expr(f, t)))
            Inherit(loc, t) => Inherit(loc, mapvar_expr(f, t))
          }
        }),
        a,
      )
    Record(loc, fl, a) =>
      Record(
        loc,
        fl.map(fd => {
          match fd {
            Field(sf) => Field({ ..sf, expr: mapvar_expr(f, sf.expr), })
            Inherit(loc, t) => Inherit(loc, mapvar_expr(f, t))
          }
        }),
        a,
      )
    Tuple(loc, tl, a) =>
      Tuple(loc, tl.map(c => { ..c, expr: mapvar_expr(f, c.expr), }), a)
    List(loc, t, a) => List(loc, mapvar_expr(f, t), a)
    Option(loc, t, a) => Option(loc, mapvar_expr(f, t), a)
    Nullable(loc, t, a) => Nullable(loc, mapvar_expr(f, t), a)
    Shared(loc, t, a) => Shared(loc, mapvar_expr(f, t), a)
    Wrap(loc, t, a) => Wrap(loc, mapvar_expr(f, t), a)
    Tvar(loc, s) => Tvar(loc, f(s))
    Name(loc, inst, a) =>
      Name(loc, { ..inst, args: inst.args.map(t => mapvar_expr(f, t)), }, a)
  }
}

///|
fn var_of_int(i : Int) -> String {
  let letter = i % 26
  let number = i / 26
  let prefix = (letter + 'a'.to_int()).unsafe_to_char().to_string()
  if number == 0 {
    prefix
  } else {
    prefix + number.to_string()
  }
}

///|
fn vars_of_int(n : Int) -> Array[String] {
  Array::makei(n, var_of_int)
}

///|
fn is_special(name : TypeName) -> Bool {
  match name.path {
    [s] => s.length() > 0 && s[0] == '@'
    _ => false
  }
}

///|
/// Standardize a type expression by numbering the type variables using the
/// order in which they are encountered. Returns the new name, the new
/// arguments and the substitution environment.
///
/// Note: like the original implementation, each occurrence of a type
/// variable receives a new number, even if the same variable occurs twice.
fn make_type_name(
  loc : Loc,
  orig_name : TypeName,
  args : Array[TypeExpr],
  an : Annot,
) -> (TypeName, Array[TypeExpr], Array[(String, TypeExpr)]) {
  let mut n = 0
  let mapping = []
  let assign_name = s => {
    let name = var_of_int(n)
    mapping.push((s, name))
    n += 1
    name
  }
  let normalized_args = args.map(t => mapvar_expr(assign_name, t))
  let new_name = TypeName::simple(
    "@(" + string_of_type_inst(orig_name, normalized_args, an) + ")",
  )
  let new_args = mapping.map(m => Tvar(loc, m.0))
  let new_env = mapping.map(m => (m.0, Tvar(loc, m.1)))
  (new_name, new_args, new_env)
}

///|
fn is_abstract(x : TypeExpr) -> Bool {
  x is Name(_, { name: { path: ["abstract"], }, .. }, _)
}

///|
fn expr_of_lvalue(
  loc : Loc,
  name : TypeName,
  param : Array[String],
  annot : Annot,
) -> TypeExpr {
  Name(loc, { loc, name, args: param.map(s => Tvar(loc, s)), }, annot)
}

///|
fn is_cyclic(lname : TypeName, t : TypeExpr) -> Bool {
  match t {
    Name(_, { name: rname, .. }, _) => lname == rname
    _ => false
  }
}

///|
fn add_annot(x : TypeExpr, a : Annot) -> TypeExpr raise AtdError {
  x.map_annot(a0 => {
    let l = a.copy()
    l.append(a0)
    annot_merge(l)
  })
}

///|
fn assoc_env(env : Array[(String, TypeExpr)], s : String) -> TypeExpr? {
  match env.iter().find_first(x => x.0 == s) {
    Some((_, v)) => Some(v)
    None => None
  }
}

///|
priv struct Expander {
  keep_builtins : Bool
  mut seqnum : Int
  /// Specializations being created: original type name and location
  stack : Array[(TypeName, Loc)]
  tbl : Map[TypeName, ExpandEntry]
}

///|
fn builtin_arg(name : TypeName, args : Array[TypeExpr]) -> (String, TypeExpr)? {
  match (name.path, args) {
    (["list" | "option" | "nullable" | "shared" | "wrap" as b], [t]) =>
      Some((b, t))
    _ => None
  }
}

///|
/// View of a type expression as an application of a builtin parametrized
/// type: `(builtin name, loc, loc2, arg, annot)`.
fn as_builtin(t : TypeExpr) -> (String, Loc, Loc, TypeExpr, Annot)? {
  match t {
    List(loc, t, a) => Some(("list", loc, loc, t, a))
    Option(loc, t, a) => Some(("option", loc, loc, t, a))
    Nullable(loc, t, a) => Some(("nullable", loc, loc, t, a))
    Shared(loc, t, a) => Some(("shared", loc, loc, t, a))
    Wrap(loc, t, a) => Some(("wrap", loc, loc, t, a))
    Name(loc, { loc: loc2, name, args, }, a) =>
      match builtin_arg(name, args) {
        Some((b, t)) => Some((b, loc, loc2, t, a))
        None => None
      }
    _ => None
  }
}

///|
fn make_builtin(b : String, loc : Loc, t : TypeExpr, a : Annot) -> TypeExpr {
  match b {
    "list" => List(loc, t, a)
    "option" => Option(loc, t, a)
    "nullable" => Nullable(loc, t, a)
    "shared" => Shared(loc, t, a)
    _ => Wrap(loc, t, a)
  }
}

///|
fn Expander::subst(
  self : Expander,
  env : Array[(String, TypeExpr)],
  t : TypeExpr,
) -> TypeExpr raise AtdError {
  match as_builtin(t) {
    Some((b, loc, loc2, t, a)) => {
      let t2 = self.subst(env, t)
      let name = TypeName::simple(b)
      if self.keep_builtins {
        return Name(loc, { loc: loc2, name, args: [t2], }, a)
      } else {
        return self.subst_type_name(loc, loc2, name, [t2], a)
      }
    }
    None => ()
  }
  match t {
    Sum(loc, vl, a) => {
      let vl2 = []
      for v in vl {
        vl2.push(self.subst_variant(env, v))
      }
      Sum(loc, vl2, a)
    }
    Record(loc, fl, a) => {
      let fl2 = []
      for f in fl {
        fl2.push(self.subst_field(env, f))
      }
      Record(loc, fl2, a)
    }
    Tuple(loc, tl, a) => {
      let cells = []
      for c in tl {
        cells.push({ ..c, expr: self.subst(env, c.expr), })
      }
      Tuple(loc, cells, a)
    }
    Tvar(_, s) as x => assoc_env(env, s).unwrap_or(x)
    Name(loc, { loc: loc2, name, args, }, a) => {
      let args2 = []
      for x in args {
        args2.push(self.subst(env, x))
      }
      if args2.iter().all(x => x is Tvar(_)) {
        Name(loc, { loc: loc2, name, args: args2, }, a)
      } else {
        self.subst_type_name(loc, loc2, name, args2, a)
      }
    }
    List(_) | Option(_) | Nullable(_) | Shared(_) | Wrap(_) =>
      abort("unreachable")
  }
}

///|
/// Reduce the number of arguments of the type by creating an intermediate
/// type, e.g. `('x, int) t` becomes `'x "('a, int) t"` and the type
/// `type 'a "('a, int) t" = ...` is created.
fn Expander::subst_type_name(
  self : Expander,
  loc : Loc,
  loc2 : Loc,
  name : TypeName,
  args : Array[TypeExpr],
  an : Annot,
) -> TypeExpr raise AtdError {
  let (new_name, new_args, new_env) = make_type_name(loc2, name, args, an)
  let n_param = new_env.length()
  if !self.tbl.contains(new_name) {
    self.create_type_def(loc, name, args, new_env, new_name, n_param, an)
  }
  Name(loc, { loc: loc2, name: new_name, args: new_args, }, [])
}

///|
/// Maximum nesting of the specializations created by the expansion.
let max_expansion_depth : Int = 100

///|
fn Expander::create_type_def(
  self : Expander,
  loc : Loc,
  orig_name : TypeName,
  orig_args : Array[TypeExpr],
  env : Array[(String, TypeExpr)],
  name : TypeName,
  n_param : Int,
  an0 : Annot,
) -> Unit raise AtdError {
  // A specialization of a type that uses itself with ever-growing
  // arguments (polymorphic recursion), e.g.
  // `type 'a t = [ Next of 'a list t ]`, can't be expanded: it would
  // create infinitely many types. Like upstream, the expansion would not
  // terminate, so give up at an arbitrary depth.
  if self.stack.length() >= max_expansion_depth {
    // report the user-defined type that keeps being specialized
    let (name, loc) = self.stack
      .iter()
      .filter(x => !predef_list.iter().any(p => p.0 == x.0))
      .head()
      .unwrap_or((orig_name, loc))
    error_at(
      loc,
      "Cannot expand type \{name}: its definition leads to infinitely many specializations (polymorphic recursion)",
    )
  }
  self.stack.push((orig_name, loc))
  defer ignore(self.stack.pop())
  self.seqnum += 1
  let i = self.seqnum
  self.tbl[name] = { seqnum: i, n_param, orig: None, rewritten: None, }
  let orig_opt_td = match self.tbl.get(orig_name) {
    Some(e) => e.orig
    None => error("Cannot expand type \{orig_name}: missing definition")
  }
  let x = match orig_opt_td {
    None => error("Cannot expand type \{orig_name}: missing definition")
    Some(x) => x
  }
  let new_params = vars_of_int(n_param)
  let t = add_annot(x.value, an0)
  let t = t.set_loc(loc)
  let args = []
  for a in orig_args {
    args.push(self.subst(env, a))
  }
  let env = x.param.mapi((i, v) => (v, args[i]))
  let t2 = if is_abstract(t) {
    let t = expr_of_lvalue(loc, orig_name, x.param, t.annot())
    self.subst_only_args(env, t)
  } else {
    let t2 = self.subst(env, t)
    if is_cyclic(name, t2) {
      self.subst_only_args(env, t)
    } else {
      t2
    }
  }
  let td2 : TypeDef = {
    ..x,
    loc,
    name,
    param: new_params,
    annot: x.annot,
    value: t2,
  }
  self.tbl[name] = { seqnum: i, n_param, orig: None, rewritten: Some(td2), }
}

///|
fn Expander::subst_field(
  self : Expander,
  env : Array[(String, TypeExpr)],
  f : Field,
) -> Field raise AtdError {
  match f {
    Field(sf) => Field({ ..sf, expr: self.subst(env, sf.expr), })
    Inherit(loc, t) => Inherit(loc, self.subst(env, t))
  }
}

///|
fn Expander::subst_variant(
  self : Expander,
  env : Array[(String, TypeExpr)],
  v : Variant,
) -> Variant raise AtdError {
  match v {
    Variant(loc, k, a, opt_t) as x =>
      match opt_t {
        None => x
        Some(t) => Variant(loc, k, a, Some(self.subst(env, t)))
      }
    Inherit(loc, t) => Inherit(loc, self.subst(env, t))
  }
}

///|
fn Expander::subst_only_args(
  self : Expander,
  env : Array[(String, TypeExpr)],
  t : TypeExpr,
) -> TypeExpr raise AtdError {
  match as_builtin(t) {
    Some((b, loc, _, t, a)) => make_builtin(b, loc, self.subst(env, t), a)
    None =>
      match t {
        Name(loc, { loc: loc2, name, args, }, an) => {
          let args2 = []
          for x in args {
            args2.push(self.subst(env, x))
          }
          Name(loc, { loc: loc2, name, args: args2, }, an)
        }
        _ => abort("assertion failed")
      }
  }
}

///|
fn expand_defs(
  l : Array[TypeDef],
  keep_builtins~ : Bool,
  keep_poly~ : Bool,
) -> Array[TypeDef] raise AtdError {
  let e : Expander = { keep_builtins, seqnum: 0, stack: [], tbl: Map([]), }
  for x in predef_list {
    let (k, n, opt_td) = x
    e.seqnum += 1
    e.tbl[k] = { seqnum: e.seqnum, n_param: n, orig: opt_td, rewritten: None, }
  }
  // first pass: add all original definitions to the table
  for x in l {
    e.seqnum += 1
    e.tbl[x.name] = {
      seqnum: e.seqnum,
      n_param: x.param.length(),
      orig: Some(x),
      rewritten: None,
    }
  }
  // second pass: perform substitutions and insert new definitions
  for td in l {
    if td.param.is_empty() || keep_poly {
      let entry = e.tbl[td.name]
      let t2 = e.subst([], td.value)
      e.tbl[td.name] = {
        ..entry,
        orig: Some(td),
        rewritten: Some({ ..td, value: t2, }),
      }
    }
  }
  // third pass: collect all parameterless definitions
  let res = []
  for _, entry in e.tbl {
    match entry.rewritten {
      None => ()
      Some(td2) =>
        if entry.n_param == 0 || keep_poly {
          res.push((entry.seqnum, td2))
        }
    }
  }
  res.sort_by((a, b) => a.0.compare(b.0))
  res.map(x => x.1)
}

///|
fn replace_type_names(subst : (TypeName) -> TypeName, t : TypeExpr) -> TypeExpr {
  t.map_deep(x => {
    match x {
      Name(loc, inst, a) => Name(loc, { ..inst, name: subst(inst.name), }, a)
      x => x
    }
  })
}

///|
fn hex_hash_string(s : String) -> String {
  let digest = @crypto.md5(@utf8.encode(s))
  let hex = @crypto.bytes_to_hex_string(digest)
  String::from_iter(hex.iter().take(7))
}

///|
fn is_alnum(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

///|
/// Remove punctuation and non-ascii symbols from a name and replace them
/// with underscores, e.g. `"@((@(bool wrap_) * type_) option)"` gives
/// `"bool_wrap_type_option"`.
fn suggest_good_name(name_with_punct : String) -> String {
  let components : Array[String] = []
  let cur = StringBuilder()
  for c in name_with_punct {
    if is_alnum(c) {
      cur.write_char(c)
    } else if cur.to_string() != "" {
      components.push(cur.to_string())
      cur.reset()
    }
  }
  if cur.to_string() != "" {
    components.push(cur.to_string())
  }
  let full_name = components.join("_")
  let hash = hex_hash_string(full_name)
  let name = if name_with_punct.contains("<") {
    "x_" + hash
  } else if components.length() > 5 {
    components[components.length() - 1] + "_" + hash
  } else {
    full_name
  }
  if name == "" {
    "x"
  } else {
    match name[0] {
      'a'..='z' | 'A'..='Z' => name
      _ => "x" + name
    }
  }
}

///|
fn standardize_type_names(
  prefix~ : String,
  defs : Array[TypeDef],
) -> Array[TypeDef] {
  let reserved_identifiers = predef_list.map(x => x.0.to_string())
  for x in defs {
    if !is_special(x.name) {
      reserved_identifiers.push(x.name.to_string())
    }
  }
  let registry = UniqueNames::new(
    reserved_identifiers~,
    reserved_prefixes=[],
    safe_prefix="",
  )
  let new_id = (id : TypeName) => {
    let str_id = id.to_string()
    let new_str_id = registry.translate(
      str_id,
      preferred_translation=prefix + suggest_good_name(str_id),
    )
    TypeName::simple(new_str_id)
  }
  let defs = defs.map(x => {
    if is_special(x.name) {
      { ..x, name: new_id(x.name), }
    } else {
      x
    }
  })
  let subst = (id : TypeName) => {
    match id.path {
      [name] =>
        match registry.translate_only(name) {
          Some(x) => TypeName::simple(x)
          None => id
        }
      _ => id
    }
  }
  defs.map(x => { ..x, value: replace_type_names(subst, x.value), })
}

///|
/// Monomorphization of type definitions.
///
/// - `prefix`: prefix to use for new type names. Default is `"_"`.
/// - `keep_builtins`: preserve occurrences of the built-in parametrized
///   types such as `list` or `option`.
/// - `keep_poly`: return definitions for the parametrized types.
/// - `debug`: keep meaningful but non ATD-compliant names for new types.
pub fn expand_type_defs(
  td_list : Array[TypeDef],
  prefix? : String = "_",
  keep_builtins? : Bool = false,
  keep_poly? : Bool = false,
  debug? : Bool = false,
) -> Array[TypeDef] raise AtdError {
  let td_list = expand_defs(td_list, keep_builtins~, keep_poly~)
  if debug {
    td_list
  } else {
    standardize_type_names(prefix~, td_list)
  }
}
