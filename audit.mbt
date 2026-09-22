///|
/// Broad category for a replayable audit event.
pub(all) enum AuditEventKind {
  PlanCreated
  PolicyDecision
  Approval
  StateTransition
  ExecutionFeedback
  Terminal
} derive(Debug, Eq)

///|
/// Stable reason code carried by an audit event.
pub(all) enum AuditReasonCode {
  PlanCreated
  Ready
  Executing
  Policy(PolicyReasonCode)
  ApprovalRequested
  ApprovalGranted
  ApprovalRejected
  FeedbackSucceeded
  FeedbackFailed
  FeedbackSkipped
  ReconciliationSucceeded
  ReconciliationFailed
  ReconciliationTerminated
} derive(Debug, Eq)

///|
/// Operation identity recorded without its free-form explanation.
pub(all) struct AuditOperation {
  resource : ResourceId
  action : ActionKind
} derive(Debug, Eq)

///|
/// A deterministic, secret-free record of one lifecycle decision.
pub(all) struct AuditEvent {
  sequence : Int
  plan_id : PlanId
  kind : AuditEventKind
  reason_code : AuditReasonCode
  state : ReconciliationState
  batch_index : Int?
  operation : AuditOperation?
  policy_decision : PolicyDecision?
  risk : RiskLevel?
  explanation : String?
  execution_state : ExecutionState?
} derive(Debug, Eq)

///|
/// Constructs one validated audit event.
pub fn AuditEvent::new(
  sequence~ : Int,
  plan_id~ : PlanId,
  kind~ : AuditEventKind,
  reason_code~ : AuditReasonCode,
  state~ : ReconciliationState,
  batch_index~ : Int?,
  operation~ : AuditOperation?,
  policy_decision~ : PolicyDecision?,
  risk~ : RiskLevel?,
  explanation~ : String?,
  execution_state~ : ExecutionState?,
) -> AuditEvent raise ModelError {
  if sequence <= 0 {
    raise ModelError::InvalidAudit("audit sequence must be positive")
  }
  {
    sequence,
    plan_id,
    kind,
    reason_code,
    state,
    batch_index,
    operation,
    policy_decision,
    risk,
    explanation,
    execution_state,
  }
}

///|
fn audit_operation(operation : Operation) -> AuditOperation {
  { resource: operation.resource, action: operation.action, }
}

///|
fn audit_append(
  events : Array[AuditEvent],
  plan_id~ : PlanId,
  kind~ : AuditEventKind,
  reason_code~ : AuditReasonCode,
  state~ : ReconciliationState,
  batch_index~ : Int?,
  operation~ : AuditOperation?,
  policy_decision~ : PolicyDecision?,
  risk~ : RiskLevel?,
  explanation~ : String?,
  execution_state~ : ExecutionState?,
) -> Unit raise ModelError {
  events.push(
    AuditEvent::new(
      sequence=events.length() + 1,
      plan_id~,
      kind~,
      reason_code~,
      state~,
      batch_index~,
      operation~,
      policy_decision~,
      risk~,
      explanation~,
      execution_state~,
    ),
  )
}

///|
fn audit_operation_matches(
  recorded : AuditOperation,
  expected : Operation,
) -> Bool {
  recorded.resource == expected.resource && recorded.action == expected.action
}

