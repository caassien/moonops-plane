///|
fn main {
  let args = @env.args()
  let command = if args.length() == 0 { "" } else { args[args.length() - 1] }
  if command == "drift" {
    run_drift()
  } else if command == "incident" {
    run_incident()
  } else if args.length() <= 1 || command == "rollout" {
    run_rollout()
  } else {
    println("Usage: moon run cmd/demo -- <rollout|drift|incident>")
  }
}
