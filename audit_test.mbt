///|
test "audit events preserve a successful lifecycle and replay" {
  let api = try! controller_resource(kind="service", name="api")
  let operation = try! controller_operation(api, ActionKind::Update)
  let plan = try! controller_batched_plan([operation])
  let started = try! controller_start(plan)
  let ready = try! evaluate_reconciliation(started, try! controller_policy())
  let executing = try! controller_begin(ready)
  let succeeded = try! apply_execution_result(
    executing,
    try! controller_execution_result(
      operation,
      ExecutionState::Succeeded,
      "token=super-secret",
    ),
  )
  let events = succeeded.audit_events
  assert_eq(events.length(), 5)
  assert_eq(events[0].sequence, 1)
  assert_eq(events[0].kind, AuditEventKind::PlanCreated)
  assert_eq(events[1].sequence, 2)
  assert_eq(events[1].kind, AuditEventKind::PolicyDecision)
  assert_eq(
    events[1].reason_code,
    AuditReasonCode::Policy(PolicyReasonCode::MediumRisk),
  )
  assert_eq(events[2].kind, AuditEventKind::StateTransition)
  assert_eq(events[2].reason_code, AuditReasonCode::Executing)
  assert_eq(events[3].kind, AuditEventKind::ExecutionFeedback)
  assert_eq(events[3].execution_state, Some(ExecutionState::Succeeded))
  assert_eq(events[4].kind, AuditEventKind::Terminal)
  assert_eq(events[4].reason_code, AuditReasonCode::ReconciliationSucceeded)
  let replayed = try! replay_audit_events(plan, events)
  assert_eq(replayed.state, ReconciliationState::Succeeded)
  assert_eq(replayed.next_operation, 1)
  assert_eq(replayed.decisions.length(), 1)
  assert_eq(replayed.results.length(), 1)
  assert_eq(replayed.results[0].operation.resource, operation.resource)
  assert_eq(replayed.results[0].operation.action, operation.action)
  assert_eq(replayed.audit_events, events)
}

///|
test "audit events record approval rejection and terminal reason" {
  let api = try! controller_resource(kind="service", name="api")
  let operation = try! controller_operation(api, ActionKind::Delete)
  let plan = try! controller_batched_plan([operation])
  let waiting = try! evaluate_reconciliation(
    try! controller_start(plan),
    try! controller_policy(),
  )
  assert_eq(waiting.audit_events.length(), 3)
  assert_eq(
    waiting.audit_events[2].reason_code,
    AuditReasonCode::ApprovalRequested,
  )
  let terminated = try! reject_reconciliation(waiting)
  assert_eq(terminated.audit_events.length(), 5)
  assert_eq(
    terminated.audit_events[3].reason_code,
    AuditReasonCode::ApprovalRejected,
  )
  assert_eq(terminated.audit_events[4].kind, AuditEventKind::Terminal)
  assert_eq(
    terminated.audit_events[4].reason_code,
    AuditReasonCode::ReconciliationTerminated,
  )
  let replayed = try! replay_audit_events(plan, terminated.audit_events)
  assert_eq(replayed.state, ReconciliationState::Terminated)
  assert_eq(replayed.plan.plan.approval, ApprovalState::Rejected)
  assert_eq(replayed.next_operation, 0)
  assert_eq(replayed.results.length(), 0)
}

///|
test "audit events capture partial execution failure in order" {
  let api = try! controller_resource(kind="service", name="api")
  let worker = try! controller_resource(kind="service", name="worker")
  let first = try! controller_operation(api, ActionKind::Update)
  let second = try! controller_operation(worker, ActionKind::Scale)
  let plan = try! controller_batched_plan([first, second])
  let ready = try! evaluate_reconciliation(
    try! controller_start(plan),
    try! controller_policy(),
  )
  let executing = try! controller_begin(ready)
  let running = try! apply_execution_result(
    executing,
    try! controller_execution_result(first, ExecutionState::Succeeded, "ok"),
  )
  let failed = try! apply_execution_result(
    running,
    try! controller_execution_result(
      second,
      ExecutionState::Failed,
      "adapter failed",
    ),
  )
  assert_eq(failed.audit_events.length(), 6)
  assert_eq(
    failed.audit_events[3].reason_code,
    AuditReasonCode::FeedbackSucceeded,
  )
  assert_eq(failed.audit_events[4].reason_code, AuditReasonCode::FeedbackFailed)
  assert_eq(failed.audit_events[4].state, ReconciliationState::Failed)
  assert_eq(
    failed.audit_events[5].reason_code,
    AuditReasonCode::ReconciliationFailed,
  )
  let replayed = try! replay_audit_events(plan, failed.audit_events)
  assert_eq(replayed.state, ReconciliationState::Failed)
  assert_eq(replayed.next_operation, 1)
  assert_eq(replayed.results.length(), 2)
}

///|
test "replay rejects non-contiguous audit sequences" {
  let plan = try! controller_batched_plan([])
  let event = try! AuditEvent::new(
    sequence=2,
    plan_id=plan.plan.id,
    kind=AuditEventKind::PlanCreated,
    reason_code=AuditReasonCode::PlanCreated,
    state=ReconciliationState::Planning,
    batch_index=None,
    operation=None,
    policy_decision=None,
    risk=None,
    explanation=None,
    execution_state=None,
  )
  try replay_audit_events(plan, [event]) catch {
    ModelError::InvalidAudit(message) =>
      inspect(message, content="audit sequence is not contiguous at 2")
    _ => fail("wrong audit replay error")
  } noraise {
    _ => fail("expected audit replay error")
  }
}
