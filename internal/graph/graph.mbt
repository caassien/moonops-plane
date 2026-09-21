///|
/// Errors raised while validating a resource dependency graph.
pub(all) suberror GraphError {
  EmptyNode(String)
  DuplicateNode(String)
  MissingNode(String)
  SelfDependency(String)
  DuplicateDependency(String, String)
  Cycle(String)
} derive(Debug, Eq)

///|
fn node_index(nodes : Array[String], value : String) -> Int? {
  let mut result : Int? = None
  for i, node in nodes {
    if result is None && node == value {
      result = Some(i)
    }
  }
  result
}

///|
fn validate_nodes(nodes : Array[String]) -> Unit raise GraphError {
  for i in 0..<nodes.length() {
    if nodes[i] == "" {
      raise GraphError::EmptyNode(nodes[i])
    }
    for j in 0..<i {
      if nodes[i] == nodes[j] {
        raise GraphError::DuplicateNode(nodes[i])
      }
    }
  }
}

///|
fn build_adjacency(
  nodes : Array[String],
  dependencies : Array[(String, String)],
) -> Array[Array[Int]] raise GraphError {
  let adjacency : Array[Array[Int]] = []
  for _ in 0..<nodes.length() {
    adjacency.push([])
  }
  for i in 0..<dependencies.length() {
    let (dependency, dependent) = dependencies[i]
    if dependency == dependent {
      raise GraphError::SelfDependency(dependency)
    }
    let dependency_index = match node_index(nodes, dependency) {
      Some(index) => index
      None => raise GraphError::MissingNode(dependency)
    }
    let dependent_index = match node_index(nodes, dependent) {
      Some(index) => index
      None => raise GraphError::MissingNode(dependent)
    }
    for existing in adjacency[dependency_index] {
      if existing == dependent_index {
        raise GraphError::DuplicateDependency(dependency, dependent)
      }
    }
    adjacency[dependency_index].push(dependent_index)
  }
  adjacency
}

///|
fn visit(
  node : Int,
  nodes : Array[String],
  adjacency : Array[Array[Int]],
  state : Array[Int],
) -> Unit raise GraphError {
  if state[node] == 1 {
    raise GraphError::Cycle(nodes[node])
  }
  if state[node] == 2 {
    ()
  } else {
    state[node] = 1
    for dependent in adjacency[node] {
      visit(dependent, nodes, adjacency, state)
    }
    state[node] = 2
  }
}

///|
/// Validates nodes and dependency edges, including cycles.
pub fn validate(
  nodes : Array[String],
  dependencies : Array[(String, String)],
) -> Unit raise GraphError {
  validate_nodes(nodes)
  let adjacency = build_adjacency(nodes, dependencies)
  let state : Array[Int] = []
  for _ in 0..<nodes.length() {
    state.push(0)
  }
  for i in 0..<nodes.length() {
    if state[i] == 0 {
      visit(i, nodes, adjacency, state)
    }
  }
}
