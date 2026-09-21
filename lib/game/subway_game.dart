import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subway_surf_demo/components/daily_mission.dart';
import 'package:subway_surf_demo/components/magnetic_pickup.dart';
import 'package:subway_surf_demo/components/sheild_pickup.dart';
import '../components/rocket_pickup.dart';
import '../components/coin_pickup.dart';
import '../components/game_background.dart';
import '../components/key_pickup.dart';
import '../components/low_barrier.dart';
import '../components/multiplier_pickup.dart';
import '../components/overhead_barrier.dart';
import '../components/runner_player.dart';
import '../components/train_obstacle.dart';
import '../components/world_entity.dart';
import 'perspective.dart';
import 'shop_items.dart';

class SubwayGame extends FlameGame with HasCollisionDetection, PanDetector, KeyboardEvents {
  late RunnerPlayer player;
  late Perspective persp;
  late TextComponent scoreText;
  late TextComponent coinText;
  late TextComponent keyText;
  late TextComponent shieldText;
  late TextComponent rocketText;
  late TextComponent multiplierText;
  late TextComponent magnetText;
  late TextComponent bestText;
  late TextComponent bannerTitle; // big message in the upper-middle of the screen
  late TextComponent bannerSub;
  double _bannerTime = 0;
  int _roofTips = 0; // roof tip is only shown for the first couple of hop-ons
  late List<double> laneXPositions;

  // ---- world speed (depth-units per second; 1.0 is the runner's depth) ----
  // Tune these three to change how the run feels:
  static const double _startZSpeed = 2.4; // gentle start
  static const double _zSpeedRamp = 0.045; // extra speed per second played
  static const double _maxZSpeed = 9.0; // top speed (reached after ~2.5 min)

  /// Pace at which the run animation plays at its normal speed; the legs only
  /// speed up once the world is faster than this.
  static const double _legsBaseZSpeed = 3.7;

  double elapsedTime = 0;
  int score = 0;
  int coins = 0;
  int keys = 0;
  int rockets = 0; // bought in the shop, spent to launch a run already flying
  int shields = 0; // bought or found; absorbs one hit each, kept until used
  int multipliers = 0; // bought in the shop, spent to start a run at 2x coins
  int magnets = 0; // bought in the shop, spent to start a run auto-collecting
  int bestScore = 0;
  bool isNewBest = false; // this run beat the saved best (shown on game over)

  /// True once the player has tapped Play/Launch on the start screen. Nothing
  /// moves or spawns before that.
  bool started = false;
  bool _tipShown = false; // the "swipe up to jump on trains" tip: first run only
  String _returnOverlay = 'start'; // where the shop/missions screen returns to
  bool isPaused = false; // set by the in-run pause menu

  // ---- daily missions: progress resets the first time the app opens on a
  // new calendar day (see kDailyMissions in daily_missions.dart) ----
  String _dailyDate = '';
  int dailyCoins = 0;
  int dailyHops = 0;
  int dailyBestScore = 0;
  Set<String> claimedMissions = {};

  // ---- saved progress: keys, coins and best score survive closing the app ----
  // (Plain variables live in memory only, so without this they reset to 0 on
  // every launch.)
  SharedPreferences? _prefs;

  // ---- shop: what you own and what Jack is wearing (saved on the device) ----
  Set<String> ownedCaps = {'red'};
  String equippedCap = 'red';
  bool _saveDirty = false; // coins changed since the last save
  double _sinceSave = 0;
  static const double _saveEvery = 2.0; // seconds, at most, between coin saves
  bool isGameOver = false;

  /// Everything (background, trains, coins) reads this, so it all moves at
  /// one shared speed and freezes together when the game ends.
  double get zSpeed => (isGameOver || !started || isPaused)
      ? 0
      : min(_startZSpeed + elapsedTime * _zSpeedRamp, _maxZSpeed) * _speedBoost;

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

  // ---- coin multiplier + magnet power-ups ----
  double _multiplierTimeLeft = 0;
  static const double _multiplierDuration = 10.0;
  double _magnetTimeLeft = 0;
  static const double _magnetDuration = 8.0;

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
    rockets = _prefs?.getInt('rockets') ?? 0;
    shields = _prefs?.getInt('shields') ?? 0;
    multipliers = _prefs?.getInt('multipliers') ?? 0;
    magnets = _prefs?.getInt('magnets') ?? 0;
    coins = _prefs?.getInt('coins') ?? 0;
    bestScore = _prefs?.getInt('best_score') ?? 0;
    ownedCaps = (_prefs?.getStringList('owned_caps') ?? const ['red']).toSet()..add('red');
    equippedCap = _prefs?.getString('equipped_cap') ?? 'red';
    if (!ownedCaps.contains(equippedCap)) equippedCap = 'red';

