// The atdcat command: check syntax, reformat, expand inherited definitions, export to
// JSON Schema, ... A port of `atdcat/src/atdcat.ml`.

///|
/// Input/output functions used by `run`.
pub(all) struct Io {
  /// Read a file, or standard input if the path is `None`.
  read_file : (String?) -> Bytes raise
  write_file : (String, String) -> Unit raise
  /// Print on standard output
  print_out : (String) -> Unit
  /// Print on standard error
  print_err : (String) -> Unit
}

///|
priv enum OutFormat {
  Atd
  Ocaml(String)
  Jsonschema(String)
}

///|
priv suberror Exit {
  Exit(Int)
}

///|
let usage_options : String = [
  "  -o <path>", "          write to this file instead of stdout", "  -x ", "          make type expressions monomorphic",
  "  -xk ", "          keep parametrized type definitions and imply -x.", "          Default is to return only monomorphic type definitions",
  "  -xd ", "          debug mode implying -x", "  -i ", "          expand all 'inherit' statements",
  "  -if ", "          expand 'inherit' statements in records", "  -iv ", "          expand 'inherit' statements in sum types",
  "  -jsonschema <root type name>", "          translate the ATD file to JSON Schema.",
  "  -jsonschema-no-additional-properties ", "          emit a JSON Schema that doesn't tolerate extra fields on JSON",
  "          objects.", "  -jsonschema-version { draft-2019-09 | draft-2020-12 }",
  "          specify which version of the JSON Schema standard to target.", "          Default: latest supported version, which is currently 'draft-2020-12'.",
  "  -ml <name>", "          output the ocaml code of the ATD abstract syntax tree",
  "  -html-doc ", "          replace directly <doc html=\"...\"> by (*html ... *)",
  "          or replace <doc text=\"...\"> by (*html ... *)", "          where the contents are formatted as HTML",
  "          using <p>, <code> and <pre>.", "          This is suitable input for \"caml2html -ext html:cat\"",
  "          which converts ATD files into HTML.", "  -remove-wraps ", "          eliminate all 'wrap' constructs and their annotations",
  "  -strip NAME1[,NAME2,...]", "          remove all annotations of the form <NAME1 ...>,",
  "          <NAME2 ...>, etc.", "  -strip-all ", "          remove all annotations",
  "  -version ", "          print the version of atd and exit", "  -help  Display this list of options",
  "  --help  Display this list of options",
].join("\n")

///|
fn format_html_comments(x : @atd.AnnotSection) -> @easy_format.T {
  let comment = s => @easy_format.T::Atom("(*html " + s + "*)")
  if x.name == "doc" {
    match x.fields.iter().find_first(f => f.name == "html") {
      Some({ value: Some(s), .. }) => comment(s)
      _ =>
        match x.fields.iter().find_first(f => f.name == "text") {
          Some({ loc, value: Some(s), .. }) =>
            // unreachable error: the documentation is validated before
            // printing
            comment(@atd.html_of_doc(@atd.parse_doc_text(loc, s))) catch {
              _ => @atd.default_format_annot(x)
            }
          _ => @atd.default_format_annot(x)
        }
    }
  } else {
    @atd.default_format_annot(x)
  }
}

///|
fn basename(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path.view(start_offset=i + 1).to_owned()
    None => path
  }
}

///|
fn read_source(io : Io, path : String?) -> (Bytes, String) raise Error {
  match path {
    None => ((io.read_file)(None), "<stdin>")
    Some(path) => ((io.read_file)(Some(path)), path)
  }
}

