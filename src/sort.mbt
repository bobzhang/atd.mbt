// Topological sort that doesn't give up on cycles, a port of `sort.ml`.
//
//   A --> B
//   C --> D        gives: [A] [B C] [D]
//   B --> C
//   C --> B
//
// Sets of nodes are represented as arrays of node indices sorted by node
// identifier, reproducing the iteration order of OCaml's `Set`.

///|
priv struct SortGraph {
  /// node index -> neighbors (indices)
  forward : Array[Array[Int]]
  backward : Array[Array[Int]]
  /// node index -> rank of its id in the sorted order of ids
  rank : Array[Int]
  visited : Array[Bool]
}

///|
/// A set of node indices, kept sorted by rank.
priv struct NodeSet {
  elts : Array[Int]
}

///|
fn SortGraph::empty(_self : SortGraph) -> NodeSet {
  { elts: [], }
}

///|
fn SortGraph::singleton(_self : SortGraph, v : Int) -> NodeSet {
  { elts: [v], }
}

///|
fn NodeSet::mem(self : NodeSet, v : Int) -> Bool {
  self.elts.contains(v)
}

///|
fn SortGraph::add(self : SortGraph, s : NodeSet, v : Int) -> NodeSet {
  if s.mem(v) {
    return s
  }
  let elts = s.elts.copy()
  let r = self.rank[v]
  let mut i = 0
  while i < elts.length() && self.rank[elts[i]] < r {
    i += 1
  }
  elts.insert(i, v)
  { elts, }
}

///|
fn NodeSet::remove(self : NodeSet, v : Int) -> NodeSet {
  { elts: self.elts.filter(x => x != v), }
}

///|
fn NodeSet::diff(self : NodeSet, other : NodeSet) -> NodeSet {
  { elts: self.elts.filter(x => !other.mem(x)), }
}

///|
fn NodeSet::inter(self : NodeSet, other : NodeSet) -> NodeSet {
  { elts: self.elts.filter(x => other.mem(x)), }
}

///|
fn NodeSet::is_empty(self : NodeSet) -> Bool {
  self.elts.is_empty()
}

///|
fn NodeSet::pick_one(self : NodeSet) -> (Int, NodeSet)? {
  match self.elts {
    [] => None
    [v, .. rest] => Some((v, { elts: rest.to_owned(), }))
  }
}

///|
fn filtered_neighbors(
  v : Int,
  edges : Array[Array[Int]],
  graph_nodes : NodeSet,
) -> Array[Int] {
  edges[v].filter(n => graph_nodes.mem(n))
}

///|
fn SortGraph::eliminate_roots_recursively(
  self : SortGraph,
  edges : Array[Array[Int]],
  back_edges : Array[Array[Int]],
  nodes : NodeSet,
) -> (Array[(Bool, NodeSet)], NodeSet) {
  let sorted = []
  let mut graph_nodes = nodes
  let mut input_nodes = nodes
  while input_nodes.pick_one() is Some((v, rest)) {
    input_nodes = rest
    if filtered_neighbors(v, back_edges, graph_nodes).is_empty() {
      sorted.push(v)
      let children = filtered_neighbors(v, edges, graph_nodes)
      graph_nodes = graph_nodes.remove(v)
      for c in children {
        input_nodes = self.add(input_nodes, c)
      }
    }
  }
  (sorted.map(v => (false, self.singleton(v))), graph_nodes)
}

///|
fn SortGraph::eliminate_roots(
  self : SortGraph,
  nodes : NodeSet,
) -> (Array[(Bool, NodeSet)], NodeSet) {
  self.eliminate_roots_recursively(self.forward, self.backward, nodes)
}

///|
fn SortGraph::eliminate_leaves(
  self : SortGraph,
  nodes : NodeSet,
) -> (NodeSet, Array[(Bool, NodeSet)]) {
  let (sorted_leaves, remaining) = self.eliminate_roots_recursively(
    self.backward,
    self.forward,
    nodes,
  )
  (remaining, sorted_leaves.rev())
}

