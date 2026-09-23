///|
fn planner_resource(
  kind~ : String,
  name~ : String,
) -> @orbitops_plane.ResourceId raise @orbitops_plane.ModelError {
  @orbitops_plane.ResourceId::new(kind~, name~)
}

///|
fn planner_operation(
  resource : @orbitops_plane.ResourceId,
  action : @orbitops_plane.ActionKind,
) -> @orbitops_plane.Operation raise @orbitops_plane.ModelError {
  @orbitops_plane.Operation::new(resource~, action~, reason="planner test")
}

///|
fn assert_plan_order(
  plan : @orbitops_plane.Plan,
  expected : Array[@orbitops_plane.ResourceId],
) -> Unit raise {
  assert_eq(plan.operations.length(), expected.length())
  for i in 0..<expected.length() {
    assert_eq(plan.operations[i].resource, expected[i])
  }
}

///|
fn plan_id(
  value : String,
) -> @orbitops_plane.PlanId raise @orbitops_plane.ModelError {
  @orbitops_plane.PlanId::new(value~)
}

///|
test "dependency chain is ordered before dependents" {
  let database = try! planner_resource(kind="database", name="primary")
  let api = try! planner_resource(kind="service", name="api")
  let worker = try! planner_resource(kind="worker", name="jobs")
  let operations = [
    try! planner_operation(worker, @orbitops_plane.ActionKind::Update),
    try! planner_operation(database, @orbitops_plane.ActionKind::Create),
    try! planner_operation(api, @orbitops_plane.ActionKind::Update),
  ]
  let plan = try! @orbitops_plane.build_ordered_plan(
    id=try! plan_id("chain"),
    operations~,
    dependencies=[(database, api), (api, worker)],
    baseline_generation=1,
  )
  assert_plan_order(plan, [database, api, worker])
}

///|
test "diamond plan uses stable order for independent branches" {
  let database = try! planner_resource(kind="database", name="primary")
  let api = try! planner_resource(kind="service", name="api")
  let worker = try! planner_resource(kind="service", name="worker")
  let frontend = try! planner_resource(kind="web", name="frontend")
  let dependencies = [
    (database, api),
    (database, worker),
    (api, frontend),
    (worker, frontend),
  ]
  let first_operations = [
    try! planner_operation(frontend, @orbitops_plane.ActionKind::Update),
    try! planner_operation(worker, @orbitops_plane.ActionKind::Update),
    try! planner_operation(database, @orbitops_plane.ActionKind::Update),
    try! planner_operation(api, @orbitops_plane.ActionKind::Update),
  ]
  let second_operations = [
    try! planner_operation(api, @orbitops_plane.ActionKind::Update),
    try! planner_operation(frontend, @orbitops_plane.ActionKind::Update),
    try! planner_operation(worker, @orbitops_plane.ActionKind::Update),
    try! planner_operation(database, @orbitops_plane.ActionKind::Update),
  ]
  let first = try! @orbitops_plane.build_ordered_plan(
    id=try! plan_id("diamond"),
    operations=first_operations,
    dependencies~,
    baseline_generation=1,
  )
  let second = try! @orbitops_plane.build_ordered_plan(
    id=try! plan_id("diamond"),
    operations=second_operations,
    dependencies~,
    baseline_generation=1,
  )
  assert_eq(first, second)
  assert_plan_order(first, [database, api, worker, frontend])
}

///|
test "all-delete plan orders dependents before dependencies" {
  let database = try! planner_resource(kind="database", name="primary")
  let api = try! planner_resource(kind="service", name="api")
  let worker = try! planner_resource(kind="worker", name="jobs")
  let operations = [
    try! planner_operation(database, @orbitops_plane.ActionKind::Delete),
    try! planner_operation(api, @orbitops_plane.ActionKind::Delete),
    try! planner_operation(worker, @orbitops_plane.ActionKind::Delete),
  ]
  let plan = try! @orbitops_plane.build_ordered_plan(
    id=try! plan_id("delete-chain"),
    operations~,
    dependencies=[(database, api), (api, worker)],
    baseline_generation=1,
  )
  assert_plan_order(plan, [worker, api, database])
}

///|
test "independent operations use resource key order" {
  let worker = try! planner_resource(kind="service", name="worker")
  let api = try! planner_resource(kind="service", name="api")
  let operations = [
    try! planner_operation(worker, @orbitops_plane.ActionKind::Scale),
    try! planner_operation(api, @orbitops_plane.ActionKind::Scale),
  ]
  let plan = try! @orbitops_plane.build_ordered_plan(
    id=try! plan_id("independent"),
    operations~,
    dependencies=[],
    baseline_generation=1,
  )
  assert_plan_order(plan, [api, worker])
}

///|
test "duplicate operations are rejected" {
  let api = try! planner_resource(kind="service", name="api")
  let operations = [
    try! planner_operation(api, @orbitops_plane.ActionKind::Update),
    try! planner_operation(api, @orbitops_plane.ActionKind::Restart),
  ]
  try
    @orbitops_plane.build_ordered_plan(
      id=try! plan_id("duplicate"),
      operations~,
      dependencies=[],
      baseline_generation=1,
    )
  catch {
    @orbitops_plane.ModelError::DuplicateOperation(resource) =>
      inspect(resource, content="service/api")
    _ => fail("wrong planner error")
  } noraise {
    _ => fail("expected duplicate operation error")
  }
}
