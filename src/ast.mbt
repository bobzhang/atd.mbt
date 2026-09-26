// Abstract syntax tree (AST) representing ATD data.

///|
/// An annotation field, i.e. a key with an optional value within an
/// annotation, e.g. `baz="123"` or `bar` in `<foo bar baz="123">`.
pub(all) struct AnnotField {
  name : String
  loc : Loc
  value : String?
} derive(Eq, Debug)

///|
/// A single annotation within edgy brackets, e.g.
/// `<"foo" bar baz="123" path.to.thing="abc">`.
pub(all) struct AnnotSection {
  name : String
  loc : Loc
  fields : Array[AnnotField]
} derive(Eq, Debug)

///|
/// An annotation, consisting of a sequence of sections.
pub type Annot = Array[AnnotSection]

///|
/// Contents of an ATD file.
pub(all) struct Module {
  /// The head of an ATD file is just a list of annotations.
  head : (Loc, Annot)
  imports : Array[Import]
  type_defs : Array[TypeDef]
} derive(Eq, Debug)

///|
/// Require the existence of another ATD module.
/// The concrete syntax is `from module.path [as alias] import type1, ...`.
pub(all) struct Import {
  loc : Loc
  /// The full name of the ATD module.
  path : Array[String]
  annot : Annot
  /// The local name overriding the default name, if any.
  alias_ : String?
  /// The local name of the module: the alias if there is one, otherwise
  /// the last component of the path.
  name : String
  /// The list of types explicitly imported from the module.
  types : Array[ImportedType]
} derive(Eq, Debug)

///|
/// A type imported by a `from ... import ...` statement.
pub(all) struct ImportedType {
  /// Type parameter names, e.g. `["a"]` for `'a t`.
  params : Array[String]
  /// The name of the type in the external module.
  name : String
  annot : Annot
} derive(Eq, Debug)

///|
/// A type definition.
pub(all) struct TypeDef {
  loc : Loc
  name : TypeName
  /// List of type variables without the tick.
  param : Array[String]
  annot : Annot
  value : TypeExpr
  /// Polymorphic type definition from which this definition has been
  /// derived through monomorphization, if applicable.
  orig : TypeDef?
} derive(Eq, Debug)

///|
/// A type expression.
pub(all) enum TypeExpr {
  /// A sum type (within square brackets)
  Sum(Loc, Array[Variant], Annot)
  /// A record type (within curly braces)
  Record(Loc, Array[Field], Annot)
  /// A tuple (within parentheses)
  Tuple(Loc, Array[Cell], Annot)
  /// `t list`
  List(Loc, TypeExpr, Annot)
  /// `t option`
  Option(Loc, TypeExpr, Annot)
  /// `t nullable`: adds a null value to a type
  Nullable(Loc, TypeExpr, Annot)
  /// `t shared`: values for which sharing must be preserved
  Shared(Loc, TypeExpr, Annot)
  /// `t wrap`: optional wrapping of a type
  Wrap(Loc, TypeExpr, Annot)
  /// A type name other than the builtins above, with its arguments
  Name(Loc, TypeInst, Annot)
  /// A type variable identifier without the tick
  Tvar(Loc, String)
} derive(Eq, Debug)

///|
/// A dot-separated type name and its arguments.
pub(all) struct TypeInst {
  loc : Loc
  name : TypeName
  args : Array[TypeExpr]
} derive(Eq, Debug)

///|
/// A single variant or an `inherit` statement.
pub(all) enum Variant {
  Variant(Loc, String, Annot, TypeExpr?)
  Inherit(Loc, TypeExpr)
} derive(Eq, Debug)

///|
/// Tuple cell, with annotations placed before the type expression, as in
/// `<ocaml default="0.0">: float`.
pub(all) struct Cell {
  loc : Loc
  expr : TypeExpr
  annot : Annot
} derive(Eq, Debug)

///|
/// Kinds of record fields.
pub(all) enum FieldKind {
  /// required field, e.g. `id : string`
  Required
  /// optional field without a default value, e.g. `?name : string option`
  Optional
  /// optional field with a default value, e.g. `~websites : string list`
  WithDefault
} derive(Eq, Debug)

