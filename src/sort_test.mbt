// Port of the tests of atd/src/sort.ml

///|
fn in_order(result : Array[(Bool, Array[Int])], a : Int, b : Int) -> Bool {
  for i, g in result {
    let l = g.1
    if l.contains(b) {
      return false
    } else if l.contains(a) {
      return result[i + 1:].iter().any(g => g.1.contains(b))
    }
  }
  false
}

///|
fn in_same_cycle(result : Array[(Bool, Array[Int])], a : Int, b : Int) -> Bool {
  result.iter().any(g => g.0 && g.1.contains(a) && g.1.contains(b))
}

///|
fn not_in_cycle(result : Array[(Bool, Array[Int])], x : Int) -> Bool {
  result.iter().any(g => !g.0 && g.1 == [x])
}

///|
fn seq(r : Array[(Bool, Array[Int])], a : Int, b : Int) -> Bool {
  in_order(r, a, b) && !in_order(r, b, a) && !in_same_cycle(r, a, b)
}

///|
fn cyc(r : Array[(Bool, Array[Int])], a : Int, b : Int) -> Bool {
  in_same_cycle(r, a, b) && !in_order(r, a, b) && !in_order(r, b, a)
}

///|
fn sorted(l : Array[(Int, Array[Int])]) -> Array[(Bool, Array[Int])] {
  @atd.topological_sort(l, x => x)
}

///|
test "sort: cycle" {
  let r = sorted([(1, [2]), (2, [3]), (3, [1])])
  assert_true(cyc(r, 1, 2))
  assert_true(cyc(r, 2, 3))
  assert_true(cyc(r, 1, 3))
}

///|
test "sort: chains" {
  let r = sorted([(1, [2]), (2, [3]), (3, []), (5, [6]), (4, [5]), (6, [])])
  assert_true(seq(r, 1, 2))
  assert_true(seq(r, 2, 3))
  assert_true(seq(r, 4, 5))
  assert_true(seq(r, 5, 6))
  assert_true(not_in_cycle(r, 3))
  assert_true(not_in_cycle(r, 6))
}

///|
test "sort: mixed" {
  let r = sorted([
    (1, [2, 3]),
    (2, [3]),
    (3, [3, 4]),
    (4, [3]),
    (5, [6]),
    (6, [6, 1]),
    (5, [7]),
    (7, [8]),
    (8, [9]),
    (9, [0]),
    (10, [10]),
    (11, [12]),
    (12, [13]),
    (13, [11]),
  ])
  assert_true(!not_in_cycle(r, 0))
  assert_true(!seq(r, 0, 1))
  assert_true(!seq(r, 1, 0))
  assert_true(!cyc(r, 0, 0))
  assert_true(not_in_cycle(r, 1))
  assert_true(seq(r, 1, 2))
  assert_true(seq(r, 1, 4))
  assert_true(seq(r, 1, 3))
  assert_true(seq(r, 2, 3))
  assert_true(cyc(r, 3, 4))
  assert_true(not_in_cycle(r, 5))
  assert_true(seq(r, 6, 1))
  assert_true(not_in_cycle(r, 7))
  assert_true(not_in_cycle(r, 8))
  assert_true(not_in_cycle(r, 9))
  assert_true(seq(r, 5, 9))
  assert_true(cyc(r, 10, 10))
  assert_true(cyc(r, 11, 12))
  assert_true(cyc(r, 12, 13))
  assert_true(cyc(r, 11, 13))
}

///|
test "tsort: type definitions" {
  let m = @atd.load_string(
    (
      #|type a = b list
      #|type b = { x : c option }
      #|type c = [ C of b | D ]
      #|type d = int
    ),
  )
  let groups = @atd.tsort(m.type_defs).map(g => {
    (g.0, g.1.map(d => d.name.to_string()))
  })
  debug_inspect(
    groups,
    content=(
      #|[(true, ["b", "c"]), (false, ["d"]), (false, ["a"])]
    ),
  )
}
