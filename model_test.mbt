///|
fn sample_resource() -> @orbitops_plane.ResourceId raise @orbitops_plane.ModelError {
  @orbitops_plane.ResourceId::new(kind="service", name="api")
}

///|
fn sample_spec() -> @orbitops_plane.ResourceSpec raise @orbitops_plane.ModelError {
  @orbitops_plane.ResourceSpec::new(
    version="2026.09.21",
    replicas=2,
    config_fingerprint="cfg-api-v1",
    enabled=true,
  )
}

///|
test "resource and specification constructors validate input" {
  let resource = try! sample_resource()
  let spec = try! sample_spec()
  assert_eq(resource.kind, "service")
  assert_eq(resource.name, "api")
  assert_eq(spec.replicas, 2)
  assert_true(spec.enabled)
}

///|
test "resource identity rejects empty fields" {
  try @orbitops_plane.ResourceId::new(kind="", name="api") catch {
    @orbitops_plane.ModelError::EmptyField(field) =>
      inspect(field, content="kind")
    _ => fail("wrong model error")
  } noraise {
    _ => fail("expected an invalid resource identity")
  }
  try @orbitops_plane.ResourceId::new(kind="service", name="") catch {
    @orbitops_plane.ModelError::EmptyField(field) =>
      inspect(field, content="name")
    _ => fail("wrong model error")
  } noraise {
    _ => fail("expected an invalid resource identity")
  }
}

///|
test "specification rejects invalid values" {
  try
    @orbitops_plane.ResourceSpec::new(
      version="",
      replicas=1,
      config_fingerprint="cfg",
      enabled=true,
    )
  catch {
    @orbitops_plane.ModelError::EmptyField(field) =>
      inspect(field, content="version")
    _ => fail("wrong model error")
  } noraise {
    _ => fail("expected an invalid version")
  }
  try
    @orbitops_plane.ResourceSpec::new(
      version="v1",
      replicas=-1,
      config_fingerprint="cfg",
      enabled=true,
    )
  catch {
    @orbitops_plane.ModelError::NegativeReplicas => ()
    _ => fail("wrong model error")
  } noraise {
    _ => fail("expected an invalid replica count")
  }
}

///|
test "states require positive generations" {
  let resource = try! sample_resource()
  let spec = try! sample_spec()
  try @orbitops_plane.DesiredState::new(resource~, spec~, generation=0) catch {
    @orbitops_plane.ModelError::NonPositiveGeneration => ()
    _ => fail("wrong model error")
  } noraise {
    _ => fail("expected an invalid desired generation")
  }
  try
    @orbitops_plane.ObservedState::new(
      resource~,
      spec~,
      generation=0,
      healthy=true,
    )
  catch {
    @orbitops_plane.ModelError::NonPositiveGeneration => ()
    _ => fail("wrong model error")
  } noraise {
    _ => fail("expected an invalid observed generation")
  }
}

///|
test "operation plan and execution result preserve model relationships" {
  let resource = try! sample_resource()
  let action = @orbitops_plane.ActionKind::Update
  let operation = try! @orbitops_plane.Operation::new(
    resource~,
    action~,
    reason="version drift",
  )
  let id = try! @orbitops_plane.PlanId::new(value="plan-001")
  let plan = try! @orbitops_plane.Plan::new(
    id~,
    operations=[operation],
    baseline_generation=1,
  )
  let result = try! @orbitops_plane.ExecutionResult::new(
    plan_id=id,
    operation~,
    state=@orbitops_plane.ExecutionState::Succeeded,
    message="applied",
  )
  assert_eq(plan.operations.length(), 1)
  assert_eq(plan.approval, @orbitops_plane.ApprovalState::NotRequired)
  assert_eq(result.plan_id, id)
  assert_eq(result.state, @orbitops_plane.ExecutionState::Succeeded)
  assert_eq(result.operation, operation)
}

///|
test "operations and identifiers reject empty explanations" {
  let resource = try! sample_resource()
  try
    @orbitops_plane.Operation::new(
      resource~,
      action=@orbitops_plane.ActionKind::Restart,
      reason="",
    )
  catch {
    @orbitops_plane.ModelError::EmptyField(field) =>
      inspect(field, content="reason")
    _ => fail("wrong model error")
  } noraise {
    _ => fail("expected an invalid operation")
  }
  try @orbitops_plane.PlanId::new(value="") catch {
    @orbitops_plane.ModelError::EmptyField(field) =>
      inspect(field, content="plan_id")
    _ => fail("wrong model error")
  } noraise {
    _ => fail("expected an invalid plan id")
  }
}