///|
/// A record field that is not an `inherit` statement.
pub(all) struct SimpleField {
  loc : Loc
  name : String
  kind : FieldKind
  annot : Annot
  expr : TypeExpr
} derive(Eq, Debug)

///|
/// A single record field or an `inherit` statement.
pub(all) enum Field {
  Field(SimpleField)
  Inherit(Loc, TypeExpr)
} derive(Eq, Debug)

///|
/// Any kind of node, used to define a visitor root.
pub(all) enum Any {
  Module(Module)
  Import(Import)
  ImportedType(ImportedType)
  TypeDef(TypeDef)
  TypeExpr(TypeExpr)
  Variant(Variant)
  Cell(Cell)
  Field(Field)
}

///|
/// Extract the source location of any type expression.
pub fn TypeExpr::loc(self : TypeExpr) -> Loc {
  match self {
    Sum(loc, _, _)
    | Record(loc, _, _)
    | Tuple(loc, _, _)
    | List(loc, _, _)
    | Option(loc, _, _)
    | Nullable(loc, _, _)
    | Shared(loc, _, _)
    | Wrap(loc, _, _)
    | Name(loc, _, _)
    | Tvar(loc, _) => loc
  }
}

///|
/// Replace the location of the given expression (shallow).
pub fn TypeExpr::set_loc(self : TypeExpr, loc : Loc) -> TypeExpr {
  match self {
    Sum(_, a, b) => Sum(loc, a, b)
    Record(_, a, b) => Record(loc, a, b)
    Tuple(_, a, b) => Tuple(loc, a, b)
    List(_, a, b) => List(loc, a, b)
    Option(_, a, b) => Option(loc, a, b)
    Nullable(_, a, b) => Nullable(loc, a, b)
    Shared(_, a, b) => Shared(loc, a, b)
    Wrap(_, a, b) => Wrap(loc, a, b)
    Name(_, a, b) => Name(loc, a, b)
    Tvar(_, a) => Tvar(loc, a)
  }
}

///|
/// Return the annotations associated with a type expression.
pub fn TypeExpr::annot(self : TypeExpr) -> Annot {
  match self {
    Sum(_, _, an)
    | Record(_, _, an)
    | Tuple(_, _, an)
    | List(_, _, an)
    | Option(_, _, an)
    | Nullable(_, _, an)
    | Shared(_, _, an)
    | Wrap(_, _, an)
    | Name(_, _, an) => an
    Tvar(_, _) => []
  }
}

///|
/// Replace the annotations associated with a type expression (shallow).
pub fn TypeExpr::map_annot(
  self : TypeExpr,
  f : (Annot) -> Annot raise AtdError,
) -> TypeExpr raise AtdError {
  match self {
    Sum(loc, vl, a) => Sum(loc, vl, f(a))
    Record(loc, fl, a) => Record(loc, fl, f(a))
    Tuple(loc, tl, a) => Tuple(loc, tl, f(a))
    List(loc, t, a) => List(loc, t, f(a))
    Option(loc, t, a) => Option(loc, t, f(a))
    Nullable(loc, t, a) => Nullable(loc, t, f(a))
    Shared(loc, t, a) => Shared(loc, t, f(a))
    Wrap(loc, t, a) => Wrap(loc, t, f(a))
    Tvar(_) as x => x
    Name(loc, inst, a) => Name(loc, inst, f(a))
  }
}

///|
fn Variant::annot(self : Variant) -> Annot {
  match self {
    Variant(_, _, an, _) => an
    Inherit(_) => []
  }
}

///|
fn Field::annot(self : Field) -> Annot {
  match self {
    Field(f) => f.annot
    Inherit(_) => []
  }
}

