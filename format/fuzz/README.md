# Differential fuzzing of bobzhang/format

This module (`bobzhang/format_fuzz`, a member of the workspace, not
published) and [driver.ml](driver.ml) are two drivers that run the same
script of pretty-printing operations, with bobzhang/format and with
OCaml's `Format` respectively, and print the result.
[scripts/fuzz_format.mbtx](../../scripts/fuzz_format.mbtx) generates random
scripts, runs both drivers and compares their outputs:

```bash
moonx scripts/fuzz_format.mbtx 1000 my-seed   # from the root of the repository
```

It needs OCaml 4.14 (`ocamlopt`) on `PATH`, and builds the two drivers
itself. When OCaml rejects a script (an invalid format string), bobzhang/format
must reject it as well, with the same error message. Besides valid format
strings, the scripts check random mutations of format strings, to compare
the errors of the parsers.

## Scripts

A script has one operation per line; strings are encoded in hexadecimal
(UTF-8), with `-` for the empty string, and floats are given by the
hexadecimal representation of their bits.

| Operation | `Format` function |
|---|---|
| `margin n`, `max_indent n`, `max_boxes n`, `ellipsis s`, `mark_tags 0\|1` | `pp_set_margin`, ... |
| `box b\|h\|v\|hv\|hov n`, `close` | `pp_open_box n`, ..., `pp_close_box` |
| `str s`, `as n s`, `int n`, `char code`, `bool 0\|1`, `float bits`, `text s` | `pp_print_string`, `pp_print_as`, ..., `pp_print_text` |
| `break w o`, `custom s w s s o s`, `space`, `cut` | `pp_print_break`, `pp_print_custom_break`, ... |
| `force_newline`, `if_newline`, `flush`, `newline` | `pp_force_newline`, ... |
| `tbox`, `tclose`, `set_tab`, `tab`, `tbreak w o` | `pp_open_tbox`, ... |
| `tag s`, `ctag` | `pp_open_stag (String_tag s)`, `pp_close_stag` |
| `printf fmt arg...` | `fprintf` |
| `check fmt` | parse a format string (`check_format`), print `ok` or the error |

The arguments of `printf` are `i:n` (`int`), `l:n` (`int32`), `L:n`
(`int64`), `n:n` (`nativeint`), `f:bits` (`float`), `s:s` (`string`),
`c:code` (`char`), `b:0|1` (`bool`), `a:s` (for `%a`, a printer printing
`@[<1>s@ s@]`), `t:s` (for `%t`, a printer printing `@[<hov 2>s@,s@]`),
`F:fmt` (for `%{ %}`) and `P:fmt` (for `%( %)`).
