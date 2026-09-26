///|
fn error_message(f : () -> Unit raise @atd_runtime.JsonError) -> String raise {
  try f() catch {
    e => e.message()
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "keywords as field names" {
  let x = @features.Match::new(match_=1, fn_="f", kind="k", x_=true)
  let s = @features.string_of_match(x)
  inspect(
    s,
    content=(
      #|{"match":1,"fn":"f","type_":"k","x'":true,"some_list":[]}
    ),
  )
  assert_eq(@features.match_of_string(s), x)
}

///|
test "constructors not shadowing builtin ones" {
  let l : Array[@features.OptionLike] = [
    None_,
    Some_(1),
    Ok_,
    Different(1, "a", true),
  ]
  let json = Json::array(l.map(@features.write_option_like))
  inspect(
    json.stringify(),
    content=(
      #|["None",["Some",1],"Ok",["other",[1,"a",true]]]
    ),
  )
  let l2 = @atd_runtime.read_list(@features.read_option_like)(
    json,
    @atd_runtime.Path::Root,
  )
  assert_eq(l2, l)
}

///|
test "64-bit integers and numeric representations" {
  let x = @features.Int64s::new(
    big=9007199254740993L,
    big_str=-9223372036854775808L,
    small_str=42,
    rounded=2.6,
    precise=3.14159,
  )
  let s = @features.string_of_int64s(x)
  inspect(
    s,
    content=(
      #|{"big":9007199254740993,"big_str":"-9223372036854775808","small_str":"42","rounded":3,"precise":3.14}
    ),
  )
  let y = @features.int64s_of_string(s)
  assert_eq(y.big, 9007199254740993L)
  assert_eq(y.big_str, -9223372036854775808L)
  assert_eq(y.small_str, 42)
  inspect(
    error_message(() => {
      ignore(
        @features.int64s_of_string(
          "{\"big\":1.5,\"big_str\":\"1\",\"small_str\":\"1\",\"rounded\":1,\"precise\":1}",
        ),
      )
    }),
    content=(
      #|incompatible JSON value where type 'int64' was expected: '1.5' at $.big
    ),
  )
}

///|
test "maps" {
  let by_name : Map[String, Int] = { "a": 1, "b": 2 }
  let by_id : Map[Int, String] = { 1: "x", 2: "y" }
  let x = @features.Maps::new(by_name~, by_id~, pairs=[("p", 1.5), ("q", 2)])
  let s = @features.string_of_maps(x)
  inspect(
    s,
    content=(
      #|{"by_name":{"a":1,"b":2},"by_id":[[1,"x"],[2,"y"]],"pairs":{"p":1.5,"q":2}}
    ),
  )
  assert_eq(@features.maps_of_string(s), x)
}

///|
test "lifted inline types" {
  let x : @features.Inline = Point(@features.InlinePoint::new(x=1, y=2))
  inspect(
    @features.string_of_inline(x),
    content=(
      #|["Point",{"x":1,"y":2}]
    ),
  )
  let y : @features.Inline = Nested([A, B(@features.InlineNestedB::new(z=3))])
  let s = @features.string_of_inline(y)
  inspect(
    s,
    content=(
      #|["Nested",["A",["B",{"z":3}]]]
    ),
  )
  assert_eq(@features.inline_of_string(s), y)
}

///|
test "recursive types" {
  let t : @features.Tree = Node(Leaf(1), Node(Leaf(2), Leaf(3)))
  let f = @features.Forest::new(
    trees=[t],
    parent=@features.Forest::new(trees=[Leaf(0)]),
  )
  let s = @features.string_of_forest(f)
  inspect(
    s,
    content=(
      #|{"trees":[["Node",[["Leaf",1],["Node",[["Leaf",2],["Leaf",3]]]]]],"parent":{"trees":[["Leaf",0]]}}
    ),
  )
  assert_eq(@features.forest_of_string(s), f)
}

///|
test "default values" {
  let d = @features.defaults_of_string("{}")
  debug_inspect(
    d,
    content=(
      #|{
      #|  b: false,
      #|  i: 0,
      #|  f: 0,
      #|  s: "",
      #|  l: [],
      #|  o: None,
      #|  u: (),
      #|  j: Null,
      #|  alias_default: [],
      #|  custom: [1, 2, 3],
      #|  custom_enum: Red,
      #|}
    ),
  )
  assert_eq(d, @features.Defaults::new())
  // null means "missing"
  let d2 = @features.defaults_of_string("{\"i\": null, \"custom\": [4]}")
  assert_eq(d2.i, 0)
  assert_eq(d2.custom, [4])
  inspect(
    @features.string_of_defaults(d),
    content=(
      #|{"b":false,"i":0,"f":0,"s":"","l":[],"o":null,"u":null,"j":null,"alias_default":[],"custom":[1,2,3],"custom_enum":"Red"}
    ),
  )
}

///|
test "keep_nulls" {
  // "set x to 1, clear y and keep z as it is"
  let p = @features.patch_of_string("{\"x\": 1, \"y\": null}")
  debug_inspect(
    p,
    content=(
      #|{ x: Some(Some(1)), y: Some(None), z: None }
    ),
  )
  inspect(
    @features.string_of_patch(p),
    content=(
      #|{"x":1,"y":null}
    ),
  )
  // without keep_nulls, null means "missing"
  let p = @features.no_patch_of_string("{\"x\": null}")
  debug_inspect(
    p,
    content=(
      #|{ x: None }
    ),
  )
}

///|
test "open enums" {
  let l = ["Apple", "Banana", "Cherry"].map(s => {
    @features.read_fruit(Json::string(s), @atd_runtime.Path::Root)
  }) catch {
    _ => []
  }
  debug_inspect(
    l,
    content=(
      #|[Apple, Banana, Other("Cherry")]
    ),
  )
  inspect(
    @features.string_of_fruit(Other("Cherry")),
    content=(
      #|["Other","Cherry"]
    ),
  )
}

///|
test "tuples" {
  let x = @features.Tuples::new(
    unit_tuple=(),
    single=1,
    pair=(2, "two"),
    annotated=(3, 3.5),
  )
  let s = @features.string_of_tuples(x)
  inspect(
    s,
    content=(
      #|{"unit_tuple":[],"single":[1],"pair":[2,"two"],"annotated":[3,3.5]}
    ),
  )
  assert_eq(@features.tuples_of_string(s), x)
  inspect(
    error_message(() => {
      ignore(
        @features.tuples_of_string(
          "{\"unit_tuple\":[1],\"single\":[1],\"pair\":[2,\"two\"],\"annotated\":[3,3.5]}",
        ),
      )
    }),
    content=(
      #|incompatible JSON value where type 'tuple of length 0' was expected: '[1]' at $.unit_tuple
    ),
  )
}

///|
test "wrapped types" {
  let x = @features.Temperatures::new(
    temps=[@features.Celsius(21.5)],
    plain="abc",
  )
  let s = @features.string_of_temperatures(x)
  inspect(
    s,
    content=(
      #|{"temps":[21.5],"plain":"abc"}
    ),
  )
  assert_eq(@features.temperatures_of_string(s), x)
}

///|
test "monomorphized polymorphic types" {
  let l : @features.IntEntries = [
    @features.StringIntEntry::new(key="a", value=1),
  ]
  let s = @features.string_of_int_entries(l)
  inspect(
    s,
    content=(
      #|[{"key":"a","value":1}]
    ),
  )
  assert_eq(@features.int_entries_of_string(s), l)
  let raw : @features.Raw = Json::array([Json::number(1)])
  inspect(@features.string_of_raw(raw), content="[1]")
}

///|
test "imported types" {
  let x = @features.Tagged::new(tag="t", tags=["a", "b"])
  let s = @features.string_of_tagged(x)
  inspect(
    s,
    content=(
      #|{"tag":"t","tags":["a","b"]}
    ),
  )
  assert_eq(@features.tagged_of_string(s), x)
}

///|
test "empty record" {
  inspect(
    @features.string_of_empty_record(@features.EmptyRecord::new()),
    content="{}",
  )
  assert_eq(
    @features.empty_record_of_string("{\"ignored\": 1}"),
    @features.EmptyRecord::new(),
  )
}

///|
test "error paths" {
  inspect(
    error_message(() => {
      ignore(
        @features.forest_of_string(
          "{\"trees\": [[\"Node\", [[\"Leaf\", 1], [\"Leaf\", \"x\"]]]]}",
        ),
      )
    }),
    content=(
      #|incompatible JSON value where type 'int' was expected: '"x"' at $.trees[0][1][1][1]
    ),
  )
  inspect(
    error_message(() => {
      ignore(
        @features.match_of_string(
          "{\"match\": 1, \"fn\": \"\", \"type_\": \"\"}",
        ),
      )
    }),
    content=(
      #|missing field 'x'' in JSON object of type 'match' at $
    ),
  )
}