///|
fn amap_type_expr(f : (Annot) -> Annot, x : TypeExpr) -> TypeExpr {
  match x {
    Sum(loc, vl, a) => Sum(loc, vl.map(v => amap_variant(f, v)), f(a))
    Record(loc, fl, a) => Record(loc, fl.map(x => amap_field(f, x)), f(a))
    Tuple(loc, tl, a) =>
      Tuple(
        loc,
        tl.map(c => { ..c, expr: amap_type_expr(f, c.expr), annot: f(c.annot), }),
        f(a),
      )
    List(loc, t, a) => List(loc, amap_type_expr(f, t), f(a))
    Option(loc, t, a) => Option(loc, amap_type_expr(f, t), f(a))
    Nullable(loc, t, a) => Nullable(loc, amap_type_expr(f, t), f(a))
    Shared(loc, t, a) => Shared(loc, amap_type_expr(f, t), f(a))
    Wrap(loc, t, a) => Wrap(loc, amap_type_expr(f, t), f(a))
    Tvar(_) as x => x
    Name(loc, inst, a) =>
      Name(
        loc,
        { ..inst, args: inst.args.map(x => amap_type_expr(f, x)), },
        f(a),
      )
  }
}

///|
fn amap_variant(f : (Annot) -> Annot, x : Variant) -> Variant {
  match x {
    Variant(loc, name, a, o) =>
      Variant(loc, name, f(a), o.map(e => amap_type_expr(f, e)))
    Inherit(loc, e) => Inherit(loc, amap_type_expr(f, e))
  }
}

///|
fn amap_field(f : (Annot) -> Annot, x : Field) -> Field {
  match x {
    Field(sf) =>
      Field({ ..sf, annot: f(sf.annot), expr: amap_type_expr(f, sf.expr), })
    Inherit(loc, e) => Inherit(loc, amap_type_expr(f, e))
  }
}

///|
/// Replacement of all annotations occurring in an ATD module.
/// Note that, as in the original implementation, annotations of type
/// definitions themselves are left untouched.
pub fn Module::map_all_annot(self : Module, f : (Annot) -> Annot) -> Module {
  {
    head: (self.head.0, f(self.head.1)),
    imports: self.imports.map(x => {
      ..x,
      annot: f(x.annot),
      types: x.types.map(it => { ..it, annot: f(it.annot), }),
    }),
    type_defs: self.type_defs.map(x => {
      ..x,
      value: amap_type_expr(f, x.value),
    }),
  }
}

///|
/// Hooks for the visitor. Each hook receives a continuation that must be
/// called to visit the children of the node.
pub(all) struct VisitorHooks {
  module_ : ((Module) -> Unit raise AtdError, Module) -> Unit raise AtdError
  import_ : ((Import) -> Unit raise AtdError, Import) -> Unit raise AtdError
  imported_type : ((ImportedType) -> Unit raise AtdError, ImportedType) -> Unit raise AtdError
  type_def : ((TypeDef) -> Unit raise AtdError, TypeDef) -> Unit raise AtdError
  type_expr : ((TypeExpr) -> Unit raise AtdError, TypeExpr) -> Unit raise AtdError
  variant : ((Variant) -> Unit raise AtdError, Variant) -> Unit raise AtdError
  cell : ((Cell) -> Unit raise AtdError, Cell) -> Unit raise AtdError
  field : ((Field) -> Unit raise AtdError, Field) -> Unit raise AtdError
}

///|
fn visit_type_expr(hooks : VisitorHooks, x : TypeExpr) -> Unit raise AtdError {
  (hooks.type_expr)(
    fn(x) raise AtdError {
      match x {
        Sum(_, vl, _) =>
          for v in vl {
            visit_variant(hooks, v)
          }
        Record(_, fl, _) =>
          for f in fl {
            visit_field(hooks, f)
          }
        Tuple(_, tl, _) =>
          for c in tl {
            visit_cell(hooks, c)
          }
        List(_, t, _)
        | Option(_, t, _)
        | Nullable(_, t, _)
        | Shared(_, t, _)
        | Wrap(_, t, _) => visit_type_expr(hooks, t)
        Tvar(_) => ()
        Name(_, inst, _) =>
          for a in inst.args {
            visit_type_expr(hooks, a)
          }
      }
    },
    x,
  )
}

