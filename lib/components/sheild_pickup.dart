import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'world_entity.dart';

/// A floating blue shield. Grabbing it banks one shield — it sits there
/// until the next hit, which it absorbs instead of ending the run.
class ShieldPickup extends WorldEntity {
  final VoidCallback onCollected;
  double _t = 0;

  ShieldPickup({
    required super.persp,
    required super.player,
    required super.speedProvider,
    required super.lane,
    required super.z,
    required this.onCollected,
  });

  double get radius1 => persp.laneSpacing * 0.17;
  static const double _floatHeight = 14;

  @override
  double get depthMargin => 0.14;

  @override
  void update(double dt) {
    _t += dt;
    super.update(dt);
  }

  /// While flying or magnet-boosted, it's swept in like a coin.
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
    final bob = math.sin(_t * 4) * r * 0.16;
    var cy = ground - (_floatHeight + radius1) / zz + bob;
    if (player.isFlying || player.hasMagnet) {
      final t = ((3.0 - z) / 2.0).clamp(0.0, 1.0).toDouble();
      cx += (player.position.x + player.size.x / 2 - cx) * t;
      cy += (player.position.y + player.size.y / 2 - cy) * t;
    }

    canvas.drawCircle(Offset(cx, cy), r * 1.5, Paint()..color = tint(0x29B6F6, 0.28));
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, ground), width: r * 1.4, height: r * 0.36),
      Paint()..color = tint(0x000000, 0.2),
    );

    // shield outline: rounded top, pointed bottom
    final shield = Path()
      ..moveTo(cx, cy - r)
      ..cubicTo(cx + r * 0.95, cy - r * 0.85, cx + r * 0.85, cy - r * 0.1, cx + r * 0.85, cy + r * 0.1)
      ..cubicTo(cx + r * 0.75, cy + r * 0.75, cx + r * 0.3, cy + r * 1.05, cx, cy + r * 1.15)
      ..cubicTo(cx - r * 0.3, cy + r * 1.05, cx - r * 0.75, cy + r * 0.75, cx - r * 0.85, cy + r * 0.1)
      ..cubicTo(cx - r * 0.85, cy - r * 0.1, cx - r * 0.95, cy - r * 0.85, cx, cy - r)
      ..close();
    canvas.drawPath(shield, Paint()..color = tint(0x1E88E5));
    canvas.drawPath(
      shield,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.12)
        ..color = tint(0xFFFFFF),
    );

    // checkmark glyph
    final glyph = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, r * 0.16)
      ..strokeCap = StrokeCap.round
      ..color = tint(0xFFFFFF);
    canvas.drawPath(
      Path()
        ..moveTo(cx - r * 0.32, cy)
        ..lineTo(cx - r * 0.06, cy + r * 0.3)
        ..lineTo(cx + r * 0.38, cy - r * 0.35),
      glyph,
    );
  }
}