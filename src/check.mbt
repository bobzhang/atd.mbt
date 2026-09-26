// Semantic verification.

///|
priv struct CheckEnv {
  def_tbl : PredefTable
  imports : Imports
}

///|
priv enum Kind {
  KSum
  KRecord
  KOther
} derive(Eq)

///|
fn get_kind(t : TypeExpr) -> Kind {
  match t {
    Sum(_) => KSum
    Record(_) => KRecord
    _ => KOther
  }
}

///|
fn check_inheritance(env : CheckEnv, t0 : TypeExpr) -> Unit raise AtdError {
  fn not_a(kind : Kind) -> Unit raise AtdError {
    let what = match kind {
      KSum => "variant"
      KRecord => "record"
      KOther => abort("assertion failed")
    }
    error_at(t0.loc(), "Cannot inherit from non-\{what} type")
  }

  fn check(
    kind : Kind,
    inherited : Array[TypeName],
    t : TypeExpr,
  ) -> Unit raise AtdError {
    match t {
      Sum(_, vl, _) if kind == KSum =>
        for x in vl {
          match x {
            Inherit(_, t) => check(kind, inherited, t)
            Variant(_) => ()
          }
        }
      Record(_, fl, _) if kind == KRecord =>
        for x in fl {
          match x {
            Inherit(_, t) => check(kind, inherited, t)
            Field(_) => ()
          }
        }
      Sum(_)
      | Record(_)
      | Tuple(_)
      | List(_)
      | Option(_)
      | Nullable(_)
      | Shared(_)
      | Wrap(_) => not_a(kind)
      Name(_, { loc, name, .. }, _) =>
        if inherited.contains(name) {
          error_at(t0.loc(), "Cyclic inheritance")
        } else {
          let (_arity, opt_def) = match resolve_import(env.imports, loc, name) {
            (Some(_), _) =>
              error_at(loc, "We cannot inherit from an external type: \{name}")
            (None, base_name) =>
              match env.def_tbl.get(name) {
                Some(x) => x
                None => error_at(loc, "Undefined type " + base_name)
              }
          }
          match opt_def {
            None => ()
            Some(x) => check(kind, [x.name, ..inherited], x.value)
          }
        }
      Tvar(_) => error_at(t0.loc(), "Cannot inherit from a type variable")
    }
  }

  let inherited = match t0 {
    Name(_, inst, _) => [inst.name]
    _ => []
  }
  check(get_kind(t0), inherited, t0)
}

///|
priv struct TypeExprChecker {
  env : CheckEnv
  tvars : Array[String]
}

///|
fn TypeExprChecker::check(
  self : TypeExprChecker,
  t : TypeExpr,
) -> Unit raise AtdError {
  match t {
    Sum(_, vl, _) as x => {
      let accu : Map[String, Unit] = Map([])
      for v in vl {
        self.check_variant(accu, v)
      }
      check_inheritance(self.env, x)
    }
    Record(_, fl, _) as x => {
      let accu : Map[String, Unit] = Map([])
      for f in fl {
        self.check_field(accu, f)
      }
      check_inheritance(self.env, x)
    }
    Tuple(_, tl, _) =>
      for c in tl {
        self.check(c.expr)
      }
    List(_, t, _) | Option(_, t, _) | Nullable(_, t, _) | Wrap(_, t, _) =>
      self.check(t)
    Shared(loc, t, _) => {
      if t.is_parametrized() {
        error_at(loc, "Shared type cannot be polymorphic")
      }
      self.check(t)
    }
    Name(_, { loc, name, args: tal, }, _) =>
      match resolve_import(self.env.imports, loc, name) {
        (Some(_), _) => () // external type; we can't check its arity
        (None, base_name) => {
          let (arity, _) = match self.env.def_tbl.get(name) {
            Some(x) => x
            None => error_at(loc, "Undefined type " + base_name)
          }
          let n = tal.length()
          if arity != n {
            let given = if n > 1 { "s are given" } else { " is given" }
            error_at(
              loc,
              "Type \{name} was defined to take \{arity} parameters, but \{n} argument\{given}.",
            )
          }
          for t in tal {
            self.check(t)
          }
        }
      }
    Tvar(loc, s) =>
      if !self.tvars.contains(s) {
        error_at(loc, "Unbound type variable '\{s}")
      }
  }
}

///|
fn TypeExprChecker::check_variant(
  self : TypeExprChecker,
  accu : Map[String, Unit],
  v : Variant,
) -> Unit raise AtdError {
  match v {
    Variant(loc, k, _, opt_t) => {
      if accu.contains(k) {
        error_at(
          loc,
          "Multiple definitions of the same variant constructor \{k}",
        )
      }
      accu[k] = ()
      match opt_t {
        None => ()
        Some(t) => self.check(t)
      }
    }
    Inherit(_, t) => self.check(t)
  }
}

///|
fn TypeExprChecker::check_field(
  self : TypeExprChecker,
  accu : Map[String, Unit],
  f : Field,
) -> Unit raise AtdError {
  match f {
    Field({ loc, name: k, expr: t, .. }) => {
      if accu.contains(k) {
        error_at(loc, "Multiple definitions of the same field \{k}")
      }
      accu[k] = ()
      self.check(t)
    }
    Inherit(_, t) => self.check(t)
  }
}

///|
/// Check the existence and arity of the types used in type expressions,
/// and that inheritance is not cyclic.
pub fn check_module(x : Module) -> Unit raise AtdError {
  let env : CheckEnv = {
    def_tbl: make_predef_table(x.type_defs),
    imports: load_imports(x.imports),
  }
  for d in x.type_defs {
    { env, tvars: d.param, }.check(d.value)
  }
}
