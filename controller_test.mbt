///|
fn controller_resource(
  kind~ : String,
  name~ : String,
) -> @orbitops_plane.ResourceId raise @orbitops_plane.ModelError {
  @orbitops_plane.ResourceId::new(kind~, name~)
}

///|
fn controller_operation(
  resource : @orbitops_plane.ResourceId,
  action : @orbitops_plane.ActionKind,
) -> @orbitops_plane.Operation raise @orbitops_plane.ModelError {
  @orbitops_plane.Operation::new(resource~, action~, reason="controller test")
}

///|
fn controller_plan(
  operations : Array[@orbitops_plane.Operation],
) -> @orbitops_plane.Plan raise @orbitops_plane.ModelError {
  @orbitops_plane.Plan::new(
    id=@orbitops_plane.PlanId::new(value="controller-plan"),
    operations~,
    baseline_generation=1,
  )
}

///|
fn controller_batched_plan(
  operations : Array[@orbitops_plane.Operation],
) -> @orbitops_plane.BatchedPlan raise @orbitops_plane.ModelError {
  @orbitops_plane.batch_plan(
    controller_plan(operations),
    @orbitops_plane.ChangeBudget::new(
      max_parallel=4,
      max_affected_resources=4,
      isolate_high_risk=false,
    ),
  )
}

///|
fn controller_start(
  plan : @orbitops_plane.BatchedPlan,
) -> @orbitops_plane.Reconciliation raise @orbitops_plane.ModelError {
  @orbitops_plane.start_reconciliation(plan, observed_generation=1)
}

///|
fn controller_begin(
  reconciliation : @orbitops_plane.Reconciliation,
) -> @orbitops_plane.Reconciliation raise @orbitops_plane.ModelError {
  @orbitops_plane.begin_execution(reconciliation, observed_generation=1)
}

///|
fn controller_policy() -> @orbitops_plane.SafetyPolicy raise @orbitops_plane.ModelError {
  @orbitops_plane.SafetyPolicy::new(
    critical_resources=[],
    max_batch_operations=4,
    max_affected_resources=4,
  )
}

///|
fn controller_execution_result(
  operation : @orbitops_plane.Operation,
  state : @orbitops_plane.ExecutionState,
  message : String,
) -> @orbitops_plane.ExecutionResult raise @orbitops_plane.ModelError {
  let plan_id = @orbitops_plane.PlanId::new(value="controller-plan")
  @orbitops_plane.ExecutionResult::new(plan_id~, operation~, state~, message~)
}

///|
test "fully allowed reconciliation reaches success" {
  let api = try! controller_resource(kind="service", name="api")
  let operation = try! controller_operation(
    api,
    @orbitops_plane.ActionKind::Update,
  )
  let started = try! controller_start(try! controller_batched_plan([operation]))
  assert_eq(started.state, @orbitops_plane.ReconciliationState::Planning)
  let ready = try! @orbitops_plane.evaluate_reconciliation(
    started,
    try! controller_policy(),
  )
  assert_eq(ready.state, @orbitops_plane.ReconciliationState::Ready)
  assert_eq(
    ready.plan.plan.approval,
    @orbitops_plane.ApprovalState::NotRequired,
  )
  let executing = try! controller_begin(ready)
  assert_eq(executing.state, @orbitops_plane.ReconciliationState::Executing)
  let succeeded = try! @orbitops_plane.apply_execution_result(
    executing,
    try! controller_execution_result(
      operation,
      @orbitops_plane.ExecutionState::Succeeded,
      "updated",
    ),
  )
  assert_eq(succeeded.state, @orbitops_plane.ReconciliationState::Succeeded)
  assert_eq(succeeded.results.length(), 1)
}

///|
test "approval is required and can make a run ready" {
  let api = try! controller_resource(kind="service", name="api")
  let operation = try! controller_operation(
    api,
    @orbitops_plane.ActionKind::Restart,
  )
  let waiting = try! @orbitops_plane.evaluate_reconciliation(
    try! controller_start(try! controller_batched_plan([operation])),
    try! controller_policy(),
  )
  assert_eq(
    waiting.state,
    @orbitops_plane.ReconciliationState::AwaitingApproval,
  )
  assert_eq(waiting.plan.plan.approval, @orbitops_plane.ApprovalState::Pending)
  let ready = try! @orbitops_plane.approve_reconciliation(waiting)
  assert_eq(ready.state, @orbitops_plane.ReconciliationState::Ready)
  assert_eq(ready.plan.plan.approval, @orbitops_plane.ApprovalState::Approved)
}

///|
test "approval rejection terminates the run" {
  let api = try! controller_resource(kind="service", name="api")
  let operation = try! controller_operation(
    api,
    @orbitops_plane.ActionKind::Delete,
  )
  let waiting = try! @orbitops_plane.evaluate_reconciliation(
    try! controller_start(try! controller_batched_plan([operation])),
    try! controller_policy(),
  )
  let terminated = try! @orbitops_plane.reject_reconciliation(waiting)
  assert_eq(terminated.state, @orbitops_plane.ReconciliationState::Terminated)
  assert_eq(
    terminated.plan.plan.approval,
    @orbitops_plane.ApprovalState::Rejected,
  )
  try controller_begin(terminated) catch {
    @orbitops_plane.ModelError::InvalidTransition(message) =>
      inspect(message, content="cannot begin execution from terminated")
    _ => fail("wrong terminal transition error")
  } noraise {
    _ => fail("expected terminal transition error")
  }
}

