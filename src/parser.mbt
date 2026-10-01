// Recursive-descent parser for ATD, a port of the Menhir grammar
// `parser.mly`.
//
// Locations follow Menhir's conventions: a production starts at the start
// of its first symbol, or at the end of the previous token if the first
// symbol derives the empty string; it ends at the end of the last token
// consumed.
//
// Error reporting emulates Menhir's "simplified" error-handling strategy,
// which upstream relies on to produce messages such as "Expecting '='":
// when a syntax error is detected, only reductions are performed, without
// popping the stack. Therefore a specific message is produced only if the
// error occurs exactly at a grammar position that has an `error`
// alternative (possibly after completing the constructs that end there).
// Such positions call `Parser::fail_with`. Other errors produce a generic
// "Syntax error" message.

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
fn Parser::Parser(lexer : Lexer) -> Parser raise Error {
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
/// Fail at a grammar position that has an `error` alternative.
fn[T] Parser::fail_with(self : Parser, msg : String) -> T raise Error {
  error_at(self.tok_loc, msg)
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
fn Parser::starts_type_expr(self : Parser) -> Bool {
  self.tok is (OpBrack | OpCurl | OpParen | Tident(_)) || self.is_lident_or_kw()
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
  if !self.is_lident_or_kw() {
    self.fail_with("Expecting lowercase identifier")
  }
  let name = self.lident_or_kw()
  let fields = []
  while self.is_lident_or_kw() {
    fields.push(self.afield())
  }
  if !(self.tok is Gt) {
    self.fail_with("Expecting '>'")
  }
  self.advance()
  { name, loc: Loc(start, self.last_end), fields, }
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
        { name, loc: Loc(start, self.last_end), value: Some(s), }
      }
      _ => self.fail()
    }
  } else {
    { name, loc: Loc(start, self.last_end), value: None, }
  }
}

///|
/// Parse a complete module.
fn Parser::module_(self : Parser) -> Module raise Error {
  let an_start = if self.tok is Lt { self.tok_loc.start } else { self.last_end }
  let an = self.annot()
  let head_loc = Loc(an_start, self.last_end)
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
  if !self.is_lident_or_kw() {
    self.fail_with("Expecting module name after 'from'")
  }
  let path = [self.lident_or_kw()]
  while self.tok is Dot {
    self.advance()
    path.push(self.lident_or_kw())
  }
  let annot = self.annot()
  let alias_ = if self.tok is As {
    self.advance()
    if !self.is_lident_or_kw() {
      self.fail_with("Expecting module alias after 'as'")
    }
    Some(self.lident_or_kw())
  } else {
    None
  }
  self.expect(ImportKw)
  let types = [self.imported_type_item()]
  while self.tok is Comma {
    self.advance()
    types.push(self.imported_type_item())
  }
  Import::new(loc=Loc(start, self.last_end), path~, annot~, alias_?, types~)
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
      if !(self.tok is Tident(_)) {
        self.fail_with("Expecting type variable list")
      }
      let ps = self.type_var_list()
      self.expect(ClParen)
      let name = self.lident_or_kw()
      let annot = self.annot()
      { params: ps, name, annot, }
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
  let param = match self.tok {
    Tident(s) => {
      self.advance()
      [s]
    }
    OpParen => {
      self.advance()
      let l = self.type_var_list()
      if !(self.tok is ClParen) {
        self.fail_with("Expecting ')'")
      }
      self.advance()
      l
    }
    _ => {
      if !self.is_lident_or_kw() {
        self.fail_with("Expecting type name")
      }
      []
    }
  }
  let name = self.lident_or_kw()
  let annot = self.annot()
  if !(self.tok is EqTok) {
    self.fail_with("Expecting '='")
  }
  self.advance()
  if !self.starts_type_expr() {
    self.fail_with("Expecting type expression")
  }
  let value = self.type_expr(TopDef)
  let orig : TypeDef = {
    loc: Loc(start, self.last_end),
    name: TypeName::simple(name),
    param,
    annot,
    value,
    orig: None,
  }
  { ..orig, orig: Some(orig), }
}