///|
/// Rebuilds controller state from a validated audit stream.
pub fn replay_audit_events(
  plan : BatchedPlan,
  events : Array[AuditEvent],
) -> Reconciliation raise ModelError {
  if events.length() == 0 {
    raise ModelError::InvalidAudit("audit stream is empty")
  }
  let decisions : Array[PolicyEvaluation] = []
  let results : Array[ExecutionResult] = []
  let mut replay_plan = plan
  let mut state = ReconciliationState::Planning
  let mut next_operation = 0
  let mut seen_plan_created = false
  for index, event in events {
    if event.sequence != index + 1 {
      raise ModelError::InvalidAudit(
        "audit sequence is not contiguous at \{event.sequence}",
      )
    }
    if event.plan_id != plan.plan.id {
      raise ModelError::PlanMismatch(
        "audit plan \{event.plan_id.value} does not match active plan \{plan.plan.id.value}",
      )
    }
    match event.kind {
      AuditEventKind::PlanCreated => {
        if index != 0 ||
          seen_plan_created ||
          event.reason_code != AuditReasonCode::PlanCreated {
          raise ModelError::InvalidAudit("invalid plan-created audit event")
        }
        seen_plan_created = true
        state = event.state
      }
      AuditEventKind::PolicyDecision => {
        let decision = match event.policy_decision {
          Some(value) => value
          None => raise ModelError::InvalidAudit("policy event lacks decision")
        }
        let risk = match event.risk {
          Some(value) => value
          None => raise ModelError::InvalidAudit("policy event lacks risk")
        }
        let reason_code = match event.reason_code {
          AuditReasonCode::Policy(value) => value
          _ => raise ModelError::InvalidAudit("policy event lacks reason code")
        }
        let explanation = match event.explanation {
          Some(value) => value
          None =>
            raise ModelError::InvalidAudit("policy event lacks explanation")
        }
        match event.batch_index {
          Some(value) =>
            if value < 0 {
              raise ModelError::InvalidAudit("policy batch index is negative")
            }
          None =>
            raise ModelError::InvalidAudit("policy event lacks batch index")
        }
        decisions.push({ decision, risk, reason_code, explanation, })
        replay_plan = match decision {
          PolicyDecision::Allow =>
            controller_with_approval(replay_plan, ApprovalState::NotRequired)
          PolicyDecision::RequireApproval =>
            controller_with_approval(replay_plan, ApprovalState::Pending)
          PolicyDecision::Deny =>
            controller_with_approval(replay_plan, ApprovalState::Rejected)
        }
        state = event.state
      }
      AuditEventKind::Approval => {
        replay_plan = match event.reason_code {
          AuditReasonCode::ApprovalRequested =>
            controller_with_approval(replay_plan, ApprovalState::Pending)
          AuditReasonCode::ApprovalGranted =>
            controller_with_approval(replay_plan, ApprovalState::Approved)
          AuditReasonCode::ApprovalRejected =>
            controller_with_approval(replay_plan, ApprovalState::Rejected)
          _ => raise ModelError::InvalidAudit("invalid approval reason code")
        }
        state = event.state
      }
      AuditEventKind::StateTransition => state = event.state
      AuditEventKind::ExecutionFeedback => {
        let recorded = match event.operation {
          Some(value) => value
          None =>
            raise ModelError::InvalidAudit("feedback event lacks operation")
        }
        let execution_state = match event.execution_state {
          Some(value) => value
          None =>
            raise ModelError::InvalidAudit(
              "feedback event lacks execution state",
            )
        }
        let expected = match controller_operation_at(plan, next_operation) {
          Some(value) => value
          None =>
            raise ModelError::InvalidAudit(
              "feedback event exceeds planned operations",
            )
        }
        if !audit_operation_matches(recorded, expected) {
          raise ModelError::InvalidAudit(
            "feedback event does not match planned operation",
          )
        }
        results.push(
          ExecutionResult::new(
            plan_id=plan.plan.id,
            operation=expected,
            state=execution_state,
            message="replayed audit feedback",
          ),
        )
        if execution_state == ExecutionState::Succeeded {
          next_operation += 1
        }
        state = event.state
      }
      AuditEventKind::Terminal => {
        if event.reason_code == AuditReasonCode::ReconciliationTerminated {
          replay_plan = controller_with_approval(
            replay_plan,
            ApprovalState::Rejected,
          )
        }
        state = event.state
      }
    }
  }
  if !seen_plan_created {
    raise ModelError::InvalidAudit("audit stream lacks plan creation")
  }
  {
    plan: replay_plan,
    state,
    observed_generation: plan.plan.baseline_generation,
    decisions,
    next_operation,
    results,
    audit_events: events,
  }
}
