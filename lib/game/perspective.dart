/// One-point perspective, the way Subway Surfers looks: every lane runs to a
/// single vanishing point on the horizon, and things get smaller/higher on
/// screen the farther away they are.
///
/// Depth is a distance `z` from the camera:
///   z = 1        -> exactly where the runner stands (scale 1.0)
///   z > 1        -> farther away, smaller, closer to the horizon
///   z < 1        -> already past the runner, bigger, sliding off the bottom
///
/// Everything is driven by one formula: scale = 1 / z.
class Perspective {
  /// Screen size the game is laid out for.
  final double width;
  final double height;

  /// Screen y of the horizon (where z -> infinity).
  final double horizonY;

  /// Screen y of the ground directly under the runner's feet (z = 1).
  final double footY;

  /// Screen x where all lanes converge.
  final double vanishX;

  /// Lane centre x at z = 1 (the same numbers the runner uses).
  final List<double> laneNearX;

  /// Where new things appear (small, hazy, near the horizon).
  static const double zFar = 14.0;

  /// The runner's depth.
  static const double zPlayer = 1.0;

  /// Things whose back edge is closer than this are off-screen and removed.
  static const double zKill = 0.6;

  Perspective({
    required this.width,
    required this.height,
    required this.horizonY,
    required this.footY,
    required this.laneNearX,
  }) : vanishX = width / 2;

  /// Distance between neighbouring lane centres at z = 1.
  double get laneSpacing => laneNearX[1] - laneNearX[0];

  /// Screen y of the ground at depth [z].
  double groundY(double z) => horizonY + (footY - horizonY) / z;

  /// Screen x of a point whose x at z = 1 is [nearX], seen at depth [z].
  double xAt(double nearX, double z) => vanishX + (nearX - vanishX) / z;

  /// Screen x of lane [lane]'s centre at depth [z].
  double laneX(int lane, double z) => xAt(laneNearX[lane], z);

  /// Screen x of the line that starts at ([nearX] @ z = 1) when it crosses
  /// screen row [y]. Used to draw rails/edges that run to the vanishing point.
  double xAtRow(double nearX, double y) =>
      vanishX + (nearX - vanishX) * (y - horizonY) / (footY - horizonY);
}
