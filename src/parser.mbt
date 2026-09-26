// Recursive-descent parser for ATD, a port of the Menhir grammar
// `parser.mly`.
//
// Locations follow Menhir's conventions: a production starts at the start
// of its first symbol, or at the end of the previous token if the first
// symbol derives the empty string; it ends at the end of the last token
// consumed.
//
// Error reporting emulates Menhir's legacy error-recovery strategy, which
// upstream relies on to produce messages such as "Expecting '='": when a
// syntax error occurs, the innermost enclosing grammar position that has an
// `error` alternative determines the message. Such positions are
// represented by `Parser::frame`. Errors not caught by any frame produce a
// generic "Syntax error" message.

///|
priv suberror RawSyntaxError {
  RawSyntaxError(Loc)
}

///|
priv struct Parser {
  lexer : Lexer
  mut tok : Token
  mut tok_loc : Loc
  /// End position of the last consumed token
  mut last_end : Pos
}

///|
fn Parser::new(lexer : Lexer) -> Parser raise Error {
  let init = lexer.curr_pos()
  let (tok, tok_loc) = lexer.token()
  { lexer, tok, tok_loc, last_end: init, }
}

///|
fn Parser::advance(self : Parser) -> Unit raise Error {
  self.last_end = self.tok_loc.end_
  let (tok, loc) = self.lexer.token()
  self.tok = tok
  self.tok_loc = loc
}

///|
fn[T] Parser::fail(self : Parser) -> T raise Error {
  raise RawSyntaxError(self.tok_loc)
}

///|
fn Parser::expect(self : Parser, tok : Token) -> Unit raise Error {
  if self.tok == tok {
    self.advance()
  } else {
    self.fail()
  }
}

///|
/// Run `f` in the scope of an `error` alternative of the grammar: raw
/// syntax errors occurring within `f` are reported with message `msg`.
fn[T] Parser::frame(
  _self : Parser,
  msg : String,
  f : () -> T raise Error,
) -> T raise Error {
  f() catch {
    RawSyntaxError(loc) => error_at(loc, msg)
    e => raise e
  }
}

///|
fn Parser::is_lident_or_kw(self : Parser) -> Bool {
  self.tok is (Lident(_) | From | ImportKw | As)
}

///|
fn Parser::lident_or_kw(self : Parser) -> String raise Error {
  let s = match self.tok {
    Lident(s) => s
    From => "from"
    ImportKw => "import"
    As => "as"
    _ => self.fail()
  }
  self.advance()
  s
}

///|
/// `annot: asection annot | (empty)`
fn Parser::annot(self : Parser) -> Annot raise Error {
  let res = []
  while self.tok is Lt {
    res.push(self.asection())
  }
  res
}

///|
fn Parser::asection(self : Parser) -> AnnotSection raise Error {
  let start = self.tok_loc.start
  self.advance() // LT
  self.frame("Expecting lowercase identifier", () => {
    let name = self.lident_or_kw()
    let fields = []
    while self.is_lident_or_kw() {
      fields.push(self.afield())
    }
    if !(self.tok is Gt) {
      self.frame("Expecting '>'", () => self.fail())
    }
    self.advance()
    { name, loc: Loc::new(start, self.last_end), fields, }
  })
}

///|
fn Parser::afield(self : Parser) -> AnnotField raise Error {
  let start = self.tok_loc.start
  let path = [self.lident_or_kw()]
  while self.tok is Dot {
    self.advance()
    path.push(self.lident_or_kw())
  }
  let name = path.join(".")
  if self.tok is EqTok {
    self.advance()
    match self.tok {
      StringLit(s) => {
        self.advance()
        { name, loc: Loc::new(start, self.last_end), value: Some(s), }
      }
      _ => self.fail()
    }
  } else {
    { name, loc: Loc::new(start, self.last_end), value: None, }
  }
}

