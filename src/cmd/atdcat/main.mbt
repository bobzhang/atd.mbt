// atdcat: check syntax, reformat, expand inherited definitions, export to
// JSON Schema, ...

///|
fn main {
  let io : @atdcat_lib.Io = {
    read_file: path => {
      match path {
        None => @stdin.read_all()
        Some(path) => @fs.read_file_to_bytes(path)
      }
    },
    write_file: (path, contents) => @fs.write_string_to_file(path, contents),
    print_out: s => print_string(s),
    print_err: s => eprint_string(s),
  }
  let code = @atdcat_lib.run(io, @env.args())
  if code != 0 {
    @sys.exit(code)
  }
}

///|
fn print_string(s : String) -> Unit {
  if s.has_suffix("\n") {
    println(s.view(end_offset=s.length() - 1))
  } else if s != "" {
    println(s)
  }
}

///|
fn eprint_string(s : String) -> Unit {
  if s.has_suffix("\n") {
    eprintln(s.view(end_offset=s.length() - 1))
  } else if s != "" {
    eprintln(s)
  }
}
