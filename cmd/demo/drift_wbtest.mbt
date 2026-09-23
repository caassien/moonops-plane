///|
test "drift remediation is allowed and stale execution is rejected" {
  let plan = try! build_drift_plan()
  assert_eq(plan.plan.operations.length(), 1)
  assert_eq(plan.plan.operations[0].action, @orbitops_plane.ActionKind::Update)
  let ready = try! prepare_drift(plan)
  assert_eq(ready.state, @orbitops_plane.ReconciliationState::Ready)
  assert_eq(ready.decisions[0].decision, @orbitops_plane.PolicyDecision::Allow)
  try @orbitops_plane.begin_execution(ready, observed_generation=2) catch {
    @orbitops_plane.ModelError::StalePlan(message) =>
      inspect(
        message,
        content="plan baseline 1 is older than observed generation 2",
      )
    _ => fail("wrong stale plan error")
  } noraise {
    _ => fail("expected stale plan error")
  }
}

///|
test "drift remediation completes with one successful feedback" {
  let result = try! execute_drift(try! build_drift_plan())
  assert_eq(result.state, @orbitops_plane.ReconciliationState::Succeeded)
  assert_eq(result.results.length(), 1)
  assert_eq(result.next_operation, 1)
}
