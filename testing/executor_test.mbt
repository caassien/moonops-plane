///|
fn testing_resource(
  kind~ : String,
  name~ : String,
) -> @orbitops_plane.ResourceId raise @orbitops_plane.ModelError {
  @orbitops_plane.ResourceId::new(kind~, name~)
}

///|
fn testing_operation(
  resource : @orbitops_plane.ResourceId,
  action : @orbitops_plane.ActionKind,
) -> @orbitops_plane.Operation raise @orbitops_plane.ModelError {
  @orbitops_plane.Operation::new(resource~, action~, reason="executor test")
}

///|
test "executor emits ordered deterministic success feedback" {
  let api = try! testing_resource(kind="service", name="api")
  let worker = try! testing_resource(kind="service", name="worker")
  let operations = [
    try! testing_operation(api, @orbitops_plane.ActionKind::Update),
    try! testing_operation(worker, @orbitops_plane.ActionKind::Scale),
  ]
  let run = try! fixed_executor(script=success_script()).run(operations)
  assert_eq(run.plan_id, fixed_plan_id())
  assert_eq(run.records.length(), 2)
  assert_eq(run.records[0].sequence, 1)
  assert_eq(run.records[0].timestamp, fixed_clock_start())
  assert_eq(run.records[1].sequence, 2)
  assert_eq(run.records[1].timestamp, fixed_clock_start() + 1)
  assert_eq(
    run.records[0].result.state,
    @orbitops_plane.ExecutionState::Succeeded,
  )
  assert_eq(run.records[1].result.operation.resource, worker)
  assert_eq(run.stopped, false)
}

///|
test "executor rejects the selected action and stops" {
  let api = try! testing_resource(kind="service", name="api")
  let worker = try! testing_resource(kind="service", name="worker")
  let operations = [
    try! testing_operation(api, @orbitops_plane.ActionKind::Restart),
    try! testing_operation(worker, @orbitops_plane.ActionKind::Update),
  ]
  let run = try! fixed_executor(
    script=rejection_script(action=@orbitops_plane.ActionKind::Restart),
  ).run(operations)
  assert_eq(run.records.length(), 1)
  assert_eq(
    run.records[0].result.state,
    @orbitops_plane.ExecutionState::Skipped,
  )
  assert_eq(run.records[0].timestamp, fixed_clock_start())
  assert_eq(run.stopped, true)
}

///|
test "executor captures partial failure without running later operations" {
  let api = try! testing_resource(kind="service", name="api")
  let worker = try! testing_resource(kind="service", name="worker")
  let operations = [
    try! testing_operation(api, @orbitops_plane.ActionKind::Update),
    try! testing_operation(worker, @orbitops_plane.ActionKind::Scale),
    try! testing_operation(api, @orbitops_plane.ActionKind::Restart),
  ]
  let run = try! fixed_executor(
    script=partial_failure_script(action=@orbitops_plane.ActionKind::Scale),
  ).run(operations)
  assert_eq(run.records.length(), 2)
  assert_eq(
    run.records[0].result.state,
    @orbitops_plane.ExecutionState::Succeeded,
  )
  assert_eq(run.records[1].result.state, @orbitops_plane.ExecutionState::Failed)
  assert_eq(run.records[1].result.operation.resource, worker)
  assert_eq(run.stopped, true)
}

///|
test "identical scripts produce identical runs" {
  let api = try! testing_resource(kind="service", name="api")
  let operation = try! testing_operation(
    api,
    @orbitops_plane.ActionKind::Update,
  )
  let operations = [operation]
  let first = try! fixed_executor(script=success_script()).run(operations)
  let second = try! fixed_executor(script=success_script()).run(operations)
  assert_eq(first, second)
  assert_eq(first.results(), second.results())
}
