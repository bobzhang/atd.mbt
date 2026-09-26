// atdmbt: generate MoonBit code from ATD type definitions.
//
// This runs on the native and wasm backends; the latter is what `moonx`
// uses.

///|
priv suberror Exit {
  Exit(Int)
}

///|
let usage : String =
  #|Usage: atdmbt [OPTIONS] FILE.atd [FILE.atd ...]
  #|
  #|Generate MoonBit type definitions and JSON readers and writers from
  #|ATD files. For each input file 'foo.atd', the file 'foo.mbt' is created
  #|in the current directory, unless an output file is specified with -o.
  #|
  #|The generated code requires the package "bobzhang/atd/runtime",
  #|imported with the alias 'atd_runtime' in the moon.pkg file of the
  #|package containing the generated code.
  #|
  #|Options:
  #|  -o <path>    write to this file (only for a single input file);
  #|               use '-' for stdout
  #|  -version     print the version and exit
  #|  -help        print this help and exit

///|
async fn run(args : ArrayView[String]) -> Unit {
  let inputs = []
  let mut output : String? = None
  let mut i = 1
  while i < args.length() {
    match args[i] {
      "-o" | "--output" => {
        i += 1
        if i >= args.length() {
          @stdio.stderr.write(
            "atdmbt: option '-o' needs an argument.\n" + usage + "\n",
          )
          raise Exit(2)
        }
        output = Some(args[i])
      }
      "-version" | "--version" => {
        @stdio.stdout.write(@atd.version + "\n")
        raise Exit(0)
      }
      "-help" | "--help" | "-h" => {
        @stdio.stdout.write(usage + "\n")
        raise Exit(0)
      }
      arg =>
        if arg.has_prefix("-") {
          @stdio.stderr.write(
            "atdmbt: unknown option '\{arg}'.\n" + usage + "\n",
          )
          raise Exit(2)
        } else {
          inputs.push(arg)
        }
    }
    i += 1
  }
  if inputs.is_empty() {
    @stdio.stderr.write(usage + "\n")
    raise Exit(2)
  }
  if output is Some(_) && inputs.length() > 1 {
    @stdio.stderr.write("atdmbt: option '-o' requires a single input file.\n")
    raise Exit(2)
  }
  for input in inputs {
    let src = @fs.read_file(input).binary()
    let basename = match input.rev_find("/") {
      Some(i) => input.view(start_offset=i + 1).to_owned()
      None => input
    }
    let code = @mbtgen.generate(src, atd_filename=basename, pos_fname=input)
    match output {
      Some("-") => @stdio.stdout.write(code)
      Some(path) => @fs.write_file(path, code)
      None => @fs.write_file(@mbtgen.output_file_name(input), code)
    }
  }
}

///|
async fn main {
  run(@env.args()) catch {
    Exit(code) => @sys.exit(code)
    @atd.AtdError(msg) => {
      @stdio.stderr.write(msg + "\n")
      @sys.exit(1)
    }
    e => {
      @stdio.stderr.write("atdmbt: \{e}\n")
      @sys.exit(2)
    }
  }
}