///|
fn visit_variant(hooks : VisitorHooks, x : Variant) -> Unit raise AtdError {
  (hooks.variant)(
    fn(x) raise AtdError {
      match x {
        Variant(_, _, _, Some(e)) => visit_type_expr(hooks, e)
        Variant(_, _, _, None) => ()
        Inherit(_, e) => visit_type_expr(hooks, e)
      }
    },
    x,
  )
}

///|
fn visit_field(hooks : VisitorHooks, x : Field) -> Unit raise AtdError {
  (hooks.field)(
    fn(x) raise AtdError {
      match x {
        Field(sf) => visit_type_expr(hooks, sf.expr)
        Inherit(_, e) => visit_type_expr(hooks, e)
      }
    },
    x,
  )
}

///|
fn visit_cell(hooks : VisitorHooks, x : Cell) -> Unit raise AtdError {
  (hooks.cell)(fn(c) raise AtdError { visit_type_expr(hooks, c.expr) }, x)
}

///|
fn visit_imported_type(
  hooks : VisitorHooks,
  x : ImportedType,
) -> Unit raise AtdError {
  (hooks.imported_type)(fn(_) {  }, x)
}

///|
fn visit_import(hooks : VisitorHooks, x : Import) -> Unit raise AtdError {
  (hooks.import_)(
    fn(x) raise AtdError {
      for it in x.types {
        visit_imported_type(hooks, it)
      }
    },
    x,
  )
}

///|
fn visit_type_def(hooks : VisitorHooks, x : TypeDef) -> Unit raise AtdError {
  (hooks.type_def)(fn(x) raise AtdError { visit_type_expr(hooks, x.value) }, x)
}

///|
fn visit_module(hooks : VisitorHooks, x : Module) -> Unit raise AtdError {
  (hooks.module_)(
    fn(x) raise AtdError {
      for i in x.imports {
        visit_import(hooks, i)
      }
      for d in x.type_defs {
        visit_type_def(hooks, d)
      }
    },
    x,
  )
}

///|
fn[T] default_hook(
  cont : (T) -> Unit raise AtdError,
  x : T,
) -> Unit raise AtdError {
  cont(x)
}

///|
/// Create a function that visits all the nodes of a tree. Each optional
/// hook defines what to do when encountering a node of a particular kind;
/// it is applied as `hook(cont, x)` and must call `cont` for the visitor
/// to continue down the tree.
pub fn visit(
  module_? : ((Module) -> Unit raise AtdError, Module) -> Unit raise AtdError = default_hook,
  import_? : ((Import) -> Unit raise AtdError, Import) -> Unit raise AtdError = default_hook,
  imported_type? : ((ImportedType) -> Unit raise AtdError, ImportedType) -> Unit raise AtdError = default_hook,
  type_def? : ((TypeDef) -> Unit raise AtdError, TypeDef) -> Unit raise AtdError = default_hook,
  type_expr? : ((TypeExpr) -> Unit raise AtdError, TypeExpr) -> Unit raise AtdError = default_hook,
  variant? : ((Variant) -> Unit raise AtdError, Variant) -> Unit raise AtdError = default_hook,
  cell? : ((Cell) -> Unit raise AtdError, Cell) -> Unit raise AtdError = default_hook,
  field? : ((Field) -> Unit raise AtdError, Field) -> Unit raise AtdError = default_hook,
) -> (Any) -> Unit raise AtdError {
  let hooks : VisitorHooks = {
    module_,
    import_,
    imported_type,
    type_def,
    type_expr,
    variant,
    cell,
    field,
  }
  fn(any) raise AtdError {
    match any {
      Module(x) => visit_module(hooks, x)
      Import(x) => visit_import(hooks, x)
      ImportedType(x) => visit_imported_type(hooks, x)
      TypeDef(x) => visit_type_def(hooks, x)
      TypeExpr(x) => visit_type_expr(hooks, x)
      Variant(x) => visit_variant(hooks, x)
      Cell(x) => visit_cell(hooks, x)
      Field(x) => visit_field(hooks, x)
    }
  }
}

///|
/// Kinds of nodes that carry annotations.
pub(all) enum NodeKind {
  ModuleHead
  Import
  ImportedType
  TypeDef
  TypeExpr
  Variant
  Cell
  Field
} derive(Eq, Debug)

