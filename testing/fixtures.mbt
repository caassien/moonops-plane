///|
/// Stable plan identifier shared by deterministic examples.
pub fn fixed_plan_id() -> @orbitops_plane.PlanId {
  { value: "orbitops-fixed-plan", }
}

///|
/// Stable clock origin used by deterministic examples.
pub fn fixed_clock_start() -> Int {
  1_700_000_000
}

///|
/// Script that succeeds for every operation.
pub fn success_script() -> ExecutionScript {
  ExecutionScript::SucceedAll
}

///|
/// Script that rejects the first operation with the selected action.
pub fn rejection_script(
  action~ : @orbitops_plane.ActionKind,
) -> ExecutionScript {
  ExecutionScript::RejectAction(action)
}

///|
/// Script that fails the first operation with the selected action.
pub fn partial_failure_script(
  action~ : @orbitops_plane.ActionKind,
) -> ExecutionScript {
  ExecutionScript::FailAction(action)
}

///|
/// Creates an executor using the fixed plan identifier and clock.
pub fn fixed_executor(script~ : ExecutionScript) -> InMemoryExecutor {
  InMemoryExecutor::new(
    plan_id=fixed_plan_id(),
    script~,
    clock_start=fixed_clock_start(),
  )
}
