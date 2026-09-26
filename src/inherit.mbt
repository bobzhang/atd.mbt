// Expansion of `inherit` statements.

///|
fn[T] keep_last_defined(get_name : (T) -> String, l : Array[T]) -> Array[T] {
  let seen : Map[String, Unit] = Map([])
  let rev = []
  for i = l.length() - 1; i >= 0; i = i - 1 {
    let k = get_name(l[i])
    if !seen.contains(k) {
      seen[k] = ()
      rev.push(l[i])
    }
  }
  rev.rev()
}

///|
fn get_field_name(f : Field) -> String {
  match f {
    Field(sf) => sf.name
    Inherit(_) => abort("assertion failed")
  }
}

///|
fn get_variant_name(v : Variant) -> String {
  match v {
    Variant(_, k, _, _) => k
    Inherit(_) => abort("assertion failed")
  }
}

///|
priv struct InheritExpander {
  tbl : PredefTable
  inherit_fields : Bool
  inherit_variants : Bool
}

///|
fn InheritExpander::subst(
  self : InheritExpander,
  deref : Bool,
  param : Array[(String, TypeExpr)],
  t : TypeExpr,
) -> TypeExpr raise AtdError {
  match t {
    Sum(loc, vl, a) => {
      let vl2 = []
      for v in vl {
        vl2.append(self.subst_variant(param, v))
      }
      let vl2 = if self.inherit_variants {
        keep_last_defined(get_variant_name, vl2)
      } else {
        vl2
      }
      Sum(loc, vl2, a)
    }
    Record(loc, fl, a) => {
      let fl2 = []
      for f in fl {
        fl2.append(self.subst_field(param, f))
      }
      let fl2 = if self.inherit_fields {
        keep_last_defined(get_field_name, fl2)
      } else {
        fl2
      }
      Record(loc, fl2, a)
    }
    Tuple(loc, tl, a) => {
      let cells = []
      for c in tl {
        cells.push({ ..c, expr: self.subst(false, param, c.expr), })
      }
      Tuple(loc, cells, a)
    }
    List(loc, t, a)
    | Name(loc, { name: { path: ["list"], }, args: [t], .. }, a) =>
      List(loc, self.subst(false, param, t), a)
    Option(loc, t, a)
    | Name(loc, { name: { path: ["option"], }, args: [t], .. }, a) =>
      Option(loc, self.subst(false, param, t), a)
    Nullable(loc, t, a)
    | Name(loc, { name: { path: ["nullable"], }, args: [t], .. }, a) =>
      Nullable(loc, self.subst(false, param, t), a)
    Shared(loc, t, a)
    | Name(loc, { name: { path: ["shared"], }, args: [t], .. }, a) =>
      Shared(loc, self.subst(false, param, t), a)
    Wrap(loc, t, a)
    | Name(loc, { name: { path: ["wrap"], }, args: [t], .. }, a) =>
      Wrap(loc, self.subst(false, param, t), a)
    Tvar(_, s) =>
      match param.iter().find_first(x => x.0 == s) {
        Some((_, v)) => v
        None => t
      }
    Name(loc, { loc: loc2, name: k, args, }, a) => {
      let expanded_args = []
      for x in args {
        expanded_args.push(self.subst(false, param, x))
      }
      if deref {
        let (vars, t) = match self.tbl.get(k) {
          Some((_, Some(x))) => (x.param, x.value)
          Some((_, None)) => error("Cannot inherit from type \{k}")
          None => error("Missing type definition for \{k}")
        }
        if vars.length() != expanded_args.length() {
          error("Invalid_argument(\"List.combine\")")
        }
        let param = vars.mapi((i, v) => (v, expanded_args[i]))
        self.subst(true, param, t)
      } else {
        Name(loc, { loc: loc2, name: k, args: expanded_args, }, a)
      }
    }
  }
}

///|
fn InheritExpander::subst_field(
  self : InheritExpander,
  param : Array[(String, TypeExpr)],
  f : Field,
) -> Array[Field] raise AtdError {
  match f {
    Field(sf) => [Field({ ..sf, expr: self.subst(false, param, sf.expr), })]
    Inherit(_, t) as x =>
      match self.subst(true, param, t) {
        Record(_, vl, _) => if self.inherit_fields { vl } else { [x] }
        _ => error("Not a record type")
      }
  }
}

///|
fn InheritExpander::subst_variant(
  self : InheritExpander,
  param : Array[(String, TypeExpr)],
  v : Variant,
) -> Array[Variant] raise AtdError {
  match v {
    Variant(loc, k, a, opt_t) as x =>
      match opt_t {
        None => [x]
        Some(t) => [Variant(loc, k, a, Some(self.subst(false, param, t)))]
      }
    Inherit(_, t) as x =>
      match self.subst(true, param, t) {
        Sum(_, vl, _) => if self.inherit_variants { vl } else { [x] }
        _ => error("Not a sum type")
      }
  }
}

///|
/// Expand the `inherit` statements of all the type definitions.
pub fn expand_inherit(
  defs : Array[TypeDef],
  inherit_fields? : Bool = true,
  inherit_variants? : Bool = true,
) -> Array[TypeDef] raise AtdError {
  let tbl = make_predef_table(defs)
  let e : InheritExpander = { tbl, inherit_fields, inherit_variants, }
  let res = []
  for x in defs {
    res.push({ ..x, value: e.subst(false, [], x.value), })
  }
  res
}
