///|
/// Deterministic script used by the in-memory executor.
pub(all) enum ExecutionScript {
  SucceedAll
  RejectAction(@moonops_plane.ActionKind)
  FailAction(@moonops_plane.ActionKind)
} derive(Debug, Eq)

///|
/// One structured feedback record emitted by the in-memory executor.
pub(all) struct ExecutionRecord {
  sequence : Int
  timestamp : Int
  result : @moonops_plane.ExecutionResult
} derive(Debug, Eq)

///|
/// The complete deterministic output of one executor run.
pub(all) struct ExecutionRun {
  plan_id : @moonops_plane.PlanId
  records : Array[ExecutionRecord]
  stopped : Bool
} derive(Debug, Eq)

///|
/// A side-effect-free executor for examples and tests.
pub(all) struct InMemoryExecutor {
  plan_id : @moonops_plane.PlanId
  script : ExecutionScript
  clock_start : Int
} derive(Debug, Eq)

///|
/// Creates an executor with a fixed plan identifier and clock origin.
pub fn InMemoryExecutor::new(
  plan_id~ : @moonops_plane.PlanId,
  script~ : ExecutionScript,
  clock_start~ : Int,
) -> InMemoryExecutor {
  { plan_id, script, clock_start, }
}

///|
fn feedback_for(
  plan_id : @moonops_plane.PlanId,
  script : ExecutionScript,
  operation : @moonops_plane.Operation,
) -> @moonops_plane.ExecutionResult raise @moonops_plane.ModelError {
  let state = match script {
    ExecutionScript::SucceedAll => @moonops_plane.ExecutionState::Succeeded
    ExecutionScript::RejectAction(action) =>
      if action == operation.action {
        @moonops_plane.ExecutionState::Skipped
      } else {
        @moonops_plane.ExecutionState::Succeeded
      }
    ExecutionScript::FailAction(action) =>
      if action == operation.action {
        @moonops_plane.ExecutionState::Failed
      } else {
        @moonops_plane.ExecutionState::Succeeded
      }
  }
  let message = match state {
    @moonops_plane.ExecutionState::Succeeded => "in-memory operation succeeded"
    @moonops_plane.ExecutionState::Failed => "in-memory operation failed"
    @moonops_plane.ExecutionState::Skipped => "in-memory operation rejected"
  }
  @moonops_plane.ExecutionResult::new(plan_id~, operation~, state~, message~)
}

///|
/// Executes operations in order and stops after the first non-success result.
pub fn InMemoryExecutor::run(
  self : InMemoryExecutor,
  operations : Array[@moonops_plane.Operation],
) -> ExecutionRun raise @moonops_plane.ModelError {
  let records : Array[ExecutionRecord] = []
  let mut stopped = false
  for operation in operations {
    if !stopped {
      let sequence = records.length() + 1
      let result = feedback_for(self.plan_id, self.script, operation)
      records.push({
        sequence,
        timestamp: self.clock_start + sequence - 1,
        result,
      })
      if result.state != @moonops_plane.ExecutionState::Succeeded {
        stopped = true
      }
    }
  }
  { plan_id: self.plan_id, records, stopped, }
}

///|
/// Extracts feedback in the same order in which it was emitted.
pub fn ExecutionRun::results(
  self : ExecutionRun,
) -> Array[@moonops_plane.ExecutionResult] {
  let results : Array[@moonops_plane.ExecutionResult] = []
  for record in self.records {
    results.push(record.result)
  }
  results
}
