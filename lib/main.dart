
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:subway_surf_demo/components/daily_mission.dart';
import 'game/shop_items.dart';
import 'game/subway_game.dart';

//bool get _isDesktop => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// Desktop platforms (Windows in particular): launch borderless and filling
/// the whole monitor instead of a small windowed app, so the game feels
/// like a real full-screen title rather than an app in a window. Mobile and
/// web are untouched — window_manager is a no-op there.
// Future<void> _goFullScreenOnDesktop() async {
//   if (!_isDesktop) return;
//   await windowManager.ensureInitialized();
//   const options = WindowOptions(
//     fullScreen: true,
//     backgroundColor: Colors.black,
//     titleBarStyle: TitleBarStyle.hidden,
//   );
//   windowManager.waitUntilReadyToShow(options, () async {
//     await windowManager.setFullScreen(true);
//     await windowManager.show();
//     await windowManager.focus();
//   });

//   // Esc drops out of fullscreen — there's no title bar to grab otherwise.
//   // A global hook (not tied to whichever widget has focus) so it works even
//   // while the game itself is capturing arrow-key/space input.
//   HardwareKeyboard.instance.addHandler((KeyEvent event) {
//     if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
//       windowManager.isFullScreen().then((full) {
//         if (full) windowManager.setFullScreen(false);
//       });
//     }
//     return false; // never consume it — the game's own key handling still runs
//   });
// }

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  //await _goFullScreenOnDesktop();
  runApp(const SubwayApp());
}

class SubwayApp extends StatelessWidget {
  const SubwayApp({super.key});

  @override
  Widget build(BuildContext context) {
    final game = SubwayGame();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        // Fills the whole window — no letterbox box. Lane positions and the
        // rest of the layout are computed from the game's actual size, so
        // this just gives it a wider field of view on a wide window instead
        // of leaving black bars down the sides.
        body: GameWidget(
          game: game,
          overlayBuilderMap: {
            'start': (context, SubwayGame game) => StartOverlay(game: game),
            'hud': (context, SubwayGame game) => HudOverlay(game: game),
            'pause': (context, SubwayGame game) => PauseOverlay(game: game),
            'gameOver': (context, SubwayGame game) => GameOverOverlay(game: game),
            'shop': (context, SubwayGame game) => ShopOverlay(game: game),
            'missions': (context, SubwayGame game) => MissionsOverlay(game: game),
          },
        ),
      ),
    );
  }
}

/// The title screen: shown on launch and whenever a run ends and the player
/// comes back to it via the shop. Play starts a normal run; if a rocket has
/// been bought, a second button launches the run already flying.
class StartOverlay extends StatelessWidget {
  final SubwayGame game;
  const StartOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Container(
        color: Colors.black.withOpacity(0.55),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => game.openShop('start'),
                      icon: const Icon(Icons.menu, color: Colors.white, size: 30),
                      tooltip: 'Menu',
                    ),
                    const Spacer(),
                    if (game.shields > 0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.lightBlueAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.lightBlueAccent),
                        ),
                        child: Text(
                          '🛡 ${game.shields}',
                          style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.amber),
                      ),
                      child: Text(
                        '🪙 ${game.coins}',
                        style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                const Text(
                  '🚇 SUBWAY SURF',
                  style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 1),
                ),
                const SizedBox(height: 6),
                Text('Best: ${game.bestScore}', style: const TextStyle(color: Colors.white60, fontSize: 16)),
                const SizedBox(height: 40),
                SizedBox(
                  width: 220,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () => game.startGame(),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlueAccent),
                    child: const Text('▶  PLAY', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
                  ),
                ),
                const SizedBox(height: 12),
                if (game.rockets > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SizedBox(
                      width: 250,
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: () => game.startGame(withRocket: true),
                        icon: const Text('🚀', style: TextStyle(fontSize: 16)),
                        label: Text('Launch with rocket (${game.rockets})'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepOrangeAccent,
                          side: const BorderSide(color: Colors.deepOrangeAccent),
                        ),
                      ),
                    ),
                  ),
                if (game.multipliers > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SizedBox(
                      width: 250,
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: () => game.startGame(withMultiplier: true),
                        icon: const Text('✨', style: TextStyle(fontSize: 16)),
                        label: Text('Start with 2x coins (${game.multipliers})'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.amber,
                          side: const BorderSide(color: Colors.amber),
                        ),
                      ),
                    ),
                  ),
                if (game.magnets > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SizedBox(
                      width: 250,
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: () => game.startGame(withMagnet: true),
                        icon: const Text('🧲', style: TextStyle(fontSize: 16)),
                        label: Text('Start with magnet (${game.magnets})'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => game.openShop('start'),
                      icon: const Text('🛍'),
                      label: const Text('Shop'),
                      style: TextButton.styleFrom(foregroundColor: Colors.white70),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: () => game.openMissions('start'),
                      icon: const Text('🎯'),
                      label: const Text('Missions'),
                      style: TextButton.styleFrom(foregroundColor: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The ☰ menu icon shown in the corner any time a run is actually playing
/// (not on the title screen, not while paused/shopping/game-over — those
/// screens have their own way back). Tapping it opens the pause menu.
class HudOverlay extends StatelessWidget {
  final SubwayGame game;
  const HudOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 44, right: 8),
          child: Material(
            color: Colors.black45,
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: game.openPause,
              icon: const Icon(Icons.menu, color: Colors.white, size: 24),
              tooltip: 'Menu',
            ),
          ),
        ),
      ),
    );
  }
}

