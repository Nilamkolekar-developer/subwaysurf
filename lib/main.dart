import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'game/subway_game.dart';

void main() {
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
        // Black letterbox bars fill the window; the actual game renders in
        // a fixed portrait (9:16) box centered inside it — this is what
        // keeps the game truly VERTICAL even on a wide desktop window,
        // without needing to touch native Windows window-sizing code.
        backgroundColor: Colors.black,
        body: Center(
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: GameWidget(
              game: game,
              overlayBuilderMap: {
                'gameOver': (context, SubwayGame game) => GameOverOverlay(game: game),
              },
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
            ElevatedButton(
              onPressed: () => game.restart(),
              child: const Text('Play Again'),
            ),
          ],
        ),
      ),
    );
  }
}