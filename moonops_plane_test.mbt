///|
test "package exposes its version" {
  inspect(@moonops_plane.version(), content="0.1.0")
}