/// The in-run pause menu: freezes the run so Shop and Missions can be
/// reached mid-game too, not just before/after a run.
class PauseOverlay extends StatelessWidget {
  final SubwayGame game;
  const PauseOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Container(
        color: Colors.black.withOpacity(0.75),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⏸ Paused', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('Score: ${game.score}', style: const TextStyle(color: Colors.white70, fontSize: 16)),
                const SizedBox(height: 20),
                SizedBox(
                  width: 210,
                  child: ElevatedButton(
                    onPressed: game.closePause,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlueAccent),
                    child: const Text('▶  Resume'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: 210,
                  child: OutlinedButton.icon(
                    onPressed: () => game.openShop('pause'),
                    icon: const Text('🛍'),
                    label: const Text('Shop'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: 210,
                  child: OutlinedButton.icon(
                    onPressed: () => game.openMissions('pause'),
                    icon: const Text('🎯'),
                    label: const Text('Missions'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: game.quitToMenu,
                  child: const Text('🏠 Quit to menu', style: TextStyle(color: Colors.white54)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GameOverOverlay extends StatefulWidget {
  final SubwayGame game;
  const GameOverOverlay({super.key, required this.game});

  @override
  State<GameOverOverlay> createState() => _GameOverOverlayState();
}

class _GameOverOverlayState extends State<GameOverOverlay> {
  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final hasKey = game.keys > 0;

    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Game Over', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Score: ${game.score}', style: const TextStyle(color: Colors.white70, fontSize: 18)),
            Text('Best: ${game.bestScore}', style: const TextStyle(color: Colors.white54, fontSize: 16)),
            if (game.isNewBest)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('🏆 New best!', style: TextStyle(color: Colors.amberAccent, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            Text('Coins: ${game.coins}', style: const TextStyle(color: Colors.amber, fontSize: 16)),
            const SizedBox(height: 20),
            if (hasKey)
              ElevatedButton.icon(
                onPressed: () => setState(() => game.reviveWithKey()),
                icon: const Text('🔑'),
                label: Text('Revive (${game.keys} key${game.keys == 1 ? '' : 's'} left)'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlueAccent),
              ),
            if (hasKey) const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () => game.openShop('gameOver'),
                  icon: const Text('🛍'),
                  label: const Text('Shop'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => game.openMissions('gameOver'),
                  icon: const Text('🎯'),
                  label: const Text('Missions'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => game.playAgain(),
              child: const Text('Play Again'),
            ),
          ],
        ),
      ),
    );
  }
}


/// The in-game shop: spend saved coins on revive keys and cap colours.
/// Opened from the game-over screen; everything bought is saved on the device.
class ShopOverlay extends StatefulWidget {
  final SubwayGame game;
  const ShopOverlay({super.key, required this.game});

  @override
  State<ShopOverlay> createState() => _ShopOverlayState();
}

class _ShopOverlayState extends State<ShopOverlay> {
  String? _message;
  bool _isError = false;

  SubwayGame get game => widget.game;

  void _say(String text, {bool error = false}) {
    setState(() {
      _message = text;
      _isError = error;
    });
  }

  void _buyKey() {
    if (game.buyKey()) {
      _say('Bought a key! 🔑');
    } else {
      _say('Not enough coins for a key', error: true);
    }
  }

  void _buyRocket() {
    if (game.buyRocket()) {
      _say('Bought a rocket! 🚀');
    } else {
      _say('Not enough coins for a rocket', error: true);
    }
  }

  void _buyShield() {
    if (game.buyShield()) {
      _say('Bought a shield! 🛡');
    } else {
      _say('Not enough coins for a shield', error: true);
    }
  }

  void _buyMultiplier() {
    if (game.buyMultiplier()) {
      _say('Bought a 2x boost! ✨');
    } else {
      _say('Not enough coins for a boost', error: true);
    }
  }

  void _buyMagnet() {
    if (game.buyMagnet()) {
      _say('Bought a magnet! 🧲');
    } else {
      _say('Not enough coins for a magnet', error: true);
    }
  }

  void _tapCap(CapItem cap) {
    if (game.ownedCaps.contains(cap.id)) {
      game.equipCap(cap.id);
      _say('${cap.name} equipped');
    } else if (game.buyCap(cap.id)) {
      _say('${cap.name} bought and equipped!');
    } else {
      _say('Not enough coins for ${cap.name}', error: true);
    }
  }

  BoxDecoration _cardDecoration({Color? highlight}) => BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlight ?? Colors.white24, width: highlight != null ? 2 : 1),
      );

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      );

  Widget _keyCard() {
    final canAfford = game.coins >= kKeyPrice;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          const Text('🔑', style: TextStyle(fontSize: 36)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Revive key',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  'A second chance after a crash · you have ${game.keys}',
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _buyKey,
            style: ElevatedButton.styleFrom(
              backgroundColor: canAfford ? Colors.amber : Colors.grey.shade700,
              foregroundColor: canAfford ? Colors.black : Colors.white54,
            ),
            child: Text('🪙 $kKeyPrice'),
          ),
        ],
      ),
    );
  }

