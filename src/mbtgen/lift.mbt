// Lifting of inline record and sum types into named type definitions,
// since MoonBit has no anonymous records or enums:
//
//   type t = [ A of { x : int } ]
//
// becomes
//
//   type t = [ A of t_a ]
//   type t_a = { x : int }

///|
priv struct Lifter {
  names : @atd.UniqueNames
  new_defs : Array[@atd.TypeDef]
  /// Annotations inherited by the lifted definitions: `<mbt derive=...>`
  mut inherited_annot : @atd.Annot
}

///|
fn Lifter::lift_expr(
  self : Lifter,
  parent : String,
  hint : String,
  e : @atd.TypeExpr,
) -> @atd.TypeExpr {
  match e {
    Sum(loc, _, _) | Record(loc, _, _) => {
      let base = if hint == "" { parent } else { parent + "_" + hint }
      let name = self.names.create(base)
      let value = self.lift_children(name, e)
      self.new_defs.push({
        loc,
        name: @atd.TypeName::simple(name),
        param: [],
        annot: self.inherited_annot,
        value,
        orig: None,
      })
      Name(loc, { loc, name: @atd.TypeName::simple(name), args: [], }, [])
    }
    _ =>
      self.lift_children(parent + (if hint == "" { "" } else { "_" + hint }), e)
  }
}

///|
/// Lift the inline types found in the children of `e`, keeping `e`
/// itself.
fn Lifter::lift_children(
  self : Lifter,
  parent : String,
  e : @atd.TypeExpr,
) -> @atd.TypeExpr {
  match e {
    Sum(loc, vl, an) =>
      Sum(
        loc,
        vl.map(v => {
          match v {
            Variant(loc, k, a, Some(t)) =>
              Variant(loc, k, a, Some(self.lift_expr(parent, k.to_lower(), t)))
            v => v
          }
        }),
        an,
      )
    Record(loc, fl, an) =>
      Record(
        loc,
        fl.map(f => {
          match f {
            Field(sf) =>
              Field({ ..sf, expr: self.lift_expr(parent, sf.name, sf.expr), })
            f => f
          }
        }),
        an,
      )
    Tuple(loc, cells, an) =>
      Tuple(
        loc,
        cells.mapi((i, c) => {
          ..c,
          expr: self.lift_expr(parent, "\{i}", c.expr),
        }),
        an,
      )
    List(loc, t, an) => List(loc, self.lift_expr(parent, "", t), an)
    Option(loc, t, an) => Option(loc, self.lift_expr(parent, "", t), an)
    Nullable(loc, t, an) => Nullable(loc, self.lift_expr(parent, "", t), an)
    Shared(loc, t, an) => Shared(loc, self.lift_expr(parent, "", t), an)
    Wrap(loc, t, an) => Wrap(loc, self.lift_expr(parent, "", t), an)
    Name(loc, inst, an) =>
      Name(
        loc,
        { ..inst, args: inst.args.map(a => self.lift_expr(parent, "", a)), },
        an,
      )
    Tvar(_) => e
  }
}

///|
/// Strip the `wrap` constructs that have no MoonBit-specific annotation,
/// since they're transparent.
fn is_transparent_wrap(an : @atd.Annot) -> Bool {
  !@atd.annot_has_section(an, "mbt")
}

///|
/// Lift all inline records and sums so that they only occur at the top of
/// type definitions.
fn lift_inline_types(defs : Array[@atd.TypeDef]) -> Array[@atd.TypeDef] {
  let names = @atd.UniqueNames(
    reserved_identifiers=defs.map(d => d.name.to_string()),
    reserved_prefixes=[],
    safe_prefix="",
  )
  for d in defs {
    ignore(names.translate(d.name.to_string()))
  }
  let lifter : Lifter = { names, new_defs: [], inherited_annot: [], }
  let res = []
  for d in defs {
    let name = d.name.to_string()
    lifter.inherited_annot = derive_annot(d.annot)
    // the top of a type definition may be a record or a sum, possibly under
    // transparent 'wrap' constructs
    let value = loop_top(d.value, e => lifter.lift_children(name, e))
    res.push({ ..d, value, })
    res.append(lifter.new_defs)
    lifter.new_defs.clear()
  }
  res
}

///|
fn loop_top(
  e : @atd.TypeExpr,
  f : (@atd.TypeExpr) -> @atd.TypeExpr,
) -> @atd.TypeExpr {
  match e {
    Wrap(loc, t, an) if is_transparent_wrap(an) => Wrap(loc, loop_top(t, f), an)
    _ => f(e)
  }
}

///|
/// The `<mbt derive=...>` annotation of a type definition, if any, to be
/// inherited by the types lifted from it.
fn derive_annot(an : @atd.Annot) -> @atd.Annot {
  let res = []
  for sec in an {
    if sec.name == "mbt" {
      let fields = sec.fields.filter(f => f.name == "derive")
      if !fields.is_empty() {
        res.push({ ..sec, fields, })
      }
    }
  }
  res
}
