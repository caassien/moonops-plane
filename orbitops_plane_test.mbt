///|
test "package exposes its version" {
  inspect(@orbitops_plane.version(), content="0.1.0")
}
