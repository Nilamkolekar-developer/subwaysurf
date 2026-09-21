import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'world_entity.dart';

/// A spinning gold coin. [height] is how far above the ground it floats
/// (px at depth 1): 0 for a ground coin, ~90 for a coin over a barrier that
/// you collect at the top of a jump.
class CoinPickup extends WorldEntity {
  final double height;
  final VoidCallback onCollected;
  double _spin = 0;

  CoinPickup({
    required super.persp,
    required super.player,
    required super.speedProvider,
    required super.lane,
    required super.z,
    required this.onCollected,
    this.height = 0,
  });

  /// Coin radius in px at depth 1.
  double get radius1 => persp.laneSpacing * 0.13;

  @override
  double get depthMargin => 0.14;

  @override
  void update(double dt) {
    _spin += dt * 7;
    super.update(dt);
  }

  /// While flying, the magnet covers all three lanes.
  @override
  bool get overlapsPlayer {
    if (player.isFlying || player.hasMagnet) return z <= 1.14 && z >= 0.6;
    return super.overlapsPlayer;
  }

  @override
  void onOverlap({required bool justStarted}) {
    if (player.isFlying || player.hasMagnet) {
      onCollected();
      removeFromParent();
      return;
    }
    // Collect only if the coin is within the runner's body height, so a
    // ground coin is missed while you're at the top of a jump.
    final center = height + radius1;
    final ph = player.heightAboveGround;
    if (center > ph - 12 && center < ph + player.size.y + 12) {
      onCollected();
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final zz = math.max(z, 0.4);
    final r = radius1 / zz;
    var cx = persp.xAt(laneNearX, zz);
    final ground = persp.groundY(zz);
    var cy = ground - (height + radius1) / zz;
    if (player.isFlying || player.hasMagnet) {
      // magnet: coins stream toward Jack as they get close
      final t = ((3.0 - z) / 2.0).clamp(0.0, 1.0).toDouble();
      cx += (player.position.x + player.size.x / 2 - cx) * t;
      cy += (player.position.y + player.size.y / 2 - cy) * t;
    }
    final squash = math.cos(_spin).abs() * 0.8 + 0.2;

    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, ground), width: r * 1.6, height: r * 0.4),
      Paint()..color = tint(0x000000, 0.2),
    );

    final outer = Rect.fromCenter(center: Offset(cx, cy), width: r * 2 * squash, height: r * 2);
    final inner = Rect.fromCenter(
      center: Offset(cx, cy),
      width: math.max(1.0, r * 2 * squash - r * 0.30),
      height: r * 2 - r * 0.30,
    );
    canvas.drawOval(outer, Paint()..color = tint(0xB07A00));
    canvas.drawOval(inner, Paint()..color = tint(0xFFC928));
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx - r * 0.25 * squash, cy - r * 0.30),
        width: r * 0.5 * squash,
        height: r * 0.5,
      ),
      Paint()..color = tint(0xFFF3B0, 0.9),
    );
  }
}