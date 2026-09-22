///|
fn main {
  let args = @env.args()
  let rollout_requested = args.length() > 0 &&
    args[args.length() - 1] == "rollout"
  if args.length() <= 1 || rollout_requested {
    run_rollout()
  } else {
    println("Usage: moon run cmd/demo -- rollout")
  }
}
