// Ported from easy-format's examples/lambda_example.ml (https://github.com/ocaml-community/easy-format);
// the expected output is the output of the OCaml program.

///|
priv enum Lambda {
  Lambda(String, Lambda)
  Var(String)
  Apply(Lambda, Lambda)
}

///|
/// \n f x. n (\g h. h (g f)) (\u. x) (\u. u)
let sample_data : Lambda = Lambda(
  "n",
  Lambda(
    "f",
    Lambda(
      "x",
      Apply(
        Apply(
          Apply(
            Var("n"),
            Lambda("g", Lambda("h", Apply(Var("h"), Apply(Var("g"), Var("f"))))),
          ),
          Lambda("u", Var("x")),
        ),
        Lambda("u", Var("u")),
      ),
    ),
  ),
)

// Example from http://caml.inria.fr/resources/doc/guides/format.html using
// Format directly

///|
fn pr_exp0(ppf : @format.Formatter, x : Lambda) -> Unit {
  match x {
    Var(s) => ppf.print_string(s)
    lam => ppf.printf("@[<1>(%a)@]", [Print(ppf => pr_lambda(ppf, lam))])
  }
}

///|
fn pr_app(ppf : @format.Formatter, e : Lambda) -> Unit {
  ppf.printf("@[<2>%a@]", [Print(ppf => pr_other_applications(ppf, e))])
}

///|
fn pr_other_applications(ppf : @format.Formatter, f : Lambda) -> Unit {
  match f {
    Apply(f, arg) =>
      ppf.printf("%a@ %a", [
        Print(ppf => pr_app(ppf, f)),
        Print(ppf => pr_exp0(ppf, arg)),
      ])
    f => pr_exp0(ppf, f)
  }
}

///|
fn pr_lambda(ppf : @format.Formatter, x : Lambda) -> Unit {
  match x {
    Lambda(s, lam) =>
      ppf.printf("@[<1>%a%a%a@ %a@]", [
        Print(ppf => ppf.print_string("\\")),
        Print(ppf => ppf.print_string(s)),
        Print(ppf => ppf.print_string(".")),
        Print(ppf => pr_lambda(ppf, lam)),
      ])
    e => pr_app(ppf, e)
  }
}

// Same example, using easy_format

///|
let p1 : @easy_format.LabelParam = {
  ..@easy_format.label,
  indent_after_label: 1,
}

///|
let p2 : @easy_format.LabelParam = {
  ..@easy_format.label,
  indent_after_label: 2,
}

///|
let paren_style : @easy_format.ListParam = {
  ..@easy_format.list,
  space_after_opening: false,
  space_before_closing: false,
  align_closing: false,
}

///|
fn exp0_node(x : Lambda) -> @easy_format.T {
  match x {
    Var(s) => Atom(s, @easy_format.atom)
    lam => List(("(", "", ")", paren_style), [lambda_node(lam)])
  }
}

///|
fn app_node(x : Lambda) -> @easy_format.T {
  match x {
    Apply(f, arg) => Label((app_node(f), p2), exp0_node(arg))
    f => exp0_node(f)
  }
}

///|
fn lambda_node(x : Lambda) -> @easy_format.T {
  match x {
    Lambda(s, lam) =>
      Label((Atom("\\\{s}.", @easy_format.atom), p1), lambda_node(lam))
    e => app_node(e)
  }
}

///|
test "lambda_example" {
  let stdout = StringBuilder()
  // the standard formatter, with a narrow page for illustration purposes
  let std_formatter = @format.Formatter::of_buffer(stdout)
  std_formatter.set_margin(20)
  stdout.write_string(
    "Example from http://caml.inria.fr/resources/doc/guides/format.html#example\n",
  )
  pr_lambda(std_formatter, sample_data)
  std_formatter.print_flush()
  std_formatter.print_newline()
  stdout.write_string("Same, using Easy_format:\n")
  // `Pretty.to_stdout` uses a new formatter (with the default margin)
  @easy_format.to_buffer(stdout, lambda_node(sample_data))
  std_formatter.print_newline()
  assert_eq(
    stdout.to_string(),
    (
      #|Example from http://caml.inria.fr/resources/doc/guides/format.html#example
      #|\n.
      #| \f.
      #|  \x.
      #|   n
      #|     (\g.
      #|       \h. h (g f))
      #|     (\u. x)
      #|     (\u. u)
      #|Same, using Easy_format:
      #|\n. \f. \x. n (\g. \h. h (g f)) (\u. x) (\u. u)
      #|
    ),
  )
}
