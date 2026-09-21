import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/flame.dart';
import 'package:flutter/material.dart';

import 'world_entity.dart';

/// A short striped barrier on the track. Clear it by jumping: the runner must
/// be high enough off the ground when it arrives, otherwise [onHitPlayer].
class LowBarrier extends WorldEntity {
  /// Sprite height / width (assets/images/barrier_low.png is 256x130).
  static const double aspect = 130 / 256;

  final VoidCallback onHitPlayer;
  ui.Image? _img;

  LowBarrier({
    required super.persp,
    required super.player,
    required super.speedProvider,
    required super.lane,
    required super.z,
    required this.onHitPlayer,
  }) : super(length: 0.22);

  /// Size in px at depth 1.
  double get spriteW => persp.laneSpacing * 0.86;
  double get spriteH => spriteW * aspect;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _img = await Flame.images.load('barrier_low.png');
  }

  @override
  void onOverlap({required bool justStarted}) {
    if (player.isRiding || player.isInvulnerable) return;
    // Physically clear once the runner's feet are above ~60% of the barrier.
    if (player.heightAboveGround < spriteH * 0.6) onHitPlayer();
  }

  @override
  void render(Canvas canvas) {
    final img = _img;
    if (img == null) return;
    final zz = math.max(z, 0.4);
    final cx = persp.xAt(laneNearX, zz);
    final w = spriteW / zz;
    final h = spriteH / zz;
    final bottom = persp.groundY(zz);

    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, bottom), width: w * 1.05, height: w * 0.16),
      Paint()..color = tint(0x000000, 0.25),
    );
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(cx - w / 2, bottom - h, w, h),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(255, 255, 255, fade),
    );
  }
}