    // Daily missions: keep progress if it's the same day, otherwise reset.
    _dailyDate = _todayKey();
    if (_prefs?.getString('daily_date') == _dailyDate) {
      dailyCoins = _prefs?.getInt('daily_coins') ?? 0;
      dailyHops = _prefs?.getInt('daily_hops') ?? 0;
      dailyBestScore = _prefs?.getInt('daily_best_score') ?? 0;
      claimedMissions = (_prefs?.getStringList('daily_claimed') ?? const []).toSet();
    }

    // Lane spacing (and everything scaled off it — trains, coins, the
    // player) is tuned for a portrait-ish width. On a very wide monitor now
    // filling the whole screen, using the full width here would spread
    // lanes out far more than that art was ever sized for (tiny player,
    // huge obstacles). So gameplay stays laid out in a portrait-shaped
    // "play width", centered in the middle of the screen — while the sky,
    // ground and side walls (GameBackground) still stretch to the actual
    // full screen width, so there's no visible seam or black bar either
    // side, just extra track/skyline width.
    final playWidth = min(size.x, size.y * 9 / 16);
    final xOffset = (size.x - playWidth) / 2;
    laneXPositions = [
      xOffset + playWidth * 0.25,
      xOffset + playWidth * 0.5,
      xOffset + playWidth * 0.75,
    ];

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

    add(GameBackground(persp: persp, speedProvider: () => zSpeed));

    player = RunnerPlayer(laneXPositions: laneXPositions, fixedY: fixedY);
    player.capId = equippedCap;
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

