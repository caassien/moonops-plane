///|
test "rollout plan follows database api worker dependencies" {
  let plan = try! build_rollout()
  assert_eq(plan.plan.operations.length(), 3)
  assert_eq(plan.batches.length(), 3)
  assert_eq(plan.plan.operations[0].resource.name, "primary")
  assert_eq(plan.plan.operations[1].resource.name, "api")
  assert_eq(plan.plan.operations[2].resource.name, "jobs")
  assert_eq(plan.batches[0].operations[0], plan.plan.operations[0])
  assert_eq(plan.batches[1].operations[0], plan.plan.operations[1])
  assert_eq(plan.batches[2].operations[0], plan.plan.operations[2])
}

///|
test "rollout completes through the in-memory executor" {
  let result = try! execute_rollout(try! build_rollout())
  assert_eq(result.state, @orbitops_plane.ReconciliationState::Succeeded)
  assert_eq(result.results.length(), 3)
  assert_eq(result.next_operation, 3)
  assert_eq(
    result.audit_events[result.audit_events.length() - 1].kind,
    @orbitops_plane.AuditEventKind::Terminal,
  )
  assert_eq(
    result.audit_events[result.audit_events.length() - 1].state,
    @orbitops_plane.ReconciliationState::Succeeded,
  )
}
