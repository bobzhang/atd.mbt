// Tests ported from OCaml's testsuite/tests/lib-format: the expected
// outputs are the `.reference` files of the OCaml testsuite.

///|
let example : Array[String] = [
  "Foo", "Baz", "Bar", "Qux", "Quux", "Quuz", "Corge", "Grault", "Garply",
]

///|
/// The output of `pp_print_custom_break.ml` for one of its modules.
fn custom_break_test(
  ppf : @format.Formatter,
  title : String,
  format : (String) -> (@format.Formatter) -> Unit,
) -> Unit {
  ppf.printf(title, [])
  for box in ["v", "b", "h", "hv", "hov"] {
    ppf.printf("## The %S box@\n```@\n@[<%s 0>%a@]@\n```@\n@\n", [
      String(box),
      String(box),
      Print(format(box)),
    ])
  }
}

///|
test "pp_print_custom_break" {
  let buf = StringBuilder()
  let ppf = @format.Formatter::of_buffer(buf)
  ppf.set_margin(30)
  // Printing arrays: last trailing semicolon is optional
  custom_break_test(
    ppf,
    "# Printing arrays: last trailing semicolon is optional@\n@\n",
    box_type => {
      ppf => {
        ppf.printf("[@;<0 2>@[<%s>%a@]%t]", [
          String(box_type),
          Print(ppf => {
            ppf.print_array(
              pp_sep=ppf => ppf.printf(";@ ", []),
              @format.Formatter::print_string,
              example,
            )
          }),
          Print(ppf => {
            ppf.print_custom_break(fits=("", 0, ""), breaks=(";", 0, ""))
          }),
        ])
      }
    },
  )
  // Printing statements: terminator is optional after newline
  custom_break_test(
    ppf,
    "# Printing statements: terminator is optional after newline@\n@\n",
    box_type => {
      ppf => {
        ppf.printf("{@;<0 2>@[<%s>%a@]@,}", [
          String(box_type),
          Print(ppf => {
            ppf.print_array(
              pp_sep=ppf => {
                ppf.print_custom_break(fits=(";", 1, ""), breaks=("", 0, ""))
              },
              @format.Formatter::print_string,
              example,
            )
          }),
        ])
      }
    },
  )
  // Printing function: first pipe character is optional
  custom_break_test(
    ppf,
    "# Printing function: first pipe character is optional@\n@\n",
    box_type => {
      ppf => {
        ppf.printf("@[<%s>function%t%a@]", [
          String(box_type),
          Print(ppf => {
            ppf.print_custom_break(fits=("", 1, ""), breaks=("", 0, "| "))
          }),
          Print(ppf => {
            ppf.print_array(
              pp_sep=ppf => ppf.printf("@ | ", []),
              (ppf, s) => ppf.printf("%s -> ()", [String(s)]),
              example,
            )
          }),
        ])
      }
    },
  )
  ppf.print_flush()
  assert_eq(
    buf.to_string(),
    (
      #|# Printing arrays: last trailing semicolon is optional
      #|
      #|## The "v" box
      #|```
      #|[
      #|  Foo;
      #|  Baz;
      #|  Bar;
      #|  Qux;
      #|  Quux;
      #|  Quuz;
      #|  Corge;
      #|  Grault;
      #|  Garply;
      #|]
      #|```
      #|
      #|## The "b" box
      #|```
      #|[
      #|  Foo; Baz; Bar; Qux; Quux;
      #|  Quuz; Corge; Grault; Garply;
      #|]
      #|```
      #|
      #|## The "h" box
      #|```
      #|[Foo; Baz; Bar; Qux; Quux; Quuz; Corge; Grault; Garply]
      #|```
      #|
      #|## The "hv" box
      #|```
      #|[
      #|  Foo;
      #|  Baz;
      #|  Bar;
      #|  Qux;
      #|  Quux;
      #|  Quuz;
      #|  Corge;
      #|  Grault;
      #|  Garply;
      #|]
      #|```
      #|
      #|## The "hov" box
      #|```
      #|[
      #|  Foo; Baz; Bar; Qux; Quux;
      #|  Quuz; Corge; Grault; Garply;
      #|]
      #|```
      #|
      #|# Printing statements: terminator is optional after newline
      #|
      #|## The "v" box
      #|```
      #|{
      #|  Foo
      #|  Baz
      #|  Bar
      #|  Qux
      #|  Quux
      #|  Quuz
      #|  Corge
      #|  Grault
      #|  Garply
      #|}
      #|```
      #|
      #|## The "b" box
      #|```
      #|{
      #|  Foo; Baz; Bar; Qux; Quux
      #|  Quuz; Corge; Grault; Garply
      #|}
      #|```
      #|
      #|## The "h" box
      #|```
      #|{Foo; Baz; Bar; Qux; Quux; Quuz; Corge; Grault; Garply}
      #|```
      #|
      #|## The "hv" box
      #|```
      #|{
      #|  Foo
      #|  Baz
      #|  Bar
      #|  Qux
      #|  Quux
      #|  Quuz
      #|  Corge
      #|  Grault
      #|  Garply
      #|}
      #|```
      #|
      #|## The "hov" box
      #|```
      #|{
      #|  Foo; Baz; Bar; Qux; Quux
      #|  Quuz; Corge; Grault; Garply
      #|}
      #|```
      #|
      #|# Printing function: first pipe character is optional
      #|
      #|## The "v" box
      #|```
      #|function
      #|| Foo -> ()
      #|| Baz -> ()
      #|| Bar -> ()
      #|| Qux -> ()
      #|| Quux -> ()
      #|| Quuz -> ()
      #|| Corge -> ()
      #|| Grault -> ()
      #|| Garply -> ()
      #|```
      #|
      #|## The "b" box
      #|```
      #|function Foo -> ()
      #|| Baz -> () | Bar -> ()
      #|| Qux -> () | Quux -> ()
      #|| Quuz -> () | Corge -> ()
      #|| Grault -> () | Garply -> ()
      #|```
      #|
      #|## The "h" box
      #|```
      #|function Foo -> () | Baz -> () | Bar -> () | Qux -> () | Quux -> () | Quuz -> () | Corge -> () | Grault -> () | Garply -> ()
      #|```
      #|
      #|## The "hv" box
      #|```
      #|function
      #|| Foo -> ()
      #|| Baz -> ()
      #|| Bar -> ()
      #|| Qux -> ()
      #|| Quux -> ()
      #|| Quuz -> ()
      #|| Corge -> ()
      #|| Grault -> ()
      #|| Garply -> ()
      #|```
      #|
      #|## The "hov" box
      #|```
      #|function Foo -> ()
      #|| Baz -> () | Bar -> ()
      #|| Qux -> () | Quux -> ()
      #|| Quuz -> () | Corge -> ()
      #|| Grault -> () | Garply -> ()
      #|```
      #|
      #|
    ),
  )
}

