import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../components/rocket_pickup.dart';
import '../components/coin_pickup.dart';
import '../components/game_background.dart';
import '../components/key_pickup.dart';
import '../components/low_barrier.dart';
import '../components/overhead_barrier.dart';
import '../components/runner_player.dart';
import '../components/train_obstacle.dart';
import '../components/world_entity.dart';
import 'perspective.dart';

class SubwayGame extends FlameGame with HasCollisionDetection, PanDetector, KeyboardEvents {
  late RunnerPlayer player;
  late GameBackground background;
  late Perspective persp;
  late TextComponent scoreText;
  late TextComponent coinText;
  late TextComponent keyText;
  late TextComponent rocketText;
  late TextComponent bestText;
  late TextComponent bannerTitle; // big message in the upper-middle of the screen
  late TextComponent bannerSub;
  double _bannerTime = 0;
  int _roofTips = 0; // roof tip is only shown for the first couple of hop-ons
  late List<double> laneXPositions;

  // ---- world speed (depth-units per second; 1.0 is the runner's depth) ----
  // Tune these three to change how the run feels:
  static const double _startZSpeed = 0.10; // gentle start
  static const double _zSpeedRamp = 0.045; // extra speed per second played
  static const double _maxZSpeed = 5.0; // top speed (reached after ~2.5 min)

  /// Pace at which the run animation plays at its normal speed; the legs only
  /// speed up once the world is faster than this.
  static const double _legsBaseZSpeed = 3.7;

  double elapsedTime = 0;
  int score = 0;
  int coins = 0;
  int keys = 0;
  int bestScore = 0;
  bool isNewBest = false; // this run beat the saved best (shown on game over)

  // ---- saved progress: keys, coins and best score survive closing the app ----
  // (Plain variables live in memory only, so without this they reset to 0 on
  // every launch.)
  SharedPreferences? _prefs;
  bool _saveDirty = false; // coins changed since the last save
  double _sinceSave = 0;
  static const double _saveEvery = 2.0; // seconds, at most, between coin saves
  bool isGameOver = false;

  /// Everything (background, trains, coins) reads this, so it all moves at
  /// one shared speed and freezes together when the game ends.
  double get zSpeed =>
      isGameOver ? 0 : min(_startZSpeed + elapsedTime * _zSpeedRamp, _maxZSpeed) * _speedBoost;

  // ---- spawner: patterns are spaced by DISTANCE, not time ----
  double _distSinceSpawn = 0;
  double _nextGap = 2.0;
  static const double _coinStep = 0.7;

  // ---- rocket power-up (autopilot flight) ----
  double _rocketTimeLeft = 0;
  static const double _rocketDuration = 8.0; // seconds of flight
  static const double _flySpeedBoost = 1.5; // the world rushes past faster
  double _speedBoost = 1.0;
  double _steerCooldown = 0;

  // ---- corners: Temple-Run style turns ----
  // Every so often the track ends in a T-junction with two signs (for example
  // WATER on the left, FOREST on the right). Swipe LEFT or RIGHT as it arrives
  // and the view swings 90 degrees into that world. Miss it and you run into
  // the wall.
  double? _cornerZ; // depth of the junction, null when the track is straight
  bool _cornerWarned = false;
  double _nextCornerAt = 26; // elapsed seconds before the first junction
  double _turnT = -1; // -1 = not turning, otherwise 0..1 progress of the swing
  int _turnDir = 0; // -1 left, 1 right
  int _theme = 0; // index of the world we are in (0 station, 1 forest, 2 water)
  int _leftDest = 1; // world the LEFT way of the junction leads to
  int _rightDest = 2; // world the RIGHT way leads to
  static const double _turnDuration = 0.7; // seconds the swing takes
  static const double _turnWindow = 0.9; // a swipe this many seconds (or less) before the wall turns

  // ---- camera shake ----
  double _shakeTime = 0;
  double _shakeDuration = 0.15;

  // Train-hopping: jump as a train arrives and you land on its roof. The
  // train keeps moving at world speed, so you RUN ALONG the roof from the nose
  // to the tail. You stay up as long as a train is under your feet (you can
  // even swipe across to a neighbouring train), and drop back to the track
  // when the roof runs out.
  TrainObstacle? _ridingTrain;
  TrainObstacle? _leftTrain; // the train we just ran off the end of
  static const int _hopOnCoinBonus = 5;
  static const double _roofCoinChance = 1.0; // every train has coins on its roof

