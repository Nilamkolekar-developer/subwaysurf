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

/// Colours of one "view". Every corner you turn switches to the next theme.
class _Theme {
  final Color skyTop, skyBottom, skyline, groundTop, groundBottom;
  final Color wall, wallCap, wallBase, pillar, haze;
  const _Theme({
    required this.skyTop,
    required this.skyBottom,
    required this.skyline,
    required this.groundTop,
    required this.groundBottom,
    required this.wall,
    required this.wallCap,
    required this.wallBase,
    required this.pillar,
    required this.haze,
  });
}

/// The whole scenery, drawn in one-point perspective so the track runs off to
/// a vanishing point like the real game: sky + skyline, tall side walls with
/// scrolling ad panels, a ballast bed, and sleepers/rails that stream toward
/// the camera at the same world speed as the trains.
class GameBackground extends Component {
  final Perspective persp;

  /// World speed in depth-units per second (0 when the game is over).
  final double Function() speedProvider;

  // ---- views / corners (driven by SubwayGame) ----
  static const List<_Theme> _themes = [
    // 0: daytime station (the original look)
    _Theme(
      skyTop: Color(0xFF4FA8DE), skyBottom: Color(0xFFCDEBF7), skyline: Color(0xFF93B9CF),
      groundTop: Color(0xFF8A8F98), groundBottom: Color(0xFF585C64),
      wall: Color(0xFF80858E), wallCap: Color(0xFFA3A8B1), wallBase: Color(0xFF5A5E66),
      pillar: Color(0xFF666B74), haze: Color(0xFFCDEBF7),
    ),
    // 1: sunset
    _Theme(
      skyTop: Color(0xFFE8743B), skyBottom: Color(0xFFFFD29A), skyline: Color(0xFFB9836B),
      groundTop: Color(0xFF9A8F88), groundBottom: Color(0xFF5F5650),
      wall: Color(0xFF8E7F7A), wallCap: Color(0xFFB5A49E), wallBase: Color(0xFF61524D),
      pillar: Color(0xFF75655F), haze: Color(0xFFFFD29A),
    ),
    // 2: night
    _Theme(
      skyTop: Color(0xFF0B1638), skyBottom: Color(0xFF34508C), skyline: Color(0xFF1D2C55),
      groundTop: Color(0xFF3B4150), groundBottom: Color(0xFF20232C),
      wall: Color(0xFF404760), wallCap: Color(0xFF5A6482), wallBase: Color(0xFF262B3C),
      pillar: Color(0xFF313852), haze: Color(0xFF34508C),
    ),
  ];
  static int get themeCount => _themes.length;

  /// Depth of the near edge of a T-junction ahead (null = straight track).
  double? cornerZ;

  /// How deep the cross corridor is (depth units) before its far wall.
  static const double cornerDepth = 1.2;

  int theme = 0; // view currently in use (the NEW view while turning)
  int oldTheme = 0; // view we are turning away from
  int turnDir = 0; // -1 = turning left, 1 = turning right, 0 = not turning
  double turnT = 0; // 0..1 progress of the swing while turning