///|
test "partial execution failure stops later operations" {
  let api = try! controller_resource(kind="service", name="api")
  let worker = try! controller_resource(kind="service", name="worker")
  let first = try! controller_operation(api, @orbitops_plane.ActionKind::Update)
  let second = try! controller_operation(
    worker,
    @orbitops_plane.ActionKind::Scale,
  )
  let ready = try! @orbitops_plane.evaluate_reconciliation(
    try! controller_start(try! controller_batched_plan([first, second])),
    try! controller_policy(),
  )
  let executing = try! controller_begin(ready)
  let running = try! @orbitops_plane.apply_execution_result(
    executing,
    try! controller_execution_result(
      first,
      @orbitops_plane.ExecutionState::Succeeded,
      "updated",
    ),
  )
  assert_eq(running.state, @orbitops_plane.ReconciliationState::Executing)
  let failed = try! @orbitops_plane.apply_execution_result(
    running,
    try! controller_execution_result(
      second,
      @orbitops_plane.ExecutionState::Failed,
      "adapter failed",
    ),
  )
  assert_eq(failed.state, @orbitops_plane.ReconciliationState::Failed)
  assert_eq(failed.results.length(), 2)
}

///|
test "duplicate feedback is rejected while execution continues" {
  let api = try! controller_resource(kind="service", name="api")
  let worker = try! controller_resource(kind="service", name="worker")
  let first = try! controller_operation(api, @orbitops_plane.ActionKind::Update)
  let second = try! controller_operation(
    worker,
    @orbitops_plane.ActionKind::Scale,
  )
  let ready = try! @orbitops_plane.evaluate_reconciliation(
    try! controller_start(try! controller_batched_plan([first, second])),
    try! controller_policy(),
  )
  let executing = try! controller_begin(ready)
  let running = try! @orbitops_plane.apply_execution_result(
    executing,
    try! controller_execution_result(
      first,
      @orbitops_plane.ExecutionState::Succeeded,
      "updated",
    ),
  )
  try
    @orbitops_plane.apply_execution_result(
      running,
      try! controller_execution_result(
        first,
        @orbitops_plane.ExecutionState::Succeeded,
        "replayed",
      ),
    )
  catch {
    @orbitops_plane.ModelError::DuplicateFeedback(resource) =>
      inspect(resource, content="service/api")
    _ => fail("wrong duplicate feedback error")
  } noraise {
    _ => fail("expected duplicate feedback error")
  }
  assert_eq(running.state, @orbitops_plane.ReconciliationState::Executing)
}

///|
test "denied policy produces a failed terminal run" {
  let api = try! controller_resource(kind="service", name="api")
  let operation = try! controller_operation(
    api,
    @orbitops_plane.ActionKind::Unknown,
  )
  let result = try! @orbitops_plane.evaluate_reconciliation(
    try! controller_start(try! controller_batched_plan([operation])),
    try! controller_policy(),
  )
  assert_eq(result.state, @orbitops_plane.ReconciliationState::Failed)
  assert_eq(result.plan.plan.approval, @orbitops_plane.ApprovalState::Rejected)
  assert_eq(result.decisions[0].decision, @orbitops_plane.PolicyDecision::Deny)
}

///|
test "terminal states reject further transitions" {
  let api = try! controller_resource(kind="service", name="api")
  let operation = try! controller_operation(
    api,
    @orbitops_plane.ActionKind::Create,
  )
  let ready = try! @orbitops_plane.evaluate_reconciliation(
    try! controller_start(try! controller_batched_plan([operation])),
    try! controller_policy(),
  )
  let succeeded = try! @orbitops_plane.apply_execution_result(
    try! controller_begin(ready),
    try! controller_execution_result(
      operation,
      @orbitops_plane.ExecutionState::Succeeded,
      "created",
    ),
  )
  try controller_begin(succeeded) catch {
    @orbitops_plane.ModelError::InvalidTransition(message) =>
      inspect(message, content="cannot begin execution from succeeded")
    _ => fail("wrong terminal state error")
  } noraise {
    _ => fail("expected terminal state error")
  }
  try @orbitops_plane.terminate_reconciliation(succeeded) catch {
    @orbitops_plane.ModelError::InvalidTransition(message) =>
      inspect(message, content="cannot terminate a terminal reconciliation")
    _ => fail("wrong termination error")
  } noraise {
    _ => fail("expected termination error")
  }
}

///|
test "explicit termination stops a running reconciliation" {
  let api = try! controller_resource(kind="service", name="api")
  let operation = try! controller_operation(
    api,
    @orbitops_plane.ActionKind::Create,
  )
  let ready = try! @orbitops_plane.evaluate_reconciliation(
    try! controller_start(try! controller_batched_plan([operation])),
    try! controller_policy(),
  )
  let executing = try! controller_begin(ready)
  let terminated = try! @orbitops_plane.terminate_reconciliation(executing)
  assert_eq(terminated.state, @orbitops_plane.ReconciliationState::Terminated)
  assert_eq(
    terminated.plan.plan.approval,
    @orbitops_plane.ApprovalState::Rejected,
  )
}
