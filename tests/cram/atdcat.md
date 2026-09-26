# atdcat

`atdcat` checks ATD files, pretty-prints them and transforms them. It
behaves like the upstream OCaml tool, byte for byte.

These examples are executed by `moon cram test tests/cram`, which builds the
native executables and puts them on `PATH` as `atdcat.exe` and `atdmbt.exe`.
With `moonx`, the same commands work with `moonx bobzhang/atd/cmd/atdcat` in
place of `atdcat.exe`.

## Pretty-printing

`atdcat` reads ATD files, checks them and prints them in a normalized form.

```mooncram
$ cat > example.atd <<'EOF' && atdcat.exe example.atd
> (* A comment, which is not preserved *)
> type point = { x : float; y : float; ?label : string option }
> type shape = [ Dot of point | Circle of (point * float) | Nothing ] <json repr="object">
> type 'a named = { name : string; value : 'a }
> type named_shape = shape named
> EOF
type point = { x: float; y: float; ?label: string option }
type shape =
  [ Dot of point | Circle of (point * float) | Nothing ] <json repr="object">
type 'a named = { name: string; value: 'a }
type named_shape = shape named
```

It also reads the standard input:

```mooncram
$ echo 'type t = {a:int;b:string list}' | atdcat.exe
type t = { a: int; b: string list }
```

## Expanding parametrized types (monomorphization)

With `-x`, parametrized types are specialized and removed, which is what
code generators such as `atdmbt` work with. Generated type names start with
an underscore.

```mooncram
$ atdcat.exe -x example.atd
type point = { x: float; y: float; ?label: _string_option }
type shape =
  [ Dot of point | Circle of (point * float) | Nothing ] <json repr="object">
type named_shape = _shape_named
type _string_option = string option
type _shape_named = { name: string; value: shape }
```

## Expanding `inherit`

```mooncram
$ cat > inherit.atd <<'EOF' && atdcat.exe -i inherit.atd
> type base = { id : string; ~tags : string list }
> type user = { inherit base; name : string }
> type color = [ Red | Green ]
> type more_colors = [ inherit color | Blue ]
> EOF
type base = { id: string; ~tags: string list }
type user = { id: string; ~tags: string list; name: string }
type color = [ Red | Green ]
type more_colors = [ Red | Green | Blue ]
```

## Removing annotations

```mooncram
$ atdcat.exe -strip json example.atd
type point = { x: float; y: float; ?label: string option }
type shape = [ Dot of point | Circle of (point * float) | Nothing ]
type 'a named = { name: string; value: 'a }
type named_shape = shape named
```

## JSON Schema

`-jsonschema` translates the definitions into a JSON Schema whose root is
the given type.

```mooncram
$ cat > schema.atd <<'EOF' && atdcat.exe -jsonschema root schema.atd
> <doc text="A demo schema.">
> type root = {
>   id <json name="ID"> <doc text="The identifier.">: string;
>   ?count : int option;
>   items : item list;
> }
> type item = [ A | B of float ]
> EOF
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "root",
  "description": "Translated by atdcat from 'schema.atd'.\n\nA demo schema.",
  "type": "object",
  "required": [ "ID", "items" ],
  "properties": {
    "ID": { "description": "The identifier.", "type": "string" },
    "count": { "type": "integer" },
    "items": { "type": "array", "items": { "$ref": "#/definitions/item" } }
  },
  "definitions": {
    "item": {
      "oneOf": [
        { "const": "A" },
        {
          "type": "array",
          "minItems": 2,
          "items": false,
          "prefixItems": [ { "const": "B" }, { "type": "number" } ]
        }
      ]
    }
  }
}
```

## Errors

Errors are reported with their location, and `atdcat` exits with code 1.

```mooncram
$ echo 'type t = { x : int; x : string }' > dup.atd && atdcat.exe dup.atd 2>&1
File "dup.atd", line 1, characters 20-30:
Multiple definitions of the same field x
[1]
```

```mooncram
$ echo 'type t = [ A | ]' > syntax.atd && atdcat.exe syntax.atd 2>&1
Syntax error:
File "syntax.atd", line 1, characters 16-16
[1]
```

```mooncram
$ echo 'type t = { x: int' > eof.atd && atdcat.exe eof.atd 2>&1
File "eof.atd", line 2, characters 0-0:
Expecting '}'
[1]
```

```mooncram
$ echo 'type t = u list' > undefined.atd && atdcat.exe undefined.atd 2>&1
File "undefined.atd", line 1, characters 8-10:
Undefined type u
[1]
```

Unused imports produce warnings on the standard error:

```mooncram
$ printf 'from m import a, b\ntype t = m.a\n' > imports.atd && atdcat.exe imports.atd 2>&1
File "imports.atd", line 1, characters 0-18:
Warning: Type 'b' was imported from module 'm' but is never used.
from m import a , b
type t = m.a
```
