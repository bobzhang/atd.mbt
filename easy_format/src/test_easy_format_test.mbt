// Ported from easy-format's test/test_easy_format.ml (https://github.com/ocaml-community/easy-format);
// the expected output is the output of the OCaml program.

///|
fn make_data(
  list_param : @easy_format.ListParam,
  label_param : @easy_format.LabelParam,
  atom_param : @easy_format.AtomParam,
) -> @easy_format.T {
  let obj_param = ("{", ",", "}", list_param)
  let array_param = ("[", ",", "]", list_param)
  let at = (s : String) => @easy_format.T::Atom(s, atom_param)
  let obj = @easy_format.T::List(obj_param, [
    Label((at("x:"), label_param), at("y")),
    Label(
      (at("y:"), label_param),
      List(obj_param, [Label((at("z:"), label_param), at("aaa"))]),
    ),
    Label(
      (at("a:"), label_param),
      List(array_param, [
        at("abc"),
        at(
          "\"long long long......................................" +
          "....................................................\"",
        ),
      ]),
    ),
    Label(
      (
        at(
          "\"a long label .................." +
          ".............................\":",
        ),
        label_param,
      ),
      List(array_param, [
        at("123"),
        at("456"),
        at("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"),
      ]),
    ),
  ])
  let array = @easy_format.T::List(array_param, [
    at("a"),
    at("b"),
    at("c"),
    at("d"),
  ])
  Label(
    (at("abc:"), label_param),
    List(array_param, [obj, array, obj, at("xyz")]),
  )
}

///|
test "long lists" {
  // a test of stack overflows in OCaml
  let data = @easy_format.T::List(
    ("[", ",", "]", @easy_format.list),
    Array::make(1_000_000, @easy_format.T::Atom("x", @easy_format.atom)),
  )
  let s = @easy_format.to_string(data)
  // like OCaml's output
  assert_eq(s.length(), 3080002)
  assert_eq(
    s.view(end_offset=87).to_owned(),
    "[\n  x, x, x, x, x, x, x, x, x, x, x, x, x, x, x, x, x, x, x, x, x, x, x, x, x,\n  x, x, ",
  )
}

///|
test "test_easy_format" {
  let list = @easy_format.list
  let label = @easy_format.label
  let atom = @easy_format.atom
  let x1 = make_data(list, label, atom)
  let x2 = make_data(
    {
      ..list,
      space_after_opening: false,
      space_after_separator: false,
      space_before_closing: false,
      stick_to_label: false,
      align_closing: false,
    },
    { ..label, space_after_label: true, },
    atom,
  )
  let x3 = make_data(
    {
      ..list,
      space_after_opening: false,
      space_before_separator: true,
      space_after_separator: true,
      separators_stick_left: false,
      space_before_closing: false,
      stick_to_label: true,
      align_closing: true,
    },
    { ..label, space_after_label: true, },
    atom,
  )
  let x4 = make_data({ ..list, stick_to_label: false, }, label, atom)
  let stdout = StringBuilder()
  for x in [x1, x2, x3, x4] {
    @easy_format.to_buffer(stdout, x)
    stdout.write_char('\n')
  }
  @easy_format.compact_to_buffer(stdout, x1)
  stdout.write_char('\n')
  assert_eq(
    stdout.to_string(),
    (
      #|abc: [
      #|  {
      #|    x: y,
      #|    y: { z: aaa },
      #|    a: [
      #|      abc,
      #|      "long long long.........................................................................................."
      #|    ],
      #|    "a long label ...............................................": [
      #|      123, 456, xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
      #|    ]
      #|  },
      #|  [ a, b, c, d ],
      #|  {
      #|    x: y,
      #|    y: { z: aaa },
      #|    a: [
      #|      abc,
      #|      "long long long.........................................................................................."
      #|    ],
      #|    "a long label ...............................................": [
      #|      123, 456, xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
      #|    ]
      #|  },
      #|  xyz
      #|]
      #|abc:
      #|  [{x: y,
      #|    y: {z: aaa},
      #|    a:
      #|      [abc,
      #|       "long long long.........................................................................................."],
      #|    "a long label ...............................................":
      #|      [123,456,xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx]},
      #|   [a,b,c,d],
      #|   {x: y,
      #|    y: {z: aaa},
      #|    a:
      #|      [abc,
      #|       "long long long.........................................................................................."],
      #|    "a long label ...............................................":
      #|      [123,456,xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx]},
      #|   xyz]
      #|abc: [
      #|    {
      #|        x: y
      #|      , y: {z: aaa}
      #|      , a: [
      #|            abc
      #|          , "long long long.........................................................................................."
      #|        ]
      #|      , "a long label ...............................................": [
      #|            123 , 456
      #|          , xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
      #|        ]
      #|    }
      #|  , [a , b , c , d]
      #|  , {
      #|        x: y
      #|      , y: {z: aaa}
      #|      , a: [
      #|            abc
      #|          , "long long long.........................................................................................."
      #|        ]
      #|      , "a long label ...............................................": [
      #|            123 , 456
      #|          , xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
      #|        ]
      #|    }
      #|  , xyz
      #|]
      #|abc:
      #|  [
      #|    {
      #|      x: y,
      #|      y: { z: aaa },
      #|      a:
      #|        [
      #|          abc,
      #|          "long long long.........................................................................................."
      #|        ],
      #|      "a long label ...............................................":
      #|        [
      #|          123, 456, xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
      #|        ]
      #|    },
      #|    [ a, b, c, d ],
      #|    {
      #|      x: y,
      #|      y: { z: aaa },
      #|      a:
      #|        [
      #|          abc,
      #|          "long long long.........................................................................................."
      #|        ],
      #|      "a long label ...............................................":
      #|        [
      #|          123, 456, xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
      #|        ]
      #|    },
      #|    xyz
      #|  ]
      #|abc:[{x:y,y:{z:aaa},a:[abc,"long long long.........................................................................................."],"a long label ...............................................":[123,456,xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx]},[a,b,c,d],{x:y,y:{z:aaa},a:[abc,"long long long.........................................................................................."],"a long label ...............................................":[123,456,xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx]},xyz]
      #|
    ),
  )
}

///|
test "README example" {
  let point = @easy_format.T::List(("{", ",", "}", @easy_format.list), [
    Label(
      (Atom("x:", @easy_format.atom), @easy_format.label),
      Atom("1", @easy_format.atom),
    ),
    Label(
      (Atom("y:", @easy_format.atom), @easy_format.label),
      Atom("2", @easy_format.atom),
    ),
  ])
  inspect(@easy_format.to_string(point), content="{ x: 1, y: 2 }")
  inspect(@easy_format.compact_to_string(point), content="{x:1,y:2}")
}