///|
fn run_exn(io : Io, args : ArrayView[String]) -> Unit raise Error {
  @atd.annot_reset_ids()
  let mut expand = false
  let mut keep_poly = false
  let mut xdebug = false
  let mut inherit_fields = false
  let mut inherit_variants = false
  let mut remove_wraps = false
  let strip_sections : Array[String] = []
  let mut strip_all = false
  let mut out_format = Atd
  let mut jsonschema_version = @atd.default_jsonschema_version
  let mut xprop = true
  let mut html_doc = false
  let input_files : Array[String] = []
  let mut output_file : String? = None
  let prog = if args.length() > 0 { args[0] } else { "atdcat" }
  let usage = () => "Usage: \{prog} [FILE ...]\n" + usage_options
  let mut i = 1
  let next_arg = (opt : String) => {
    i += 1
    if i >= args.length() {
      (io.print_err)(
        "\{prog}: option '\{opt}' needs an argument.\n" + usage() + "\n",
      )
      raise Exit(2)
    }
    args[i]
  }
  while i < args.length() {
    let arg = args[i]
    match arg {
      "-o" => output_file = Some(next_arg(arg))
      "-x" => expand = true
      "-xk" => {
        expand = true
        keep_poly = true
      }
      "-xd" => {
        expand = true
        xdebug = true
      }
      "-i" => {
        inherit_fields = true
        inherit_variants = true
      }
      "-if" => inherit_fields = true
      "-iv" => inherit_variants = true
      "-jsonschema" => out_format = Jsonschema(next_arg(arg))
      "-jsonschema-no-additional-properties" => xprop = false
      "-jsonschema-version" =>
        jsonschema_version = match next_arg(arg) {
          "draft-2019-09" => Draft_2019_09
          "draft-2020-12" => Draft_2020_12
          s => {
            (io.print_err)(
              "Invalid JSON Schema version identifier: " +
              @atd.ocaml_quote(s) +
              "\n",
            )
            raise Exit(1)
          }
        }
      "-ml" => out_format = Ocaml(next_arg(arg))
      "-html-doc" => html_doc = true
      "-remove-wraps" => remove_wraps = true
      "-strip" => {
        let l = next_arg(arg).split(",").map(x => x.to_owned()).collect()
        let old = strip_sections.copy()
        strip_sections.clear()
        strip_sections.append(l)
        strip_sections.append(old)
      }
      "-strip-all" => strip_all = true
      "-version" => {
        (io.print_out)(@atd.version + "\n")
        raise Exit(0)
      }
      "-help" | "--help" => {
        (io.print_out)(usage() + "\n")
        raise Exit(0)
      }
      _ =>
        if arg.has_prefix("-") && arg != "-" {
          (io.print_err)("\{prog}: unknown option '\{arg}'.\n" + usage() + "\n")
          raise Exit(2)
        } else {
          // like OCaml's Arg, files are accumulated in reverse order
          input_files.insert(0, arg)
        }
    }
    i += 1
  }
  let (force_inherit, annot_schema) = match out_format {
    Jsonschema(_) => (true, Some(@atd.jsonschema_annot_schema))
    _ => (false, None)
  }
  let inherit_fields = inherit_fields || force_inherit
  let inherit_variants = inherit_variants || force_inherit
  let sources : Array[String?] = if input_files.is_empty() {
    [None]
  } else {
    input_files.map(f => Some(f))
  }
  let modules = []
  for source in sources {
    let (src, pos_fname) = read_source(io, source)
    modules.push(
      @atd.load_bytes(
        src,
        annot_schema?,
        expand~,
        keep_poly~,
        xdebug~,
        inherit_fields~,
        inherit_variants~,
        pos_fname~,
        on_warning=w => (io.print_err)(w + "\n"),
      ),
    )
  }
  let (first_head, first_imports) = match modules {
    [first, ..] => (first.head, first.imports)
    [] => ((@atd.dummy_loc, []), [])
  }
  let all_type_defs = []
  for m in modules {
    all_type_defs.append(m.type_defs)
  }
  let m : @atd.Module = {
    head: first_head,
    imports: first_imports,
    type_defs: all_type_defs,
  }
  let m = if remove_wraps { m.remove_wrap_constructs() } else { m }
  let m = if strip_all {
    m.map_all_annot(_ => [])
  } else {
    m.map_all_annot(an => an.filter(s => !strip_sections.contains(s.name)))
  }
  let src_name = match input_files {
    [] => "<stdin>"
    [file] => "'" + basename(file) + "'"
    _ => "multiple files"
  }
  if html_doc && out_format is Atd {
    // report invalid documentation, which can't be converted to HTML
    @atd.iter_annot(Module(m), (_, an) => {
      for sec in an {
        // like format_html_comments: <doc html="..."> takes precedence over
        // text, but only if it has a value
        let has_html = match
          sec.fields.iter().find_first(f => f.name == "html") {
          Some({ value: Some(_), .. }) => true
          _ => false
        }
        if sec.name == "doc" && !has_html {
          match sec.fields.iter().find_first(f => f.name == "text") {
            Some({ loc, value: Some(s), .. }) =>
              ignore(@atd.parse_doc_text(loc, s))
            _ => ()
          }
        }
      }
    })
  }
  let output = match out_format {
    Atd => {
      let format_annot = if html_doc {
        format_html_comments
      } else {
        @atd.default_format_annot
      }
      @atd.to_string(Module(m), format_annot~) + "\n"
    }
    Ocaml(name) => @atd.reflect_module(name, m) + "\n"
    Jsonschema(root_type) =>
      @atd.print_jsonschema(
        m,
        src_name~,
        root_type~,
        version=jsonschema_version,
        xprop~,
      )
  }
  match output_file {
    None => (io.print_out)(output)
    Some(file) => (io.write_file)(file, output)
  }
}

///|
/// Run atdcat with the given command-line arguments (including the program
/// name), returning the exit code.
pub fn run(io : Io, args : ArrayView[String]) -> Int {
  try run_exn(io, args) catch {
    Exit(code) => code
    @atd.AtdError(msg) => {
      (io.print_err)(msg + "\n")
      1
    }
    e => {
      (io.print_err)("\{e}\n")
      2
    }
  } noraise {
    _ => 0
  }
}

///|
/// The files that `run` reads for the given command-line arguments, in the
/// order in which it reads them (`None` for the standard input).
///
/// This lets an asynchronous program read the input files before calling
/// `run` with an `Io` that serves them from memory. It is implemented by
/// running atdcat on empty inputs, which are valid ATD files, and
/// discarding its output.
pub fn input_files(args : ArrayView[String]) -> Array[String?] {
  let files = []
  let io : Io = {
    read_file: path => {
      files.push(path)
      b""
    },
    write_file: (_, _) => (),
    print_out: _ => (),
    print_err: _ => (),
  }
  ignore(run(io, args))
  files
}
