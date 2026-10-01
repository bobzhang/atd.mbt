# bobzhang/format

A faithful MoonBit port of OCaml's
[`Format`](https://v2.ocaml.org/releases/4.14/api/Format.html) module
(OCaml 4.14): the pretty-printing engine with its boxes, break hints,
tabulations, semantic tags and maximum depth, the printf-like functions
with their format strings (`%d`, `%s`, `@[`, `@ `, ...), and the
convenience printers.

```moonbit
let doc = @format.asprintf("@[<hov 2>let x =@ %a@]", [
  Print(ppf => ppf.print_list(
    pp_sep=ppf => ppf.printf(";@ ", []),
    @format.Formatter::print_int,
    @list.List([1, 2, 3]),
  )),
])
```

## Formatters

A `Formatter` prints to output functions (`Formatter(out_string)`, given a
function writing strings, or `Formatter::of_out_functions`), to a `StringBuilder`
(`Formatter::of_buffer`) or to a list of symbolic items
(`Formatter::of_symbolic_output_buffer`). OCaml's `pp_<name>` functions are
methods of the formatter, without the prefix:

| OCaml | MoonBit |
|---|---|
| `Format.formatter_of_buffer b` | `Formatter::of_buffer(b)` |
| `pp_open_box ppf 2` | `ppf.open_box(2)` (also `open_hbox`, `open_vbox`, `open_hvbox`, `open_hovbox`) |
| `pp_print_string ppf s`, `pp_print_as` | `ppf.print_string(s)`, `ppf.print_as(size, s)` |
| `pp_print_space ppf ()`, `pp_print_cut`, `pp_print_break` | `ppf.print_space()`, `ppf.print_cut()`, `ppf.print_break(width, offset)` |
| `pp_print_custom_break ~fits ~breaks` | `ppf.print_custom_break(fits~, breaks~)` |
| `pp_open_tbox`, `pp_set_tab`, `pp_print_tab`, `pp_print_tbreak` | `ppf.open_tbox()`, `ppf.set_tab()`, `ppf.print_tab()`, `ppf.print_tbreak(width, offset)` |
| `pp_open_stag`, `pp_set_mark_tags`, ... | `ppf.open_stag(StringTag(s))`, `ppf.set_mark_tags(true)`, ... |
| `pp_set_margin`, `pp_set_geometry`, `pp_set_max_boxes`, ... | `ppf.set_margin(n)`, `ppf.set_geometry(max_indent~, margin~)`, ... |
| `pp_print_list`, `pp_print_seq`, `pp_print_text`, `pp_print_option`, `pp_print_result` | `ppf.print_list(...)`, `ppf.print_iter(...)`, `ppf.print_text(s)`, ... |
| `pp_print_flush ppf ()`, `pp_print_newline ppf ()` | `ppf.print_flush()`, `ppf.print_newline()` |

## Format strings

MoonBit has no typed format strings, so the format is parsed at run time,
exactly like OCaml parses format literals (in the default, "legacy" mode of
the compiler), and the arguments are given as an array of `Arg`:

```moonbit
ppf.printf("@[<v 2>%s:@,%5.2f@,%a@]", [
  String("total"),
  Float(3.14159),
  Print(ppf => ppf.print_bool(true)),
])
@format.asprintf("%-8s|%08.3e|%#x", [String("a"), Float(-1.5), Int(255)])
```

- `Int` is used by `%d %i %u %x %X %o` and by `*` widths and precisions,
  with the semantics of OCaml's 63-bit `int` (`%x` of `-1` is
  `7fffffffffffffff`); `Int32` by `%ld`...; `Int64` by `%Ld` and `%nd`...;
  `Float` by `%f %e %E %g %G %F %h %H`; `String` by `%s %S`; `Char` by
  `%c %C`; `Bool` by `%b %B`.
- `%a` and `%t` take a `Print` function (OCaml's `%a` takes a printer and
  a value: here, the printer is applied to its value).
- `%{ fmt %}` and `%( fmt %)` take a `Format(String)`.
- All the formatting directives are supported: boxes `@[<hov 2>` and `@]`,
  break hints `@ `, `@,`, `@;<1 2>`, `@\n`, `@.`, `@?`, tags `@{<tag>`
  and `@}`, sizes `@<n>`, `@@` and `@%`.

The functions are `Formatter::printf` (OCaml's `fprintf`),
`Formatter::kprintf` (`kfprintf`), `asprintf`, `sprintf`, `kasprintf` and
`dprintf`. An invalid format string, or arguments that don't match it, abort
the program: they are programming errors, detected by the type checker in
OCaml. The error messages are OCaml's, and `check_format` checks a format
string without printing:

```moonbit
@format.check_format("%{%d") // raises Failure("invalid format \"%{%d\": unclosed sub-format, expected \"%}\" at character number 4")
```

The conversions of numbers are also available directly:
`format_float_c(x, 'e', 6)` is C's `printf("%.6e", x)`,
`hexstring_of_float` is OCaml's `%h`, and `string_of_float` is OCaml's
`string_of_float`.

## Differences with OCaml

- Strings are Unicode. Like in OCaml, widths (of texts, padding, break
  hints...) and positions in error messages count UTF-8 bytes, so the
  output is the same as OCaml's for the same text. A `Char` is a Unicode
  character: `%c` prints it in UTF-8, and an invalid conversion such as
  `%é` is reported as such (OCaml prints the first byte of the character).
- There are no global formatters (`std_formatter`, `err_formatter`...).
- NaN with the `+` or space flag (`%+f`): the result depends on the C
  library in OCaml (`nan` on macOS, `+nan` on Linux); it is `+nan` here, as
  in C99.

## Testing

The tests of OCaml's testsuite for `Format` (`tests/lib-format`: `tformat`,
`pp_print_custom_break`, `print_if_newline`, `print_seq`, `pr6824`) are
ported with their reference outputs.

The module is also tested by differential fuzzing against OCaml's `Format`:
random scripts of pretty-printing operations, including `printf` with random
format strings, are run with both implementations and their outputs are
compared; see [fuzz/README.md](fuzz/README.md).

## License

This is a derivative work of OCaml's standard library, so it is distributed
under the same license: the GNU Lesser General Public License version 2.1,
with the special exception on linking described in [LICENSE](LICENSE).
