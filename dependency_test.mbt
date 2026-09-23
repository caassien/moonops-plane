///|
fn dependency_resource(
  kind~ : String,
  name~ : String,
) -> @orbitops_plane.ResourceId raise @orbitops_plane.ModelError {
  @orbitops_plane.ResourceId::new(kind~, name~)
}

///|
test "valid dependency chain is accepted" {
  let database = try! dependency_resource(kind="database", name="primary")
  let api = try! dependency_resource(kind="service", name="api")
  @orbitops_plane.validate_resource_dependencies([database, api], [
    (database, api),
  ])
}

///|
test "missing resource is mapped to a model error" {
  let api = try! dependency_resource(kind="service", name="api")
  let database = try! dependency_resource(kind="database", name="primary")
  try
    @orbitops_plane.validate_resource_dependencies([api], [(database, api)])
  catch {
    @orbitops_plane.ModelError::InvalidDependency(message) =>
      inspect(message, content="missing resource: database/primary")
    _ => fail("wrong dependency error")
  } noraise {
    _ => fail("expected a missing resource error")
  }
}

///|
test "cycle is mapped to a dependency cycle error" {
  let database = try! dependency_resource(kind="database", name="primary")
  let api = try! dependency_resource(kind="service", name="api")
  try
    @orbitops_plane.validate_resource_dependencies([database, api], [
      (database, api),
      (api, database),
    ])
  catch {
    @orbitops_plane.ModelError::DependencyCycle(node) =>
      inspect(node, content="database/primary")
    _ => fail("wrong dependency error")
  } noraise {
    _ => fail("expected a dependency cycle error")
  }
}
