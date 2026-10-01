// Port of atd/test/unique_name.ml

///|
test "unique names: reserved identifiers" {
  let u = @atd.UniqueNames(
    reserved_identifiers=["y"],
    reserved_prefixes=[],
    safe_prefix="x_",
  )
  assert_eq(u.translate_only("a"), None)
  assert_eq(u.translate("a"), "a")
  assert_eq(u.translate("a"), "a")
  assert_eq(u.translate_only("a"), Some("a"))
  assert_eq(u.translate("y_"), "y_")
  assert_eq(u.translate("y"), "y2")
  let u = @atd.UniqueNames(
    reserved_identifiers=["y"],
    reserved_prefixes=["y_"],
    safe_prefix="x_",
  )
  assert_eq(u.translate("y"), "x_y_")
}

///|
test "panic unique names: safe prefix conflicting with the empty prefix" {
  ignore(
    @atd.UniqueNames(
      reserved_identifiers=[],
      reserved_prefixes=[""],
      safe_prefix="x_",
    ),
  )
}

///|
test "panic unique names: safe prefix conflicting with a reserved prefix" {
  ignore(
    @atd.UniqueNames(
      reserved_identifiers=[],
      reserved_prefixes=["x"],
      safe_prefix="x_",
    ),
  )
}

///|
test "unique names: reserved prefixes" {
  let u = @atd.UniqueNames(
    reserved_identifiers=[],
    reserved_prefixes=["y_"],
    safe_prefix="x_",
  )
  assert_eq(u.translate("a"), "a")
  assert_eq(u.translate("y_a"), "x_y_a")
  assert_eq(u.translate("y_a"), "x_y_a")
  assert_eq(u.translate("x_y_a_"), "x_y_a_")
  assert_eq(u.translate("x_y_a"), "x_y_a2")
  assert_eq(u.reverse_translate("x_y_a2"), Some("x_y_a"))
}

///|
test "unique names: identifier creation" {
  let u = @atd.UniqueNames(
    reserved_identifiers=[],
    reserved_prefixes=["y_"],
    safe_prefix="x_",
  )
  assert_eq(u.translate("y"), "y")
  assert_eq(u.create("y"), "y_")
  assert_eq(u.translate("y_"), "x_y_")
  assert_eq(u.create("y"), "y2")
  assert_eq(u.translate("y2"), "y2")
}
