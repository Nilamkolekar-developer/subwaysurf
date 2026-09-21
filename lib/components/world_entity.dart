import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../game/perspective.dart';
import 'runner_player.dart';

/// Base class for everything that travels down the track toward the camera
/// (trains, barriers, coins, keys).
///
/// Instead of a screen position + Flame hitbox, an entity has a [lane] and a
/// depth [z]. It draws itself in screen space using [persp], and decides
/// whether it touches the runner by comparing lane + depth. That keeps
/// collisions fair no matter how big or small the thing looks on screen.
///
/// Draw order is farther-first: [priority] follows depth automatically, and
/// the game gives the runner priority -1000 (depth 1.0), so anything farther
/// draws behind the runner and anything nearer draws in front.
abstract class WorldEntity extends Component {
  final Perspective persp;
  final RunnerPlayer player;

  /// World speed in depth-units per second (shared by the whole game, so
  /// everything speeds up together and nothing overtakes anything else).
  final double Function() speedProvider;

  final int lane;

  /// Depth of the FRONT (nearest) edge.
  double z;

  /// How far the entity extends behind its front edge, in depth units.
  final double length;

  /// A frozen entity doesn't move (used for the train you're riding).
  bool frozen = false;

  bool _inContact = false;
  double _age = 0; // seconds since it appeared (for the quick fade-in)

  /// If set, this entity is drawn immediately after [drawAfter] instead of by
  /// its own depth. Used for coins lying on a train's roof: they sit BEHIND the
  /// train's front edge, so by depth alone the roof would paint over them.
  WorldEntity? drawAfter;

  WorldEntity({
    required this.persp,
    required this.player,
    required this.speedProvider,
    required this.lane,
    required this.z,
    this.length = 0.0,
  }) {
    priority = _depthPriority;
  }

  int get _depthPriority {
    final anchor = drawAfter;
    return anchor != null ? (-anchor.z * 1000).round() + 1 : (-z * 1000).round();
  }

  double get frontZ => z;
  double get backZ => z + length;

  /// Extra depth tolerance around the runner's depth when testing contact.
  double get depthMargin => 0.10;

  /// How far (px, at z = 1) the runner's centre may be from the lane centre
  /// and still count as "in this lane".
  double get laneTolerance => persp.laneSpacing * 0.36;

  /// 0 at spawn -> 1 a few units later, so things fade in out of the haze
  /// instead of popping.
  double get fade =>
      ((Perspective.zFar - z) / 4.0).clamp(0.0, 1.0).toDouble() *
      (_age / 0.4).clamp(0.0, 1.0).toDouble();

  /// Lane centre x at z = 1.
  double get laneNearX => persp.laneNearX[lane];

  bool get overlapsPlayer {
    final playerX = player.position.x + player.size.x / 2;
    if ((playerX - laneNearX).abs() > laneTolerance) return false;
    return frontZ <= Perspective.zPlayer + depthMargin &&
        backZ >= Perspective.zPlayer - depthMargin;
  }

  /// Called every frame the runner overlaps this entity. [justStarted] is
  /// true only on the first frame of that overlap.
  void onOverlap({required bool justStarted});

  @override
  void update(double dt) {
    super.update(dt);
    _age += dt;
    if (player.isGameOver) return;

    if (!frozen) z -= speedProvider() * dt;
    priority = _depthPriority;

    if (backZ < Perspective.zKill) {
      removeFromParent();
      return;
    }

    final overlapping = overlapsPlayer;
    if (overlapping) onOverlap(justStarted: !_inContact);
    _inContact = overlapping;
  }

  /// Colour from a 0xRRGGBB int, faded by [fade].
  Color tint(int rgb, [double opacity = 1.0]) {
    final a = (opacity * fade).clamp(0.0, 1.0).toDouble();
    return Color(0xFF000000 | rgb).withOpacity(a);
  }
}
