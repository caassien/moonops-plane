///|
test "incident plan requires approval for restart" {
  let waiting = try! prepare_incident(try! build_incident_plan())
  assert_eq(
    waiting.state,
    @orbitops_plane.ReconciliationState::AwaitingApproval,
  )
  assert_eq(
    waiting.decisions[0].decision,
    @orbitops_plane.PolicyDecision::RequireApproval,
  )
  assert_eq(waiting.decisions[0].risk, @orbitops_plane.RiskLevel::High)
}

///|
test "incident failure stops after the selected action" {
  let result = try! execute_incident(try! build_incident_plan())
  assert_eq(result.state, @orbitops_plane.ReconciliationState::Failed)
  assert_eq(result.results.length(), 2)
  assert_eq(
    result.results[0].operation.action,
    @orbitops_plane.ActionKind::Restart,
  )
  assert_eq(
    result.results[1].operation.action,
    @orbitops_plane.ActionKind::Scale,
  )
  assert_eq(
    result.audit_events[result.audit_events.length() - 1].state,
    @orbitops_plane.ReconciliationState::Failed,
  )
}
