# atd.mbt — ATD for MoonBit

[![CI](https://github.com/bobzhang/atd.mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/bobzhang/atd.mbt/actions/workflows/ci.yml)

A MoonBit port of [ATD](https://github.com/ahrefs/atd) (Adaptable Type
Definitions), a syntax for defining cross-language data types used to
generate type-safe JSON serializers and deserializers. It also adds a
new target language, MoonBit, with the `atdmbt` code generator.

What's included:

| Package | Description |
|---|---|
| `bobzhang/atd` (`src/`) | The ATD library: lexer, parser, AST, annotations, semantic checks, `inherit` expansion, monomorphization, pretty-printing, documentation format, JSON Schema export. Port of upstream `atd/src`. |
| `bobzhang/atd/easy_format` | Port of the `easy-format` library. |
| `bobzhang/atd/yojson` | Yojson-compatible JSON pretty-printer. |
| `bobzhang/atd/atdcat` | The `atdcat` tool as a library. |
| `bobzhang/atd/mbtgen` | The MoonBit code generator. |
| `bobzhang/atd/runtime` | Runtime library used by the generated MoonBit code. |
| `cmd/atdcat`, `cmd/atdmbt` | Command-line tools (wasm and native), runnable with `moonx`. |

The pretty-printing relies on [`bobzhang/format`](format/README.md)
(`format/`), a faithful port of OCaml's `Format` module, including
printf-like format strings, published as a separate module. The two modules
are developed together in a `moon.work` workspace.

## Installation

The command-line tools run with `moonx`, without installation:

```bash
moonx bobzhang/atd/cmd/atdcat foo.atd
moonx bobzhang/atd/cmd/atdmbt foo.atd
```

They are built on [`moonbitlang/async`](https://mooncakes.io/docs/moonbitlang/async)
and run on the wasm (the default for `moonx`) and native backends. To use
the library, add the module to a project:

```bash
moon add bobzhang/atd
```

From a clone of the repository:

```bash
moon run src/cmd/atdcat -- foo.atd
moon build --target native   # _build/native/debug/build/cmd/{atdcat,atdmbt}/*.exe
```

## atdcat

`atdcat` checks, pretty-prints and transforms ATD files, exactly like the
upstream tool (more examples in [tests/cram/atdcat.md](tests/cram/atdcat.md)):

```bash
atdcat foo.atd                    # check and pretty-print
atdcat -x foo.atd                 # monomorphize (expand parametrized types)
atdcat -i foo.atd                 # expand 'inherit' statements
atdcat -jsonschema root foo.atd   # translate to JSON Schema
atdcat -help                      # all options
```

## atdmbt: MoonBit code generation

More examples in [tests/cram/atdmbt.md](tests/cram/atdmbt.md).

```bash
atdmbt foo.atd          # creates foo.mbt
atdmbt -o - foo.atd     # prints to stdout
```

The generated file goes into a MoonBit package whose `moon.pkg` imports the
runtime with the alias `atd_runtime` (and the packages of the imported ATD
modules, see below):

```
import {
  "bobzhang/atd/runtime" @atd_runtime,
}
```

### Example

```ocaml
type point = { x : float; ~y <mbt default="1.0"> : float }
type shape = [ Dot | Circle of (point * float) ]
```

generates, among other things:

```mbt nocheck
pub(all) struct Point {
  x : Double
  y : Double
} derive(Eq, Debug)

pub fn Point::new(x~ : Double, y? : Double = 1.0) -> Point

pub(all) enum Shape {
  Dot
  Circle(Point, Double)
} derive(Eq, Debug)

pub fn write_shape(x : Shape) -> Json
pub fn read_shape(x : Json, path : @atd_runtime.Path) -> Shape raise @atd_runtime.JsonError
pub fn shape_of_json(x : Json) -> Shape raise @atd_runtime.JsonError
pub fn shape_of_string(s : StringView) -> Shape raise @atd_runtime.JsonError
pub fn string_of_shape(x : Shape, indent? : Int = 0) -> String
pub impl ToJson for Shape
```

```mbt nocheck
let s = string_of_shape(Circle(Point::new(x=0), 2.5))
// ["Circle",[{"x":0,"y":1},2.5]]
let shape = shape_of_string(s)
```

For each ATD type `foo`:

- `Foo` is a `struct` for records, an `enum` for sum types and a type alias
  otherwise. Records get a `Foo::new` constructor with labelled arguments,
  optional for the optional fields and the fields with a default value.
- `write_foo` and `read_foo` are the composable JSON writer and reader;
  `foo_of_string` parses JSON with `@atd_runtime.parse`, which keeps the
  exact text of numbers so that integers are validated and 64-bit integers
  read without loss;
  readers report errors with the path of the offending value, e.g.
  `incompatible JSON value where type 'int' was expected: '"x"' at $.trees[0][1]`.
- `foo_of_json`, `foo_of_string` and `string_of_foo` are conveniences.
- `ToJson` is implemented for structs and enums.

### Type mapping

The JSON representation is the same as with atdgen, atdts and atdpy.

| ATD | MoonBit | JSON |
|---|---|---|
| `unit` | `Unit` | `null` |
| `bool` | `Bool` | boolean |
| `int` | `Int` (range-checked) | integer literal, like atdgen (`1.0` is rejected); `<json repr="string">`: string |
| `int <mbt repr="int64">` | `Int64` (all digits preserved) | number or string |
| `float` | `Double` | number; `<json repr="int">` and `<json precision="N">` (N significant digits) are written exactly like atdgen; non-finite numbers can't be represented in JSON and are written as `NaN`/`Infinity` |
| `string` | `String` | string |
| `abstract` | `Json` | any |
| `t list` | `Array[T]` | array |
| `(string * t) list <json repr="object">` | `Array[(String, T)]` | object |
| `... <mbt repr="map">` | `Map[K, V]` | object or array of pairs |
| `t option` | `T?` | `"None"` or `["Some", x]` |
| `t nullable` | `T?` | `null` or `x` |
| `(a * b)` | `(A, B)` | array; `(a)` is `A`, `()` is `Unit` |
| record | `pub(all) struct` | object |
| sum type | `pub(all) enum` | `"Tag"` or `["Tag", x]`; `{"Tag": x}` with `<json repr="object">` |
| `t wrap` | `T`, or the type given by `<mbt t=...>` | same as `t` |
| `mod.t` (imported) | `@mod.T` | |
| `'a t` (parametrized) | monomorphized, e.g. `(string, int) entry` → `StringIntEntry` | |

Record fields:

- `?foo : t option` is `foo : T?`, omitted from the JSON object when `None`;
- `~foo : t` is `foo : T` with a default value used when the field is
  missing: the implicit default (`[]`, `None`, `0`, `""`, `false`, ...) or
  `<mbt default="expression">`;
- for optional and defaulted fields, `null` is treated like a missing field
  unless the record has `<json keep_nulls>`; a required field passes `null`
  to the reader of its type (so `x : int nullable` accepts `null` but must
  be present);
- unknown fields are ignored.

Other supported features: `<json name="...">` on fields and variants,
`<json open_enum>` (unknown tags are read into the variant with a string
payload, which is written as a plain string), `inherit`, `<doc text="...">` (turned into `///`
comments), inline records and sum types (lifted into named types such as
`InlinePoint`), recursive types (except type aliases defined in terms of
themselves, e.g. `type t = t list`), and names that clash with MoonBit
keywords or builtin names (renamed, e.g. `match` → `match_`, `Some` →
`Some_`). `shared` is not supported.

### `<mbt ...>` annotations

| Annotation | Position | Meaning |
|---|---|---|
| `<mbt name="alias">` | `from m <mbt name="alias"> import ...` | package alias of an imported module (default: the module's local name) |
| `<mbt name="T" functions="f">` | `from m import t <mbt name="T" functions="f">` | MoonBit name of an imported type and base name of its functions (`read_f`, `write_f`), if not the defaults |
| `<mbt name="n">` | field, variant | MoonBit name of a field or constructor |
| `<mbt default="expr">` | `~field` | default value, a MoonBit expression |
| `<mbt repr="map">` | `(k * v) list` | represent as `Map[K, V]` |
| `<mbt repr="int64">` | `int` | represent as `Int64` |
| `<mbt t="T" wrap="f" unwrap="g">` | `wrap` | custom MoonBit type `T`, with `f : (Inner) -> T` and `g : (T) -> Inner` |
| `<mbt derive="Eq, Show">` | type definition | traits to derive (default: `Eq, Debug`; empty for none) |

### Imports

`from foo import t` makes `foo.t` refer to `@foo.T`, read with
`@foo.read_t` and written with `@foo.write_t`. These are the names that
atdmbt gives by default to the type `t` of `foo.atd` (names of builtin types
such as `Json` get an underscore, e.g. `Json_`); if the names were
adjusted to avoid a conflict in `foo.atd`, give them with
`<mbt name="..." functions="...">` on the imported type. The MoonBit package
containing the code generated from `foo.atd` must be imported in `moon.pkg`
with the alias `foo`, or the alias given by `<mbt name="...">`.

## Using the library

```mbt nocheck
let m = @atd.load_string(
  "type t = { x : int list }",
  inherit_fields=true,
  inherit_variants=true,
)
println(@atd.to_string(Module(m)))
println(@atd.print_jsonschema(m, src_name="t.atd", root_type="t"))
let code = @mbtgen.generate_module(m, atd_filename="t.atd")
```

## Fidelity to upstream

The port aims at byte-for-byte compatibility with the OCaml implementation
(upstream commit `c714a58`), including pretty-printing, error messages and
their locations, generated type names and JSON Schema output:

- OCaml's `Format` and `easy-format` are ported faithfully, and all offsets
  are computed on UTF-8 bytes like in OCaml. `bobzhang/format` passes the
  `Format` tests of the OCaml testsuite and is fuzzed against OCaml's
  `Format` (`scripts/fuzz_format.mbtx`).
- The hand-written parser replaces Menhir and reproduces its locations and
  its error messages, including Menhir's error-recovery behavior that
  selects messages such as `Expecting '='`.
- `src/atdcat/compat_*_test.mbt` contains 405 tests comparing the output
  of `atdcat` (stdout, stderr and exit code) with the reference OCaml
  implementation, for all the ATD files of the upstream repository with
  various options, and for a corpus of malformed inputs (`tests/errors`).
- Differential fuzzing of the parser (thousands of mutated upstream files)
  found no differences.

Known, intentional differences:

- Inputs that make upstream crash with an uncaught exception (decimal escape
  sequences above `\255`, type names with more than two components, an
  invalid `-jsonschema-version`) produce proper error messages instead.
- Strings are Unicode: invalid UTF-8 in string literals is replaced with
  U+FFFD.
- `atdcat -version` prints the version of this port.

Known upstream limitations of `atdcat -jsonschema`, kept for compatibility:
a recursive root type refers to `#/definitions/<root>`, which is not
defined (the root is not repeated in `definitions`), and `t nullable` loses
its nullability when `t` is a type name (e.g. `type a = int` then
`a nullable`).

## Development

The repository is a `moon.work` workspace with three modules: `bobzhang/atd`
(the root), `bobzhang/format` (`format/`) and the unpublished fuzzer of the
latter (`format/fuzz`). Commands run at the root apply to the whole
workspace, and `bobzhang/atd` uses the local `bobzhang/format`.

The upstream sources are used for reference and for generating the
compatibility tests; clone them into `.repos` (ignored by git):

```bash
git clone https://github.com/ahrefs/atd .repos/atd
git -C .repos/atd checkout c714a585771bfe7a6eb414a3ebefed30e0611c66
```

Tests:

```bash
moon test                                  # also with --target native|js|wasm
moon cram test tests/cram                  # CLI documentation, see below
moonx scripts/regen_fixtures.mbtx          # regenerate the code of src/tests/*
```

[`tests/cram/atdcat.md`](tests/cram/atdcat.md) and
[`tests/cram/atdmbt.md`](tests/cram/atdmbt.md) document the command-line
tools with examples that are checked by `moon cram test`; after changing the
tools, update the expected outputs with
`moon-cram update -r -y tests/cram` (with the tools on `PATH`).

The compatibility tests and the fuzzer need a reference `atdcat` built from
`.repos/atd` with dune, OCaml 4.14 and Yojson 2.1.0 (it also needs
easy-format, menhir, re and cmdliner); see
[.github/workflows/upstream.yml](.github/workflows/upstream.yml), which runs
them in CI:

```bash
moonx scripts/gen_compat_tests.mbtx path/to/atdcat.exe && moon fmt
moon build --target native
moonx scripts/fuzz_atdcat.mbtx path/to/atdcat.exe 1000
```

The differential fuzzer of `bobzhang/format` only needs OCaml 4.14
(`ocamlopt`); see [format/fuzz/README.md](format/fuzz/README.md):

```bash
moonx scripts/fuzz_format.mbtx 1000
```

To publish, publish `bobzhang/format` first when it has changed, then
`bobzhang/atd` with `moon publish` at the root (`.moonignore` keeps the
workspace files and `format/` out of its package). Since the ignore files of
the root also apply to `format/`, publish `bobzhang/format` from a copy:

```bash
rm -rf /tmp/format && cp -R format /tmp/format && (cd /tmp/format && moon publish)
```

## License

BSD-3-Clause, like the upstream ATD project; see [LICENSE.md](LICENSE.md).

`bobzhang/format` (`format/`) is a derivative work of OCaml's standard
library and is distributed under its license, the LGPL 2.1 with the OCaml
linking exception; see [format/LICENSE](format/LICENSE).
