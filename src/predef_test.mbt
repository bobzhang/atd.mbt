///|
test "get_original_definition follows aliases and stops on cycles" {
  let m = @atd.load_string(
    (
      #|type a = b
      #|type b = c
      #|type c = { x : int }
      #|type t = t
      #|type u = v
      #|type v = u
      #|type w = abstract
    ),
  )
  let tbl = @atd.make_predef_table(m.type_defs)
  let orig = (n : String) => {
    match @atd.get_original_definition(tbl, @atd.TypeName::simple(n)) {
      Some((_, Some(d))) => d.name.to_string()
      Some((_, None)) => "(predefined)"
      None => "(undefined)"
    }
  }
  inspect(
    ["a", "t", "u", "w", "int", "nope"].map(orig).join(" "),
    content="c t v (predefined) (predefined) (undefined)",
  )
}
