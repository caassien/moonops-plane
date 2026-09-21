///|
/// Result of comparing one desired state with its observation.
pub(all) enum DiffResult {
  NoChange
  Action(Operation)
} derive(Debug, Eq)

///|
/// Compares desired and observed state and returns one deterministic action.
///
/// A missing enabled resource is created. A disabled desired state deletes an
/// enabled observation. Version and configuration changes take precedence over
/// scaling, while an otherwise matching unhealthy resource is restarted.
pub fn compute_diff(
  desired : DesiredState,
  observed : ObservedState?,
) -> DiffResult raise ModelError {
  match observed {
    None =>
      if desired.spec.enabled {
        Action(
          Operation::new(
            resource=desired.resource,
            action=ActionKind::Create,
            reason="resource is missing",
          ),
        )
      } else {
        NoChange
      }
    Some(current) => {
      if desired.resource != current.resource {
        raise ModelError::ResourceMismatch
      }
      let spec_changed = desired.spec.version != current.spec.version ||
        desired.spec.config_fingerprint != current.spec.config_fingerprint
      if !desired.spec.enabled && current.spec.enabled {
        Action(
          Operation::new(
            resource=desired.resource,
            action=ActionKind::Delete,
            reason="resource is disabled",
          ),
        )
      } else if desired.spec.enabled && !current.spec.enabled {
        Action(
          Operation::new(
            resource=desired.resource,
            action=ActionKind::Update,
            reason="resource should be enabled",
          ),
        )
      } else if spec_changed {
        Action(
          Operation::new(
            resource=desired.resource,
            action=ActionKind::Update,
            reason="version or configuration differs",
          ),
        )
      } else if desired.spec.replicas != current.spec.replicas {
        Action(
          Operation::new(
            resource=desired.resource,
            action=ActionKind::Scale,
            reason="replica count differs",
          ),
        )
      } else if desired.spec.enabled && !current.healthy {
        Action(
          Operation::new(
            resource=desired.resource,
            action=ActionKind::Restart,
            reason="resource is unhealthy",
          ),
        )
      } else {
        NoChange
      }
    }
  }
}
