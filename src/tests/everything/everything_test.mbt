///|
/// The value used by the atdts test suite (`test_atdts.ts`).
fn sample_root() -> @everything.Root raise {
  @everything.Root::new(
    id="abc",
    this=100,
    items=[[], [1, 2]],
    extras=[17, 53],
    answer=42,
    aliased=[8, 9, 10],
    point=(3.3, -77.22),
    kinds=[
      @everything.DifferentKindsOfThings::WOW,
      @everything.DifferentKindsOfThings::Thing(99),
      @everything.DifferentKindsOfThings::Amaze(["a", "b"]),
      @everything.DifferentKindsOfThings::Root,
    ],
    assoc1=[(1.1, 1), (2.2, 2)],
    assoc2=[("c", 3), ("d", 4)],
    assoc3=[(5.5, 5), (6.6, 6)],
    assoc4=[("g", 7), ("h", 8)],
    options=[Some(10), None, Some(88)],
    nullables=[Some(13), Some(71)],
    untyped_things=[
      Json::empty_object(),
      Json::array([Json::array([Json::string("hello")])]),
      Json::number(123),
    ],
    foo=None,
    parametrized_record=@everything.IntFloatParametrizedRecord::new(
      field_a=42,
      field_b=[9.9, 8.8],
    ),
    parametrized_tuple=(
      @everything.DifferentKindsOfThings::WOW,
      @everything.DifferentKindsOfThings::WOW,
      100,
    ),
    anything=@atd_runtime.parse(
      "{\"any_a\": 1234, \"any_b\": [[], [[[]]], true, {}, null]}",
    ),
    wrapped=["a", "b"],
    ext_tag="hello",
  )
}

///|
/// The JSON expected by the atdts test suite for the same value, which
/// checks the compatibility of the JSON encodings.
let expected_json : String =
  #|{
  #|  "ID": "abc",
  #|  "this": 100,
  #|  "items": [[], [1, 2]],
  #|  "extras": [17, 53],
  #|  "answer": 42,
  #|  "aliased": [8, 9, 10],
  #|  "point": [3.3, -77.22],
  #|  "kinds": ["wow", ["Thing", 99], ["!!!", ["a", "b"]], "Root"],
  #|  "assoc1": [[1.1, 1], [2.2, 2]],
  #|  "assoc2": {"c": 3, "d": 4},
  #|  "assoc3": [[5.5, 5], [6.6, 6]],
  #|  "assoc4": {"g": 7, "h": 8},
  #|  "options": [["Some", 10], "None", ["Some", 88]],
  #|  "nullables": [13, 71],
  #|  "untyped_things": [{}, [["hello"]], 123],
  #|  "foo": null,
  #|  "parametrized_record": {"field_a": 42, "field_b": [9.9, 8.8]},
  #|  "parametrized_tuple": ["wow", "wow", 100],
  #|  "anything": {"any_a": 1234, "any_b": [[], [[[]]], true, {}, null]},
  #|  "wrapped": ["a", "b"],
  #|  "ext_tag": "hello"
  #|}

///|
test "everything: JSON output compatible with atdts" {
  let x = sample_root()
  let expected = @atd_runtime.parse(expected_json).stringify()
  assert_eq(@everything.string_of_root(x), expected)
}

///|
test "everything: round-trip" {
  let x = sample_root()
  let s = @everything.string_of_root(x)
  let y = @everything.root_of_string(s)
  assert_eq(x, y)
  assert_eq(@everything.string_of_root(y), s)
  // reading the atdts output gives the same value
  assert_eq(@everything.root_of_string(expected_json), x)
}

///|
test "everything: missing optional and default fields" {
  let json =
    #|{"ID": "x", "this": 1, "items": [], "aliased": [], "point": [0, 0],
    #| "kinds": [], "assoc1": [], "assoc2": {}, "assoc3": [], "assoc4": {},
    #| "untyped_things": [], "foo": {"foo": "bar"},
    #| "parametrized_record": {"field_a": 0},
    #| "parametrized_tuple": ["Root", "Root", 0], "anything": null,
    #| "wrapped": [], "ext_tag": "", "maybe": null}
  let x = @everything.root_of_string(json)
  debug_inspect(x.maybe, content="None")
  debug_inspect(x.maybe2, content="None")
  debug_inspect(x.extras, content="[]")
  debug_inspect(x.answer, content="0")
  debug_inspect(x.foo, content="Some({ foo: \"bar\" })")
  debug_inspect(x.parametrized_record.field_b, content="[]")
  // optional fields set to None are omitted
  inspect(
    @everything.string_of_root(x),
    content=(
      #|{"ID":"x","this":1,"items":[],"extras":[],"answer":0,"aliased":[],"point":[0,0],"kinds":[],"assoc1":[],"assoc2":{},"assoc3":[],"assoc4":{},"options":[],"nullables":[],"untyped_things":[],"foo":{"foo":"bar"},"parametrized_record":{"field_a":0,"field_b":[]},"parametrized_tuple":["Root","Root",0],"anything":null,"wrapped":[],"ext_tag":""}
    ),
  )
}

///|
/// Return the message of the error raised by `f`.
fn error_message(f : () -> Unit raise @atd_runtime.JsonError) -> String raise {
  try f() catch {
    e => e.message()
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "everything: sum types represented as JSON objects" {
  inspect(
    @everything.string_of_shape(@everything.Shape::Circle(3.14)),
    content="{\"Circle\":3.14}",
  )
  inspect(
    @everything.string_of_shape(@everything.Shape::Point),
    content="\"Point\"",
  )
  assert_eq(
    @everything.shape_of_string("{\"Square\": 2}"),
    @everything.Shape::Square(2),
  )
  assert_eq(@everything.shape_of_string("\"Point\""), @everything.Shape::Point)
  inspect(
    error_message(() => {
      ignore(@everything.shape_of_string("{\"Square\": 2, \"Circle\": 1}"))
    }),
    content=(
      #|incompatible JSON value where type 'shape' was expected: '{"Square":2,"Circle":1}' at $
    ),
  )
}

///|
test "everything: errors" {
  inspect(
    error_message(() => ignore(@everything.root_of_string("{\"ID\": \"x\"}"))),
    content=(
      #|missing field 'this' in JSON object of type 'root' at $
    ),
  )
  inspect(
    error_message(() => {
      ignore(
        @everything.different_kinds_of_things_of_string("[\"Thing\", 1.5]"),
      )
    }),
    content=(
      #|incompatible JSON value where type 'int' was expected: '1.5' at $[1]
    ),
  )
  inspect(
    error_message(() => ignore(@everything.pair_of_string("[\"a\"]"))),
    content=(
      #|incompatible JSON value where type 'tuple of length 2' was expected: '["a"]' at $
    ),
  )
  inspect(
    error_message(() => ignore(@everything.root_of_string("{\"ID\""))),
    content=(
      #|invalid JSON: Unexpected end of file
    ),
  )
}

///|
test "everything: ToJson" {
  let x : @everything.DifferentKindsOfThings = Thing(3)
  json_inspect(x, content=["Thing", 3])
}