  void resetViews() {
    cornerZ = null;
    theme = 0;
    oldTheme = 0;
    turnDir = 0;
    turnT = 0;
  }

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
    if (turnDir == 0) {
      _drawScene(canvas, cornerZ, _themes[theme % _themes.length]);
      return;
    }
    // Mid-turn: the old view (standing at the junction) swings out of the
    // screen while the new straight track swings in from the other side.
    final w = persp.width;
    final t = turnT.clamp(0.0, 1.0).toDouble();
    canvas.save();
    canvas.translate(-turnDir * w * t, 0);
    _drawScene(canvas, cornerZ, _themes[oldTheme % _themes.length]);
    canvas.restore();
    canvas.save();
    canvas.translate(turnDir * w * (1 - t), 0);
    _drawScene(canvas, null, _themes[theme % _themes.length]);
    canvas.restore();
  }

  /// Draws one complete view. [cz] is the depth of a T-junction ahead, or null
  /// for an endless straight track.
  void _drawScene(Canvas canvas, double? cz, _Theme th) {
    final p = persp;
    final w = p.width;
    final h = p.height;
    final hy = p.horizonY;
    final spacing = p.laneSpacing;
    final zEnd = cz ?? 1000.0; // where the main track stops

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, h));

    Offset gp(double x, double z) => Offset(p.xAt(x, z), p.groundY(z));

    // ---- sky
    final skyRect = Rect.fromLTWH(0, 0, w, hy);
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [th.skyTop, th.skyBottom],
        ).createShader(skyRect),
    );
    final cloudPaint = Paint()..color = const Color(0xCCFFFFFF);
    for (final c in _clouds) {
      final r = 14 * c.scale;
      canvas.drawCircle(Offset(c.x, c.y), r, cloudPaint);
      canvas.drawCircle(Offset(c.x + r * 1.1, c.y + r * 0.2), r * 0.85, cloudPaint);
      canvas.drawCircle(Offset(c.x - r * 1.0, c.y + r * 0.25), r * 0.75, cloudPaint);
    }
    final skylinePaint = Paint()..color = th.skyline;
    for (final b in _skyline) {
      canvas.drawRect(Rect.fromLTWH(b.x, hy - b.h, b.w, b.h), skylinePaint);
    }

    // ---- ground (platform)
    final groundRect = Rect.fromLTRB(0, hy, w, h);
    canvas.drawRect(
      groundRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [th.groundTop, th.groundBottom],
        ).createShader(groundRect),
    );

    // ---- junction: cross corridor floor + the wall at its far side
    if (cz != null) _drawCorner(canvas, cz, th);

    // ---- track bed (stops at the junction)
    final nearL = p.laneNearX.first - spacing * 0.62;
    final nearR = p.laneNearX.last + spacing * 0.62;
    final bed = Path()
      ..moveTo(gp(nearL, zEnd).dx, gp(nearL, zEnd).dy)
      ..lineTo(gp(nearR, zEnd).dx, gp(nearR, zEnd).dy)
      ..lineTo(p.xAtRow(nearR, h), h)
      ..lineTo(p.xAtRow(nearL, h), h)
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
    canvas.drawLine(gp(nearL, zEnd), Offset(p.xAtRow(nearL, h), h), edgeLine);
    canvas.drawLine(gp(nearR, zEnd), Offset(p.xAtRow(nearR, h), h), edgeLine);

    // ---- side walls with scrolling ad panels
    _drawWall(canvas, -1, th, zEnd);
    _drawWall(canvas, 1, th, zEnd);

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
        if (zb >= zEnd) break;
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

    // ---- rails: two per lane, running to the vanishing point (or the junction)
    final railBody = Paint()..color = const Color(0xFF9EA7B4);
    final railShine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFFE9EEF5);
    final wBottom = 3.2 * (h - hy) / (p.footY - hy);
    final yTop = p.groundY(zEnd);
    final wTop = 0.3 + (wBottom - 0.3) * (yTop - hy) / (h - hy);
    for (final lx in p.laneNearX) {
      for (final off in const [-0.26, 0.26]) {
        final railX = lx + off * spacing;
        final bottomX = p.xAtRow(railX, h);
        final topX = p.xAt(railX, zEnd);
        final rail = Path()
          ..moveTo(topX - wTop, yTop)
          ..lineTo(topX + wTop, yTop)
          ..lineTo(bottomX + wBottom, h)
          ..lineTo(bottomX - wBottom, h)
          ..close();
        canvas.drawPath(rail, railBody);
        canvas.drawLine(Offset(topX, yTop), Offset(bottomX - wBottom * 0.35, h), railShine);
      }
    }

    // ---- hazard strip where the track ends at the junction
    if (cz != null) {
      final zNear = math.max(cz - 0.12, 0.5);
      canvas.drawPath(
        _q(gp(nearL, cz), gp(nearR, cz), gp(nearR, zNear), gp(nearL, zNear)),
        Paint()..color = const Color(0xFFF2C230),
      );
    }

    // ---- haze at the horizon (hides things spawning far away)
    final hazeRect = Rect.fromLTRB(0, hy - 12, w, hy + 55);
    canvas.drawRect(
      hazeRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [th.haze.withOpacity(0), th.haze.withOpacity(0.7), th.haze.withOpacity(0)],
          stops: const [0.0, 0.2, 1.0],
        ).createShader(hazeRect),
    );

    canvas.restore();
  }

  /// The T-junction: a floor running left/right across the track's end and a
  /// wall on its far side with two big arrows on it.
  void _drawCorner(Canvas canvas, double cz, _Theme th) {
    final p = persp;
    final w = p.width;
    final zw = cz + cornerDepth; // depth of the far wall
    final wallH = p.laneSpacing * 3.0;
    final yBot = p.groundY(zw);
    final yTrueTop = yBot - wallH / zw;
    final yTop = math.min(yTrueTop, p.horizonY);

    // cross corridor floor
    canvas.drawRect(
      Rect.fromLTRB(0, yBot, w, p.groundY(cz)),
      Paint()..color = const Color(0xFF56524A),
    );
    // far wall (face, cap, baseboard)
    canvas.drawRect(Rect.fromLTRB(0, yTop, w, yBot), Paint()..color = th.wall);
    canvas.drawRect(
      Rect.fromLTRB(0, yTrueTop, w, yTrueTop + 0.07 * wallH / zw),
      Paint()..color = th.wallCap,
    );
    canvas.drawRect(
      Rect.fromLTRB(0, yBot - 0.07 * wallH / zw, w, yBot),
      Paint()..color = th.wallBase,
    );

    // big arrows: left and right
    final yMid = yBot - 0.5 * wallH / zw;
    final s = p.laneSpacing * 0.42 / zw;
    final panel = Paint()..color = const Color(0x99000000);
    final arrowPaint = Paint()..color = const Color(0xFFF2C230);
    for (final d in const [-1.0, 1.0]) {
      final cx = p.xAt(p.vanishX + d * p.laneSpacing * 1.3, zw);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, yMid), width: s * 2.8, height: s * 2.2),
          Radius.circular(s * 0.3),
        ),
        panel,
      );
      Offset a(double x, double y) => Offset(cx + d * x * s, yMid + y * s);
      final arrow = Path()
        ..moveTo(a(1.0, 0).dx, a(1.0, 0).dy)
        ..lineTo(a(0.0, -0.8).dx, a(0.0, -0.8).dy)
        ..lineTo(a(0.0, -0.35).dx, a(0.0, -0.35).dy)
        ..lineTo(a(-1.0, -0.35).dx, a(-1.0, -0.35).dy)
        ..lineTo(a(-1.0, 0.35).dx, a(-1.0, 0.35).dy)
        ..lineTo(a(0.0, 0.35).dx, a(0.0, 0.35).dy)
        ..lineTo(a(0.0, 0.8).dx, a(0.0, 0.8).dy)
        ..close();
      canvas.drawPath(arrow, arrowPaint);
    }
  }

  void _drawWall(Canvas canvas, double sign, _Theme th, double zEnd) {
    final p = persp;
    final nearX = p.vanishX + sign * p.laneSpacing * 2.15;
    final wallH = p.laneSpacing * 3.0; // px tall at depth 1
    const zMin = 0.6;
    final zMax = math.min(16.0, zEnd);

    Offset pt(double z, double hf) => Offset(p.xAt(nearX, z), p.groundY(z) - hf * wallH / z);

    // wall face
    canvas.drawPath(
      _q(pt(zMin, 0), pt(zMin, 1), pt(zMax, 1), pt(zMax, 0)),
      Paint()..color = th.wall,
    );
    // lighter cap along the top, dark baseboard along the bottom
    canvas.drawPath(
      _q(pt(zMin, 0.93), pt(zMin, 1), pt(zMax, 1), pt(zMax, 0.93)),
      Paint()..color = th.wallCap,
    );
    canvas.drawPath(
      _q(pt(zMin, 0), pt(zMin, 0.07), pt(zMax, 0.07), pt(zMax, 0)),
      Paint()..color = th.wallBase,
    );

    const dz = 1.4;
    final shift = _offset % dz;
    final baseIdx = (_offset / dz).floor();
    final pillar = Paint()..color = th.pillar;
    for (var n = 0; n < 12; n++) {
      final za = n * dz - shift; // near edge of this panel
      final zb = za + dz; // far edge
      if (zb <= zMin) continue;
      if (za >= zMax) break;
      final idx = baseIdx + n;

      final z0 = math.max(za + 0.15, zMin);
      final z1 = math.min(zb - 0.15, zMax);
      if (z0 < z1) {
        final color = (idx % 3 == 0)
            ? th.wallBase // dark vent/door bay
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
      final zp1 = math.min(zb + 0.06, zMax);
      if (zp0 < zp1) {
        canvas.drawPath(_q(pt(zp0, 0), pt(zp0, 1), pt(zp1, 1), pt(zp1, 0)), pillar);
      }
    }
  }
}