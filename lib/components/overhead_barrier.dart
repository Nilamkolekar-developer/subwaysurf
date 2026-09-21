import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/flame.dart';
import 'package:flutter/material.dart';

import 'world_entity.dart';

/// A hazard-striped beam on two posts, hanging at head height. Clear it by
/// sliding under; anything else calls [onHitPlayer].
class OverheadBarrier extends WorldEntity {
  /// Sprite height / width (assets/images/barrier_overhead.png is 256x200).
  static const double aspect = 200 / 256;

  final VoidCallback onHitPlayer;
  ui.Image? _img;

  OverheadBarrier({
    required super.persp,
    required super.player,
    required super.speedProvider,
    required super.lane,
    required super.z,
    required this.onHitPlayer,
  }) : super(length: 0.20);

  /// Size in px at depth 1.
  double get spriteW => persp.laneSpacing * 0.94;
  double get spriteH => spriteW * aspect;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _img = await Flame.images.load('barrier_overhead.png');
  }

  @override
  void onOverlap({required bool justStarted}) {
    if (player.isRiding || player.isInvulnerable) return;
    if (!player.isSliding) onHitPlayer();
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
      Rect.fromCenter(center: Offset(cx, bottom), width: w * 0.95, height: w * 0.14),
      Paint()..color = tint(0x000000, 0.22),
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