///|
/// Parse a complete module.
fn Parser::module_(self : Parser) -> Module raise Error {
  let an_start = if self.tok is Lt { self.tok_loc.start } else { self.last_end }
  let an = self.annot()
  let head_loc = Loc::new(an_start, self.last_end)
  let imports = []
  while self.tok is From {
    imports.push(self.from_import())
  }
  let type_defs = []
  while self.tok is TypeKw {
    type_defs.push(self.type_def())
  }
  if !(self.tok is Eof) {
    self.fail()
  }
  { head: (head_loc, an), imports, type_defs, }
}

///|
fn Parser::from_import(self : Parser) -> Import raise Error {
  let start = self.tok_loc.start
  self.advance() // FROM
  self.frame("Expecting module name after 'from'", () => {
    let path = [self.lident_or_kw()]
    while self.tok is Dot {
      self.advance()
      path.push(self.lident_or_kw())
    }
    let annot = self.annot()
    let alias_ = if self.tok is As {
      self.advance()
      Some(
        self.frame("Expecting module alias after 'as'", () => {
          self.lident_or_kw()
        }),
      )
    } else {
      None
    }
    self.expect(ImportKw)
    let types = [self.imported_type_item()]
    while self.tok is Comma {
      self.advance()
      types.push(self.imported_type_item())
    }
    if !(self.tok is (From | TypeKw | Eof)) {
      self.fail()
    }
    Import::new(
      loc=Loc::new(start, self.last_end),
      path~,
      annot~,
      alias_?,
      types~,
    )
  })
}

///|
fn Parser::imported_type_item(self : Parser) -> ImportedType raise Error {
  match self.tok {
    Tident(p) => {
      self.advance()
      let name = self.lident_or_kw()
      let annot = self.annot()
      { params: [p], name, annot, }
    }
    OpParen => {
      self.advance()
      self.frame("Expecting type variable list", () => {
        let ps = self.type_var_list()
        self.expect(ClParen)
        let name = self.lident_or_kw()
        let annot = self.annot()
        { params: ps, name, annot, }
      })
    }
    _ => {
      let name = self.lident_or_kw()
      let annot = self.annot()
      { params: [], name, annot, }
    }
  }
}

///|
/// `type_var_list: TIDENT COMMA type_var_list | TIDENT`
fn Parser::type_var_list(self : Parser) -> Array[String] raise Error {
  let res = []
  for ;; {
    match self.tok {
      Tident(s) => {
        self.advance()
        res.push(s)
      }
      _ => self.fail()
    }
    if self.tok is Comma {
      self.advance()
    } else {
      break
    }
  }
  res
}

///|
fn Parser::type_def(self : Parser) -> TypeDef raise Error {
  let start = self.tok_loc.start
  self.advance() // TYPE
  self.frame("Expecting type name", () => {
    let param = match self.tok {
      Tident(s) => {
        self.advance()
        [s]
      }
      OpParen => {
        self.advance()
        let l = self.type_var_list()
        if !(self.tok is ClParen) {
          self.frame("Expecting ')'", () => self.fail())
        }
        self.advance()
        l
      }
      _ => []
    }
    let name = self.lident_or_kw()
    let annot = self.annot()
    if !(self.tok is EqTok) {
      self.frame("Expecting '='", () => self.fail())
    }
    self.advance()
    let value = self.frame("Expecting type expression", () => {
      let t = self.type_expr()
      if !(self.tok is (TypeKw | Eof)) {
        self.fail()
      }
      t
    })
    let orig : TypeDef = {
      loc: Loc::new(start, self.last_end),
      name: TypeName::simple(name),
      param,
      annot,
      value,
      orig: None,
    }
    { ..orig, orig: Some(orig), }
  })
}

///|
/// Result of parsing a parenthesized construct: either a complete tuple
/// type or a list of type arguments that must be followed by a type name.
priv enum Paren {
  PTuple(TypeExpr)
  PArgs(Pos, Array[TypeExpr])
}