///|
/// Iterate over all the annotations of a tree, calling `f` with the kind of
/// node and its annotation. This is a simplified version of OCaml's
/// `Ast.fold_annot` sufficient for collecting or validating annotations.
pub fn iter_annot(
  any : Any,
  f : (NodeKind, Annot) -> Unit raise AtdError,
) -> Unit raise AtdError {
  let visitor = visit(
    module_=(cont, x) => {
      f(ModuleHead, x.head.1)
      cont(x)
    },
    import_=(cont, x) => {
      f(Import, x.annot)
      cont(x)
    },
    imported_type=(cont, x) => {
      f(ImportedType, x.annot)
      cont(x)
    },
    type_def=(cont, x) => {
      f(TypeDef, x.annot)
      cont(x)
    },
    type_expr=(cont, x) => {
      f(TypeExpr, x.annot())
      cont(x)
    },
    variant=(cont, x) => {
      f(Variant, x.annot())
      cont(x)
    },
    cell=(cont, x) => {
      f(Cell, x.annot)
      cont(x)
    },
    field=(cont, x) => {
      f(Field, x.annot())
      cont(x)
    },
  )
  visitor(any)
}

///|
/// Iteration and accumulation over each type expression node within a
/// given type expression, in pre-order.
pub fn[A] TypeExpr::fold(
  self : TypeExpr,
  init : A,
  f : (TypeExpr, A) -> A raise AtdError,
) -> A raise AtdError {
  let acc = f(self, init)
  match self {
    Sum(_, vl, _) => {
      let mut acc = acc
      for i = vl.length() - 1; i >= 0; i = i - 1 {
        match vl[i] {
          Variant(_, _, _, Some(e)) | Inherit(_, e) => acc = e.fold(acc, f)
          Variant(_, _, _, None) => ()
        }
      }
      acc
    }
    Record(_, fl, _) => {
      let mut acc = acc
      for i = fl.length() - 1; i >= 0; i = i - 1 {
        match fl[i] {
          Field(sf) => acc = sf.expr.fold(acc, f)
          Inherit(_, e) => acc = e.fold(acc, f)
        }
      }
      acc
    }
    Tuple(_, l, _) => {
      let mut acc = acc
      for i = l.length() - 1; i >= 0; i = i - 1 {
        acc = l[i].expr.fold(acc, f)
      }
      acc
    }
    List(_, e, _)
    | Option(_, e, _)
    | Nullable(_, e, _)
    | Shared(_, e, _)
    | Wrap(_, e, _) => e.fold(acc, f)
    Name(_, inst, _) => {
      let mut acc = acc
      for i = inst.args.length() - 1; i >= 0; i = i - 1 {
        acc = inst.args[i].fold(acc, f)
      }
      acc
    }
    Tvar(_) => acc
  }
}

///|
/// Extract all the type names occurring in a type expression under `Name`,
/// without duplicates, sorted.
pub fn TypeExpr::extract_type_names(
  self : TypeExpr,
  ignorable? : Array[TypeName] = [],
) -> Array[TypeName] {
  let names : Array[TypeName] = []
  (self.fold((), (x, _) => {
    match x {
      Name(_, inst, _) =>
        if !ignorable.contains(inst.name) && !names.contains(inst.name) {
          names.push(inst.name)
        }
      _ => ()
    }
  }) catch {
    _ => ()
  })
  |> ignore
  names.sort()
  names
}

///|
/// Test whether a type expression contains type variables.
pub fn TypeExpr::is_parametrized(self : TypeExpr) -> Bool {
  self.fold(false, (x, b) => b || x is Tvar(_)) catch {
    _ => false
  }
}

///|
/// Test whether a field kind is `Required`.
pub fn FieldKind::is_required(self : FieldKind) -> Bool {
  self is Required
}

