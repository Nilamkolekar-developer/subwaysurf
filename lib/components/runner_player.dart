import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/material.dart';

// ignore: unused_field
enum _Action { jump, slide }

class RunnerPlayer extends SpriteAnimationComponent with CollisionCallbacks {
  static const double laneSwitchSpeed = 1400; // px/s, horizontal slide speed
  static const double jumpDuration = 0.5; // seconds, full up-and-down arc
  static const double jumpPeakHeight = 200; // px risen at the peak of the jump
  static const double boostedJumpPeak = 190; // rocket boots: much higher...
  static const double boostedJumpDuration = 0.62; // ...and a longer hang time
  static const double slideDuration = 0.45; // seconds spent ducked

  // Sprite sheet: 8 frames, 192x256 each, single row.
  static const int _frameCount = 8;
  static const double _frameWidth = 192;
  static const double _frameHeight = 256;
  static const double _stepTime = 0.07; // seconds per frame at runSpeed 1.0
  static const int _airFrame = 2; // pose shown while airborne (knee-up frame)

  static const double _bufferWindow = 0.18; // seconds a swipe stays queued
  static const double _diveSpeedup = 3.2; // fall speed multiplier when diving

  final List<double> laneXPositions;
  final double fixedY;
  int currentLane = 1;
  bool isGameOver = false;

  bool isJumping = false;
  double _jumpTime = 0;
  double _jumpOffset = 0;
  bool _diving = false;

  bool isSliding = false;
  double _slideTime = 0;

  /// True while standing on a frozen [TrainObstacle]'s roof. Set/cleared by
  /// [SubwayGame], which owns the ride timer and the frozen train itself.
  bool isRiding = false;

  /// Set from the game as it speeds up (1.0 = base pace). Scales how fast the
  /// run cycle plays so the legs keep up with the scrolling track.
  double runSpeed = 1.0;

  /// Rocket boots / super sneakers: while true, new jumps are higher and
  /// longer, and flames shoot out of the boots in the air. Set by the game.
  bool rocketBoots = false;

  /// Rocket autopilot: while true Jack flies above everything, ignores swipes
  /// and can't be hurt. Started/stopped by the game (which also steers him).
  bool flying = false;
  static const double flyHeight = 175; // px above the track (clears trains)

  /// Short invulnerability after a rocket flight ends, so he never lands
  /// inside something. He blinks while it lasts.
  double graceTime = 0;

  bool get isFlying => flying;
  bool get isInvulnerable => flying || graceTime > 0;
  double _activePeak = jumpPeakHeight; // fixed at take-off so a jump never
  double _activeDur = jumpDuration; //   changes shape mid-air
  double _flameT = 0;

  double rideElevation = 90;

  double get heightAboveGround => _jumpOffset;

  /// Hooks for the game: play sounds, shake the camera on landing, etc.
  VoidCallback? onJump;
  VoidCallback? onSlide;
  VoidCallback? onLand;

  // --- visual-only state (never affects collisions) ---
  double _lean = 0; // -1 (left) .. 1 (right)
  double _vx = 1, _vy = 1; // smoothed squash & stretch
  double _landSquash = 0; // 1 -> 0 right after touching down

  // --- input buffer ---
  _Action? _buffered;
  double _bufferTimer = 0;

  RectangleHitbox? _hitbox;

  RunnerPlayer({required this.laneXPositions, required this.fixedY})
      : super(
          size: Vector2(48, 64),
          position: Vector2(laneXPositions[1] - 24, fixedY),
          autoResize: false,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final image = await Flame.images.load('redcap_sheet.png');
    animation = SpriteAnimation.fromFrameData(
      image,
      SpriteAnimationData.sequenced(
        amount: _frameCount,
        stepTime: _stepTime,
        textureSize: Vector2(_frameWidth, _frameHeight),
      ),
    );
    _hitbox = RectangleHitbox(size: Vector2(36, 60), position: Vector2(6, 4));
    add(_hitbox!);
  }

  void moveToLane(int lane) {
    if (isGameOver || flying) return;
    currentLane = lane.clamp(0, laneXPositions.length - 1);
  }

  void moveLeft() => moveToLane(currentLane - 1);
  void moveRight() => moveToLane(currentLane + 1);

