///|
fn policy_resource(
  kind~ : String,
  name~ : String,
) -> ResourceId raise ModelError {
  ResourceId::new(kind~, name~)
}

///|
fn policy_operation(
  resource : ResourceId,
  action : ActionKind,
) -> Operation raise ModelError {
  Operation::new(resource~, action~, reason="policy test")
}

///|
fn policy(
  critical_resources~ : Array[ResourceId],
  max_batch_operations~ : Int,
  max_affected_resources~ : Int,
) -> SafetyPolicy raise ModelError {
  SafetyPolicy::new(
    critical_resources~,
    max_batch_operations~,
    max_affected_resources~,
  )
}

///|
fn assert_decision(
  result : PolicyEvaluation,
  decision : PolicyDecision,
  risk : RiskLevel,
  reason : PolicyReasonCode,
) -> Unit raise {
  assert_eq(result.decision, decision)
  assert_eq(result.risk, risk)
  assert_eq(result.reason_code, reason)
  assert_true(result.explanation.length() > 0)
}

///|
test "low risk operations are allowed with an explanation" {
  let resource = try! policy_resource(kind="service", name="api")
  let result = try! evaluate_operation_safety(
    try! policy_operation(resource, ActionKind::Create),
    try! policy(
      critical_resources=[],
      max_batch_operations=2,
      max_affected_resources=2,
    ),
  )
  assert_decision(
    result,
    PolicyDecision::Allow,
    RiskLevel::Low,
    PolicyReasonCode::LowRisk,
  )
}

///|
test "medium risk operations are allowed within budget" {
  let resource = try! policy_resource(kind="service", name="api")
  let result = try! evaluate_operation_safety(
    try! policy_operation(resource, ActionKind::Scale),
    try! policy(
      critical_resources=[],
      max_batch_operations=2,
      max_affected_resources=2,
    ),
  )
  assert_decision(
    result,
    PolicyDecision::Allow,
    RiskLevel::Medium,
    PolicyReasonCode::MediumRisk,
  )
}

///|
test "high risk restart waits for approval" {
  let resource = try! policy_resource(kind="service", name="api")
  let result = try! evaluate_operation_safety(
    try! policy_operation(resource, ActionKind::Restart),
    try! policy(
      critical_resources=[],
      max_batch_operations=2,
      max_affected_resources=2,
    ),
  )
  assert_decision(
    result,
    PolicyDecision::RequireApproval,
    RiskLevel::High,
    PolicyReasonCode::HighRiskAction,
  )
}

///|
test "deletes require approval before automatic execution" {
  let resource = try! policy_resource(kind="service", name="api")
  let result = try! evaluate_operation_safety(
    try! policy_operation(resource, ActionKind::Delete),
    try! policy(
      critical_resources=[],
      max_batch_operations=2,
      max_affected_resources=2,
    ),
  )
  assert_decision(
    result,
    PolicyDecision::RequireApproval,
    RiskLevel::High,
    PolicyReasonCode::DeleteProtection,
  )
}

///|
test "critical resources require approval" {
  let database = try! policy_resource(kind="database", name="primary")
  let result = try! evaluate_operation_safety(
    try! policy_operation(database, ActionKind::Update),
    try! policy(
      critical_resources=[database],
      max_batch_operations=2,
      max_affected_resources=2,
    ),
  )
  assert_decision(
    result,
    PolicyDecision::RequireApproval,
    RiskLevel::Medium,
    PolicyReasonCode::CriticalResource,
  )
}

///|
test "batch restarts require approval" {
  let api = try! policy_resource(kind="service", name="api")
  let worker = try! policy_resource(kind="service", name="worker")
  let batch : ChangeBatch = {
    operations: [
      try! policy_operation(api, ActionKind::Restart),
      try! policy_operation(worker, ActionKind::Restart),
    ],
  }
  let result = try! evaluate_safety_policy(
    batch,
    try! policy(
      critical_resources=[],
      max_batch_operations=2,
      max_affected_resources=2,
    ),
  )
  assert_decision(
    result,
    PolicyDecision::RequireApproval,
    RiskLevel::High,
    PolicyReasonCode::BatchRestart,
  )
}

///|
test "unknown actions fail closed" {
  let resource = try! policy_resource(kind="service", name="api")
  let result = try! evaluate_operation_safety(
    try! policy_operation(resource, ActionKind::Unknown),
    try! policy(
      critical_resources=[],
      max_batch_operations=2,
      max_affected_resources=2,
    ),
  )
  assert_decision(
    result,
    PolicyDecision::Deny,
    RiskLevel::Unknown,
    PolicyReasonCode::UnknownAction,
  )
}

///|
test "budget conflict is denied before approval rules" {
  let api = try! policy_resource(kind="service", name="api")
  let worker = try! policy_resource(kind="service", name="worker")
  let batch : ChangeBatch = {
    operations: [
      try! policy_operation(api, ActionKind::Delete),
      try! policy_operation(worker, ActionKind::Update),
    ],
  }
  let result = try! evaluate_safety_policy(
    batch,
    try! policy(
      critical_resources=[],
      max_batch_operations=1,
      max_affected_resources=2,
    ),
  )
  assert_decision(
    result,
    PolicyDecision::Deny,
    RiskLevel::High,
    PolicyReasonCode::BudgetConflict,
  )
}

///|
test "invalid safety policy budgets are rejected" {
  try
    SafetyPolicy::new(
      critical_resources=[],
      max_batch_operations=0,
      max_affected_resources=1,
    )
  catch {
    ModelError::InvalidBudget(message) =>
      inspect(message, content="max_batch_operations must be positive")
    _ => fail("wrong safety policy error")
  } noraise {
    _ => fail("expected an invalid safety policy budget")
  }
}
