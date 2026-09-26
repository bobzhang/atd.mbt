// Port of atd/test/annot.ml

///|
let schema : @atd.Schema = [
  {
    section: "foo",
    fields: [
      (ModuleHead, "a"),
      (TypeDef, "b"),
      (TypeExpr, "c"),
      (Variant, "d"),
      (Cell, "e"),
      (Field, "f"),
      (Field, "g"),
    ],
  },
  {
    section: "bar",
    fields: [
      (ModuleHead, "m"),
      (TypeDef, "n"),
      (TypeExpr, "o"),
      (Variant, "p"),
      (Cell, "q"),
      (Field, "r"),
    ],
  },
]

///|
fn validate(atd_input : String) -> Unit raise {
  let root = @atd.load_string(atd_input)
  @atd.annot_validate(schema, Module(root))
}

///|
fn invalid(atd_input : String) -> String raise {
  try validate(atd_input) catch {
    @atd.AtdError(msg) => msg
    e => raise e
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "annot: valid" {
  validate(
    (
      #|<foo a>
      #|<bar m>
      #|
      #|type record <foo b> = {
      #|  field
      #|    <buz x>
      #|    <foo f>
      #|    <bar r="x">
      #|    <foo g>:
      #|      int <foo c>
      #|        list <foo c="">;
      #|}
      #|
      #|type sum = [
      #|| Hello <bar p> of string <foo c>
      #|| World <foo d>
      #|| Tuple of (<foo e>: int * <bar q>: string * record option <bar o>) <foo c>
      #|]
    ),
  )
}

///|
test "annot: invalid" {
  inspect(
    invalid("<foo hello>"),
    content=(
      #|File "", line 1, characters 5-10:
      #|Invalid or misplaced annotation <foo ... hello... >
    ),
  )
  inspect(
    invalid("type t = int <foo f>"),
    content=(
      #|File "", line 1, characters 18-19:
      #|Invalid or misplaced annotation <foo ... f... >
    ),
  )
  inspect(
    invalid("type t = int <foo f> list list list"),
    content=(
      #|File "", line 1, characters 18-19:
      #|Invalid or misplaced annotation <foo ... f... >
    ),
  )
  inspect(
    invalid("type t <foo b c> = int"),
    content=(
      #|File "", line 1, characters 14-15:
      #|Invalid or misplaced annotation <foo ... c... >
    ),
  )
  inspect(
    invalid(
      (
        #|
        #|type t = {
        #|  ?k: (int * int <foo f> list) option
        #|}
      ),
    ),
    content=(
      #|File "", line 3, characters 22-23:
      #|Invalid or misplaced annotation <foo ... f... >
    ),
  )
  inspect(
    invalid(
      (
        #|
        #|type t = {
        #|  ?k <foo x>: int;
        #|}
      ),
    ),
    content=(
      #|File "", line 3, characters 10-11:
      #|Invalid or misplaced annotation <foo ... x... >
    ),
  )
  inspect(
    invalid(" type t = [ A <foo f> ] "),
    content=(
      #|File "", line 1, characters 19-20:
      #|Invalid or misplaced annotation <foo ... f... >
    ),
  )
  inspect(
    invalid(" type t = [ A <foo f> of int ] "),
    content=(
      #|File "", line 1, characters 19-20:
      #|Invalid or misplaced annotation <foo ... f... >
    ),
  )
  inspect(
    invalid("type t = (<foo f>: int * int)"),
    content=(
      #|File "", line 1, characters 15-16:
      #|Invalid or misplaced annotation <foo ... f... >
    ),
  )
}

///|
test "annot: accessors" {
  let m = @atd.load_string(
    (
      #|type t = int <json repr="string" x="1" flag> <json y> <ocaml z>
    ),
  )
  let an = m.type_defs[0].value.annot()
  assert_eq(
    @atd.annot_get_string(an, sections=["json"], field="repr"),
    Some("string"),
  )
  assert_eq(@atd.annot_get_flag(an, sections=["json"], field="flag"), true)
  assert_eq(@atd.annot_get_flag(an, sections=["json"], field="other"), false)
  assert_eq(
    @atd.annot_has_field(an, sections=["ocaml", "json"], field="y"),
    true,
  )
  assert_eq(@atd.annot_has_section(an, "ocaml"), true)
  let merged = @atd.annot_merge(an)
  inspect(
    merged
    .map(s => s.name + ":" + s.fields.map(f => f.name).join(","))
    .join(" "),
    content="json:repr,x,flag,y ocaml:z",
  )
  let an2 = @atd.annot_set_field(
    an,
    loc=@atd.dummy_loc,
    section="json",
    field="x",
    Some("2"),
  )
  assert_eq(@atd.annot_get_string(an2, sections=["json"], field="x"), Some("2"))
  let an3 = @atd.annot_set_field(
    an,
    loc=@atd.dummy_loc,
    section="new",
    field="k",
    None,
  )
  assert_eq(an3[0].name, "new")
}

///|
test "annot: duplicate field" {
  let m = @atd.load_string("type t = int <json repr=\"int\" repr=\"string\">")
  try @atd.get_json_int(m.type_defs[0].value.annot()) catch {
    e =>
      inspect(
        e,
        content=(
          #|File "", line 1, characters 19-29:
          #|Duplicate annotation json.repr (also in:
          #|  File "", line 1, characters 30-43
          #|)
        ),
      )
  } noraise {
    _ => fail("expected an error")
  }
}
