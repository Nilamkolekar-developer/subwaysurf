import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../game/perspective.dart';

class _Cloud {
  double x;
  final double y;
  final double scale;
  _Cloud(this.x, this.y, this.scale);
}

class _Building {
  final double x, w, h;
  const _Building(this.x, this.w, this.h);
}

/// The whole scenery, drawn in one-point perspective so the track runs off to
/// a vanishing point like the real game: sky + skyline, tall side walls with
/// scrolling ad panels, a ballast bed, and sleepers/rails that stream toward
/// the camera at the same world speed as the trains.
class GameBackground extends Component {
  final Perspective persp;

  /// World speed in depth-units per second (0 when the game is over).
  final double Function() speedProvider;

  double _offset = 0; // total depth scrolled so far
  final math.Random _random = math.Random(7);
  final List<_Cloud> _clouds = [];
  final List<_Building> _skyline = [];

  static const List<int> _adColors = [
    0xE2503C, 0x2F9BD6, 0xF2B632, 0x4CB86B, 0x9B5FD0, 0xEF7B3A,
  ];

  GameBackground({required this.persp, required this.speedProvider}) {
    priority = -100000;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    for (var i = 0; i < 4; i++) {
      _clouds.add(_Cloud(
        _random.nextDouble() * persp.width,
        8 + _random.nextDouble() * persp.horizonY * 0.5,
        0.6 + _random.nextDouble() * 0.7,
      ));
    }
    var x = -10.0;
    while (x < persp.width + 10) {
      final w = 18 + _random.nextDouble() * 34;
      final h = 14 + _random.nextDouble() * persp.horizonY * 0.42;
      _skyline.add(_Building(x, w, h));
      x += w + _random.nextDouble() * 6;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _offset += speedProvider() * dt;
    for (final c in _clouds) {
      c.x += 6 * dt;
      if (c.x > persp.width + 60) c.x = -60;
    }
  }

  static Path _q(Offset a, Offset b, Offset c, Offset d) => Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(c.dx, c.dy)
    ..lineTo(d.dx, d.dy)
    ..close();

  @override
  void render(Canvas canvas) {
    final p = persp;
    final w = p.width;
    final h = p.height;
    final hy = p.horizonY;
    final spacing = p.laneSpacing;

    // ---- sky
    final skyRect = Rect.fromLTWH(0, 0, w, hy);
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF4FA8DE), Color(0xFFCDEBF7)],
        ).createShader(skyRect),
    );
    final cloudPaint = Paint()..color = const Color(0xCCFFFFFF);
    for (final c in _clouds) {
      final r = 14 * c.scale;
      canvas.drawCircle(Offset(c.x, c.y), r, cloudPaint);
      canvas.drawCircle(Offset(c.x + r * 1.1, c.y + r * 0.2), r * 0.85, cloudPaint);
      canvas.drawCircle(Offset(c.x - r * 1.0, c.y + r * 0.25), r * 0.75, cloudPaint);
    }
    final skylinePaint = Paint()..color = const Color(0xFF93B9CF);
    for (final b in _skyline) {
      canvas.drawRect(Rect.fromLTWH(b.x, hy - b.h, b.w, b.h), skylinePaint);
    }

    // ---- ground (platform) + track bed
    final groundRect = Rect.fromLTRB(0, hy, w, h);
    canvas.drawRect(
      groundRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8A8F98), Color(0xFF585C64)],
        ).createShader(groundRect),
    );

    final nearL = p.laneNearX.first - spacing * 0.62;
    final nearR = p.laneNearX.last + spacing * 0.62;
    final bed = Path()
      ..moveTo(p.vanishX, hy)
      ..lineTo(p.xAtRow(nearL, h), h)
      ..lineTo(p.xAtRow(nearR, h), h)
      ..close();
    canvas.drawPath(
      bed,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5D554A), Color(0xFF453D33)],
        ).createShader(groundRect),
    );
    final edgeLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFFE8C24A);
    canvas.drawLine(Offset(p.vanishX, hy), Offset(p.xAtRow(nearL, h), h), edgeLine);
    canvas.drawLine(Offset(p.vanishX, hy), Offset(p.xAtRow(nearR, h), h), edgeLine);

    // ---- side walls with scrolling ad panels
    _drawWall(canvas, -1);
    _drawWall(canvas, 1);

    // ---- sleepers (one short plank per lane per step)
    const sd = 0.40;
    final sShift = _offset % sd;
    final sleeperPaint = Paint()..color = const Color(0xFF6B4E37);
    final sleeperTop = Paint()..color = const Color(0xFF86664A);
    for (final lx in p.laneNearX) {
      final a = lx - spacing * 0.40;
      final b = lx + spacing * 0.40;
      for (var n = 1; n < 36; n++) {
        final za = n * sd - sShift;
        if (za < 0.55) continue;
        final zb = za + 0.08;
        canvas.drawPath(
          _q(
            Offset(p.xAt(a, zb), p.groundY(zb)),
            Offset(p.xAt(b, zb), p.groundY(zb)),
            Offset(p.xAt(b, za), p.groundY(za)),
            Offset(p.xAt(a, za), p.groundY(za)),
          ),
          sleeperPaint,
        );
        final zt = za + 0.025;
        canvas.drawPath(
          _q(
            Offset(p.xAt(a, zb), p.groundY(zb)),
            Offset(p.xAt(b, zb), p.groundY(zb)),
            Offset(p.xAt(b, zt), p.groundY(zt)),
            Offset(p.xAt(a, zt), p.groundY(zt)),
          ),
          sleeperTop,
        );
      }
    }

    // ---- rails: two per lane, running to the vanishing point
    final railBody = Paint()..color = const Color(0xFF9EA7B4);
    final railShine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFFE9EEF5);
    final wBottom = 3.2 * (h - hy) / (p.footY - hy);
    for (final lx in p.laneNearX) {
      for (final off in const [-0.26, 0.26]) {
        final bottomX = p.xAtRow(lx + off * spacing, h);
        final rail = Path()
          ..moveTo(p.vanishX - 0.3, hy)
          ..lineTo(p.vanishX + 0.3, hy)
          ..lineTo(bottomX + wBottom, h)
          ..lineTo(bottomX - wBottom, h)
          ..close();
        canvas.drawPath(rail, railBody);
        canvas.drawLine(Offset(p.vanishX, hy), Offset(bottomX - wBottom * 0.35, h), railShine);
      }
    }

    // ---- haze at the horizon (hides things spawning far away)
    final hazeRect = Rect.fromLTRB(0, hy - 12, w, hy + 55);
    canvas.drawRect(
      hazeRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00CDEBF7), Color(0xB3CDEBF7), Color(0x00CDEBF7)],
          stops: [0.0, 0.2, 1.0],
        ).createShader(hazeRect),
    );
  }

  void _drawWall(Canvas canvas, double sign) {
    final p = persp;
    final nearX = p.vanishX + sign * p.laneSpacing * 2.15;
    final wallH = p.laneSpacing * 3.0; // px tall at depth 1
    const zMin = 0.6;
    const zMax = 16.0;

    Offset pt(double z, double hf) => Offset(p.xAt(nearX, z), p.groundY(z) - hf * wallH / z);

    // wall face
    canvas.drawPath(
      _q(pt(zMin, 0), pt(zMin, 1), pt(zMax, 1), pt(zMax, 0)),
      Paint()..color = const Color(0xFF80858E),
    );
    // lighter cap along the top, dark baseboard along the bottom
    canvas.drawPath(
      _q(pt(zMin, 0.93), pt(zMin, 1), pt(zMax, 1), pt(zMax, 0.93)),
      Paint()..color = const Color(0xFFA3A8B1),
    );
    canvas.drawPath(
      _q(pt(zMin, 0), pt(zMin, 0.07), pt(zMax, 0.07), pt(zMax, 0)),
      Paint()..color = const Color(0xFF5A5E66),
    );

    const dz = 1.4;
    final shift = _offset % dz;
    final baseIdx = (_offset / dz).floor();
    final pillar = Paint()..color = const Color(0xFF666B74);
    for (var n = 0; n < 12; n++) {
      final za = n * dz - shift; // near edge of this panel
      final zb = za + dz; // far edge
      if (zb <= zMin) continue;
      final idx = baseIdx + n;

      final z0 = math.max(za + 0.15, zMin);
      final z1 = zb - 0.15;
      if (z0 < z1) {
        final color = (idx % 3 == 0)
            ? const Color(0xFF5A5E66) // dark vent/door bay
            : Color(0xFF000000 | _adColors[(idx * 7 + (sign > 0 ? 3 : 0)) % _adColors.length]);
        canvas.drawPath(
          _q(pt(z0, 0.22), pt(z0, 0.80), pt(z1, 0.80), pt(z1, 0.22)),
          Paint()..color = color,
        );
        if (idx % 3 != 0) {
          // white "text line" so ads read as posters
          canvas.drawPath(
            _q(pt(z0, 0.62), pt(z0, 0.70), pt(z1, 0.70), pt(z1, 0.62)),
            Paint()..color = const Color(0x88FFFFFF),
          );
        }
      }
      final zp0 = math.max(zb - 0.06, zMin);
      final zp1 = zb + 0.06;
      if (zp0 < zp1) {
        canvas.drawPath(_q(pt(zp0, 0), pt(zp0, 1), pt(zp1, 1), pt(zp1, 0)), pillar);
      }
    }
  }
}
