///|
/// Run atdcat on in-memory files and compare its output with the expected
/// output of the reference implementation.
fn check_atdcat(
  inputs : Map[String, String],
  args : Array[String],
  stdin~ : String,
  stdout~ : String,
  stderr~ : String,
  code~ : Int,
) -> Unit raise {
  let out = StringBuilder()
  let err = StringBuilder()
  let io : @atdcat.Io = {
    read_file: path => {
      let path = match path {
        Some(p) => p
        None => stdin
      }
      match inputs.get(path) {
        Some(content) => @utf8.encode(content)
        None => fail("no such file: " + path)
      }
    },
    write_file: (_, _) => fail("unexpected write"),
    print_out: s => out.write_string(s),
    print_err: s => err.write_string(s),
  }
  let exit_code = @atdcat.run(io, ["atdcat", ..args])
  assert_eq(err.to_string(), stderr)
  assert_eq(out.to_string(), stdout)
  assert_eq(exit_code, code)
}

///|
test "input files" {
  debug_inspect(@atdcat.input_files(["atdcat"]), content="[None]")
  debug_inspect(
    @atdcat.input_files(["atdcat", "-ml", "foo", "a.atd", "-o", "out", "b.atd"]),
    content=(
      #|[Some("b.atd"), Some("a.atd")]
    ),
  )
  debug_inspect(
    @atdcat.input_files(["atdcat", "-jsonschema", "root", "a.atd"]),
    content=(
      #|[Some("a.atd")]
    ),
  )
  debug_inspect(
    @atdcat.input_files(["atdcat", "-version", "a.atd"]),
    content="[]",
  )
}