  /// Jump. Mid-air presses are queued briefly (not chained). Pressing jump
  /// while sliding hops straight out of the slide.
  void jump() {
    if (isGameOver || isRiding || flying) return;
    if (isJumping) {
      _queue(_Action.jump);
      return;
    }
    if (isSliding) {
      isSliding = false;
      _setDuckHitbox(false);
    }
    isJumping = true;
    _diving = false;
    _jumpTime = 0;
    _activePeak = rocketBoots ? boostedJumpPeak : jumpPeakHeight;
    _activeDur = rocketBoots ? boostedJumpDuration : jumpDuration;
    onJump?.call();
  }

  /// Slide. Pressing it while airborne dives to the ground and rolls straight
  /// into a slide, like the real game.
  void slide() {
    if (isGameOver || isRiding || flying) return;
    if (isJumping) {
      _startDive();
      return;
    }
    if (isSliding) return;
    isSliding = true;
    _slideTime = 0;
    _setDuckHitbox(true);
    onSlide?.call();
  }

  void _startDive() {
    if (_diving) return;
    _diving = true;
    // The arc is symmetric: if we're still rising, jump to the matching
    // point on the way down so the dive starts immediately.
    if (_jumpTime / _activeDur < 0.5) {
      _jumpTime = _activeDur - _jumpTime;
    }
  }

  void _queue(_Action a) {
    _buffered = a;
    _bufferTimer = _bufferWindow;
  }

  /// Rocket take-off (called by the game).
  void startFlying() {
    flying = true;
    isJumping = false;
    _diving = false;
    isSliding = false;
    _buffered = null;
    _setDuckHitbox(false);
  }

  /// End of the flight (the game decides where he lands).
  void stopFlying() {
    flying = false;
  }

  /// Lane change ordered by the game's autopilot (swipes are ignored).
  void autoMoveToLane(int lane) {
    currentLane = lane.clamp(0, laneXPositions.length - 1);
  }

  /// Called by [SubwayGame] when a well-timed jump lands the player on a
  /// train's roof.
  void startRiding() {
    isJumping = false;
    _diving = false;
    isRiding = true; // _jumpOffset eases up to rideElevation in update()
  }

  /// Called by [SubwayGame] when the ride timer ends (or the run resets).
  void stopRiding() {
    isRiding = false;
  }

