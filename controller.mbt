///|
/// Lifecycle stages for a reconciliation run.
pub(all) enum ReconciliationState {
  Planning
  AwaitingApproval
  Ready
  Executing
  Succeeded
  Failed
  Terminated
} derive(Debug, Eq)

///|
/// Controller-owned state for one plan execution lifecycle.
pub(all) struct Reconciliation {
  plan : BatchedPlan
  state : ReconciliationState
  observed_generation : Int
  decisions : Array[PolicyEvaluation]
  next_operation : Int
  results : Array[ExecutionResult]
} derive(Debug, Eq)

///|
/// Starts a reconciliation after validating its observed generation.
pub fn start_reconciliation(
  plan : BatchedPlan,
  observed_generation~ : Int,
) -> Reconciliation raise ModelError {
  validate_plan_freshness(plan.plan, observed_generation~)
  {
    plan,
    state: ReconciliationState::Planning,
    observed_generation,
    decisions: [],
    next_operation: 0,
    results: [],
  }
}

///|
fn controller_state_name(state : ReconciliationState) -> String {
  match state {
    ReconciliationState::Planning => "planning"
    ReconciliationState::AwaitingApproval => "awaiting approval"
    ReconciliationState::Ready => "ready"
    ReconciliationState::Executing => "executing"
    ReconciliationState::Succeeded => "succeeded"
    ReconciliationState::Failed => "failed"
    ReconciliationState::Terminated => "terminated"
  }
}

///|
fn controller_with_approval(
  plan : BatchedPlan,
  approval : ApprovalState,
) -> BatchedPlan {
  let source = plan.plan
  let updated : Plan = {
    id: source.id,
    operations: source.operations,
    baseline_generation: source.baseline_generation,
    approval,
  }
  { plan: updated, batches: plan.batches, }
}

///|
fn controller_set_state(
  reconciliation : Reconciliation,
  state : ReconciliationState,
  approval : ApprovalState,
) -> Reconciliation {
  {
    plan: controller_with_approval(reconciliation.plan, approval),
    state,
    observed_generation: reconciliation.observed_generation,
    decisions: reconciliation.decisions,
    next_operation: reconciliation.next_operation,
    results: reconciliation.results,
  }
}

///|
fn controller_set_evaluation(
  reconciliation : Reconciliation,
  state : ReconciliationState,
  approval : ApprovalState,
  decisions : Array[PolicyEvaluation],
) -> Reconciliation {
  {
    plan: controller_with_approval(reconciliation.plan, approval),
    state,
    observed_generation: reconciliation.observed_generation,
    decisions,
    next_operation: reconciliation.next_operation,
    results: reconciliation.results,
  }
}

///|
/// Evaluates every batch and moves the run to ready, approval, or failed.
pub fn evaluate_reconciliation(
  reconciliation : Reconciliation,
  policy : SafetyPolicy,
) -> Reconciliation raise ModelError {
  if reconciliation.state != ReconciliationState::Planning {
    raise ModelError::InvalidTransition(
      "cannot evaluate from \{controller_state_name(reconciliation.state)}",
    )
  }
  let decisions : Array[PolicyEvaluation] = []
  let mut denied = false
  let mut approval_required = false
  for batch in reconciliation.plan.batches {
    let decision = evaluate_safety_policy(batch, policy)
    decisions.push(decision)
    match decision.decision {
      PolicyDecision::Deny => denied = true
      PolicyDecision::RequireApproval => approval_required = true
      PolicyDecision::Allow => ()
    }
  }
  if denied {
    controller_set_evaluation(
      reconciliation,
      ReconciliationState::Failed,
      ApprovalState::Rejected,
      decisions,
    )
  } else if approval_required {
    controller_set_evaluation(
      reconciliation,
      ReconciliationState::AwaitingApproval,
      ApprovalState::Pending,
      decisions,
    )
  } else {
    controller_set_evaluation(
      reconciliation,
      ReconciliationState::Ready,
      ApprovalState::NotRequired,
      decisions,
    )
  }
}

///|
/// Approves a run that is waiting for an explicit approval.
pub fn approve_reconciliation(
  reconciliation : Reconciliation,
) -> Reconciliation raise ModelError {
  if reconciliation.state != ReconciliationState::AwaitingApproval {
    raise ModelError::InvalidTransition(
      "cannot approve from \{controller_state_name(reconciliation.state)}",
    )
  }
  controller_set_state(
    reconciliation,
    ReconciliationState::Ready,
    ApprovalState::Approved,
  )
}

