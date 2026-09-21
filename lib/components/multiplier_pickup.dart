import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'world_entity.dart';

/// A spinning gold "x2" star. Grabbing it doubles the coin value of
/// everything collected for the next few seconds.
class MultiplierPickup extends WorldEntity {
  final VoidCallback onCollected;
  double _t = 0;

  MultiplierPickup({
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

    final spin = _t * 2.2;
    canvas.drawCircle(Offset(cx, cy), r * 1.6, Paint()..color = tint(0xFFD700, 0.26));
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, ground), width: r * 1.5, height: r * 0.38),
      Paint()..color = tint(0x000000, 0.2),
    );

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(spin);
    final star = Path();
    for (var i = 0; i < 5; i++) {
      final outerA = -math.pi / 2 + i * 2 * math.pi / 5;
      final innerA = outerA + math.pi / 5;
      final ox = math.cos(outerA) * r, oy = math.sin(outerA) * r;
      final ix = math.cos(innerA) * r * 0.45, iy = math.sin(innerA) * r * 0.45;
      if (i == 0) {
        star.moveTo(ox, oy);
      } else {
        star.lineTo(ox, oy);
      }
      star.lineTo(ix, iy);
    }
    star.close();
    canvas.drawPath(star, Paint()..color = tint(0xFFC928));
    canvas.drawPath(
      star,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.10)
        ..color = tint(0xFFFFFF),
    );
    canvas.restore();

    // "x2" label
    final tp = TextPainter(
      text: TextSpan(
        text: 'x2',
        style: TextStyle(color: tint(0x5A3D00), fontSize: r * 0.85, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }
}