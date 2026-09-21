///|
fn resource_key(resource : ResourceId) -> String {
  "\{resource.kind}/\{resource.name}"
}

///|
/// Validates resource dependency edges before a plan is generated.
///
/// Each dependency pair is `(dependency, dependent)`: the first resource
/// must be ready before the second resource may be changed.
pub fn validate_resource_dependencies(
  resources : Array[ResourceId],
  dependencies : Array[(ResourceId, ResourceId)],
) -> Unit raise ModelError {
  let node_names : Array[String] = []
  for resource in resources {
    node_names.push(resource_key(resource))
  }
  let edge_names : Array[(String, String)] = []
  for i in 0..<dependencies.length() {
    let (dependency, dependent) = dependencies[i]
    edge_names.push((resource_key(dependency), resource_key(dependent)))
  }
  @graph.validate(node_names, edge_names) catch {
    @graph.GraphError::EmptyNode(node) =>
      raise ModelError::InvalidDependency("empty resource: \{node}")
    @graph.GraphError::DuplicateNode(node) =>
      raise ModelError::InvalidDependency("duplicate resource: \{node}")
    @graph.GraphError::MissingNode(node) =>
      raise ModelError::InvalidDependency("missing resource: \{node}")
    @graph.GraphError::SelfDependency(node) =>
      raise ModelError::InvalidDependency("self dependency: \{node}")
    @graph.GraphError::DuplicateDependency(dependency, dependent) =>
      raise ModelError::InvalidDependency(
        "duplicate dependency: \{dependency} -> \{dependent}",
      )
    @graph.GraphError::Cycle(node) => raise ModelError::DependencyCycle(node)
  }
}
