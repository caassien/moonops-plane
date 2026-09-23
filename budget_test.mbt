///|
fn budget_resource(
  kind~ : String,
  name~ : String,
) -> @orbitops_plane.ResourceId raise @orbitops_plane.ModelError {
  @orbitops_plane.ResourceId::new(kind~, name~)
}

///|
fn budget_operation(
  resource : @orbitops_plane.ResourceId,
  action : @orbitops_plane.ActionKind,
) -> @orbitops_plane.Operation raise @orbitops_plane.ModelError {
  @orbitops_plane.Operation::new(resource~, action~, reason="budget test")
}

///|
fn budget_plan(
  operations : Array[@orbitops_plane.Operation],
) -> @orbitops_plane.Plan raise @orbitops_plane.ModelError {
  let id = @orbitops_plane.PlanId::new(value="budget-plan")
  @orbitops_plane.Plan::new(id~, operations~, baseline_generation=1)
}

///|
fn budget(
  max_parallel~ : Int,
  max_affected_resources~ : Int,
  isolate_high_risk~ : Bool,
) -> @orbitops_plane.ChangeBudget raise @orbitops_plane.ModelError {
  @orbitops_plane.ChangeBudget::new(
    max_parallel~,
    max_affected_resources~,
    isolate_high_risk~,
  )
}

///|
fn assert_batch_sizes(
  plan : @orbitops_plane.BatchedPlan,
  expected : Array[Int],
) -> Unit raise {
  assert_eq(plan.batches.length(), expected.length())
  for i in 0..<expected.length() {
    assert_eq(plan.batches[i].operations.length(), expected[i])
  }
}

///|
test "parallel and resource limits split normal operations" {
  let api = try! budget_resource(kind="service", name="api")
  let worker = try! budget_resource(kind="service", name="worker")
  let database = try! budget_resource(kind="database", name="primary")
  let operations = [
    try! budget_operation(api, @orbitops_plane.ActionKind::Update),
    try! budget_operation(worker, @orbitops_plane.ActionKind::Update),
    try! budget_operation(database, @orbitops_plane.ActionKind::Update),
  ]
  let plan = try! budget_plan(operations)
  let result = try! @orbitops_plane.batch_plan(
    plan,
    try! budget(
      max_parallel=2,
      max_affected_resources=2,
      isolate_high_risk=false,
    ),
  )
  assert_batch_sizes(result, [2, 1])
  assert_eq(result.batches[0].operations[0], operations[0])
  assert_eq(result.batches[1].operations[0], operations[2])
}

///|
test "resource limit splits before a new resource exceeds the budget" {
  let api = try! budget_resource(kind="service", name="api")
  let worker = try! budget_resource(kind="service", name="worker")
  let operations = [
    try! budget_operation(api, @orbitops_plane.ActionKind::Scale),
    try! budget_operation(worker, @orbitops_plane.ActionKind::Scale),
  ]
  let result = try! @orbitops_plane.batch_plan(
    try! budget_plan(operations),
    try! budget(
      max_parallel=3,
      max_affected_resources=1,
      isolate_high_risk=false,
    ),
  )
  assert_batch_sizes(result, [1, 1])
}

///|
test "high risk operations are isolated" {
  let api = try! budget_resource(kind="service", name="api")
  let worker = try! budget_resource(kind="service", name="worker")
  let database = try! budget_resource(kind="database", name="primary")
  let operations = [
    try! budget_operation(api, @orbitops_plane.ActionKind::Update),
    try! budget_operation(worker, @orbitops_plane.ActionKind::Restart),
    try! budget_operation(database, @orbitops_plane.ActionKind::Update),
  ]
  let result = try! @orbitops_plane.batch_plan(
    try! budget_plan(operations),
    try! budget(
      max_parallel=3,
      max_affected_resources=3,
      isolate_high_risk=true,
    ),
  )
  assert_batch_sizes(result, [1, 1, 1])
  assert_eq(result.batches[1].operations[0], operations[1])
}

///|
test "delete operations are isolated when requested" {
  let api = try! budget_resource(kind="service", name="api")
  let worker = try! budget_resource(kind="service", name="worker")
  let operations = [
    try! budget_operation(api, @orbitops_plane.ActionKind::Delete),
    try! budget_operation(worker, @orbitops_plane.ActionKind::Update),
  ]
  let result = try! @orbitops_plane.batch_plan(
    try! budget_plan(operations),
    try! budget(
      max_parallel=2,
      max_affected_resources=2,
      isolate_high_risk=true,
    ),
  )
  assert_batch_sizes(result, [1, 1])
}

///|
test "empty plan produces no batches" {
  let result = try! @orbitops_plane.batch_plan(
    try! budget_plan([]),
    try! budget(
      max_parallel=2,
      max_affected_resources=2,
      isolate_high_risk=true,
    ),
  )
  assert_eq(result.batches.length(), 0)
}

///|
test "non-positive budgets return diagnostics" {
  try
    @orbitops_plane.ChangeBudget::new(
      max_parallel=0,
      max_affected_resources=1,
      isolate_high_risk=false,
    )
  catch {
    @orbitops_plane.ModelError::InvalidBudget(message) =>
      inspect(message, content="max_parallel must be positive")
    _ => fail("wrong budget error")
  } noraise {
    _ => fail("expected an invalid parallel budget")
  }
  try
    @orbitops_plane.ChangeBudget::new(
      max_parallel=1,
      max_affected_resources=0,
      isolate_high_risk=false,
    )
  catch {
    @orbitops_plane.ModelError::InvalidBudget(message) =>
      inspect(message, content="max_affected_resources must be positive")
    _ => fail("wrong budget error")
  } noraise {
    _ => fail("expected an invalid resource budget")
  }
}
