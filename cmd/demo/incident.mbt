///|
fn incident_resource(
  kind~ : String,
  name~ : String,
) -> @orbitops_plane.ResourceId raise @orbitops_plane.ModelError {
  @orbitops_plane.ResourceId::new(kind~, name~)
}

///|
fn incident_operation(
  resource : @orbitops_plane.ResourceId,
  action : @orbitops_plane.ActionKind,
  reason~ : String,
) -> @orbitops_plane.Operation raise @orbitops_plane.ModelError {
  @orbitops_plane.Operation::new(resource~, action~, reason~)
}

///|
fn build_incident_plan() -> @orbitops_plane.BatchedPlan raise @orbitops_plane.ModelError {
  let api = try! incident_resource(kind="service", name="api")
  let worker = try! incident_resource(kind="worker", name="jobs")
  let queue = try! incident_resource(kind="worker", name="queue")
  let operations = [
    try! incident_operation(
      api,
      @orbitops_plane.ActionKind::Restart,
      reason="recover unhealthy API",
    ),
    try! incident_operation(
      worker,
      @orbitops_plane.ActionKind::Scale,
      reason="restore worker capacity",
    ),
    try! incident_operation(
      queue,
      @orbitops_plane.ActionKind::Update,
      reason="refresh queue configuration",
    ),
  ]
  let dependencies : Array[
    (@orbitops_plane.ResourceId, @orbitops_plane.ResourceId),
  ] = [(api, worker)]
  let ordered = @orbitops_plane.build_ordered_plan(
    id=@testing.fixed_plan_id(),
    operations~,
    dependencies~,
    baseline_generation=1,
  )
  @orbitops_plane.batch_plan(
    ordered,
    @orbitops_plane.ChangeBudget::new(
      max_parallel=2,
      max_affected_resources=2,
      isolate_high_risk=true,
    ),
  )
}

///|
fn prepare_incident(
  plan : @orbitops_plane.BatchedPlan,
) -> @orbitops_plane.Reconciliation raise @orbitops_plane.ModelError {
  let policy = @orbitops_plane.SafetyPolicy::new(
    critical_resources=[],
    max_batch_operations=2,
    max_affected_resources=2,
  )
  let started = @orbitops_plane.start_reconciliation(
    plan,
    observed_generation=1,
  )
  @orbitops_plane.evaluate_reconciliation(started, policy)
}

///|
fn execute_incident(
  plan : @orbitops_plane.BatchedPlan,
) -> @orbitops_plane.Reconciliation raise @orbitops_plane.ModelError {
  let waiting = try! prepare_incident(plan)
  let approved = @orbitops_plane.approve_reconciliation(waiting)
  let executing = @orbitops_plane.begin_execution(
    approved,
    observed_generation=1,
  )
  let run = @testing.fixed_executor(
    script=@testing.partial_failure_script(
      action=@orbitops_plane.ActionKind::Scale,
    ),
  ).run(plan.plan.operations)
  let mut current = executing
  for result in run.results() {
    current = @orbitops_plane.apply_execution_result(current, result)
  }
  current
}

///|
fn run_incident() -> Unit {
  try {
    let plan = build_incident_plan()
    let waiting = prepare_incident(plan)
    println("OrbitOps incident recovery")
    println("approval=\{state_label(waiting.state)}")
    println(
      "decision[0]=\{policy_decision_label(waiting.decisions[0].decision)} " +
      "risk=\{risk_label(waiting.decisions[0].risk)}",
    )
    let result = execute_incident(plan)
    for index, feedback in result.results {
      println(
        "feedback[\{index}]=\{operation_label(feedback.operation)} " +
        "state=\{execution_state_label(feedback.state)}",
      )
    }
    println("feedback-count=\{result.results.length()}")
    println("state=\{state_label(result.state)}")
  } catch {
    _ => println("incident scenario failed")
  }
}
