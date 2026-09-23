///|
test "audit events preserve a successful lifecycle and replay" {
  let api = try! controller_resource(kind="service", name="api")
  let operation = try! controller_operation(
    api,
    @orbitops_plane.ActionKind::Update,
  )
  let plan = try! controller_batched_plan([operation])
  let started = try! controller_start(plan)
  let ready = try! @orbitops_plane.evaluate_reconciliation(
    started,
    try! controller_policy(),
  )
  let executing = try! controller_begin(ready)
  let succeeded = try! @orbitops_plane.apply_execution_result(
    executing,
    try! controller_execution_result(
      operation,
      @orbitops_plane.ExecutionState::Succeeded,
      "token=super-secret",
    ),
  )
  let events = succeeded.audit_events
  assert_eq(events.length(), 5)
  assert_eq(events[0].sequence, 1)
  assert_eq(events[0].kind, @orbitops_plane.AuditEventKind::PlanCreated)
  assert_eq(events[1].sequence, 2)
  assert_eq(events[1].kind, @orbitops_plane.AuditEventKind::PolicyDecision)
  assert_eq(
    events[1].reason_code,
    @orbitops_plane.AuditReasonCode::Policy(
      @orbitops_plane.PolicyReasonCode::MediumRisk,
    ),
  )
  assert_eq(events[2].kind, @orbitops_plane.AuditEventKind::StateTransition)
  assert_eq(events[2].reason_code, @orbitops_plane.AuditReasonCode::Executing)
  assert_eq(events[3].kind, @orbitops_plane.AuditEventKind::ExecutionFeedback)
  assert_eq(
    events[3].execution_state,
    Some(@orbitops_plane.ExecutionState::Succeeded),
  )
  assert_eq(events[4].kind, @orbitops_plane.AuditEventKind::Terminal)
  assert_eq(
    events[4].reason_code,
    @orbitops_plane.AuditReasonCode::ReconciliationSucceeded,
  )
  let replayed = try! @orbitops_plane.replay_audit_events(plan, events)
  assert_eq(replayed.state, @orbitops_plane.ReconciliationState::Succeeded)
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
  let operation = try! controller_operation(
    api,
    @orbitops_plane.ActionKind::Delete,
  )
  let plan = try! controller_batched_plan([operation])
  let waiting = try! @orbitops_plane.evaluate_reconciliation(
    try! controller_start(plan),
    try! controller_policy(),
  )
  assert_eq(waiting.audit_events.length(), 3)
  assert_eq(
    waiting.audit_events[2].reason_code,
    @orbitops_plane.AuditReasonCode::ApprovalRequested,
  )
  let terminated = try! @orbitops_plane.reject_reconciliation(waiting)
  assert_eq(terminated.audit_events.length(), 5)
  assert_eq(
    terminated.audit_events[3].reason_code,
    @orbitops_plane.AuditReasonCode::ApprovalRejected,
  )
  assert_eq(
    terminated.audit_events[4].kind,
    @orbitops_plane.AuditEventKind::Terminal,
  )
  assert_eq(
    terminated.audit_events[4].reason_code,
    @orbitops_plane.AuditReasonCode::ReconciliationTerminated,
  )
  let replayed = try! @orbitops_plane.replay_audit_events(
    plan,
    terminated.audit_events,
  )
  assert_eq(replayed.state, @orbitops_plane.ReconciliationState::Terminated)
  assert_eq(
    replayed.plan.plan.approval,
    @orbitops_plane.ApprovalState::Rejected,
  )
  assert_eq(replayed.next_operation, 0)
  assert_eq(replayed.results.length(), 0)
}

///|
test "audit events capture partial execution failure in order" {
  let api = try! controller_resource(kind="service", name="api")
  let worker = try! controller_resource(kind="service", name="worker")
  let first = try! controller_operation(api, @orbitops_plane.ActionKind::Update)
  let second = try! controller_operation(
    worker,
    @orbitops_plane.ActionKind::Scale,
  )
  let plan = try! controller_batched_plan([first, second])
  let ready = try! @orbitops_plane.evaluate_reconciliation(
    try! controller_start(plan),
    try! controller_policy(),
  )
  let executing = try! controller_begin(ready)
  let running = try! @orbitops_plane.apply_execution_result(
    executing,
    try! controller_execution_result(
      first,
      @orbitops_plane.ExecutionState::Succeeded,
      "ok",
    ),
  )
  let failed = try! @orbitops_plane.apply_execution_result(
    running,
    try! controller_execution_result(
      second,
      @orbitops_plane.ExecutionState::Failed,
      "adapter failed",
    ),
  )
  assert_eq(failed.audit_events.length(), 6)
  assert_eq(
    failed.audit_events[3].reason_code,
    @orbitops_plane.AuditReasonCode::FeedbackSucceeded,
  )
  assert_eq(
    failed.audit_events[4].reason_code,
    @orbitops_plane.AuditReasonCode::FeedbackFailed,
  )
  assert_eq(
    failed.audit_events[4].state,
    @orbitops_plane.ReconciliationState::Failed,
  )
  assert_eq(
    failed.audit_events[5].reason_code,
    @orbitops_plane.AuditReasonCode::ReconciliationFailed,
  )
  let replayed = try! @orbitops_plane.replay_audit_events(
    plan,
    failed.audit_events,
  )
  assert_eq(replayed.state, @orbitops_plane.ReconciliationState::Failed)
  assert_eq(replayed.next_operation, 1)
  assert_eq(replayed.results.length(), 2)
}

///|
test "replay rejects non-contiguous audit sequences" {
  let plan = try! controller_batched_plan([])
  let event = try! @orbitops_plane.AuditEvent::new(
    sequence=2,
    plan_id=plan.plan.id,
    kind=@orbitops_plane.AuditEventKind::PlanCreated,
    reason_code=@orbitops_plane.AuditReasonCode::PlanCreated,
    state=@orbitops_plane.ReconciliationState::Planning,
    batch_index=None,
    operation=None,
    policy_decision=None,
    risk=None,
    explanation=None,
    execution_state=None,
  )
  try @orbitops_plane.replay_audit_events(plan, [event]) catch {
    @orbitops_plane.ModelError::InvalidAudit(message) =>
      inspect(message, content="audit sequence is not contiguous at 2")
    _ => fail("wrong audit replay error")
  } noraise {
    _ => fail("expected audit replay error")
  }
}
