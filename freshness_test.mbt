///|
fn freshness_resource() -> @orbitops_plane.ResourceId raise @orbitops_plane.ModelError {
  @orbitops_plane.ResourceId::new(kind="service", name="api")
}

///|
fn freshness_operation() -> @orbitops_plane.Operation raise @orbitops_plane.ModelError {
  @orbitops_plane.Operation::new(
    resource=try! freshness_resource(),
    action=@orbitops_plane.ActionKind::Update,
    reason="freshness test",
  )
}

///|
fn freshness_plan(
  generation : Int,
) -> @orbitops_plane.Plan raise @orbitops_plane.ModelError {
  @orbitops_plane.Plan::new(
    id=@orbitops_plane.PlanId::new(value="freshness-plan"),
    operations=[try! freshness_operation()],
    baseline_generation=generation,
  )
}

///|
fn freshness_batch_plan(
  generation : Int,
) -> @orbitops_plane.BatchedPlan raise @orbitops_plane.ModelError {
  @orbitops_plane.batch_plan(
    freshness_plan(generation),
    @orbitops_plane.ChangeBudget::new(
      max_parallel=2,
      max_affected_resources=2,
      isolate_high_risk=false,
    ),
  )
}

///|
test "current observation generation is accepted" {
  @orbitops_plane.validate_plan_freshness(
    freshness_plan(2),
    observed_generation=2,
  )
  let plan = try! freshness_plan(2)
  let result = try! @orbitops_plane.ExecutionResult::new(
    plan_id=plan.id,
    operation=try! freshness_operation(),
    state=@orbitops_plane.ExecutionState::Succeeded,
    message="applied",
  )
  @orbitops_plane.validate_feedback_plan(plan, result)
}

///|
test "older observations are rejected before reconciliation starts" {
  try
    @orbitops_plane.start_reconciliation(
      freshness_batch_plan(2),
      observed_generation=1,
    )
  catch {
    @orbitops_plane.ModelError::StaleObservation(message) =>
      inspect(
        message,
        content="observed generation 1 is older than plan baseline 2",
      )
    _ => fail("wrong stale observation error")
  } noraise {
    _ => fail("expected an old observation to be rejected")
  }
}

///|
test "new observations invalidate a plan before execution" {
  let started = try! @orbitops_plane.start_reconciliation(
    freshness_batch_plan(2),
    observed_generation=2,
  )
  let ready = try! @orbitops_plane.evaluate_reconciliation(
    started,
    @orbitops_plane.SafetyPolicy::new(
      critical_resources=[],
      max_batch_operations=2,
      max_affected_resources=2,
    ),
  )
  try @orbitops_plane.begin_execution(ready, observed_generation=3) catch {
    @orbitops_plane.ModelError::StalePlan(message) =>
      inspect(
        message,
        content="plan baseline 2 is older than observed generation 3",
      )
    _ => fail("wrong stale plan error")
  } noraise {
    _ => fail("expected a new observation to invalidate the plan")
  }
}

///|
test "matching observation generation reaches execution" {
  let started = try! @orbitops_plane.start_reconciliation(
    freshness_batch_plan(2),
    observed_generation=2,
  )
  let ready = try! @orbitops_plane.evaluate_reconciliation(
    started,
    @orbitops_plane.SafetyPolicy::new(
      critical_resources=[],
      max_batch_operations=2,
      max_affected_resources=2,
    ),
  )
  let executing = try! @orbitops_plane.begin_execution(
    ready,
    observed_generation=2,
  )
  assert_eq(executing.state, @orbitops_plane.ReconciliationState::Executing)
}

///|
test "feedback from another plan is rejected" {
  let plan = try! freshness_plan(2)
  let other_plan_id = try! @orbitops_plane.PlanId::new(value="other-plan")
  let result = try! @orbitops_plane.ExecutionResult::new(
    plan_id=other_plan_id,
    operation=try! freshness_operation(),
    state=@orbitops_plane.ExecutionState::Succeeded,
    message="applied",
  )
  try @orbitops_plane.validate_feedback_plan(plan, result) catch {
    @orbitops_plane.ModelError::PlanMismatch(message) =>
      inspect(
        message,
        content="feedback plan other-plan does not match active plan freshness-plan",
      )
    _ => fail("wrong plan mismatch error")
  } noraise {
    _ => fail("expected a mismatched feedback plan")
  }
}

///|
test "non-positive observed generations are rejected" {
  try
    @orbitops_plane.validate_plan_freshness(
      freshness_plan(2),
      observed_generation=0,
    )
  catch {
    @orbitops_plane.ModelError::NonPositiveGeneration => ()
    _ => fail("wrong generation error")
  } noraise {
    _ => fail("expected a non-positive generation error")
  }
}