///|
/// The syntactic context of a type expression, which determines the tokens
/// on which Menhir reduces it (and runs its semantic action).
priv enum Ctx {
  /// Right-hand side of a type definition
  TopDef
  /// First cell of a parenthesized expression, not annotated
  ParenFirst
  /// First cell of a parenthesized expression, annotated
  ParenFirstAnnotated
  /// Contexts where the expression can also be reduced on the error token
  ErrorFollow
}

///|
/// Result of parsing a parenthesized construct: either a complete tuple
/// type or a list of type arguments that must be followed by a type name.
priv enum Paren {
  PTuple(TypeExpr)
  PArgs(Pos, Array[TypeExpr])
}

///|
fn Parser::type_expr(self : Parser, ctx : Ctx) -> TypeExpr raise Error {
  let start = self.tok_loc.start
  let base = match self.tok {
    OpBrack => {
      self.advance()
      if self.tok is ClBrack {
        self.advance()
        let a = self.annot()
        Sum(Loc(start, self.last_end), [], a)
      } else {
        let l = self.variant_list()
        if !(self.tok is ClBrack) {
          self.fail_with("Expecting ']'")
        }
        self.advance()
        let a = self.annot()
        Sum(Loc(start, self.last_end), l, a)
      }
    }
    OpCurl => {
      self.advance()
      if self.tok is ClCurl {
        self.advance()
        let a = self.annot()
        Record(Loc(start, self.last_end), [], a)
      } else {
        let l = self.field_list()
        if !(self.tok is ClCurl) {
          self.fail_with("Expecting '}'")
        }
        self.advance()
        let a = self.annot()
        Record(Loc(start, self.last_end), l, a)
      }
    }
    OpParen =>
      match self.paren() {
        PTuple(t) => t
        PArgs(start, args) => self.type_inst_rest(start, args, ctx)
      }
    Tident(s) => {
      self.advance()
      Tvar(Loc(start, self.last_end), s)
    }
    Lident(_) | From | ImportKw | As =>
      // empty type_args: the production starts at the end of the previous
      // token
      self.type_inst_rest(self.last_end, [], ctx)
    _ => self.fail()
  }
  let mut t = base
  while self.is_lident_or_kw() {
    t = self.type_inst_rest(t.loc().start, [t], ctx)
  }
  t
}

///|
fn Parser::starts_annot_expr(self : Parser) -> Bool {
  self.tok is (Lt | Colon) || self.starts_type_expr()
}

///|
/// Parse the parenthesized part of a type expression, after `(`:
/// a tuple, or a list of type arguments.
///
/// The grammar is:
/// ```text
/// type_expr: OP_PAREN annot_expr CL_PAREN annot
///          | OP_PAREN cartesian_product CL_PAREN annot
///          | OP_PAREN cartesian_product error
/// cartesian_product: annot_expr STAR cartesian_product
///                  | annot_expr STAR annot_expr
///                  | (empty)
/// type_args: OP_PAREN type_arg_list CL_PAREN
///          | OP_PAREN type_arg_list error
/// type_arg_list: type_expr COMMA type_arg_list | type_expr COMMA type_expr
/// ```
fn Parser::paren(self : Parser) -> Paren raise Error {
  let start = self.tok_loc.start
  self.advance() // OP_PAREN
  let finish_tuple = (cells : Array[Cell]) => {
    self.advance() // CL_PAREN
    let a = self.annot()
    PTuple(Tuple(Loc(start, self.last_end), cells, a))
  }
  if self.tok is ClParen {
    // empty cartesian product
    return finish_tuple([])
  }
  if !self.starts_annot_expr() {
    // the empty cartesian product can be reduced
    self.fail_with("Expecting ')'")
  }
  let (first, annotated) = self.annot_expr(first=true)
  match self.tok {
    Star => {
      let cells = [first]
      while self.tok is Star {
        self.advance()
        if self.starts_annot_expr() {
          cells.push(self.annot_expr(first=false).0)
        } else if self.tok is ClParen {
          // empty cartesian product after the star
          break
        } else {
          self.fail_with("Expecting ')'")
        }
      }
      if !(self.tok is ClParen) {
        self.fail_with("Expecting ')'")
      }
      finish_tuple(cells)
    }
    ClParen => finish_tuple([first])
    Comma if !annotated => {
      let args = [first.expr]
      while self.tok is Comma {
        self.advance()
        args.push(self.type_expr(ErrorFollow))
      }
      if !(self.tok is ClParen) {
        self.fail_with("Expecting ')'")
      }
      self.advance()
      if !self.is_lident_or_kw() {
        self.fail()
      }
      PArgs(start, args)
    }
    _ => self.fail()
  }
}

