import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'world_entity.dart';

/// A floating red horseshoe magnet. Grabbing it pulls in every coin and key
/// in any lane for a few seconds — no flying, just the pull.
class MagnetPickup extends WorldEntity {
  final VoidCallback onCollected;
  double _t = 0;

  MagnetPickup({
    required super.persp,
    required super.player,
    required super.speedProvider,
    required super.lane,
    required super.z,
    required this.onCollected,
  });

  double get radius1 => persp.laneSpacing * 0.19;
  static const double _floatHeight = 16;

  @override
  double get depthMargin => 0.14;

  @override
  void update(double dt) {
    _t += dt;
    super.update(dt);
  }

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
    final bob = math.sin(_t * 4) * r * 0.15;
    var cy = ground - (_floatHeight + radius1) / zz + bob;
    if (player.isFlying || player.hasMagnet) {
      final t = ((3.0 - z) / 2.0).clamp(0.0, 1.0).toDouble();
      cx += (player.position.x + player.size.x / 2 - cx) * t;
      cy += (player.position.y + player.size.y / 2 - cy) * t;
    }

    canvas.drawCircle(Offset(cx, cy), r * 1.55, Paint()..color = tint(0xE53935, 0.24));
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, ground), width: r * 1.5, height: r * 0.38),
      Paint()..color = tint(0x000000, 0.2),
    );

    // horseshoe: an arc with two straight legs and white/red banded tips
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.44
      ..strokeCap = StrokeCap.butt
      ..color = tint(0xD32F2F);
    final arcRect = Rect.fromCenter(center: Offset(cx, cy - r * 0.05), width: r * 1.3, height: r * 1.3);
    canvas.drawArc(arcRect, math.pi * 0.05, math.pi * 0.9, false, outline);

    final tipPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.44
      ..strokeCap = StrokeCap.butt
      ..color = tint(0xEEEEEE);
    // short white bands at the very ends (tips) of the horseshoe
    canvas.drawArc(arcRect, math.pi * 0.05, math.pi * 0.14, false, tipPaint);
    canvas.drawArc(arcRect, math.pi * 0.81, math.pi * 0.14, false, tipPaint);

    canvas.drawArc(
      arcRect,
      math.pi * 0.05,
      math.pi * 0.9,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.06)
        ..color = tint(0x1C1E2A),
    );
  }
}