///|
fn Parser::type_expr(self : Parser) -> TypeExpr raise Error {
  let start = self.tok_loc.start
  let base = match self.tok {
    OpBrack => {
      self.advance()
      if self.tok is ClBrack {
        self.advance()
        let a = self.annot()
        Sum(Loc::new(start, self.last_end), [], a)
      } else {
        let l = self.variant_list()
        if !(self.tok is ClBrack) {
          self.frame("Expecting ']'", () => self.fail())
        }
        self.advance()
        let a = self.annot()
        Sum(Loc::new(start, self.last_end), l, a)
      }
    }
    OpCurl => {
      self.advance()
      if self.tok is ClCurl {
        self.advance()
        let a = self.annot()
        Record(Loc::new(start, self.last_end), [], a)
      } else {
        let l = self.field_list()
        if !(self.tok is ClCurl) {
          self.frame("Expecting '}'", () => self.fail())
        }
        self.advance()
        let a = self.annot()
        Record(Loc::new(start, self.last_end), l, a)
      }
    }
    OpParen =>
      match self.paren() {
        PTuple(t) => t
        PArgs(start, args) => self.type_inst_rest(start, args)
      }
    Tident(s) => {
      self.advance()
      Tvar(Loc::new(start, self.last_end), s)
    }
    Lident(_) | From | ImportKw | As =>
      // empty type_args: the production starts at the end of the previous
      // token
      self.type_inst_rest(self.last_end, [])
    _ => self.fail()
  }
  let mut t = base
  while self.is_lident_or_kw() {
    t = self.type_inst_rest(t.loc().start, [t])
  }
  t
}

///|
/// Parse the parenthesized part of a type expression, after `(`:
/// a tuple, or a list of type arguments.
fn Parser::paren(self : Parser) -> Paren raise Error {
  let start = self.tok_loc.start
  self.advance() // OP_PAREN
  self.frame("Expecting ')'", () => {
    if self.tok is ClParen {
      // empty cartesian product
      self.advance()
      let a = self.annot()
      return PTuple(Tuple(Loc::new(start, self.last_end), [], a))
    }
    let (first, annotated) = self.annot_expr()
    match self.tok {
      Star => {
        let cells = [first]
        while self.tok is Star {
          self.advance()
          cells.push(self.annot_expr().0)
        }
        if !(self.tok is ClParen) {
          self.fail()
        }
        self.advance()
        let a = self.annot()
        PTuple(Tuple(Loc::new(start, self.last_end), cells, a))
      }
      ClParen => {
        self.advance()
        let a = self.annot()
        PTuple(Tuple(Loc::new(start, self.last_end), [first], a))
      }
      Comma if !annotated => {
        let args = [first.expr]
        while self.tok is Comma {
          self.advance()
          args.push(self.type_expr())
        }
        if !(self.tok is ClParen) {
          self.fail()
        }
        self.advance()
        if !self.is_lident_or_kw() {
          self.fail()
        }
        PArgs(start, args)
      }
      _ => self.fail()
    }
  })
}

///|
/// `annot_expr: annot COLON type_expr | type_expr`
/// Also return whether the first form was used.
fn Parser::annot_expr(self : Parser) -> (Cell, Bool) raise Error {
  match self.tok {
    Lt | Colon => {
      let start = if self.tok is Lt {
        self.tok_loc.start
      } else {
        self.last_end
      }
      let a = self.annot()
      self.expect(Colon)
      let x = self.type_expr()
      ({ loc: Loc::new(start, self.last_end), expr: x, annot: a, }, true)
    }
    _ => {
      let x = self.type_expr()
      (
        { loc: Loc::new(x.loc().start, self.last_end), expr: x, annot: [], },
        false,
      )
    }
  }
}

