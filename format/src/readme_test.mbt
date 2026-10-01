///|
test "README examples" {
  let doc = @format.asprintf("@[<hov 2>let x =@ %a@]", [
    Print(ppf => {
      ppf.print_list(
        pp_sep=ppf => ppf.printf(";@ ", []),
        @format.Formatter::print_int,
        @list.List([1, 2, 3]),
      )
    }),
  ])
  inspect(doc, content="let x = 1; 2; 3")
  let buf = StringBuilder()
  let ppf = @format.Formatter::of_buffer(buf)
  ppf.printf("@[<v 2>%s:@,%5.2f@,%a@]", [
    String("total"),
    Float(3.14159),
    Print(ppf => ppf.print_bool(true)),
  ])
  ppf.print_flush()
  inspect(
    buf.to_string(),
    content=(
      #|total:
      #|   3.14
      #|  true
    ),
  )
  inspect(
    @format.asprintf("%-8s|%08.3e|%#x", [String("a"), Float(-1.5), Int(255)]),
    content="a       |-1.500e+00|0xff",
  )
  inspect(@format.sprintf("%x", [Int(-1)]), content="7fffffffffffffff")
  inspect(@format.format_float_c(1.0 / 3.0, 'e', 6), content="3.333333e-01")
}

///|
test "check_format" {
  @format.check_format("@[<hov 2>%d@ %s@]")
  let msg = try {
    @format.check_format("%{%d")
    ""
  } catch {
    Failure(msg) => msg
  }
  inspect(
    msg,
    content=(
      #|invalid format "%{%d": unclosed sub-format, expected "%}" at character number 4
    ),
  )
}
