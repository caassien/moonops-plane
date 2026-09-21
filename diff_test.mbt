///|
fn desired_state() -> DesiredState raise ModelError {
  let resource = ResourceId::new(kind="service", name="api")
  let spec = ResourceSpec::new(
    version="v1",
    replicas=2,
    config_fingerprint="cfg-v1",
    enabled=true,
  )
  DesiredState::new(resource~, spec~, generation=1)
}

///|
fn observed_state(
  version? : String = "v1",
  replicas? : Int = 2,
  config_fingerprint? : String = "cfg-v1",
  enabled? : Bool = true,
  healthy? : Bool = true,
) -> ObservedState raise ModelError {
  let resource = ResourceId::new(kind="service", name="api")
  let spec = ResourceSpec::new(
    version~,
    replicas~,
    config_fingerprint~,
    enabled~,
  )
  ObservedState::new(resource~, spec~, generation=1, healthy~)
}

///|
fn assert_action(
  result : DiffResult,
  expected_kind : ActionKind,
  expected_reason : String,
) -> Unit raise {
  match result {
    DiffResult::Action(operation) => {
      assert_eq(operation.action, expected_kind)
      assert_eq(operation.reason, expected_reason)
    }
    DiffResult::NoChange => fail("expected an action")
  }
}

///|
test "matching state produces no change" {
  let desired = try! desired_state()
  let observed = try! observed_state()
  assert_eq(compute_diff(desired, Some(observed)), DiffResult::NoChange)
}

///|
test "missing enabled resource produces create" {
  let desired = try! desired_state()
  assert_action(
    compute_diff(desired, None),
    ActionKind::Create,
    "resource is missing",
  )
}

///|
test "missing disabled resource produces no change" {
  let resource = ResourceId::new(kind="service", name="api")
  let spec = ResourceSpec::new(
    version="v1",
    replicas=0,
    config_fingerprint="cfg-v1",
    enabled=false,
  )
  let desired = try! DesiredState::new(resource~, spec~, generation=1)
  assert_eq(compute_diff(desired, None), DiffResult::NoChange)
}

///|
test "version and configuration drift produces update" {
  let desired = try! desired_state()
  let observed = try! observed_state(version="v0", config_fingerprint="cfg-v0")
  assert_action(
    compute_diff(desired, Some(observed)),
    ActionKind::Update,
    "version or configuration differs",
  )
}

///|
test "replica drift produces scale" {
  let desired = try! desired_state()
  let observed = try! observed_state(replicas=1)
  assert_action(
    compute_diff(desired, Some(observed)),
    ActionKind::Scale,
    "replica count differs",
  )
}

///|
test "unhealthy matching resource produces restart" {
  let desired = try! desired_state()
  let observed = try! observed_state(healthy=false)
  assert_action(
    compute_diff(desired, Some(observed)),
    ActionKind::Restart,
    "resource is unhealthy",
  )
}

///|
test "disabled desired resource produces delete" {
  let resource = ResourceId::new(kind="service", name="api")
  let spec = ResourceSpec::new(
    version="v1",
    replicas=0,
    config_fingerprint="cfg-v1",
    enabled=false,
  )
  let desired = try! DesiredState::new(resource~, spec~, generation=1)
  let observed = try! observed_state()
  assert_action(
    compute_diff(desired, Some(observed)),
    ActionKind::Delete,
    "resource is disabled",
  )
}

///|
test "disabled observed resource produces enable update" {
  let desired = try! desired_state()
  let observed = try! observed_state(enabled=false)
  assert_action(
    compute_diff(desired, Some(observed)),
    ActionKind::Update,
    "resource should be enabled",
  )
}

///|
test "resource mismatch is rejected" {
  let desired = try! desired_state()
  let other_resource = ResourceId::new(kind="worker", name="api")
  let other_spec = ResourceSpec::new(
    version="v1",
    replicas=2,
    config_fingerprint="cfg-v1",
    enabled=true,
  )
  let observed = try! ObservedState::new(
    resource=other_resource,
    spec=other_spec,
    generation=1,
    healthy=true,
  )
  try compute_diff(desired, Some(observed)) catch {
    ModelError::ResourceMismatch => ()
    _ => fail("wrong model error")
  } noraise {
    _ => fail("expected a resource mismatch")
  }
}
