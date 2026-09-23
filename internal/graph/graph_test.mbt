///|
test "empty graph and dependency chain are valid" {
  @graph.validate([], [])
  @graph.validate(["database/primary", "service/api", "worker/jobs"], [
    ("database/primary", "service/api"),
    ("service/api", "worker/jobs"),
  ])
}

///|
test "duplicate nodes are rejected" {
  try @graph.validate(["service/api", "service/api"], []) catch {
    @graph.GraphError::DuplicateNode(node) =>
      inspect(node, content="service/api")
    _ => fail("wrong graph error")
  } noraise {
    _ => fail("expected a duplicate node error")
  }
}

///|
test "empty and missing nodes are rejected" {
  try @graph.validate([""], []) catch {
    @graph.GraphError::EmptyNode(node) => inspect(node, content="")
    _ => fail("wrong graph error")
  } noraise {
    _ => fail("expected an empty node error")
  }
  try
    @graph.validate(["service/api"], [("database/primary", "service/api")])
  catch {
    @graph.GraphError::MissingNode(node) =>
      inspect(node, content="database/primary")
    _ => fail("wrong graph error")
  } noraise {
    _ => fail("expected a missing node error")
  }
}

///|
test "self and duplicate dependencies are rejected" {
  try @graph.validate(["service/api"], [("service/api", "service/api")]) catch {
    @graph.GraphError::SelfDependency(node) =>
      inspect(node, content="service/api")
    _ => fail("wrong graph error")
  } noraise {
    _ => fail("expected a self dependency error")
  }
  try
    @graph.validate(["database/primary", "service/api"], [
      ("database/primary", "service/api"),
      ("database/primary", "service/api"),
    ])
  catch {
    @graph.GraphError::DuplicateDependency(dependency, dependent) => {
      inspect(dependency, content="database/primary")
      inspect(dependent, content="service/api")
    }
    _ => fail("wrong graph error")
  } noraise {
    _ => fail("expected a duplicate dependency error")
  }
}

///|
test "cycles are rejected with a stable node" {
  try
    @graph.validate(["database/primary", "service/api", "worker/jobs"], [
      ("database/primary", "service/api"),
      ("service/api", "worker/jobs"),
      ("worker/jobs", "database/primary"),
    ])
  catch {
    @graph.GraphError::Cycle(node) => inspect(node, content="database/primary")
    _ => fail("wrong graph error")
  } noraise {
    _ => fail("expected a cycle error")
  }
}