///|
test "pr6824" {
  let f = (n : Int) => @format.sprintf("[%i]", [Int(n)])
  assert_eq(f(1), "[1]")
  assert_eq(f(2), "[2]")
  let f = (n : Int) => @format.asprintf("[%i]", [Int(n)])
  assert_eq(f(1), "[1]")
  assert_eq(f(2), "[2]")
}

///|
test "print_if_newline" {
  let buf = StringBuilder()
  let ppf = @format.Formatter::of_buffer(buf)
  ppf.printf("\ntest print_if_newline\n%!", [])
  ppf.printf("  newline here\n%!", [])
  ppf.print_if_newline()
  ppf.printf("  this gets printed", [])
  ppf.print_if_newline()
  ppf.printf("  this doesn't get printed", [])
  ppf.printf("\nprint_if_newline doesn't crash when last statement\n%!", [])
  ppf.printf("  newline here\n", [])
  // print_if_newline doesn't crash when it is the last statement
  ppf.print_if_newline()
  // at exit, OCaml flushes the standard formatter
  ppf.print_flush()
  assert_eq(
    buf.to_string(),
    (
      #|
      #|test print_if_newline
      #|  newline here
      #|  this gets printed
      #|print_if_newline doesn't crash when last statement
      #|  newline here
      #|
    ),
  )
}

