///|
/// Coarse risk classification used by safety policy decisions.
pub(all) enum RiskLevel {
  Low
  Medium
  High
  Unknown
} derive(Debug, Eq)

///|
/// Machine-readable outcome of evaluating a safety policy.
pub(all) enum PolicyDecision {
  Allow
  Deny
  RequireApproval
} derive(Debug, Eq)

///|
/// Stable reason code attached to every safety policy decision.
pub(all) enum PolicyReasonCode {
  LowRisk
  MediumRisk
  HighRiskAction
  DeleteProtection
  BatchRestart
  CriticalResource
  BudgetConflict
  UnknownAction
} derive(Debug, Eq)

///|
/// Explainable result returned by a safety policy evaluation.
pub(all) struct PolicyEvaluation {
  decision : PolicyDecision
  risk : RiskLevel
  reason_code : PolicyReasonCode
  explanation : String
} derive(Debug, Eq)

///|
/// Rules applied to a change batch before execution is considered.
pub(all) struct SafetyPolicy {
  critical_resources : Array[ResourceId]
  max_batch_operations : Int
  max_affected_resources : Int
} derive(Debug, Eq)

///|
/// Creates a policy with positive batch limits.
pub fn SafetyPolicy::new(
  critical_resources~ : Array[ResourceId],
  max_batch_operations~ : Int,
  max_affected_resources~ : Int,
) -> SafetyPolicy raise ModelError {
  if max_batch_operations <= 0 {
    raise ModelError::InvalidBudget("max_batch_operations must be positive")
  }
  if max_affected_resources <= 0 {
    raise ModelError::InvalidBudget("max_affected_resources must be positive")
  }
  { critical_resources, max_batch_operations, max_affected_resources, }
}

///|
fn action_risk(action : ActionKind) -> RiskLevel {
  match action {
    ActionKind::Create => RiskLevel::Low
    ActionKind::Update | ActionKind::Scale => RiskLevel::Medium
    ActionKind::Restart | ActionKind::Delete => RiskLevel::High
    ActionKind::Unknown => RiskLevel::Unknown
  }
}

///|
fn contains_policy_resource(
  resources : Array[ResourceId],
  resource : ResourceId,
) -> Bool {
  let mut found = false
  for candidate in resources {
    if candidate == resource {
      found = true
    }
  }
  found
}

///|
fn policy_affected_resource_count(operations : Array[Operation]) -> Int {
  let resources : Array[ResourceId] = []
  for operation in operations {
    if !contains_policy_resource(resources, operation.resource) {
      resources.push(operation.resource)
    }
  }
  resources.length()
}

///|
fn has_critical_resource(
  operations : Array[Operation],
  critical_resources : Array[ResourceId],
) -> Bool {
  let mut found = false
  for operation in operations {
    if contains_policy_resource(critical_resources, operation.resource) {
      found = true
    }
  }
  found
}

///|
fn has_action(operations : Array[Operation], action : ActionKind) -> Bool {
  let mut found = false
  for operation in operations {
    if operation.action == action {
      found = true
    }
  }
  found
}

///|
fn action_count(operations : Array[Operation], action : ActionKind) -> Int {
  let mut count = 0
  for operation in operations {
    if operation.action == action {
      count += 1
    }
  }
  count
}

///|
fn batch_risk(operations : Array[Operation]) -> RiskLevel {
  let mut result = RiskLevel::Low
  for operation in operations {
    let current = action_risk(operation.action)
    match current {
      RiskLevel::Unknown => result = RiskLevel::Unknown
      RiskLevel::High =>
        if result != RiskLevel::Unknown {
          result = RiskLevel::High
        }
      RiskLevel::Medium =>
        if result == RiskLevel::Low {
          result = RiskLevel::Medium
        }
      RiskLevel::Low => ()
    }
  }
  result
}

///|
fn evaluation(
  decision : PolicyDecision,
  risk : RiskLevel,
  reason_code : PolicyReasonCode,
  explanation : String,
) -> PolicyEvaluation {
  { decision, risk, reason_code, explanation, }
}

///|
/// Evaluates a batch and returns a deterministic, explainable decision.
///
/// Unknown actions fail closed. Budget conflicts take precedence over
/// approval rules, while delete, restart and critical-resource rules require
/// approval instead of silently allowing a high-risk change.
pub fn evaluate_safety_policy(
  batch : ChangeBatch,
  policy : SafetyPolicy,
) -> PolicyEvaluation raise ModelError {
  if policy.max_batch_operations <= 0 {
    raise ModelError::InvalidBudget("max_batch_operations must be positive")
  }
  if policy.max_affected_resources <= 0 {
    raise ModelError::InvalidBudget("max_affected_resources must be positive")
  }
  let operations = batch.operations
  let risk = batch_risk(operations)
  if has_action(operations, ActionKind::Unknown) {
    evaluation(
      PolicyDecision::Deny,
      RiskLevel::Unknown,
      PolicyReasonCode::UnknownAction,
      "unknown action is rejected by default",
    )
  } else if operations.length() > policy.max_batch_operations ||
    policy_affected_resource_count(operations) > policy.max_affected_resources {
    evaluation(
      PolicyDecision::Deny,
      risk,
      PolicyReasonCode::BudgetConflict,
      "change batch exceeds the safety policy budget",
    )
  } else if has_action(operations, ActionKind::Delete) {
    evaluation(
      PolicyDecision::RequireApproval,
      RiskLevel::High,
      PolicyReasonCode::DeleteProtection,
      "delete operations require explicit approval",
    )
  } else if action_count(operations, ActionKind::Restart) > 1 {
    evaluation(
      PolicyDecision::RequireApproval,
      RiskLevel::High,
      PolicyReasonCode::BatchRestart,
      "multiple restart operations require explicit approval",
    )
  } else if has_critical_resource(operations, policy.critical_resources) {
    evaluation(
      PolicyDecision::RequireApproval,
      risk,
      PolicyReasonCode::CriticalResource,
      "changes affecting a critical resource require approval",
    )
  } else if risk == RiskLevel::High {
    evaluation(
      PolicyDecision::RequireApproval,
      RiskLevel::High,
      PolicyReasonCode::HighRiskAction,
      "high-risk operations require explicit approval",
    )
  } else if risk == RiskLevel::Medium {
    evaluation(
      PolicyDecision::Allow,
      RiskLevel::Medium,
      PolicyReasonCode::MediumRisk,
      "medium-risk operations fit the configured safety policy",
    )
  } else {
    evaluation(
      PolicyDecision::Allow,
      RiskLevel::Low,
      PolicyReasonCode::LowRisk,
      "low-risk operations fit the configured safety policy",
    )
  }
}

///|
/// Evaluates one operation using the same batch-level safety rules.
pub fn evaluate_operation_safety(
  operation : Operation,
  policy : SafetyPolicy,
) -> PolicyEvaluation raise ModelError {
  evaluate_safety_policy({ operations: [operation], }, policy)
}