  // All movement — lane changes AND jump/slide — comes from a single swipe
  // gesture: left/right to change lanes, up to jump, down to slide.
  double _panDx = 0;
  double _panDy = 0;
  bool _actionFiredThisGesture = false;
  static const double _swipeThreshold = 34;

  final Random _random = Random();

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    _prefs = await SharedPreferences.getInstance();
    keys = _prefs?.getInt('keys') ?? 0;
    coins = _prefs?.getInt('coins') ?? 0;
    bestScore = _prefs?.getInt('best_score') ?? 0;

    // 3 lanes spread evenly across the screen width (at the runner's depth).
    laneXPositions = [size.x * 0.25, size.x * 0.5, size.x * 0.75];

    // Runner stands near the bottom; the horizon sits well up the screen so
    // there is a long stretch of track receding into the distance.
    final fixedY = size.y * 0.78;
    persp = Perspective(
      width: size.x,
      height: size.y,
      horizonY: size.y * 0.30,
      footY: fixedY + 64, // runner is 64px tall -> his feet
      laneNearX: laneXPositions,
    );

    // kept in a field so the game can control corners and worlds
    background = GameBackground(persp: persp, speedProvider: () => zSpeed);
    add(background);

    player = RunnerPlayer(laneXPositions: laneXPositions, fixedY: fixedY);
    player.priority = -1000; // depth 1.0: things farther draw behind him
    player.onLand = () => shake(0.12);
    add(player);

    scoreText = TextComponent(
      text: 'Score: 0',
      position: Vector2(16, 16),
      priority: 1000,
      textRenderer: TextPaint(
        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
      ),
    );
    add(scoreText);

