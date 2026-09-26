// atdcat: check syntax, reformat, expand inherited definitions, export to
// JSON Schema, ...
//
// This runs on the native and wasm backends; the latter is what `moonx`
// uses.

///|
priv suberror ReadError {
  ReadError(String)
}

///|
impl Show for ReadError with fn output(self, logger) {
  match self {
    ReadError(msg) => logger.write_string(msg)
  }
}

///|
async fn main {
  let args = @env.args()
  // Read the input files first, since the core of atdcat is synchronous.
  let files : Map[String, Result[Bytes, String]] = Map([])
  let mut stdin : Bytes? = None
  for path in @atdcat_lib.input_files(args) {
    match path {
      None =>
        if stdin is None {
          stdin = Some(@stdio.stdin.read_all().binary())
        }
      Some(p) =>
        if !files.contains(p) {
          files[p] = try @fs.read_file(p).binary() catch {
            e => Err("atdcat: cannot read \{p}: \{e}")
          } noraise {
            b => Ok(b)
          }
        }
    }
  }
  let out = StringBuilder()
  let err = StringBuilder()
  let outputs : Array[(String, String)] = []
  let io : @atdcat_lib.Io = {
    read_file: path => {
      match path {
        None => stdin.unwrap_or(b"")
        Some(p) =>
          match files.get(p) {
            Some(Ok(b)) => b
            Some(Err(msg)) => raise ReadError(msg)
            None => raise ReadError("atdcat: cannot read \{p}")
          }
      }
    },
    write_file: (path, contents) => outputs.push((path, contents)),
    print_out: s => out.write_string(s),
    print_err: s => err.write_string(s),
  }
  let code = @atdcat_lib.run(io, args)
  for o in outputs {
    @fs.write_file(o.0, o.1)
  }
  @stdio.stderr.write(err.to_string())
  @stdio.stdout.write(out.to_string())
  if code != 0 {
    @sys.exit(code)
  }
}