///|
test "print_seq" {
  let pp_print_intseq = (ppf : @format.Formatter, seq : Iter[Int]) => {
    ppf.print_iter(
      pp_sep=ppf => ppf.print_char(' '),
      @format.Formatter::print_int,
      seq,
    )
  }
  // empty
  assert_eq(
    @format.asprintf("%a%!", [Print(ppf => pp_print_intseq(ppf, Iter::empty()))]),
    "",
  )
  // misc
  assert_eq(
    @format.asprintf("%a", [Print(ppf => pp_print_intseq(ppf, [0].iter()))]),
    "0",
  )
  assert_eq(
    @format.asprintf("%a", [
      Print(ppf => pp_print_intseq(ppf, [0, 1, 2].iter())),
    ]),
    "0 1 2",
  )
  assert_eq(
    @format.asprintf("%a", [Print(ppf => pp_print_intseq(ppf, [0, 0].iter()))]),
    "0 0",
  )
}

///|
test "kprintf and kasprintf" {
  let buf = StringBuilder()
  let ppf = @format.Formatter::of_buffer(buf)
  let n = ppf.kprintf(
    ppf => {
      ppf.print_flush()
      buf.to_string().length()
    },
    "@[%s@ %d@]",
    [String("x"), Int(1)],
  )
  assert_eq(n, 3)
  assert_eq(
    @format.kasprintf(s => s + "!", "@[%a@]", [
      Print(ppf => ppf.print_text("a b")),
    ]),
    "a b!",
  )
  // like in OCaml, a break hint outside of any box is a newline when the
  // formatter is flushed
  assert_eq(
    @format.asprintf("%a", [Print(ppf => ppf.print_text("a b"))]),
    "a\nb",
  )
}

///|
test "texts of unknown size don't overflow" {
  // Texts of negative size count for a large value in the computations of
  // the engine: three of them would overflow 32-bit integers (found by
  // fuzzing, the expected outputs are OCaml's).
  let buf = StringBuilder()
  let ppf = @format.Formatter::of_buffer(buf)
  ppf.print_as(-2, "a")
  ppf.print_string("x".repeat(80))
  ppf.print_as(-2, "a")
  ppf.print_as(-2, "a")
  ppf.print_break(1, 1)
  ppf.print_flush()
  assert_eq(buf.to_string(), "a" + "x".repeat(80) + "aa\n ")
  // the widths of boxes opened after such texts
  buf.reset()
  ppf.open_box(0)
  ppf.print_as(-2, "a")
  ppf.print_string("x".repeat(80))
  ppf.print_as(-2, "a")
  ppf.open_hovbox(0)
  ppf.print_as(-2, "a")
  ppf.print_as(-2, "a")
  ppf.open_box(0)
  ppf.print_string("z")
  ppf.print_cut()
  ppf.print_string("z")
  ppf.close_box()
  ppf.close_box()
  ppf.print_break(1, 1)
  ppf.print_string("y")
  ppf.close_box()
  ppf.print_flush()
  assert_eq(buf.to_string(), "a" + "x".repeat(80) + "a\naa\nz\nz\n y")
}

///|
test "set_output_functions" {
  // like in OCaml, newlines and spaces go through the current output
  // function of a formatter made by `Formatter(output)`
  let buf = StringBuilder()
  let ppf = @format.Formatter::of_buffer(buf)
  let (out_string, out_flush) = ppf.get_output_functions()
  ppf.set_output_functions(s => out_string(s.to_owned().to_upper()), out_flush)
  ppf.printf("@[<v 2>a@,b@]@.", [])
  ppf.set_output_functions(s => out_string("[" + s.to_owned() + "]"), out_flush)
  ppf.printf("@[<v 2>a@,b@]@.", [])
  assert_eq(buf.to_string(), "A\n  B\n[a][\n][  ][b][\n]")
}