    shieldText = TextComponent(
      text: '🛡 $shields',
      position: Vector2(16, 96),
      priority: 1000,
      textRenderer: TextPaint(
        style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
    add(shieldText);

    rocketText = TextComponent(
      text: '',
      position: Vector2(16, 122),
      priority: 1000,
      textRenderer: TextPaint(
        style: const TextStyle(color: Colors.deepOrangeAccent, fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
    add(rocketText);

    multiplierText = TextComponent(
      text: '',
      position: Vector2(16, 148),
      priority: 1000,
      textRenderer: TextPaint(
        style: const TextStyle(color: Colors.amberAccent, fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
    add(multiplierText);

    magnetText = TextComponent(
      text: '',
      position: Vector2(16, 174),
      priority: 1000,
      textRenderer: TextPaint(
        style: const TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
    add(magnetText);

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

    overlays.add('start');
  }

  /// Calendar-day key used to reset daily-mission progress.
  String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
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
    player.shielded = shields > 0; // visual reminder, even before a run starts
    if (isGameOver || !started || isPaused) return;

    elapsedTime += dt;
    _speedBoost += ((player.isFlying ? _flySpeedBoost : 1.0) - _speedBoost) * min(1.0, 3 * dt);
    score = elapsedTime.floor();
    scoreText.text = 'Score: $score';
    bestText.text = 'Best: ${max(bestScore, score)}';
    if (score > dailyBestScore) {
      dailyBestScore = score;
      _saveDirty = true;
    }

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
    if (_multiplierTimeLeft > 0) {
      _multiplierTimeLeft -= dt;
      multiplierText.text = _multiplierTimeLeft <= 0 ? '' : '✨ x2 ${_multiplierTimeLeft.ceil()}s';
    }
    if (_magnetTimeLeft > 0) {
      _magnetTimeLeft -= dt;
      if (_magnetTimeLeft <= 0) {
        _deactivateMagnet();
      } else {
        magnetText.text = '🧲 ${_magnetTimeLeft.ceil()}s';
      }
    }
    if (player.isFlying) _autoSteer(dt);

    // legs keep up with the track as the game speeds up
    player.runSpeed = (zSpeed / _legsBaseZSpeed).clamp(1.0, 1.7).toDouble();

    _distSinceSpawn += zSpeed * dt;
    if (_distSinceSpawn >= _nextGap) {
      _distSinceSpawn = 0;
      final depth = _spawnPattern();
      // next pattern starts once this one has cleared plus a reaction gap
      // that tightens slowly as you survive longer
      final minGap = (2.4 - elapsedTime * 0.01).clamp(1.5, 2.4).toDouble();
      _nextGap = depth + minGap;
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
      // breather: a long line of coins (rarely with a power-up at the end)
      final r2 = _random.nextDouble();
      depth = _addCoinLine(
        lanes[0],
        8,
        withKey: r2 < 0.12,
        withRocket: r2 >= 0.12 && r2 < 0.30 && _rocketTimeLeft <= 0,
        withShield: r2 >= 0.30 && r2 < 0.42,
        withMultiplier: r2 >= 0.42 && r2 < 0.54 && _multiplierTimeLeft <= 0,
        withMagnet: r2 >= 0.54 && r2 < 0.66 && _magnetTimeLeft <= 0,
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

  void _addShield(int lane, double z) {
    add(ShieldPickup(
      persp: persp,
      player: player,
      speedProvider: () => zSpeed,
      lane: lane,
      z: z,
      onCollected: () {
        shields++;
        shieldText.text = '🛡 $shields';
        _save();
      },
    ));
  }

  void _addMultiplier(int lane, double z) {
    add(MultiplierPickup(
      persp: persp,
      player: player,
      speedProvider: () => zSpeed,
      lane: lane,
      z: z,
      onCollected: _activateMultiplier,
    ));
  }

  void _addMagnet(int lane, double z) {
    add(MagnetPickup(
      persp: persp,
      player: player,
      speedProvider: () => zSpeed,
      lane: lane,
      z: z,
      onCollected: _activateMagnet,
    ));
  }

  /// 2x-coins picked up: every coin collected while this is running counts
  /// double. Grabbing another one just refuels the timer.
  void _activateMultiplier() {
    _multiplierTimeLeft = _multiplierDuration;
    multiplierText.text = '✨ x2 ${_multiplierDuration.ceil()}s';
    _showBanner('✨ 2x COINS!', 'Every coin counts double (${_multiplierDuration.ceil()}s)', 2.5);
  }

  /// Magnet picked up: coins and keys in every lane stream toward Jack and
  /// are collected automatically — no flying, he still has to dodge.
  void _activateMagnet() {
    _magnetTimeLeft = _magnetDuration;
    magnetText.text = '🧲 ${_magnetDuration.ceil()}s';
    player.hasMagnet = true;
    _showBanner('🧲 MAGNET!', 'Coins & keys are drawn to you (${_magnetDuration.ceil()}s)', 2.5);
  }

  void _deactivateMagnet() {
    _magnetTimeLeft = 0;
    magnetText.text = '';
    player.hasMagnet = false;
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
        final gained = _multiplierTimeLeft > 0 ? 2 : 1;
        coins += gained;
        dailyCoins += gained;
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
  double _addCoinLine(int lane, int count, {
    double height = 0,
    bool withKey = false,
    bool withRocket = false,
    bool withShield = false,
    bool withMultiplier = false,
    bool withMagnet = false,
  }) {
    for (var i = 0; i < count; i++) {
      final z = Perspective.zFar + i * _coinStep;
      if (withKey && i == count - 1) {
        _addKey(lane, z);
      } else if (withRocket && i == count - 1) {
        _addRocket(lane, z);
      } else if (withShield && i == count - 1) {
        _addShield(lane, z);
      } else if (withMultiplier && i == count - 1) {
        _addMultiplier(lane, z);
      } else if (withMagnet && i == count - 1) {
        _addMagnet(lane, z);
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
  // ------------------------------------------------------------------ shop
  /// Buys one revive key. Returns false if you can't afford it.
  bool buyKey() {
    if (coins < kKeyPrice) return false;
    coins -= kKeyPrice;
    keys++;
    coinText.text = '🪙 $coins';
    keyText.text = '🔑 $keys';
    _save();
    return true;
  }

  /// Buys one rocket. Returns false if you can't afford it.
  bool buyRocket() {
    if (coins < kRocketPrice) return false;
    coins -= kRocketPrice;
    rockets++;
    coinText.text = '🪙 $coins';
    _save();
    return true;
  }

  /// Buys one shield. Returns false if you can't afford it.
  bool buyShield() {
    if (coins < kShieldPrice) return false;
    coins -= kShieldPrice;
    shields++;
    coinText.text = '🪙 $coins';
    shieldText.text = '🛡 $shields';
    _save();
    return true;
  }

  /// Buys one 2x-coins boost. Returns false if you can't afford it.
  bool buyMultiplier() {
    if (coins < kMultiplierPrice) return false;
    coins -= kMultiplierPrice;
    multipliers++;
    coinText.text = '🪙 $coins';
    _save();
    return true;
  }

  /// Buys one magnet. Returns false if you can't afford it.
  bool buyMagnet() {
    if (coins < kMagnetPrice) return false;
    coins -= kMagnetPrice;
    magnets++;
    coinText.text = '🪙 $coins';
    _save();
    return true;
  }

  /// Claims a completed daily mission's coin reward. Returns false if it
  /// isn't finished yet or was already claimed today.
  bool claimMission(String id) {
    if (claimedMissions.contains(id)) return false;
    final def = kDailyMissions.firstWhere((m) => m.id == id, orElse: () => kDailyMissions.first);
    if (missionProgress(id) < def.target) return false;
    claimedMissions.add(id);
    coins += def.reward;
    coinText.text = '🪙 $coins';
    _save();
    return true;
  }

  /// Today's progress toward a mission by id (see kDailyMissions).
  int missionProgress(String id) {
    switch (id) {
      case 'coins':
        return dailyCoins;
      case 'hops':
        return dailyHops;
      case 'score':
        return dailyBestScore;
      default:
        return 0;
    }
  }

  /// Buys a cap colour and puts it on. Returns false if already owned or too
  /// expensive.
  bool buyCap(String id) {
    final cap = capById(id);
    if (ownedCaps.contains(id) || coins < cap.price) return false;
    coins -= cap.price;
    ownedCaps.add(id);
    coinText.text = '🪙 $coins';
    equipCap(id); // also saves
    return true;
  }

  /// Wear a cap you own.
  void equipCap(String id) {
    if (!ownedCaps.contains(id)) return;
    equippedCap = id;
    player.setCap(id);
    _save();
  }

  /// Opens the shop. [from] is the overlay it should return to when closed:
  /// 'start', 'gameOver' or 'pause'.
  void openShop(String from) {
    _returnOverlay = from;
    overlays.remove(from);
    overlays.add('shop');
  }

  void closeShop() {
    overlays.remove('shop');
    overlays.add(_returnOverlay);
  }

  /// Opens the daily-missions list. [from] is the overlay it returns to.
  void openMissions(String from) {
    _returnOverlay = from;
    overlays.remove(from);
    overlays.add('missions');
  }

  void closeMissions() {
    overlays.remove('missions');
    overlays.add(_returnOverlay);
  }

  /// The in-run pause menu, opened from the ☰ icon that's visible any time
  /// a run is actually playing.
  void openPause() {
    isPaused = true;
    overlays.remove('hud');
    overlays.add('pause');
  }

  void closePause() {
    isPaused = false;
    overlays.remove('pause');
    overlays.add('hud');
  }

  /// Bails out of the current run back to the title screen.
  void quitToMenu() {
    overlays.remove('pause');
    overlays.remove('hud');
    isPaused = false;
    restart();
    started = false;
    overlays.add('start');
  }

  /// Begins the run: hides the start screen and lets the world move.
  /// [withRocket] / [withMultiplier] / [withMagnet] each spend one of that
  /// item (if owned) and activate it immediately.
  void startGame({bool withRocket = false, bool withMultiplier = false, bool withMagnet = false}) {
    overlays.remove('start');
    started = true;
    overlays.add('hud');
    if (!_tipShown) {
      _tipShown = true;
      _showBanner('Swipe UP to jump onto trains', 'Coins are waiting on the roof!', 4.0);
    }
    if (withRocket && rockets > 0) {
      rockets--;
      _save();
      _activateRocket();
    }
    if (withMultiplier && multipliers > 0) {
      multipliers--;
      _save();
      _activateMultiplier();
    }
    if (withMagnet && magnets > 0) {
      magnets--;
      _save();
      _activateMagnet();
    }
  }

  /// Closes the shop and jumps straight into an already-boosted run. From
  /// the start screen that's just starting; from game over it restarts
  /// first; from the pause menu it resumes the current run instantly boosted.
  void _beginFreshRun() {
    overlays.remove('shop');
    switch (_returnOverlay) {
      case 'pause':
        isPaused = false;
        overlays.remove('pause');
        overlays.add('hud');
        break;
      case 'start':
        overlays.remove('start');
        started = true;
        overlays.add('hud');
        if (!_tipShown) {
          _tipShown = true;
          _showBanner('Swipe UP to jump onto trains', 'Coins are waiting on the roof!', 4.0);
        }
        break;
      case 'gameOver':
      default:
        restart(); // also clears the 'gameOver' overlay and resets the world
        overlays.add('hud');
        break;
    }
  }

  /// Shop "Use now" buttons: spend one and jump straight into an already
  /// boosted run.
  void useRocketNow() {
    if (rockets <= 0) return;
    rockets--;
    _save();
    _beginFreshRun();
    _activateRocket();
  }

  void useMultiplierNow() {
    if (multipliers <= 0) return;
    multipliers--;
    _save();
    _beginFreshRun();
    _activateMultiplier();
  }

  void useMagnetNow() {
    if (magnets <= 0) return;
    magnets--;
    _save();
    _beginFreshRun();
    _activateMagnet();
  }

  /// Writes keys, coins, power-ups, best score and daily-mission progress to
  /// the device.
  Future<void> _save() async {
    _saveDirty = false;
    _sinceSave = 0;
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setInt('keys', keys);
    await prefs.setInt('rockets', rockets);
    await prefs.setInt('shields', shields);
    await prefs.setInt('multipliers', multipliers);
    await prefs.setInt('magnets', magnets);
    await prefs.setInt('coins', coins);
    await prefs.setInt('best_score', bestScore);
    await prefs.setStringList('owned_caps', ownedCaps.toList());
    await prefs.setString('equipped_cap', equippedCap);
    await prefs.setString('daily_date', _dailyDate);
    await prefs.setInt('daily_coins', dailyCoins);
    await prefs.setInt('daily_hops', dailyHops);
    await prefs.setInt('daily_best_score', dailyBestScore);
    await prefs.setStringList('daily_claimed', claimedMissions.toList());
  }

  void _onHitObstacle() {
    if (isGameOver) return;
    if (shields > 0) {
      shields--;
      shieldText.text = '🛡 $shields';
      _save();
      player.graceTime = 1.2; // brief invulnerability so he doesn't land in it again
      shake(0.3);
      _showBanner('🛡 Shield absorbed the hit!', 'Shields left: $shields', 2.0);
      return;
    }
    isGameOver = true;
    player.isGameOver = true;
    isNewBest = score > bestScore;
    if (isNewBest) bestScore = score;
    _save();
    shake(0.35);
    overlays.remove('hud');
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
    dailyCoins += _hopOnCoinBonus;
    dailyHops++;
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
    overlays.add('hud');
  }

  void restart() {
    _clearWorld();
    _deactivateRocket(landing: false);
    _multiplierTimeLeft = 0;
    multiplierText.text = '';
    _deactivateMagnet();
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
    _distSinceSpawn = 0;
    _nextGap = 2.0;
    overlays.remove('gameOver');
  }

  /// "Play Again" on the game-over screen: restarts and brings the ☰ menu
  /// icon back (quitToMenu also calls restart(), but goes to the title
  /// screen instead, so that one deliberately leaves the HUD off).
  void playAgain() {
    restart();
    overlays.add('hud');
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
    if (isGameOver || !started || isPaused || _actionFiredThisGesture) return;
    _panDx += info.delta.global.x;
    _panDy += info.delta.global.y;

    final horizontalPastThreshold = _panDx.abs() > _swipeThreshold;
    final verticalPastThreshold = _panDy.abs() > _swipeThreshold;
    if (!horizontalPastThreshold && !verticalPastThreshold) return;

    _actionFiredThisGesture = true;
    if (_panDx.abs() > _panDy.abs()) {
      _panDx > 0 ? player.moveRight() : player.moveLeft();
    } else {
      _panDy < 0 ? player.jump() : player.slide();
    }
  }

  // --- Keyboard: arrow left/right or A/D to move, Space/Up to jump, Down/S to slide ---
  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (event is KeyDownEvent && !isGameOver && started && !isPaused) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft || event.logicalKey == LogicalKeyboardKey.keyA) {
        player.moveLeft();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight || event.logicalKey == LogicalKeyboardKey.keyD) {
        player.moveRight();
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