///|
/// Collect all nodes reachable from the start node, excluding the start
/// node unless it can be reached by some cycle.
fn SortGraph::visit(
  self : SortGraph,
  edges : Array[Array[Int]],
  start_node : Int,
  nodes : NodeSet,
) -> NodeSet {
  let visited = []
  let mut acc = self.empty()
  fn color(v : Int) -> Unit {
    if !self.visited[v] {
      self.visited[v] = true
      visited.push(v)
      for neighbor in edges[v] {
        if nodes.mem(neighbor) {
          acc = self.add(acc, neighbor)
          color(neighbor)
        }
      }
    }
  }

  color(start_node)
  for v in visited {
    self.visited[v] = false
  }
  acc
}

///|
fn SortGraph::sort_subgraph(
  self : SortGraph,
  nodes : NodeSet,
) -> Array[(Bool, NodeSet)] {
  let (sorted_left, nodes) = self.eliminate_roots(nodes)
  let (nodes, sorted_right) = self.eliminate_leaves(nodes)
  let sorted_middle = match nodes.pick_one() {
    None => []
    Some((pivot, _)) => self.partition(pivot, nodes)
  }
  let res = sorted_left
  res.append(sorted_middle)
  res.append(sorted_right)
  res
}

///|
fn SortGraph::partition(
  self : SortGraph,
  pivot : Int,
  nodes : NodeSet,
) -> Array[(Bool, NodeSet)] {
  let ancestors = self.visit(self.backward, pivot, nodes)
  let descendants = self.visit(self.forward, pivot, nodes)
  let strict_ancestors = ancestors.diff(descendants)
  let strict_descendants = descendants.diff(ancestors)
  let cycle = descendants.inter(ancestors)
  let (is_cyclic, pivot_group) = if cycle.is_empty() {
    (false, self.singleton(pivot))
  } else {
    (true, cycle)
  }
  let other = nodes
    .diff(pivot_group)
    .diff(strict_ancestors)
    .diff(strict_descendants)
  let res = self.sort_subgraph(strict_ancestors)
  res.push((is_cyclic, pivot_group))
  res.append(self.sort_subgraph(strict_descendants))
  res.append(self.sort_subgraph(other))
  res
}

///|
/// Sort the nodes topologically. Each input element comes with the list of
/// identifiers of the nodes it points to. The result is a list of groups;
/// a group flagged `true` is a cycle. Groups are sorted such that edges only
/// go from a group to itself or to later groups.
pub fn[T, Id : Compare + Hash + Eq] topological_sort(
  l : ArrayView[(T, Array[Id])],
  id : (T) -> Id,
) -> Array[(Bool, Array[T])] {
  let node_tbl : Map[Id, Int] = Map([])
  let values : Array[T] = []
  let ids : Array[Id] = []
  for x in l {
    let i = id(x.0)
    if !node_tbl.contains(i) {
      node_tbl[i] = values.length()
      values.push(x.0)
      ids.push(i)
    }
  }
  let n = values.length()
  let order = Array::makei(n, i => i)
  order.sort_by((a, b) => Compare::compare(ids[a], ids[b]))
  let rank = Array::make(n, 0)
  for r, v in order {
    rank[v] = r
  }
  let forward = Array::makei(n, _ => [])
  let backward = Array::makei(n, _ => [])
  for x in l {
    let v1 = node_tbl[id(x.0)]
    for id2 in x.1 {
      match node_tbl.get(id2) {
        None => ()
        Some(v2) => {
          forward[v1].push(v2)
          backward[v2].push(v1)
        }
      }
    }
  }
  let graph : SortGraph = {
    forward,
    backward,
    rank,
    visited: Array::make(n, false),
  }
  let groups = graph.sort_subgraph({ elts: order, })
  groups.map(g => (g.0, g.1.elts.map(v => values[v])))
}