    coinText = TextComponent(
      text: '🪙 $coins',
      position: Vector2(16, 44),
      priority: 1000,
      textRenderer: TextPaint(
        style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
    add(coinText);

    keyText = TextComponent(
      text: '🔑 $keys',
      position: Vector2(16, 70),
      priority: 1000,
      textRenderer: TextPaint(
        style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
    add(keyText);

    rocketText = TextComponent(
      text: '',
      position: Vector2(16, 96),
      priority: 1000,
      textRenderer: TextPaint(
        style: const TextStyle(color: Colors.deepOrangeAccent, fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
    add(rocketText);

    bestText = TextComponent(
      text: 'Best: $bestScore',
      position: Vector2(size.x - 16, 16),
      anchor: Anchor.topRight,
      priority: 1000,
      textRenderer: TextPaint(
        style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
    add(bestText);

    const shadow = [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(1, 2))];
    bannerTitle = TextComponent(
      text: '',
      position: Vector2(size.x / 2, size.y * 0.20),
      anchor: Anchor.center,
      priority: 1000,
      textRenderer: TextPaint(
        style: const TextStyle(color: Colors.amberAccent, fontSize: 26, fontWeight: FontWeight.w900, shadows: shadow),
      ),
    );
    bannerSub = TextComponent(
      text: '',
      position: Vector2(size.x / 2, size.y * 0.20 + 32),
      anchor: Anchor.center,
      priority: 1000,
      textRenderer: TextPaint(
        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, shadows: shadow),
      ),
    );
    add(bannerTitle);
    add(bannerSub);

    _showBanner('Swipe UP to jump onto trains', 'Coins are waiting on the roof!', 4.0);
  }

  /// Shows a short message in the upper-middle of the screen.
  void _showBanner(String title, String sub, [double seconds = 2.8]) {
    bannerTitle.text = title;
    bannerSub.text = sub;
    _bannerTime = seconds;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_shakeTime > 0) _shakeTime -= dt;
    if (_bannerTime > 0) {
      _bannerTime -= dt;
      if (_bannerTime <= 0) {
        bannerTitle.text = '';
        bannerSub.text = '';
      }
    }
    if (isGameOver) return;

    elapsedTime += dt;
    _speedBoost += ((player.isFlying ? _flySpeedBoost : 1.0) - _speedBoost) * min(1.0, 3 * dt);
    score = elapsedTime.floor();
    scoreText.text = 'Score: $score';
    bestText.text = 'Best: ${max(bestScore, score)}';

    _sinceSave += dt;
    if (_saveDirty && _sinceSave >= _saveEvery) _save();

    if (_rocketTimeLeft > 0) {
      _rocketTimeLeft -= dt;
      if (_rocketTimeLeft <= 0) {
        _deactivateRocket();
      } else {
        rocketText.text = '🚀 Rocket ${_rocketTimeLeft.ceil()}s';
      }
    }
    if (player.isFlying) _autoSteer(dt);

    // legs keep up with the track as the game speeds up
    player.runSpeed = (zSpeed / _legsBaseZSpeed).clamp(1.0, 1.7).toDouble();

    // move the junction / run the turn animation
    _updateCorner(dt);
    if (isGameOver) return; // ran into the wall at a junction

    // no new obstacles while a junction is ahead or the view is swinging
    if (_cornerZ == null && _turnT < 0) {
      _distSinceSpawn += zSpeed * dt;
      if (_distSinceSpawn >= _nextGap) {
        _distSinceSpawn = 0;
        if (elapsedTime >= _nextCornerAt && !player.isFlying) {
          _spawnCorner();
        } else {
          final depth = _spawnPattern();
          // next pattern starts once this one has cleared plus a reaction gap
          // that tightens slowly as you survive longer
          final minGap = (2.4 - elapsedTime * 0.01).clamp(1.5, 2.4).toDouble();
          _nextGap = depth + minGap;
        }
      }
    }

    if (_ridingTrain != null) {
      final under = _trainUnderPlayer();
      if (under == null) {
        _endRide(); // ran off the tail (or swiped off the side)
      } else {
        _ridingTrain = under; // may have moved across to a neighbouring train
      }
    }

    // After running off a train's tail, keep drawing the runner on top until
    // that train has slid out of the way (it is nearer the camera than him).
    final left = _leftTrain;
    if (left != null && _ridingTrain == null && (left.parent == null || left.backZ < 0.66)) {
      player.priority = -1000;
      _leftTrain = null;
    }
  }

  /// The train whose roof is currently under the runner's feet, if any.
  /// A slightly generous lane tolerance means a sideways swipe between two
  /// trains doesn't drop you mid-swipe.
  TrainObstacle? _trainUnderPlayer() {
    final px = player.position.x + player.size.x / 2;
    TrainObstacle? best;
    for (final t in children.whereType<TrainObstacle>()) {
      if ((px - t.laneNearX).abs() > persp.laneSpacing * 0.52) continue;
      if (t.frontZ > Perspective.zPlayer + 0.02 || t.backZ < Perspective.zPlayer) continue;
      best = t;
    }
    return best;
  }

  // -------------------------------------------------------------- corners
  void _spawnCorner() {
    // the two ways lead to two different worlds (never the one we are in)
    final options = [
      for (var i = 0; i < GameBackground.themeCount; i++)
        if (i != _theme) i
    ]..shuffle(_random);
    _leftDest = options[0];
    _rightDest = options[1];
    background.leftDest = _leftDest;
    background.rightDest = _rightDest;

    _cornerZ = Perspective.zFar;
    _cornerWarned = false;
    background.cornerZ = _cornerZ;
  }

  double _ease(double t) {
    final c = t.clamp(0.0, 1.0).toDouble();
    return c * c * (3 - 2 * c);
  }

  /// Moves the junction toward the runner, runs the swing animation, and
  /// decides what happens when the junction reaches him.
  void _updateCorner(double dt) {
    final cz = _cornerZ;

    // swing in progress: the old view slides out, the new one slides in
    if (_turnT >= 0) {
      _turnT += dt / _turnDuration;
      if (cz != null) {
        // the old junction keeps coming, but stops at the runner's feet
        _cornerZ = max(Perspective.zPlayer, cz - zSpeed * dt);
        background.cornerZ = _cornerZ;
      }
      if (_turnT >= 1) {
        _finishTurn();
      } else {
        background.turnT = _ease(_turnT);
      }
      return;
    }

    if (cz == null) return;
    final next = cz - zSpeed * dt;
    _cornerZ = next;
    background.cornerZ = next;
    final eta = (next - Perspective.zPlayer) / max(zSpeed, 0.05); // seconds

    if (!_cornerWarned && eta < 2.4) {
      _cornerWarned = true;
      _showBanner('Turn ahead!', '← ${GameBackground.envName(_leftDest)}   |   ${GameBackground.envName(_rightDest)} →', 2.4);
    }

    if (player.isFlying) {
      // rocket autopilot takes the corner for you
      if (eta < 0.5) _startTurn(_random.nextBool() ? -1 : 1);
    } else if (next <= Perspective.zPlayer) {
      // no turn -> straight into the wall
      _cornerZ = Perspective.zPlayer;
      background.cornerZ = _cornerZ;
      _onHitObstacle();
    }
  }

  /// A sideways swipe. Near a junction it turns the corner; otherwise it just
  /// changes lane like before.
  void _steer(int dir) {
    if (_tryTurn(dir)) return;
    dir > 0 ? player.moveRight() : player.moveLeft();
  }

  bool _tryTurn(int dir) {
    final cz = _cornerZ;
    if (cz == null || _turnT >= 0 || player.isFlying) return false;
    final eta = (cz - Perspective.zPlayer) / max(zSpeed, 0.05);
    if (eta > _turnWindow) return false;
    _startTurn(dir);
    return true;
  }

  void _startTurn(int dir) {
    if (_ridingTrain != null) _endRide();
    _clearWorld(); // whatever is left belongs to the corridor we are leaving
    _turnDir = dir;
    _turnT = 0;
    background.oldTheme = _theme;
    _theme = dir < 0 ? _leftDest : _rightDest; // the side you swiped picks the world
    background.theme = _theme;
    background.turnDir = dir;
    background.turnT = 0;
    shake(0.12);
  }

  void _finishTurn() {
    _turnT = -1;
    _turnDir = 0;
    _cornerZ = null;
    background.cornerZ = null;
    background.turnDir = 0;
    background.turnT = 0;
    // fresh corridor: first obstacles arrive after a short breather
    _distSinceSpawn = 0;
    _nextGap = 1.6;
    _nextCornerAt = elapsedTime + 22 + _random.nextDouble() * 14;
  }

  /// Back to a straight track (used by restart / revive).
  void _resetCorner({required bool resetTheme}) {
    _cornerZ = null;
    _cornerWarned = false;
    _turnT = -1;
    _turnDir = 0;
    background.cornerZ = null;
    background.turnDir = 0;
    background.turnT = 0;
    if (resetTheme) {
      _theme = 0;
      _leftDest = 1;
      _rightDest = 2;
      background.resetViews();
      _nextCornerAt = 26;
    } else {
      _nextCornerAt = elapsedTime + 12;
    }
  }

  // ---------------------------------------------------------------- shake
  void shake([double duration = 0.15]) {
    _shakeDuration = duration;
    _shakeTime = duration;
  }

  @override
  void render(Canvas canvas) {
    if (_shakeTime > 0) {
      final k = (_shakeTime / _shakeDuration).clamp(0.0, 1.0).toDouble();
      canvas.save();
      canvas.translate(
        (_random.nextDouble() - 0.5) * 8 * k,
        (_random.nextDouble() - 0.5) * 8 * k,
      );
      super.render(canvas);
      canvas.restore();
    } else {
      super.render(canvas);
    }
  }

  // ------------------------------------------------------------- spawning
  double _trainLength() => const [2.0, 3.0, 4.2][_random.nextInt(3)];

  /// Spawns one "row" of the classic Subway Surfers mix and returns how far
  /// behind the front edge it extends (in depth units). Every pattern leaves
  /// at least one lane you can survive in.
  double _spawnPattern() {
    final lanes = [0, 1, 2]..shuffle(_random);
    final roll = _random.nextDouble();
    double depth;

    if (roll < 0.24) {
      // one train, sometimes with coins in another lane
      final len = _trainLength();
      _addTrain(lanes[0], len);
      depth = len;
      if (_random.nextBool()) depth = max(depth, _addCoinLine(lanes[1], 6));
    } else if (roll < 0.40) {
      // two trains, coins in the free lane
      final len = _trainLength();
      _addTrain(lanes[0], len);
      _addTrain(lanes[1], len);
      depth = max(len, _addCoinLine(lanes[2], 7));
    } else if (roll < 0.60) {
      // low barriers in 1-3 lanes (jump), coin arc over the first one
      final n = 1 + _random.nextInt(3);
      for (var i = 0; i < n; i++) {
        _addLowBarrier(lanes[i], Perspective.zFar + 2 * _coinStep);
      }
      depth = max(1.8, _addCoinArc(lanes[0]));
    } else if (roll < 0.74) {
      // overhead barriers in 1-2 lanes (slide), coins on the ground beneath
      final n = 1 + _random.nextInt(2);
      for (var i = 0; i < n; i++) {
        _addOverhead(lanes[i], Perspective.zFar + 1.0);
      }
      depth = max(1.6, _addCoinLine(lanes[0], 5));
    } else if (roll < 0.88) {
      // train + low barrier + coins in the free lane
      final len = _trainLength();
      _addTrain(lanes[0], len);
      _addLowBarrier(lanes[1], Perspective.zFar + 1.0);
      depth = max(len, _addCoinLine(lanes[2], 6));
    } else {
      // breather: a long line of coins (rarely with a key at the end)
      final r2 = _random.nextDouble();
      depth = _addCoinLine(
        lanes[0],
        8,
        withKey: r2 < 0.15,
        withRocket: r2 >= 0.15 && r2 < 0.40 && _rocketTimeLeft <= 0,
      );
    }
    return depth;
  }

  void _addTrain(int lane, double len) {
    final train = TrainObstacle(
      persp: persp,
      player: player,
      speedProvider: () => zSpeed,
      lane: lane,
      z: Perspective.zFar,
      length: len,
      colorName: TrainObstacle.colors[_random.nextInt(TrainObstacle.colors.length)],
      onHitPlayer: _onHitObstacle,
      onHopOn: _onHopOnTrain,
    );
    add(train);

    // A line of coins lying along the roof: the reason to jump up there. You
    // only collect them while running on the roof. They are drawn right after
    // the train so the roof doesn't hide them.
    if (_random.nextDouble() < _roofCoinChance) {
      final roofH = persp.laneSpacing * 0.92 * TrainObstacle.faceAspect;
      for (var zc = Perspective.zFar + 0.35; zc < Perspective.zFar + len - 0.25; zc += 0.5) {
        _addCoin(lane, zc, height: roofH, onTrain: train);
      }
    }
  }

  void _addLowBarrier(int lane, double z) {
    add(LowBarrier(
      persp: persp,
      player: player,
      speedProvider: () => zSpeed,
      lane: lane,
      z: z,
      onHitPlayer: _onHitObstacle,
    ));
  }

  void _addOverhead(int lane, double z) {
    add(OverheadBarrier(
      persp: persp,
      player: player,
      speedProvider: () => zSpeed,
      lane: lane,
      z: z,
      onHitPlayer: _onHitObstacle,
    ));
  }

  void _addRocket(int lane, double z) {
    add(RocketPickup(
      persp: persp,
      player: player,
      speedProvider: () => zSpeed,
      lane: lane,
      z: z,
      onCollected: _activateRocket,
    ));
  }

  /// Rocket picked up: Jack takes off on autopilot. He flies above everything
  /// (nothing can hurt him), the game steers him toward the coins, and every
  /// coin/key in ALL lanes is pulled in. Swipes are ignored until it ends.
  void _activateRocket() {
    final alreadyFlying = player.isFlying;
    _rocketTimeLeft = _rocketDuration; // grabbing another one just refuels
    rocketText.text = '🚀 Rocket ${_rocketDuration.ceil()}s';
    if (alreadyFlying) return;

    // leave a train roof if he was riding one
    if (_ridingTrain != null) {
      _ridingTrain = null;
      _leftTrain = null;
      player.stopRiding();
    }
    player.startFlying();
    player.priority = 50; // draw above the trains he flies over
    _steerCooldown = 0;
    _spawnRocketTrail();
    _showBanner('🚀 ROCKET!', 'Auto-fly: it grabs every coin (${_rocketDuration.ceil()}s)', 3.0);
    shake(0.2);
  }

  /// A long coin trail that starts just ahead of Jack and lasts the whole
  /// flight, weaving gently between lanes at "flying height".
  void _spawnRocketTrail() {
    final base = min(_startZSpeed + elapsedTime * _zSpeedRamp, _maxZSpeed);
    final trailLen = base * _flySpeedBoost * _rocketDuration;
    var lane = player.currentLane;
    var z = 2.5;
    var segLeft = 0;
    while (z < 2.5 + trailLen - 1.0) {
      if (segLeft <= 0) {
        final options = <int>[lane];
        if (lane > 0) options.add(lane - 1);
        if (lane < 2) options.add(lane + 1);
        lane = options[_random.nextInt(options.length)];
        segLeft = 6 + _random.nextInt(4);
      }
      _addCoin(lane, z, height: 110);
      z += _coinStep;
      segLeft--;
    }
  }

  /// Rocket finished (or the run was reset). On a normal finish he lands on a
  /// train roof if one is under him; otherwise he drops to the track and is
  /// invulnerable for a moment so he can't land inside something.
  void _deactivateRocket({bool landing = true}) {
    final wasFlying = player.isFlying;
    _rocketTimeLeft = 0;
    rocketText.text = '';
    player.stopFlying();
    if (!wasFlying) return;

    if (landing) {
      final under = _trainUnderPlayer();
      if (under != null) {
        _ridingTrain = under;
        _leftTrain = null;
        player.rideElevation = under.bodyHeight;
        player.startRiding(); // priority stays 50 while on the roof
        _showBanner('🚂 Landed on a train!', 'Keep running along the roof', 2.0);
        return;
      }
      player.graceTime = 1.5;
    }
    player.priority = -1000;
  }

  /// Autopilot: every so often, move Jack to the lane with the most pickups
  /// coming up (keys count triple). Purely for looks — the magnet already
  /// collects everything in all lanes.
  void _autoSteer(double dt) {
    _steerCooldown -= dt;
    if (_steerCooldown > 0) return;
    final score = [0.0, 0.0, 0.0];
    for (final e in children.whereType<WorldEntity>()) {
      if (e is! CoinPickup && e is! KeyPickup) continue;
      if (e.z < 1.0 || e.z > 5.0) continue;
      score[e.lane] += (e is KeyPickup ? 3.0 : 1.0) / e.z;
    }
    var best = player.currentLane;
    for (var l = 0; l < score.length; l++) {
      if (score[l] > score[best] * 1.25 + 0.05) best = l;
    }
    if (best != player.currentLane) {
      player.autoMoveToLane(best);
      _steerCooldown = 0.3;
    }
  }

  void _addCoin(int lane, double z, {double height = 0, TrainObstacle? onTrain}) {
    final coin = CoinPickup(
      persp: persp,
      player: player,
      speedProvider: () => zSpeed,
      lane: lane,
      z: z,
      height: height,
      onCollected: () {
        coins++;
        coinText.text = '🪙 $coins';
        _saveDirty = true;
      },
    );
    coin.drawAfter = onTrain;
    add(coin);
  }

  void _addKey(int lane, double z) {
    add(KeyPickup(
      persp: persp,
      player: player,
      speedProvider: () => zSpeed,
      lane: lane,
      z: z,
      onCollected: () {
        keys++;
        keyText.text = '🔑 $keys';
        _save();
      },
    ));
  }

  /// A straight line of coins running away from the camera.
  double _addCoinLine(int lane, int count,
      {double height = 0, bool withKey = false, bool withRocket = false}) {
    for (var i = 0; i < count; i++) {
      final z = Perspective.zFar + i * _coinStep;
      if (withKey && i == count - 1) {
        _addKey(lane, z);
      } else if (withRocket && i == count - 1) {
        _addRocket(lane, z);
      } else {
        _addCoin(lane, z, height: height);
      }
    }
    return count * _coinStep;
  }

  /// Coins that rise and fall like a jump arc (grab them at the top of a jump).
  double _addCoinArc(int lane) {
    const heights = [0.0, 55.0, 95.0, 55.0, 0.0];
    for (var i = 0; i < heights.length; i++) {
      _addCoin(lane, Perspective.zFar + i * _coinStep, height: heights[i]);
    }
    return heights.length * _coinStep;
  }

  // ------------------------------------------------------------ game flow
  /// Writes keys, coins and best score to the device.
  Future<void> _save() async {
    _saveDirty = false;
    _sinceSave = 0;
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setInt('keys', keys);
    await prefs.setInt('coins', coins);
    await prefs.setInt('best_score', bestScore);
  }

  void _onHitObstacle() {
    if (isGameOver) return;
    isGameOver = true;
    player.isGameOver = true;
    isNewBest = score > bestScore;
    if (isNewBest) bestScore = score;
    _save();
    shake(0.35);
    overlays.add('gameOver');
  }

  /// Called by a [TrainObstacle] when the player jumps right as it arrives.
  /// Nudges that train so its nose is just in front of the runner (he lands on
  /// the roof) and starts the ride. The train keeps moving, so he runs along
  /// it. Only one ride at a time.
  void _onHopOnTrain(TrainObstacle train) {
    if (_ridingTrain != null) return;
    _ridingTrain = train;
    _leftTrain = null;
    train.z = 0.96; // nose just in front of the runner -> he's on the roof
    player.rideElevation = train.bodyHeight; // roof height at his depth
    player.startRiding();
    player.priority = 50; // draw on top of the train he's standing on
    if (_roofTips < 2) {
      _roofTips++;
      _showBanner('🚂 On the roof!', 'Run along it and grab the coins', 2.2);
    }
    coins += _hopOnCoinBonus;
    coinText.text = '🪙 $coins';
    _saveDirty = true;
  }

  /// The roof ran out: drop back to the track. The train is NOT removed — it
  /// keeps moving and slides past behind him. His draw priority is restored
  /// later, once that train has cleared (see update()).
  void _endRide() {
    _leftTrain = _ridingTrain;
    _ridingTrain = null;
    player.stopRiding();
  }

  void _clearWorld({bool includePickups = true}) {
    for (final e in children.whereType<WorldEntity>().toList()) {
      if (!includePickups && (e is CoinPickup || e is KeyPickup)) continue;
      e.removeFromParent();
    }
  }

  void reviveWithKey() {
    if (keys <= 0) return;
    keys--;
    keyText.text = '🔑 $keys';
    _save();

    _clearWorld(includePickups: false);
    _resetCorner(resetTheme: false);
    isNewBest = false;
    _ridingTrain = null;
    _leftTrain = null;
    player.stopRiding();
    player.priority = -1000;
    player.isGameOver = false;
    isGameOver = false;
    _distSinceSpawn = 0;
    _nextGap = 2.0;
    overlays.remove('gameOver');
  }

  void restart() {
    _clearWorld();
    _deactivateRocket(landing: false);
    _speedBoost = 1.0;
    player.graceTime = 0;
    isNewBest = false;
    _ridingTrain = null;
    _leftTrain = null;
    player.stopRiding();
    player.priority = -1000;
    player.currentLane = 1;
    player.isGameOver = false;
    player.position = Vector2(laneXPositions[1] - player.size.x / 2, player.position.y);
    isGameOver = false;
    elapsedTime = 0;
    _resetCorner(resetTheme: true);
    _distSinceSpawn = 0;
    _nextGap = 2.0;
    overlays.remove('gameOver');
  }

  // --- All touch input is swipe-based: left/right to change lanes, up to
  // jump, down to slide. One action per swipe. ---
  @override
  void onPanStart(DragStartInfo info) {
    _panDx = 0;
    _panDy = 0;
    _actionFiredThisGesture = false;
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    if (isGameOver || _actionFiredThisGesture) return;
    _panDx += info.delta.global.x;
    _panDy += info.delta.global.y;

    final horizontalPastThreshold = _panDx.abs() > _swipeThreshold;
    final verticalPastThreshold = _panDy.abs() > _swipeThreshold;
    if (!horizontalPastThreshold && !verticalPastThreshold) return;

    _actionFiredThisGesture = true;
    if (_panDx.abs() > _panDy.abs()) {
      _steer(_panDx > 0 ? 1 : -1); // at a junction this turns the corner
    } else {
      _panDy < 0 ? player.jump() : player.slide();
    }
  }

  // --- Keyboard: arrow left/right or A/D to move, Space/Up to jump, Down/S to slide ---
  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (event is KeyDownEvent && !isGameOver) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft || event.logicalKey == LogicalKeyboardKey.keyA) {
        _steer(-1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight || event.logicalKey == LogicalKeyboardKey.keyD) {
        _steer(1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.space || event.logicalKey == LogicalKeyboardKey.arrowUp) {
        player.jump();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown || event.logicalKey == LogicalKeyboardKey.keyS) {
        player.slide();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }
}