///|
/// `annot_expr: annot COLON type_expr | type_expr`
/// Also return whether the first form was used.
fn Parser::annot_expr(self : Parser, first~ : Bool) -> (Cell, Bool) raise Error {
  match self.tok {
    Lt | Colon => {
      let start = if self.tok is Lt {
        self.tok_loc.start
      } else {
        self.last_end
      }
      let a = self.annot()
      self.expect(Colon)
      let x = self.type_expr(
        if first {
          ParenFirstAnnotated
        } else {
          ErrorFollow
        },
      )
      ({ loc: Loc(start, self.last_end), expr: x, annot: a, }, true)
    }
    _ => {
      let x = self.type_expr(if first { ParenFirst } else { ErrorFollow })
      ({ loc: Loc(x.loc().start, self.last_end), expr: x, annot: [], }, false)
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
  ctx : Ctx,
) -> TypeExpr raise Error {
  let path = [self.lident_or_kw()]
  while self.tok is Dot {
    self.advance()
    path.push(self.lident_or_kw())
  }
  let inst_loc = Loc(start, self.last_end)
  let a = self.annot()
  let loc = Loc(start, self.last_end)
  let name = TypeName(path)
  let inst : TypeInst = { loc: inst_loc, name, args, }
  if path is ["list" | "option" | "nullable" | "shared" | "wrap"] &&
    !self.can_reduce(ctx) {
    // Menhir would detect the syntax error before running the semantic
    // action of this production
    self.fail()
  }
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
/// Whether Menhir reduces a type expression in context `ctx`, given the
/// current lookahead token.
fn Parser::can_reduce(self : Parser, ctx : Ctx) -> Bool {
  self.is_lident_or_kw() ||
  (match ctx {
    TopDef => self.tok is (TypeKw | Eof)
    ParenFirst => self.tok is (Star | ClParen | Comma)
    ParenFirstAnnotated => self.tok is (Star | ClParen)
    ErrorFollow => true
  })
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
        if !self.starts_type_expr() {
          self.fail_with("Expecting type expression after 'of'")
        }
        let t = self.type_expr(ErrorFollow)
        Variant(Loc(start, self.last_end), x, a, Some(t))
      } else {
        Variant(Loc(start, self.last_end), x, a, None)
      }
    }
    InheritKw => {
      self.advance()
      let t = self.type_expr(ErrorFollow)
      Inherit(Loc(start, self.last_end), t)
    }
    _ => self.fail()
  }
}

///|
fn Parser::starts_field(self : Parser) -> Bool {
  self.tok is (Question | Tilde | InheritKw) || self.is_lident_or_kw()
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
      let t = self.type_expr(ErrorFollow)
      return Inherit(Loc(start, self.last_end), t)
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
    self.fail_with("Expecting ':'")
  }
  self.advance()
  if !self.starts_type_expr() {
    self.fail_with("Expecting type expression after ':'")
  }
  let t = self.type_expr(ErrorFollow)
  Field({ loc: Loc(start, self.last_end), name, kind, annot: a, expr: t, })
}

///|
/// Parse ATD source code (UTF-8 bytes) into a module, without any
/// semantic check.
pub fn parse_module(
  src : BytesView,
  pos_fname? : String = "",
  pos_lnum? : Int = 1,
) -> Module raise AtdError {
  let lexer = Lexer(src.to_owned(), fname=pos_fname, lnum=pos_lnum)
  let parser = Parser(lexer) catch {
    AtdError(_) as e => raise e
    _ => abort("unexpected error")
  }
  parser.module_() catch {
    RawSyntaxError(_) => {
      let pos = parser.tok_loc.end_
      error("Syntax error:\n" + string_of_loc(Loc(pos, pos)))
    }
    AtdError(_) as e => raise e
    _ => abort("unexpected error")
  }
}