///|
/// Replace type expression nodes by other nodes: first the mapper is
/// applied to a node, then the children nodes are mapped recursively.
pub fn TypeExpr::map_deep(
  self : TypeExpr,
  m : (TypeExpr) -> TypeExpr,
) -> TypeExpr {
  match m(self) {
    Sum(loc, vl, an) =>
      Sum(
        loc,
        vl.map(v => {
          match v {
            Variant(loc, n, a, Some(x)) =>
              Variant(loc, n, a, Some(x.map_deep(m)))
            Variant(_) as v => v
            Inherit(loc, x) => Inherit(loc, x.map_deep(m))
          }
        }),
        an,
      )
    Record(loc, fl, an) =>
      Record(
        loc,
        fl.map(f => {
          match f {
            Field(sf) => Field({ ..sf, expr: sf.expr.map_deep(m), })
            Inherit(loc, x) => Inherit(loc, x.map_deep(m))
          }
        }),
        an,
      )
    Tuple(loc, cells, an) =>
      Tuple(loc, cells.map(c => { ..c, expr: c.expr.map_deep(m), }), an)
    List(loc, x, an) => List(loc, x.map_deep(m), an)
    Option(loc, x, an) => Option(loc, x.map_deep(m), an)
    Nullable(loc, x, an) => Nullable(loc, x.map_deep(m), an)
    Shared(loc, x, an) => Shared(loc, x.map_deep(m), an)
    Wrap(loc, x, an) => Wrap(loc, x.map_deep(m), an)
    Name(loc, inst, an) =>
      Name(loc, { ..inst, args: inst.args.map(x => x.map_deep(m)), }, an)
    Tvar(_) as x => x
  }
}

///|
/// Apply `TypeExpr::map_deep` to all the type definitions of a module.
pub fn Module::map_type_exprs(
  self : Module,
  m : (TypeExpr) -> TypeExpr,
) -> Module {
  {
    ..self,
    type_defs: self.type_defs.map(x => { ..x, value: x.value.map_deep(m), }),
  }
}

///|
/// Use the dedicated variants `List`, `Option`, etc. instead of the generic
/// variant `Name`.
pub fn Module::use_only_specific_variants(self : Module) -> Module {
  self.map_type_exprs(x => {
    match x {
      Name(loc, { name, args: [arg], .. }, an) =>
        match name.path {
          ["list"] => List(loc, arg, an)
          ["option"] => Option(loc, arg, an)
          ["nullable"] => Nullable(loc, arg, an)
          ["shared"] => Shared(loc, arg, an)
          ["wrap"] => Wrap(loc, arg, an)
          _ => x
        }
      x => x
    }
  })
}

///|
/// Use the generic variant `Name` instead of the dedicated variants
/// `List`, `Option`, etc. (except `Wrap`).
pub fn Module::use_only_name_variant(self : Module) -> Module {
  fn mk(loc : Loc, name : String, arg : TypeExpr, an : Annot) -> TypeExpr {
    Name(loc, { loc, name: TypeName::simple(name), args: [arg], }, an)
  }

  self.map_type_exprs(x => {
    match x {
      List(loc, arg, an) => mk(loc, "list", arg, an)
      Option(loc, arg, an) => mk(loc, "option", arg, an)
      Nullable(loc, arg, an) => mk(loc, "nullable", arg, an)
      Shared(loc, arg, an) => mk(loc, "shared", arg, an)
      x => x
    }
  })
}

///|
fn shallow_unwrap(e : TypeExpr) -> TypeExpr {
  match e {
    Wrap(_, e, _) => shallow_unwrap(e)
    e => e
  }
}

///|
/// Remove all `Wrap` constructs from the module.
pub fn Module::remove_wrap_constructs(self : Module) -> Module {
  self.map_type_exprs(shallow_unwrap)
}

///|
/// Create an import, computing its local name.
pub fn Import::new(
  loc~ : Loc,
  path~ : Array[String],
  annot~ : Annot,
  alias_? : String,
  types~ : Array[ImportedType],
) -> Import {
  let name = match (path.last(), alias_) {
    (None, _) => abort("Import::new: empty path")
    (Some(name), None) => name
    (Some(_), Some(override_)) => override_
  }
  { loc, path, annot, alias_, name, types, }
}
