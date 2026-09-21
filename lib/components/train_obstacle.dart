import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/flame.dart';
import 'package:flutter/material.dart';

import 'world_entity.dart';

/// A full-lane train coming straight at the camera, drawn Subway Surfers
/// style: the front face is a sprite (assets/images/train_front_<colour>.png),
/// and the roof and the side wall are drawn in perspective behind it, so a
/// long train really looks long and its side windows stream past.
///
/// Ways to survive (unchanged):
///  - dodge to another lane, or
///  - jump as it arrives to hop onto the roof ([onHopOn]).
/// Touching it any other way calls [onHitPlayer].
class TrainObstacle extends WorldEntity {
  static const List<String> colors = ['yellow', 'red', 'blue', 'green', 'orange'];
  static const Map<String, int> _bodyRgb = {
    'yellow': 0xF6C21A,
    'red': 0xE23E3E,
    'blue': 0x2F7DE1,
    'green': 0x3DBE6B,
    'orange': 0xF58A1F,
  };

  /// Sprite height / width of the front face.
  static const double faceAspect = 340 / 256;

  final String colorName;
  final VoidCallback onHitPlayer;
  final void Function(TrainObstacle train) onHopOn;

  ui.Image? _face;

  TrainObstacle({
    required super.persp,
    required super.player,
    required super.speedProvider,
    required super.lane,
    required super.z,
    required super.length,
    required this.colorName,
    required this.onHitPlayer,
    required this.onHopOn,
  });

  /// Width / height of the train body in px at depth 1 (the runner's depth).
  double get bodyWidth => persp.laneSpacing * 0.92;
  double get bodyHeight => bodyWidth * faceAspect;

  @override
  double get depthMargin => 0.06;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _face = await Flame.images.load('train_front_$colorName.png');
  }

  @override
  void onOverlap({required bool justStarted}) {
    if (player.isFlying) return; // rocket: he flies right over it
    if (!justStarted || player.isRiding) return;
    // just after a rocket landing, touching a train pops him onto the roof
    if (player.isJumping || player.graceTime > 0) {
      onHopOn(this);
    } else {
      onHitPlayer();
    }
  }

  static int _shade(int rgb, double f) {
    int c(double v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());
    final r = c(((rgb >> 16) & 0xFF) * f);
    final g = c(((rgb >> 8) & 0xFF) * f);
    final b = c((rgb & 0xFF) * f);
    return (r << 16) | (g << 8) | b;
  }

  static Path _quad(Offset a, Offset b, Offset c, Offset d) => Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(c.dx, c.dy)
    ..lineTo(d.dx, d.dy)
    ..close();

  @override
  void render(Canvas canvas) {
    final p = persp;
    final zf = math.max(z, 0.35); // front edge, clamped so 1/z stays sane
    final zb = math.max(z + length, 0.36); // back edge
    final half = bodyWidth / 2;
    final cx = laneNearX;
    final h = bodyHeight;
    final base = _bodyRgb[colorName]!;

    double xl(double zz) => p.xAt(cx - half, zz);
    double xr(double zz) => p.xAt(cx + half, zz);
    double gy(double zz) => p.groundY(zz);
    double ty(double zz) => p.groundY(zz) - h / zz; // roof height on screen

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = tint(0x1C1E2A);

    // ---- side wall: only the side that faces the vanishing point is visible
    double Function(double)? wallX;
    if (cx + half < p.vanishX) {
      wallX = xr;
    } else if (cx - half > p.vanishX) {
      wallX = xl;
    }
    if (wallX != null) {
      final wx = wallX;
      Offset pt(double zz, double hh) => Offset(wx(zz), gy(zz) - hh / zz);
      final wall = _quad(pt(zf, 0), pt(zf, h), pt(zb, h), pt(zb, 0));
      canvas.drawPath(wall, Paint()..color = tint(_shade(base, 0.72)));
      // white stripe band
      canvas.drawPath(
        _quad(pt(zf, h * 0.20), pt(zf, h * 0.27), pt(zb, h * 0.27), pt(zb, h * 0.20)),
        Paint()..color = tint(0xFFFFFF, 0.85),
      );
      // windows streaming along the side
      var za = zf + 0.30;
      while (za + 0.5 < zb - 0.15) {
        final zc = za + 0.5;
        canvas.drawPath(
          _quad(pt(za, h * 0.42), pt(za, h * 0.82), pt(zc, h * 0.82), pt(zc, h * 0.42)),
          Paint()..color = tint(0x24435E),
        );
        za += 0.75;
      }
      canvas.drawPath(wall, outline);
    }

    // ---- roof (top surface, receding toward the vanishing point)
    final roof = _quad(
      Offset(xl(zf), ty(zf)),
      Offset(xr(zf), ty(zf)),
      Offset(xr(zb), ty(zb)),
      Offset(xl(zb), ty(zb)),
    );
    canvas.drawPath(roof, Paint()..color = tint(0xC9D2DB));

    final rib = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = tint(0x8E9AA8);
    for (final f in const [0.22, 0.5, 0.78]) {
      final nx = cx - half + 2 * half * f;
      canvas.drawLine(
        Offset(p.xAt(nx, zf), ty(zf)),
        Offset(p.xAt(nx, zb), ty(zb)),
        rib,
      );
    }
    // roof vents
    final vent = Paint()..color = tint(0x8E9AA8);
    var zv = zf + 0.7;
    while (zv + 0.25 < zb - 0.2) {
      canvas.drawPath(
        _quad(
          Offset(p.xAt(cx - half * 0.28, zv), ty(zv)),
          Offset(p.xAt(cx + half * 0.28, zv), ty(zv)),
          Offset(p.xAt(cx + half * 0.28, zv + 0.25), ty(zv + 0.25)),
          Offset(p.xAt(cx - half * 0.28, zv + 0.25), ty(zv + 0.25)),
        ),
        vent,
      );
      zv += 0.95;
    }
    canvas.drawPath(roof, outline);

    // ---- front face (the sprite)
    final face = _face;
    if (face != null && z >= 0.5) {
      final dst = Rect.fromLTRB(xl(z), ty(z), xr(z), gy(z));
      final src = Rect.fromLTWH(0, 0, face.width.toDouble(), face.height.toDouble());
      canvas.drawImageRect(
        face,
        src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(255, 255, 255, fade),
      );
    }
  }
}
