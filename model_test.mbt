///|
fn sample_resource() -> ResourceId raise ModelError {
  ResourceId::new(kind="service", name="api")
}

///|
fn sample_spec() -> ResourceSpec raise ModelError {
  ResourceSpec::new(
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
  try ResourceId::new(kind="", name="api") catch {
    ModelError::EmptyField(field) => inspect(field, content="kind")
    _ => fail("wrong model error")
  } noraise {
    _ => fail("expected an invalid resource identity")
  }
  try ResourceId::new(kind="service", name="") catch {
    ModelError::EmptyField(field) => inspect(field, content="name")
    _ => fail("wrong model error")
  } noraise {
    _ => fail("expected an invalid resource identity")
  }
}

///|
test "specification rejects invalid values" {
  try
    ResourceSpec::new(
      version="",
      replicas=1,
      config_fingerprint="cfg",
      enabled=true,
    )
  catch {
    ModelError::EmptyField(field) => inspect(field, content="version")
    _ => fail("wrong model error")
  } noraise {
    _ => fail("expected an invalid version")
  }
  try
    ResourceSpec::new(
      version="v1",
      replicas=-1,
      config_fingerprint="cfg",
      enabled=true,
    )
  catch {
    ModelError::NegativeReplicas => ()
    _ => fail("wrong model error")
  } noraise {
    _ => fail("expected an invalid replica count")
  }
}

///|
test "states require positive generations" {
  let resource = try! sample_resource()
  let spec = try! sample_spec()
  try DesiredState::new(resource~, spec~, generation=0) catch {
    ModelError::NonPositiveGeneration => ()
    _ => fail("wrong model error")
  } noraise {
    _ => fail("expected an invalid desired generation")
  }
  try ObservedState::new(resource~, spec~, generation=0, healthy=true) catch {
    ModelError::NonPositiveGeneration => ()
    _ => fail("wrong model error")
  } noraise {
    _ => fail("expected an invalid observed generation")
  }
}

///|
test "operation plan and execution result preserve model relationships" {
  let resource = try! sample_resource()
  let action = ActionKind::Update
  let operation = try! Operation::new(
    resource~,
    action~,
    reason="version drift",
  )
  let id = try! PlanId::new(value="plan-001")
  let plan = try! Plan::new(id~, operations=[operation], baseline_generation=1)
  let result = try! ExecutionResult::new(
    plan_id=id,
    operation~,
    state=ExecutionState::Succeeded,
    message="applied",
  )
  assert_eq(plan.operations.length(), 1)
  assert_eq(plan.approval, ApprovalState::NotRequired)
  assert_eq(result.plan_id, id)
  assert_eq(result.state, ExecutionState::Succeeded)
  assert_eq(result.operation, operation)
}

///|
test "operations and identifiers reject empty explanations" {
  let resource = try! sample_resource()
  try Operation::new(resource~, action=ActionKind::Restart, reason="") catch {
    ModelError::EmptyField(field) => inspect(field, content="reason")
    _ => fail("wrong model error")
  } noraise {
    _ => fail("expected an invalid operation")
  }
  try PlanId::new(value="") catch {
    ModelError::EmptyField(field) => inspect(field, content="plan_id")
    _ => fail("wrong model error")
  } noraise {
    _ => fail("expected an invalid plan id")
  }
}
