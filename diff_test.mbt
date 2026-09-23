///|
fn desired_state() -> @orbitops_plane.DesiredState raise @orbitops_plane.ModelError {
  let resource = @orbitops_plane.ResourceId::new(kind="service", name="api")
  let spec = @orbitops_plane.ResourceSpec::new(
    version="v1",
    replicas=2,
    config_fingerprint="cfg-v1",
    enabled=true,
  )
  @orbitops_plane.DesiredState::new(resource~, spec~, generation=1)
}

///|
fn observed_state(
  version? : String = "v1",
  replicas? : Int = 2,
  config_fingerprint? : String = "cfg-v1",
  enabled? : Bool = true,
  healthy? : Bool = true,
) -> @orbitops_plane.ObservedState raise @orbitops_plane.ModelError {
  let resource = @orbitops_plane.ResourceId::new(kind="service", name="api")
  let spec = @orbitops_plane.ResourceSpec::new(
    version~,
    replicas~,
    config_fingerprint~,
    enabled~,
  )
  @orbitops_plane.ObservedState::new(resource~, spec~, generation=1, healthy~)
}

///|
fn assert_action(
  result : @orbitops_plane.DiffResult,
  expected_kind : @orbitops_plane.ActionKind,
  expected_reason : String,
) -> Unit raise {
  match result {
    @orbitops_plane.DiffResult::Action(operation) => {
      assert_eq(operation.action, expected_kind)
      assert_eq(operation.reason, expected_reason)
    }
    @orbitops_plane.DiffResult::NoChange => fail("expected an action")
  }
}

///|
test "matching state produces no change" {
  let desired = try! desired_state()
  let observed = try! observed_state()
  assert_eq(
    @orbitops_plane.compute_diff(desired, Some(observed)),
    @orbitops_plane.DiffResult::NoChange,
  )
}

///|
test "missing enabled resource produces create" {
  let desired = try! desired_state()
  assert_action(
    @orbitops_plane.compute_diff(desired, None),
    @orbitops_plane.ActionKind::Create,
    "resource is missing",
  )
}

///|
test "missing disabled resource produces no change" {
  let resource = @orbitops_plane.ResourceId::new(kind="service", name="api")
  let spec = @orbitops_plane.ResourceSpec::new(
    version="v1",
    replicas=0,
    config_fingerprint="cfg-v1",
    enabled=false,
  )
  let desired = try! @orbitops_plane.DesiredState::new(
    resource~,
    spec~,
    generation=1,
  )
  assert_eq(
    @orbitops_plane.compute_diff(desired, None),
    @orbitops_plane.DiffResult::NoChange,
  )
}

///|
test "version and configuration drift produces update" {
  let desired = try! desired_state()
  let observed = try! observed_state(version="v0", config_fingerprint="cfg-v0")
  assert_action(
    @orbitops_plane.compute_diff(desired, Some(observed)),
    @orbitops_plane.ActionKind::Update,
    "version or configuration differs",
  )
}

///|
test "replica drift produces scale" {
  let desired = try! desired_state()
  let observed = try! observed_state(replicas=1)
  assert_action(
    @orbitops_plane.compute_diff(desired, Some(observed)),
    @orbitops_plane.ActionKind::Scale,
    "replica count differs",
  )
}

///|
test "unhealthy matching resource produces restart" {
  let desired = try! desired_state()
  let observed = try! observed_state(healthy=false)
  assert_action(
    @orbitops_plane.compute_diff(desired, Some(observed)),
    @orbitops_plane.ActionKind::Restart,
    "resource is unhealthy",
  )
}

///|
test "disabled desired resource produces delete" {
  let resource = @orbitops_plane.ResourceId::new(kind="service", name="api")
  let spec = @orbitops_plane.ResourceSpec::new(
    version="v1",
    replicas=0,
    config_fingerprint="cfg-v1",
    enabled=false,
  )
  let desired = try! @orbitops_plane.DesiredState::new(
    resource~,
    spec~,
    generation=1,
  )
  let observed = try! observed_state()
  assert_action(
    @orbitops_plane.compute_diff(desired, Some(observed)),
    @orbitops_plane.ActionKind::Delete,
    "resource is disabled",
  )
}

///|
test "disabled observed resource produces enable update" {
  let desired = try! desired_state()
  let observed = try! observed_state(enabled=false)
  assert_action(
    @orbitops_plane.compute_diff(desired, Some(observed)),
    @orbitops_plane.ActionKind::Update,
    "resource should be enabled",
  )
}

///|
test "resource mismatch is rejected" {
  let desired = try! desired_state()
  let other_resource = @orbitops_plane.ResourceId::new(
    kind="worker",
    name="api",
  )
  let other_spec = @orbitops_plane.ResourceSpec::new(
    version="v1",
    replicas=2,
    config_fingerprint="cfg-v1",
    enabled=true,
  )
  let observed = try! @orbitops_plane.ObservedState::new(
    resource=other_resource,
    spec=other_spec,
    generation=1,
    healthy=true,
  )
  try @orbitops_plane.compute_diff(desired, Some(observed)) catch {
    @orbitops_plane.ModelError::ResourceMismatch => ()
    _ => fail("wrong model error")
  } noraise {
    _ => fail("expected a resource mismatch")
  }
}
