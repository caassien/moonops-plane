///|
fn controller_resource(
  kind~ : String,
  name~ : String,
) -> ResourceId raise ModelError {
  ResourceId::new(kind~, name~)
}

///|
fn controller_operation(
  resource : ResourceId,
  action : ActionKind,
) -> Operation raise ModelError {
  Operation::new(resource~, action~, reason="controller test")
}

///|
fn controller_plan(operations : Array[Operation]) -> Plan raise ModelError {
  Plan::new(
    id=PlanId::new(value="controller-plan"),
    operations~,
    baseline_generation=1,
  )
}

///|
fn controller_batched_plan(
  operations : Array[Operation],
) -> BatchedPlan raise ModelError {
  batch_plan(
    controller_plan(operations),
    ChangeBudget::new(
      max_parallel=4,
      max_affected_resources=4,
      isolate_high_risk=false,
    ),
  )
}

///|
fn controller_policy() -> SafetyPolicy raise ModelError {
  SafetyPolicy::new(
    critical_resources=[],
    max_batch_operations=4,
    max_affected_resources=4,
  )
}

///|
fn controller_execution_result(
  operation : Operation,
  state : ExecutionState,
  message : String,
) -> ExecutionResult raise ModelError {
  ExecutionResult::new(operation~, state~, message~)
}

///|
test "fully allowed reconciliation reaches success" {
  let api = try! controller_resource(kind="service", name="api")
  let operation = try! controller_operation(api, ActionKind::Update)
  let started = start_reconciliation(try! controller_batched_plan([operation]))
  assert_eq(started.state, ReconciliationState::Planning)
  let ready = try! evaluate_reconciliation(started, try! controller_policy())
  assert_eq(ready.state, ReconciliationState::Ready)
  assert_eq(ready.plan.plan.approval, ApprovalState::NotRequired)
  let executing = try! begin_execution(ready)
  assert_eq(executing.state, ReconciliationState::Executing)
  let succeeded = try! apply_execution_result(
    executing,
    try! controller_execution_result(
      operation,
      ExecutionState::Succeeded,
      "updated",
    ),
  )
  assert_eq(succeeded.state, ReconciliationState::Succeeded)
  assert_eq(succeeded.results.length(), 1)
}

///|
test "approval is required and can make a run ready" {
  let api = try! controller_resource(kind="service", name="api")
  let operation = try! controller_operation(api, ActionKind::Restart)
  let waiting = try! evaluate_reconciliation(
    start_reconciliation(try! controller_batched_plan([operation])),
    try! controller_policy(),
  )
  assert_eq(waiting.state, ReconciliationState::AwaitingApproval)
  assert_eq(waiting.plan.plan.approval, ApprovalState::Pending)
  let ready = try! approve_reconciliation(waiting)
  assert_eq(ready.state, ReconciliationState::Ready)
  assert_eq(ready.plan.plan.approval, ApprovalState::Approved)
}

///|
test "approval rejection terminates the run" {
  let api = try! controller_resource(kind="service", name="api")
  let operation = try! controller_operation(api, ActionKind::Delete)
  let waiting = try! evaluate_reconciliation(
    start_reconciliation(try! controller_batched_plan([operation])),
    try! controller_policy(),
  )
  let terminated = try! reject_reconciliation(waiting)
  assert_eq(terminated.state, ReconciliationState::Terminated)
  assert_eq(terminated.plan.plan.approval, ApprovalState::Rejected)
  try begin_execution(terminated) catch {
    ModelError::InvalidTransition(message) =>
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
  let first = try! controller_operation(api, ActionKind::Update)
  let second = try! controller_operation(worker, ActionKind::Scale)
  let ready = try! evaluate_reconciliation(
    start_reconciliation(try! controller_batched_plan([first, second])),
    try! controller_policy(),
  )
  let executing = try! begin_execution(ready)
  let running = try! apply_execution_result(
    executing,
    try! controller_execution_result(
      first,
      ExecutionState::Succeeded,
      "updated",
    ),
  )
  assert_eq(running.state, ReconciliationState::Executing)
  let failed = try! apply_execution_result(
    running,
    try! controller_execution_result(
      second,
      ExecutionState::Failed,
      "adapter failed",
    ),
  )
  assert_eq(failed.state, ReconciliationState::Failed)
  assert_eq(failed.results.length(), 2)
}

///|
test "duplicate feedback is rejected while execution continues" {
  let api = try! controller_resource(kind="service", name="api")
  let worker = try! controller_resource(kind="service", name="worker")
  let first = try! controller_operation(api, ActionKind::Update)
  let second = try! controller_operation(worker, ActionKind::Scale)
  let ready = try! evaluate_reconciliation(
    start_reconciliation(try! controller_batched_plan([first, second])),
    try! controller_policy(),
  )
  let executing = try! begin_execution(ready)
  let running = try! apply_execution_result(
    executing,
    try! controller_execution_result(
      first,
      ExecutionState::Succeeded,
      "updated",
    ),
  )
  try
    apply_execution_result(
      running,
      try! controller_execution_result(
        first,
        ExecutionState::Succeeded,
        "replayed",
      ),
    )
  catch {
    ModelError::DuplicateFeedback(resource) =>
      inspect(resource, content="service/api")
    _ => fail("wrong duplicate feedback error")
  } noraise {
    _ => fail("expected duplicate feedback error")
  }
  assert_eq(running.state, ReconciliationState::Executing)
}

///|
test "denied policy produces a failed terminal run" {
  let api = try! controller_resource(kind="service", name="api")
  let operation = try! controller_operation(api, ActionKind::Unknown)
  let result = try! evaluate_reconciliation(
    start_reconciliation(try! controller_batched_plan([operation])),
    try! controller_policy(),
  )
  assert_eq(result.state, ReconciliationState::Failed)
  assert_eq(result.plan.plan.approval, ApprovalState::Rejected)
  assert_eq(result.decisions[0].decision, PolicyDecision::Deny)
}

///|
test "terminal states reject further transitions" {
  let api = try! controller_resource(kind="service", name="api")
  let operation = try! controller_operation(api, ActionKind::Create)
  let ready = try! evaluate_reconciliation(
    start_reconciliation(try! controller_batched_plan([operation])),
    try! controller_policy(),
  )
  let succeeded = try! apply_execution_result(
    try! begin_execution(ready),
    try! controller_execution_result(
      operation,
      ExecutionState::Succeeded,
      "created",
    ),
  )
  try begin_execution(succeeded) catch {
    ModelError::InvalidTransition(message) =>
      inspect(message, content="cannot begin execution from succeeded")
    _ => fail("wrong terminal state error")
  } noraise {
    _ => fail("expected terminal state error")
  }
  try terminate_reconciliation(succeeded) catch {
    ModelError::InvalidTransition(message) =>
      inspect(message, content="cannot terminate a terminal reconciliation")
    _ => fail("wrong termination error")
  } noraise {
    _ => fail("expected termination error")
  }
}

///|
test "explicit termination stops a running reconciliation" {
  let api = try! controller_resource(kind="service", name="api")
  let operation = try! controller_operation(api, ActionKind::Create)
  let ready = try! evaluate_reconciliation(
    start_reconciliation(try! controller_batched_plan([operation])),
    try! controller_policy(),
  )
  let executing = try! begin_execution(ready)
  let terminated = try! terminate_reconciliation(executing)
  assert_eq(terminated.state, ReconciliationState::Terminated)
  assert_eq(terminated.plan.plan.approval, ApprovalState::Rejected)
}
