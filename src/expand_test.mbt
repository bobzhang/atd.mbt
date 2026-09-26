///|
test "expand: polymorphic recursion is reported" {
  let src =
    #|type 'a t = [ Next of ('a list) t | End of 'a ]
    #|type root = int t
  try @atd.load_string(src, expand=true) catch {
    e =>
      inspect(
        e,
        content=(
          #|File "", line 2, characters 11-17:
          #|Cannot expand type t: its definition leads to infinitely many specializations (polymorphic recursion)
        ),
      )
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "expand: regular recursion terminates" {
  let src =
    #|type 'a tree = [ Leaf of 'a | Node of ('a tree * 'a tree) ]
    #|type t = int tree
  let m = @atd.load_string(src, expand=true)
  inspect(
    @atd.to_string(Module(m)),
    content=(
      #|type t = _int_tree
      #|type _int_tree = [ Leaf of int | Node of (_int_tree * _int_tree) ]
    ),
  )
}