///|
/// Rejects an approval request and terminates the run.
pub fn reject_reconciliation(
  reconciliation : Reconciliation,
) -> Reconciliation raise ModelError {
  if reconciliation.state != ReconciliationState::AwaitingApproval {
    raise ModelError::InvalidTransition(
      "cannot reject from \{controller_state_name(reconciliation.state)}",
    )
  }
  controller_set_state(
    reconciliation,
    ReconciliationState::Terminated,
    ApprovalState::Rejected,
  )
}

///|
fn controller_total_operations(plan : BatchedPlan) -> Int {
  let mut count = 0
  for batch in plan.batches {
    count += batch.operations.length()
  }
  count
}

///|
fn controller_operation_at(plan : BatchedPlan, index : Int) -> Operation? {
  let mut offset = 0
  let mut result : Operation? = None
  for batch in plan.batches {
    for operation in batch.operations {
      if offset == index {
        result = Some(operation)
      }
      offset += 1
    }
  }
  result
}

///|
fn controller_has_feedback(
  results : Array[ExecutionResult],
  operation : Operation,
) -> Bool {
  let mut found = false
  for result in results {
    if result.operation == operation {
      found = true
    }
  }
  found
}

///|
/// Moves a ready run into execution after rechecking observation freshness.
pub fn begin_execution(
  reconciliation : Reconciliation,
  observed_generation~ : Int,
) -> Reconciliation raise ModelError {
  if reconciliation.state != ReconciliationState::Ready {
    raise ModelError::InvalidTransition(
      "cannot begin execution from \{controller_state_name(reconciliation.state)}",
    )
  }
  validate_plan_freshness(reconciliation.plan.plan, observed_generation~)
  if controller_total_operations(reconciliation.plan) == 0 {
    controller_set_state(
      reconciliation,
      ReconciliationState::Succeeded,
      reconciliation.plan.plan.approval,
    )
  } else {
    controller_set_state(
      reconciliation,
      ReconciliationState::Executing,
      reconciliation.plan.plan.approval,
    )
  }
}

///|
/// Applies one ordered executor feedback without invoking an executor.
pub fn apply_execution_result(
  reconciliation : Reconciliation,
  result : ExecutionResult,
) -> Reconciliation raise ModelError {
  if reconciliation.state != ReconciliationState::Executing {
    raise ModelError::InvalidTransition(
      "cannot apply feedback from \{controller_state_name(reconciliation.state)}",
    )
  }
  validate_feedback_plan(reconciliation.plan.plan, result)
  if controller_has_feedback(reconciliation.results, result.operation) {
    raise ModelError::DuplicateFeedback(resource_key(result.operation.resource))
  }
  let expected = match
    controller_operation_at(reconciliation.plan, reconciliation.next_operation) {
    Some(operation) => operation
    None => raise ModelError::InvalidTransition("no operation awaits feedback")
  }
  if expected != result.operation {
    raise ModelError::InvalidTransition(
      "feedback operation does not match the next planned operation",
    )
  }
  reconciliation.results.push(result)
  match result.state {
    ExecutionState::Succeeded => {
      let next_operation = reconciliation.next_operation + 1
      let state = if next_operation ==
        controller_total_operations(reconciliation.plan) {
        ReconciliationState::Succeeded
      } else {
        ReconciliationState::Executing
      }
      {
        plan: reconciliation.plan,
        state,
        observed_generation: reconciliation.observed_generation,
        decisions: reconciliation.decisions,
        next_operation,
        results: reconciliation.results,
      }
    }
    ExecutionState::Failed | ExecutionState::Skipped =>
      {
        plan: reconciliation.plan,
        state: ReconciliationState::Failed,
        observed_generation: reconciliation.observed_generation,
        decisions: reconciliation.decisions,
        next_operation: reconciliation.next_operation,
        results: reconciliation.results,
      }
  }
}

///|
/// Terminates a non-terminal run without producing executor side effects.
pub fn terminate_reconciliation(
  reconciliation : Reconciliation,
) -> Reconciliation raise ModelError {
  match reconciliation.state {
    ReconciliationState::Succeeded
    | ReconciliationState::Failed
    | ReconciliationState::Terminated =>
      raise ModelError::InvalidTransition(
        "cannot terminate a terminal reconciliation",
      )
    _ =>
      controller_set_state(
        reconciliation,
        ReconciliationState::Terminated,
        ApprovalState::Rejected,
      )
  }
}
