import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'world_entity.dart';

/// A rocket floating in the lane. Grab it and Jack takes off on autopilot:
/// he flies above everything, can't be hurt, and collects every coin.
class RocketPickup extends WorldEntity {
  final VoidCallback onCollected;
  double _t = 0;

  RocketPickup({
    required super.persp,
    required super.player,
    required super.speedProvider,
    required super.lane,
    required super.z,
    required this.onCollected,
  });

  /// Pickup size in px at depth 1.
  double get radius1 => persp.laneSpacing * 0.22;

  /// Floats a little above the ground so it's easy to see and grab.
  static const double _floatHeight = 16;

  @override
  double get depthMargin => 0.14;

  @override
  void update(double dt) {
    _t += dt;
    super.update(dt);
  }

  @override
  void onOverlap({required bool justStarted}) {
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
    final cx = persp.xAt(laneNearX, zz);
    final ground = persp.groundY(zz);
    final bob = math.sin(_t * 4) * r * 0.14;
    final cy = ground - (_floatHeight + radius1) / zz + bob;

    // orange glow + ground shadow
    canvas.drawCircle(Offset(cx, cy), r * 1.5, Paint()..color = tint(0xFF9800, 0.28));
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, ground), width: r * 1.3, height: r * 0.35),
      Paint()..color = tint(0x000000, 0.2),
    );

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, r * 0.06)
      ..color = tint(0x1C1E2A);

    // flame under the rocket
    final flick = 0.75 + 0.25 * math.sin(_t * 30);
    final flameLen = r * 0.75 * flick;
    final base = cy + r * 0.50;
    canvas.drawPath(
      Path()
        ..moveTo(cx - r * 0.20, base)
        ..lineTo(cx + r * 0.20, base)
        ..lineTo(cx, base + flameLen)
        ..close(),
      Paint()..color = tint(0xFF9800),
    );
    canvas.drawPath(
      Path()
        ..moveTo(cx - r * 0.10, base)
        ..lineTo(cx + r * 0.10, base)
        ..lineTo(cx, base + flameLen * 0.6)
        ..close(),
      Paint()..color = tint(0xFFEB3B),
    );

    // fins
    for (final side in const [-1.0, 1.0]) {
      final fin = Path()
        ..moveTo(cx + side * r * 0.28, cy + r * 0.05)
        ..lineTo(cx + side * r * 0.64, cy + r * 0.62)
        ..lineTo(cx + side * r * 0.28, cy + r * 0.50)
        ..close();
      canvas.drawPath(fin, Paint()..color = tint(0xE53935));
      canvas.drawPath(fin, outline);
    }

    // body + nose cone
    final body = RRect.fromRectAndRadius(
      Rect.fromLTRB(cx - r * 0.28, cy - r * 0.70, cx + r * 0.28, cy + r * 0.50),
      Radius.circular(r * 0.12),
    );
    canvas.drawRRect(body, Paint()..color = tint(0xF5F5F5));
    final nose = Path()
      ..moveTo(cx - r * 0.28, cy - r * 0.70)
      ..lineTo(cx + r * 0.28, cy - r * 0.70)
      ..lineTo(cx, cy - r * 1.20)
      ..close();
    canvas.drawPath(nose, Paint()..color = tint(0xE53935));
    canvas.drawRRect(body, outline);
    canvas.drawPath(nose, outline);

    // window
    canvas.drawCircle(Offset(cx, cy - r * 0.22), r * 0.15, Paint()..color = tint(0x29B6F6));
    canvas.drawCircle(Offset(cx, cy - r * 0.22), r * 0.15, outline);
  }
}
