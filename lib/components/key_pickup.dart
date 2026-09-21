import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'world_entity.dart';

/// A glowing blue key (used to revive after a crash). Floats and bobs.
class KeyPickup extends WorldEntity {
  final VoidCallback onCollected;
  double _t = 0;

  KeyPickup({
    required super.persp,
    required super.player,
    required super.speedProvider,
    required super.lane,
    required super.z,
    required this.onCollected,
  });

  /// Key radius in px at depth 1.
  double get radius1 => persp.laneSpacing * 0.16;

  /// Floats a little above the ground so it's easy to see and grab.
  static const double _floatHeight = 14;

  @override
  double get depthMargin => 0.14;

  @override
  void update(double dt) {
    _t += dt;
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
    final center = _floatHeight + radius1;
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
    final bob = math.sin(_t * 4) * r * 0.18;
    var cy = ground - (_floatHeight + radius1) / zz + bob;
    if (player.isFlying || player.hasMagnet) {
      final t = ((3.0 - z) / 2.0).clamp(0.0, 1.0).toDouble();
      cx += (player.position.x + player.size.x / 2 - cx) * t;
      cy += (player.position.y + player.size.y / 2 - cy) * t;
    }

    // soft glow + ground shadow
    canvas.drawCircle(Offset(cx, cy), r * 1.5, Paint()..color = tint(0x4FC3F7, 0.25));
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, ground), width: r * 1.5, height: r * 0.4),
      Paint()..color = tint(0x000000, 0.2),
    );

    final diamond = Path()
      ..moveTo(cx, cy - r)
      ..lineTo(cx + r * 0.85, cy)
      ..lineTo(cx, cy + r)
      ..lineTo(cx - r * 0.85, cy)
      ..close();
    canvas.drawPath(diamond, Paint()..color = tint(0x2E9BD6));
    canvas.drawPath(
      diamond,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.12)
        ..color = tint(0xFFFFFF),
    );

    // little key glyph: ring + shaft + teeth
    final white = Paint()..color = tint(0xFFFFFF);
    canvas.drawCircle(Offset(cx, cy - r * 0.30), r * 0.22, white);
    canvas.drawRect(Rect.fromLTWH(cx - r * 0.06, cy - r * 0.30, r * 0.12, r * 0.75), white);
    canvas.drawRect(Rect.fromLTWH(cx, cy + r * 0.20, r * 0.22, r * 0.10), white);
    canvas.drawRect(Rect.fromLTWH(cx, cy + r * 0.38, r * 0.16, r * 0.10), white);
  }
}