  /// While ducked, the hitbox covers only the lower part of the body.
  void _setDuckHitbox(bool duck) {
    final hb = _hitbox;
    if (hb == null) return;
    if (duck) {
      hb.size = Vector2(36, 33);
      hb.position = Vector2(6, 31);
    } else {
      hb.size = Vector2(36, 60);
      hb.position = Vector2(6, 4);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _flameT += dt;
    if (graceTime > 0) graceTime -= dt;

    // ---- lane movement + lean ----
    final targetX = laneXPositions[currentLane] - size.x / 2;
    final diff = targetX - position.x;
    final step = laneSwitchSpeed * dt;
    if (diff.abs() <= step) {
      position.x = targetX;
    } else {
      position.x += diff.sign * step;
    }
    final leanTarget = (diff / 60).clamp(-1.0, 1.0).toDouble();
    _lean += (leanTarget - _lean) * math.min(1.0, 16 * dt);

    // ---- vertical state: ride / jump / dive ----
    if (flying) {
      final target = flyHeight + math.sin(_flameT * 3) * 6;
      _jumpOffset += (target - _jumpOffset) * math.min(1.0, 6 * dt);
    } else if (isRiding) {
      _jumpOffset += (rideElevation - _jumpOffset) * math.min(1.0, 16 * dt);
      if ((rideElevation - _jumpOffset).abs() < 0.5)
        _jumpOffset = rideElevation;
    } else if (isJumping) {
      _jumpTime += dt * (_diving ? _diveSpeedup : 1.0);
      final t = (_jumpTime / _activeDur).clamp(0.0, 1.0).toDouble();
      _jumpOffset = _activePeak * 4 * t * (1 - t);
      if (_jumpTime >= _activeDur) {
        isJumping = false;
        _jumpOffset = 0;
        _landSquash = 1.0;
        onLand?.call();
        if (_diving) {
          _diving = false;
          isSliding = true;
          _slideTime = 0;
          _setDuckHitbox(true);
          onSlide?.call();
        }
      }
    } else {
      // fall back to the track (instant when already on the ground)
      _jumpOffset = math.max(0.0, _jumpOffset - 800 * dt);
    }
    position.y = fixedY - _jumpOffset;

    // ---- slide timer ----
    if (isSliding) {
      _slideTime += dt;
      if (_slideTime >= slideDuration) {
        isSliding = false;
        _setDuckHitbox(false);
      }
    }

    // ---- buffered input ----
    if (_bufferTimer > 0) {
      _bufferTimer -= dt;
      if (_buffered != null &&
          !isJumping &&
          !isSliding &&
          !isRiding &&
          !isGameOver) {
        final a = _buffered!;
        _buffered = null;
        _bufferTimer = 0;
        a == _Action.jump ? jump() : slide();
      }
      if (_bufferTimer <= 0) _buffered = null;
    }

    // ---- squash & stretch (visual only) ----
    double tx = 1.0, ty = 1.0;
    if (isSliding) {
      tx = 1.08;
      ty = 0.55;
    } else if (isJumping) {
      final t = _jumpTime / _activeDur;
      if (_diving) {
        tx = 0.90;
        ty = 1.12;
      } else if (t < 0.2) {
        tx = 0.94;
        ty = 1.10; // launch stretch
      }
    }
    if (_landSquash > 0) {
      _landSquash = math.max(0.0, _landSquash - dt / 0.14);
      ty *= 1 - 0.16 * _landSquash;
      tx *= 1 + 0.10 * _landSquash;
    }
    final k = math.min(1.0, 22 * dt);
    _vx += (tx - _vx) * k;
    _vy += (ty - _vy) * k;

    // ---- animation: frozen pose in the air, speed-scaled run otherwise ----
    final airborne = (isJumping && !isRiding) || flying;
    if (airborne) {
      playing = false;
      animationTicker?.currentIndex = _airFrame;
    } else {
      playing = !isGameOver;
      if (playing && runSpeed > 1.0) {
        // super.update already advanced by dt; add the extra on top.
        animationTicker?.update(dt * (runSpeed - 1.0));
      }
    }
  }

  @override
  void render(Canvas canvas) {
    // Ground shadow (stays on the ground while the body rises; on a train
    // roof the "ground" is the roof, so it sits at the feet).
    final airH = isRiding ? 0.0 : _jumpOffset;
    final s = (1 - airH / (_activePeak * 2.5)).clamp(0.5, 1.0).toDouble();
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y + airH - 1),
        width: 34 * s,
        height: 9 * s,
      ),
      Paint()..color = Colors.black.withOpacity(0.28 * s),
    );

    // Lean / squash / stretch pivot around the feet (bottom-center), so the
    // character stays planted on the track instead of floating.
    canvas.save();
    canvas.translate(size.x / 2, size.y);
    canvas.rotate(_lean * 0.22);
    canvas.scale(_vx, _vy);
    canvas.translate(-size.x / 2, -size.y);

    if (rocketBoots || flying) {
      // orange aura so it's obvious the boots / rocket are active
      canvas.drawCircle(
        Offset(size.x / 2, size.y * 0.55),
        size.y * 0.58,
        Paint()
          ..color = const Color(0xFFFF9800)
              .withOpacity(0.18 + 0.08 * math.sin(_flameT * 8)),
      );
    }

    final blink = graceTime > 0 && ((graceTime * 10).floor() % 2 == 0);
    if (blink) {
      canvas.saveLayer(
          null, Paint()..color = const Color.fromRGBO(255, 255, 255, 0.4));
    }
    super.render(canvas);
    if (blink) canvas.restore();

    if ((rocketBoots || flying) && !isSliding) {
      final flick = 0.75 + 0.25 * math.sin(_flameT * 40);
      final len = (flying ? 30.0 : (isJumping ? 20.0 : 6.0)) *
          flick; // rocket > jump > ground sparks
      final baseY = size.y - 3;
      for (final fx in const [0.36, 0.64]) {
        final x = size.x * fx;
        canvas.drawPath(
          Path()
            ..moveTo(x - 5, baseY)
            ..lineTo(x + 5, baseY)
            ..lineTo(x, baseY + len)
            ..close(),
          Paint()..color = const Color(0xFFFF9800),
        );
        canvas.drawPath(
          Path()
            ..moveTo(x - 2.5, baseY)
            ..lineTo(x + 2.5, baseY)
            ..lineTo(x, baseY + len * 0.6)
            ..close(),
          Paint()..color = const Color(0xFFFFEB3B),
        );
      }
    }

    if (isGameOver) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.x, size.y),
        Paint()..color = Colors.red.withOpacity(0.25),
      );
    }
    canvas.restore();
  }
}
