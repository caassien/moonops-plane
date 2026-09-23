///|
fn policy_resource(
  kind~ : String,
  name~ : String,
) -> @orbitops_plane.ResourceId raise @orbitops_plane.ModelError {
  @orbitops_plane.ResourceId::new(kind~, name~)
}

///|
fn policy_operation(
  resource : @orbitops_plane.ResourceId,
  action : @orbitops_plane.ActionKind,
) -> @orbitops_plane.Operation raise @orbitops_plane.ModelError {
  @orbitops_plane.Operation::new(resource~, action~, reason="policy test")
}

///|
fn policy(
  critical_resources~ : Array[@orbitops_plane.ResourceId],
  max_batch_operations~ : Int,
  max_affected_resources~ : Int,
) -> @orbitops_plane.SafetyPolicy raise @orbitops_plane.ModelError {
  @orbitops_plane.SafetyPolicy::new(
    critical_resources~,
    max_batch_operations~,
    max_affected_resources~,
  )
}

///|
fn assert_decision(
  result : @orbitops_plane.PolicyEvaluation,
  decision : @orbitops_plane.PolicyDecision,
  risk : @orbitops_plane.RiskLevel,
  reason : @orbitops_plane.PolicyReasonCode,
) -> Unit raise {
  assert_eq(result.decision, decision)
  assert_eq(result.risk, risk)
  assert_eq(result.reason_code, reason)
  assert_true(result.explanation.length() > 0)
}

///|
test "low risk operations are allowed with an explanation" {
  let resource = try! policy_resource(kind="service", name="api")
  let result = try! @orbitops_plane.evaluate_operation_safety(
    try! policy_operation(resource, @orbitops_plane.ActionKind::Create),
    try! policy(
      critical_resources=[],
      max_batch_operations=2,
      max_affected_resources=2,
    ),
  )
  assert_decision(
    result,
    @orbitops_plane.PolicyDecision::Allow,
    @orbitops_plane.RiskLevel::Low,
    @orbitops_plane.PolicyReasonCode::LowRisk,
  )
}

///|
test "medium risk operations are allowed within budget" {
  let resource = try! policy_resource(kind="service", name="api")
  let result = try! @orbitops_plane.evaluate_operation_safety(
    try! policy_operation(resource, @orbitops_plane.ActionKind::Scale),
    try! policy(
      critical_resources=[],
      max_batch_operations=2,
      max_affected_resources=2,
    ),
  )
  assert_decision(
    result,
    @orbitops_plane.PolicyDecision::Allow,
    @orbitops_plane.RiskLevel::Medium,
    @orbitops_plane.PolicyReasonCode::MediumRisk,
  )
}

///|
test "high risk restart waits for approval" {
  let resource = try! policy_resource(kind="service", name="api")
  let result = try! @orbitops_plane.evaluate_operation_safety(
    try! policy_operation(resource, @orbitops_plane.ActionKind::Restart),
    try! policy(
      critical_resources=[],
      max_batch_operations=2,
      max_affected_resources=2,
    ),
  )
  assert_decision(
    result,
    @orbitops_plane.PolicyDecision::RequireApproval,
    @orbitops_plane.RiskLevel::High,
    @orbitops_plane.PolicyReasonCode::HighRiskAction,
  )
}

///|
test "deletes require approval before automatic execution" {
  let resource = try! policy_resource(kind="service", name="api")
  let result = try! @orbitops_plane.evaluate_operation_safety(
    try! policy_operation(resource, @orbitops_plane.ActionKind::Delete),
    try! policy(
      critical_resources=[],
      max_batch_operations=2,
      max_affected_resources=2,
    ),
  )
  assert_decision(
    result,
    @orbitops_plane.PolicyDecision::RequireApproval,
    @orbitops_plane.RiskLevel::High,
    @orbitops_plane.PolicyReasonCode::DeleteProtection,
  )
}

///|
test "critical resources require approval" {
  let database = try! policy_resource(kind="database", name="primary")
  let result = try! @orbitops_plane.evaluate_operation_safety(
    try! policy_operation(database, @orbitops_plane.ActionKind::Update),
    try! policy(
      critical_resources=[database],
      max_batch_operations=2,
      max_affected_resources=2,
    ),
  )
  assert_decision(
    result,
    @orbitops_plane.PolicyDecision::RequireApproval,
    @orbitops_plane.RiskLevel::Medium,
    @orbitops_plane.PolicyReasonCode::CriticalResource,
  )
}

///|
test "batch restarts require approval" {
  let api = try! policy_resource(kind="service", name="api")
  let worker = try! policy_resource(kind="service", name="worker")
  let batch : @orbitops_plane.ChangeBatch = {
    operations: [
      try! policy_operation(api, @orbitops_plane.ActionKind::Restart),
      try! policy_operation(worker, @orbitops_plane.ActionKind::Restart),
    ],
  }
  let result = try! @orbitops_plane.evaluate_safety_policy(
    batch,
    try! policy(
      critical_resources=[],
      max_batch_operations=2,
      max_affected_resources=2,
    ),
  )
  assert_decision(
    result,
    @orbitops_plane.PolicyDecision::RequireApproval,
    @orbitops_plane.RiskLevel::High,
    @orbitops_plane.PolicyReasonCode::BatchRestart,
  )
}

///|
test "unknown actions fail closed" {
  let resource = try! policy_resource(kind="service", name="api")
  let result = try! @orbitops_plane.evaluate_operation_safety(
    try! policy_operation(resource, @orbitops_plane.ActionKind::Unknown),
    try! policy(
      critical_resources=[],
      max_batch_operations=2,
      max_affected_resources=2,
    ),
  )
  assert_decision(
    result,
    @orbitops_plane.PolicyDecision::Deny,
    @orbitops_plane.RiskLevel::Unknown,
    @orbitops_plane.PolicyReasonCode::UnknownAction,
  )
}

///|
test "budget conflict is denied before approval rules" {
  let api = try! policy_resource(kind="service", name="api")
  let worker = try! policy_resource(kind="service", name="worker")
  let batch : @orbitops_plane.ChangeBatch = {
    operations: [
      try! policy_operation(api, @orbitops_plane.ActionKind::Delete),
      try! policy_operation(worker, @orbitops_plane.ActionKind::Update),
    ],
  }
  let result = try! @orbitops_plane.evaluate_safety_policy(
    batch,
    try! policy(
      critical_resources=[],
      max_batch_operations=1,
      max_affected_resources=2,
    ),
  )
  assert_decision(
    result,
    @orbitops_plane.PolicyDecision::Deny,
    @orbitops_plane.RiskLevel::High,
    @orbitops_plane.PolicyReasonCode::BudgetConflict,
  )
}

///|
test "invalid safety policy budgets are rejected" {
  try
    @orbitops_plane.SafetyPolicy::new(
      critical_resources=[],
      max_batch_operations=0,
      max_affected_resources=1,
    )
  catch {
    @orbitops_plane.ModelError::InvalidBudget(message) =>
      inspect(message, content="max_batch_operations must be positive")
    _ => fail("wrong safety policy error")
  } noraise {
    _ => fail("expected an invalid safety policy budget")
  }
}
