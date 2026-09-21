///|
test "empty graph and dependency chain are valid" {
  validate([], [])
  validate(["database/primary", "service/api", "worker/jobs"], [
    ("database/primary", "service/api"),
    ("service/api", "worker/jobs"),
  ])
}

///|
test "duplicate nodes are rejected" {
  try validate(["service/api", "service/api"], []) catch {
    GraphError::DuplicateNode(node) => inspect(node, content="service/api")
    _ => fail("wrong graph error")
  } noraise {
    _ => fail("expected a duplicate node error")
  }
}

///|
test "empty and missing nodes are rejected" {
  try validate([""], []) catch {
    GraphError::EmptyNode(node) => inspect(node, content="")
    _ => fail("wrong graph error")
  } noraise {
    _ => fail("expected an empty node error")
  }
  try validate(["service/api"], [("database/primary", "service/api")]) catch {
    GraphError::MissingNode(node) => inspect(node, content="database/primary")
    _ => fail("wrong graph error")
  } noraise {
    _ => fail("expected a missing node error")
  }
}

///|
test "self and duplicate dependencies are rejected" {
  try validate(["service/api"], [("service/api", "service/api")]) catch {
    GraphError::SelfDependency(node) => inspect(node, content="service/api")
    _ => fail("wrong graph error")
  } noraise {
    _ => fail("expected a self dependency error")
  }
  try
    validate(["database/primary", "service/api"], [
      ("database/primary", "service/api"),
      ("database/primary", "service/api"),
    ])
  catch {
    GraphError::DuplicateDependency(dependency, dependent) => {
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
    validate(["database/primary", "service/api", "worker/jobs"], [
      ("database/primary", "service/api"),
      ("service/api", "worker/jobs"),
      ("worker/jobs", "database/primary"),
    ])
  catch {
    GraphError::Cycle(node) => inspect(node, content="database/primary")
    _ => fail("wrong graph error")
  } noraise {
    _ => fail("expected a cycle error")
  }
}