  /// Shared layout for the power-up cards: icon + description + Buy, plus an
  /// optional full-width "Use now" button when at least one is owned.
  Widget _powerCard({
    required String emoji,
    required String name,
    required String description,
    required int price,
    required int owned,
    required Color accent,
    required VoidCallback onBuy,
    String useLabel = 'Use now',
    VoidCallback? onUseNow,
  }) {
    final canAfford = game.coins >= price;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 36)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      '$description · you have $owned',
                      style: const TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: onBuy,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canAfford ? accent : Colors.grey.shade700,
                  foregroundColor: canAfford ? Colors.black : Colors.white54,
                ),
                child: Text('🪙 $price'),
              ),
            ],
          ),
          if (owned > 0 && onUseNow != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onUseNow,
                icon: Text(emoji),
                label: Text(useLabel),
                style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _capCard(CapItem cap) {
    final owned = game.ownedCaps.contains(cap.id);
    final equipped = game.equippedCap == cap.id;
    final canAfford = game.coins >= cap.price;

    final String status;
    final Color statusColor;
    if (equipped) {
      status = 'Equipped';
      statusColor = Colors.lightGreenAccent;
    } else if (owned) {
      status = 'Tap to wear';
      statusColor = Colors.white70;
    } else {
      status = '🪙 ${cap.price}';
      statusColor = canAfford ? Colors.amber : Colors.white38;
    }

    return GestureDetector(
      onTap: () => _tapCap(cap),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: _cardDecoration(highlight: equipped ? Colors.lightGreenAccent : null),
        child: Column(
          children: [
            // Jack wearing this cap: first frame of its sprite sheet (8 frames wide)
            Expanded(
              child: FittedBox(
                fit: BoxFit.contain,
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: 1 / 8,
                    child: Image.asset(
                      'assets/images/${cap.sheet}',
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              cap.name,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              status,
              style: TextStyle(color: statusColor, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Container(
        color: Colors.black.withOpacity(0.88),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text(
                      '🛍 Shop',
                      style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.amber),
                      ),
                      child: Text(
                        '🪙 ${game.coins}',
                        style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    children: [
                      _sectionTitle('Keys'),
                      _keyCard(),
                      const SizedBox(height: 18),
                      _sectionTitle('Rockets'),
                      _powerCard(
                        emoji: '🚀',
                        name: 'Rocket',
                        description: 'Start a run already flying',
                        price: kRocketPrice,
                        owned: game.rockets,
                        accent: Colors.deepOrangeAccent,
                        onBuy: _buyRocket,
                        useLabel: 'Use now — launch flying',
                        onUseNow: game.useRocketNow,
                      ),
                      const SizedBox(height: 18),
                      _sectionTitle('Shields'),
                      _powerCard(
                        emoji: '🛡',
                        name: 'Shield',
                        description: 'Absorbs your next hit automatically',
                        price: kShieldPrice,
                        owned: game.shields,
                        accent: Colors.lightBlueAccent,
                        onBuy: _buyShield,
                      ),
                      const SizedBox(height: 18),
                      _sectionTitle('2x Coins'),
                      _powerCard(
                        emoji: '✨',
                        name: 'Coin boost',
                        description: 'Doubles coins collected for 10s',
                        price: kMultiplierPrice,
                        owned: game.multipliers,
                        accent: Colors.amber,
                        onBuy: _buyMultiplier,
                        useLabel: 'Use now — start boosted',
                        onUseNow: game.useMultiplierNow,
                      ),
                      const SizedBox(height: 18),
                      _sectionTitle('Magnets'),
                      _powerCard(
                        emoji: '🧲',
                        name: 'Magnet',
                        description: 'Auto-collects coins & keys for 8s',
                        price: kMagnetPrice,
                        owned: game.magnets,
                        accent: Colors.redAccent,
                        onBuy: _buyMagnet,
                        useLabel: 'Use now — start with magnet',
                        onUseNow: game.useMagnetNow,
                      ),
                      const SizedBox(height: 18),
                      _sectionTitle('Cap colours'),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.82,
                        children: [for (final cap in kCaps) _capCard(cap)],
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 24,
                  child: _message == null
                      ? null
                      : Text(
                          _message!,
                          style: TextStyle(
                            color: _isError ? Colors.redAccent : Colors.lightGreenAccent,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: game.closeShop,
                    child: const Text('Back'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// The daily-missions list: three fixed missions that reset each calendar
/// day. Progress builds up across runs; claim a finished one for its coins.
class MissionsOverlay extends StatefulWidget {
  final SubwayGame game;
  const MissionsOverlay({super.key, required this.game});

  @override
  State<MissionsOverlay> createState() => _MissionsOverlayState();
}

class _MissionsOverlayState extends State<MissionsOverlay> {
  String? _message;
  SubwayGame get game => widget.game;

  void _claim(MissionDef def) {
    if (game.claimMission(def.id)) {
      setState(() => _message = '+${def.reward} coins!');
    }
  }

  Widget _missionCard(MissionDef def) {
    final progress = game.missionProgress(def.id);
    final claimed = game.claimedMissions.contains(def.id);
    final done = progress >= def.target;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: claimed ? Colors.lightGreenAccent : Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  def.title,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Text('🪙 ${def.reward}', style: const TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (progress / def.target).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white12,
              color: done ? Colors.lightGreenAccent : Colors.lightBlueAccent,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${progress > def.target ? def.target : progress} / ${def.target}',
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
              if (claimed)
                const Text('Claimed ✓', style: TextStyle(color: Colors.lightGreenAccent, fontSize: 13, fontWeight: FontWeight.w600))
              else
                ElevatedButton(
                  onPressed: done ? () => _claim(def) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: done ? Colors.amber : Colors.grey.shade700,
                    foregroundColor: done ? Colors.black : Colors.white38,
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text('Claim'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Container(
        color: Colors.black.withOpacity(0.88),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text(
                      '🎯 Daily Missions',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.amber),
                      ),
                      child: Text(
                        '🪙 ${game.coins}',
                        style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView(
                    children: [for (final m in kDailyMissions) _missionCard(m)],
                  ),
                ),
                SizedBox(
                  height: 22,
                  child: _message == null
                      ? null
                      : Text(
                          _message!,
                          style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: game.closeMissions,
                    child: const Text('Back'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}