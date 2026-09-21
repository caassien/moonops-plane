///|
fn dependency_resource(
  kind~ : String,
  name~ : String,
) -> ResourceId raise ModelError {
  ResourceId::new(kind~, name~)
}

///|
test "valid dependency chain is accepted" {
  let database = try! dependency_resource(kind="database", name="primary")
  let api = try! dependency_resource(kind="service", name="api")
  validate_resource_dependencies([database, api], [(database, api)])
}

///|
test "missing resource is mapped to a model error" {
  let api = try! dependency_resource(kind="service", name="api")
  let database = try! dependency_resource(kind="database", name="primary")
  try validate_resource_dependencies([api], [(database, api)]) catch {
    ModelError::InvalidDependency(message) =>
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
    validate_resource_dependencies([database, api], [
      (database, api),
      (api, database),
    ])
  catch {
    ModelError::DependencyCycle(node) =>
      inspect(node, content="database/primary")
    _ => fail("wrong dependency error")
  } noraise {
    _ => fail("expected a dependency cycle error")
  }
}
