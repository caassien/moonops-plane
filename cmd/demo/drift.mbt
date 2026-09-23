///|
fn drift_resource() -> @orbitops_plane.ResourceId raise @orbitops_plane.ModelError {
  @orbitops_plane.ResourceId::new(kind="service", name="api")
}

///|
fn drift_desired_state() -> @orbitops_plane.DesiredState raise @orbitops_plane.ModelError {
  let resource = try! drift_resource()
  let spec = @orbitops_plane.ResourceSpec::new(
    version="v2",
    replicas=3,
    config_fingerprint="api-v2",
    enabled=true,
  )
  @orbitops_plane.DesiredState::new(resource~, spec~, generation=2)
}

///|
fn drift_observed_state() -> @orbitops_plane.ObservedState raise @orbitops_plane.ModelError {
  let resource = try! drift_resource()
  let spec = @orbitops_plane.ResourceSpec::new(
    version="v1",
    replicas=2,
    config_fingerprint="api-v1",
    enabled=true,
  )
  @orbitops_plane.ObservedState::new(
    resource~,
    spec~,
    generation=1,
    healthy=true,
  )
}

///|
fn build_drift_plan() -> @orbitops_plane.BatchedPlan raise @orbitops_plane.ModelError {
  let desired = try! drift_desired_state()
  let observed = try! drift_observed_state()
  let operation = match @orbitops_plane.compute_diff(desired, Some(observed)) {
    @orbitops_plane.DiffResult::Action(value) => value
    @orbitops_plane.DiffResult::NoChange =>
      raise @orbitops_plane.ModelError::InvalidTransition(
        "drift scenario expected an update",
      )
  }
  let plan = @orbitops_plane.Plan::new(
    id=@testing.fixed_plan_id(),
    operations=[operation],
    baseline_generation=1,
  )
  @orbitops_plane.batch_plan(
    plan,
    @orbitops_plane.ChangeBudget::new(
      max_parallel=1,
      max_affected_resources=1,
      isolate_high_risk=false,
    ),
  )
}

///|
fn prepare_drift(
  plan : @orbitops_plane.BatchedPlan,
) -> @orbitops_plane.Reconciliation raise @orbitops_plane.ModelError {
  let policy = @orbitops_plane.SafetyPolicy::new(
    critical_resources=[],
    max_batch_operations=1,
    max_affected_resources=1,
  )
  let started = @orbitops_plane.start_reconciliation(
    plan,
    observed_generation=1,
  )
  @orbitops_plane.evaluate_reconciliation(started, policy)
}

///|
fn execute_drift(
  plan : @orbitops_plane.BatchedPlan,
) -> @orbitops_plane.Reconciliation raise @orbitops_plane.ModelError {
  let ready = try! prepare_drift(plan)
  let executing = @orbitops_plane.begin_execution(ready, observed_generation=1)
  let run = @testing.fixed_executor(script=@testing.success_script()).run(
    plan.plan.operations,
  )
  let mut current = executing
  for result in run.results() {
    current = @orbitops_plane.apply_execution_result(current, result)
  }
  current
}

///|
fn run_drift() -> Unit {
  try {
    let plan = build_drift_plan()
    let result = execute_drift(plan)
    println("OrbitOps configuration drift")
    println(
      "diff=\{operation_label(result.results[0].operation)} " +
      "decision=\{policy_decision_label(result.decisions[0].decision)}",
    )
    println("state=\{state_label(result.state)}")
    let ready = prepare_drift(plan)
    try {
      let _ = @orbitops_plane.begin_execution(ready, observed_generation=2)
      println("stale-observation=unexpected-success")
    } catch {
      @orbitops_plane.ModelError::StalePlan(message) =>
        println("stale-observation=rejected: \{message}")
      _ => println("stale-observation=unexpected-error")
    }
  } catch {
    _ => println("drift scenario failed")
  }
}
