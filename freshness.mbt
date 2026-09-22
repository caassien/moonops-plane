///|
/// Confirms that a plan was built from the currently observed generation.
pub fn validate_plan_freshness(
  plan : Plan,
  observed_generation~ : Int,
) -> Unit raise ModelError {
  if observed_generation <= 0 {
    raise ModelError::NonPositiveGeneration
  }
  if observed_generation < plan.baseline_generation {
    raise ModelError::StaleObservation(
      "observed generation \{observed_generation} is older than plan baseline \{plan.baseline_generation}",
    )
  }
  if observed_generation > plan.baseline_generation {
    raise ModelError::StalePlan(
      "plan baseline \{plan.baseline_generation} is older than observed generation \{observed_generation}",
    )
  }
}

///|
/// Confirms that executor feedback belongs to the active plan.
pub fn validate_feedback_plan(
  plan : Plan,
  result : ExecutionResult,
) -> Unit raise ModelError {
  if plan.id != result.plan_id {
    raise ModelError::PlanMismatch(
      "feedback plan \{result.plan_id.value} does not match active plan \{plan.id.value}",
    )
  }
}