///|
/// Parse a dotted type name applied to `args` and the annotation that
/// follows, building the type expression.
fn Parser::type_inst_rest(
  self : Parser,
  start : Pos,
  args : Array[TypeExpr],
) -> TypeExpr raise Error {
  let path = [self.lident_or_kw()]
  while self.tok is Dot {
    self.advance()
    path.push(self.lident_or_kw())
  }
  let inst_loc = Loc::new(start, self.last_end)
  let a = self.annot()
  let loc = Loc::new(start, self.last_end)
  let name = TypeName::new(path)
  let inst : TypeInst = { loc: inst_loc, name, args, }
  match (path, args) {
    (["list"], [x]) => List(loc, x, a)
    (["option"], [x]) => Option(loc, x, a)
    (["nullable"], [x]) => Nullable(loc, x, a)
    (["shared"], [x]) => {
      let a = if annot_has_field(a, sections=["share"], field="id") {
        a
      } else {
        annot_set_field(
          a,
          loc~,
          section="share",
          field="id",
          Some(annot_create_id()),
        )
      }
      Shared(loc, x, a)
    }
    (["wrap"], [x]) => Wrap(loc, x, a)
    (["list" | "option" | "nullable" | "shared" | "wrap"], _) =>
      error_at(loc, "\{name} expects one argument")
    _ => Name(loc, inst, a)
  }
}

///|
/// `variant_list: BAR variant_list0 | variant_list0`
fn Parser::variant_list(self : Parser) -> Array[Variant] raise Error {
  if self.tok is Bar {
    self.advance()
  }
  let res = [self.variant()]
  while self.tok is Bar {
    self.advance()
    res.push(self.variant())
  }
  res
}

///|
fn Parser::variant(self : Parser) -> Variant raise Error {
  let start = self.tok_loc.start
  match self.tok {
    Uident(x) => {
      self.advance()
      let a = self.annot()
      if self.tok is Of {
        self.advance()
        let t = self.frame("Expecting type expression after 'of'", () => {
          self.type_expr()
        })
        Variant(Loc::new(start, self.last_end), x, a, Some(t))
      } else {
        Variant(Loc::new(start, self.last_end), x, a, None)
      }
    }
    InheritKw => {
      self.advance()
      let t = self.type_expr()
      Inherit(Loc::new(start, self.last_end), t)
    }
    _ => self.fail()
  }
}

///|
fn Parser::starts_field(self : Parser) -> Bool {
  self.tok is (Lident(_) | From | ImportKw | As | Question | Tilde | InheritKw)
}

///|
/// `field_list: field SEMICOLON field_list | field SEMICOLON | field`
fn Parser::field_list(self : Parser) -> Array[Field] raise Error {
  let res = [self.field()]
  while self.tok is Semicolon {
    self.advance()
    if self.starts_field() {
      res.push(self.field())
    } else {
      break
    }
  }
  res
}

///|
fn Parser::field(self : Parser) -> Field raise Error {
  let start = self.tok_loc.start
  let kind : FieldKind = match self.tok {
    InheritKw => {
      self.advance()
      let t = self.type_expr()
      return Inherit(Loc::new(start, self.last_end), t)
    }
    Question => {
      self.advance()
      Optional
    }
    Tilde => {
      self.advance()
      WithDefault
    }
    _ => Required
  }
  let name = self.lident_or_kw()
  let a = self.annot()
  if !(self.tok is Colon) {
    self.frame("Expecting ':'", () => self.fail())
  }
  self.advance()
  let t = self.frame("Expecting type expression after ':'", () => {
    self.type_expr()
  })
  Field({ loc: Loc::new(start, self.last_end), name, kind, annot: a, expr: t, })
}

///|
/// Parse ATD source code (UTF-8 bytes) into a module, without any
/// semantic check.
pub fn parse_module(
  src : BytesView,
  pos_fname? : String = "",
  pos_lnum? : Int = 1,
) -> Module raise AtdError {
  let lexer = Lexer::new(src.to_owned(), fname=pos_fname, lnum=pos_lnum)
  let parser = Parser::new(lexer) catch {
    AtdError(_) as e => raise e
    _ => abort("unexpected error")
  }
  parser.module_() catch {
    RawSyntaxError(_) => {
      let pos = parser.tok_loc.end_
      error("Syntax error:\n" + string_of_loc(Loc::new(pos, pos)))
    }
    AtdError(_) as e => raise e
    _ => abort("unexpected error")
  }
}
