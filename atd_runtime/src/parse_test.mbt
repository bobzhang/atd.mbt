///|
test "parse keeps the text of numbers" {
  let j = @atd_runtime.parse(
    "[1, 1.0, -0, 12345678901234567890, 1e3, 2.5E-3, {\"a\": [true, false, null]}]",
  )
  inspect(
    j.stringify(),
    content="[1,1.0,-0,12345678901234567890,1e3,2.5E-3,{\"a\":[true,false,null]}]",
  )
}

///|
test "parse agrees with @json.parse" {
  let inputs = [
    "{}", "[]", "\"\\u00e9\\ud83d\\ude00\\n\\t\\\\\\\"\"", " { \"a\" : { \"b\" : [ 1 , 2 ] } } ",
    "\"caf\u{e9}\"", "-12.5e+10", "0",
  ]
  for s in inputs {
    assert_eq(@atd_runtime.parse(s), @json.parse(s), msg=s)
  }
}

///|
test "parse errors" {
  let errors = []
  for
    s in [
      "", "[1,]", "{\"a\" 1}", "01", "1.", "-", "\"abc", "[1] 2", "tru", "\"\\x\"",
    ] {
    errors.push(
      try @atd_runtime.parse(s) catch {
        e => e.message()
      } noraise {
        _ => "no error for " + s
      },
    )
  }
  inspect(
    errors.join("\n"),
    content=(
      #|invalid JSON: unexpected end of input at line 1, column 1
      #|invalid JSON: unexpected character at line 1, column 4
      #|invalid JSON: expected ':' at line 1, column 6
      #|invalid JSON: unexpected data after the JSON value at line 1, column 2
      #|invalid JSON: unexpected end of input at line 1, column 3
      #|invalid JSON: unexpected end of input at line 1, column 2
      #|invalid JSON: unexpected end of input at line 1, column 5
      #|invalid JSON: unexpected data after the JSON value at line 1, column 5
      #|invalid JSON: unexpected end of input at line 1, column 4
      #|invalid JSON: invalid escape sequence at line 1, column 4
    ),
  )
}

///|
test "integers must be integer literals" {
  let read = (s : String) => {
    try
      @atd_runtime.read_int(@atd_runtime.parse(s), @atd_runtime.Path::Root)
    catch {
      e => e.message()
    } noraise {
      n => n.to_string()
    }
  }
  inspect(
    [
      "1", "-2147483648", "2147483647", "2147483648", "1.0", "1e3", "1.0000000000000000001",
    ]
    .map(read)
    .join("\n"),
    content=(
      #|1
      #|-2147483648
      #|2147483647
      #|incompatible JSON value where type 'int' was expected: '2147483648' at $
      #|incompatible JSON value where type 'int' was expected: '1.0' at $
      #|incompatible JSON value where type 'int' was expected: '1e3' at $
      #|incompatible JSON value where type 'int' was expected: '1.0000000000000000001' at $
    ),
  )
  // values that don't come from `parse` are checked by value
  assert_eq(
    @atd_runtime.read_int(Json::number(3.0), @atd_runtime.Path::Root),
    3,
  )
  inspect(
    @atd_runtime.read_int64(
      @atd_runtime.parse("-9223372036854775808"),
      @atd_runtime.Path::Root,
    ),
    content="-9223372036854775808",
  )
}
