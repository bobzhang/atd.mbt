# bobzhang/easy_format

A port of [easy-format](https://github.com/ocaml-community/easy-format)
1.3.4 to MoonBit, on top of [bobzhang/format](https://mooncakes.io/docs/bobzhang/format),
a port of OCaml's `Format`: pretty-printing of trees made of atoms, lists
and labels, with indentation made easy.

```moonbit
let point = @easy_format.T::List(("{", ",", "}", @easy_format.list), [
  Label((Atom("x:", @easy_format.atom), @easy_format.label), Atom("1", @easy_format.atom)),
  Label((Atom("y:", @easy_format.atom), @easy_format.label), Atom("2", @easy_format.atom)),
])
@easy_format.to_string(point) // "{ x: 1, y: 2 }"
```

A tree (`T`) is made of:

- `Atom(text, param)`: text printed as is;
- `List((opening, separator, closing, param), items)`: a sequence such as
  `[ 1, 2, 3 ]`, printed horizontally, vertically or wrapped;
- `Label((label, param), item)`: an item with a label such as `x:` or
  `let x =`;
- `Custom(f)`: printed with the formatter directly.

The parameters (`AtomParam`, `ListParam`, `LabelParam`) are records: derive
them from the defaults, e.g. `{ ..@easy_format.list, wrap_body: ForceBreaks }`.

The functions of OCaml's `Easy_format.Pretty` are `to_formatter`,
`to_buffer`, `to_string` and `define_styles`, with styles (the markers of
semantic tags, e.g. for HTML or terminal colors) and escaping. Those of
`Easy_format.Compact` are `compact_to_formatter`, `compact_to_buffer` and
`compact_to_string`. The deprecated `Easy_format.Param` values are
`list_true`, `list_false`, `label_true` and `label_false`.

## Testing

The test and the examples of easy-format (`test/test_easy_format.ml`,
`examples/simple_example.ml` and `examples/lambda_example.ml`) are ported,
and their outputs are compared with the outputs of the OCaml programs.

## License

BSD-3-Clause, like easy-format; see [LICENSE](LICENSE).
