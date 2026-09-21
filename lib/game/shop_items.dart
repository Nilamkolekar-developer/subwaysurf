import 'package:flutter/material.dart';

/// Everything the shop sells. To add a cap colour: add a line to [kCaps], put
/// its sprite sheet in assets/images/ (redcap_sheet_<id>.png) and list that
/// file in pubspec.yaml.

/// Price of one revive key.
const int kKeyPrice = 100;

/// Price of one rocket (used to launch a run already flying).
const int kRocketPrice = 150;

/// Price of one shield (absorbs a single hit; kept until used).
const int kShieldPrice = 120;

/// Price of one 2x-coins boost.
const int kMultiplierPrice = 130;

/// Price of one magnet (auto-collects coins/keys in every lane for a while).
const int kMagnetPrice = 140;

class CapItem {
  final String id;
  final String name;
  final int price; // coins (0 = owned from the start)
  final Color color;

  const CapItem(this.id, this.name, this.price, this.color);

  /// Sprite sheet for Jack wearing this cap (file name inside assets/images/).
  String get sheet => id == 'red' ? 'redcap_sheet.png' : 'redcap_sheet_$id.png';
}

const List<CapItem> kCaps = [
  CapItem('red', 'Classic Red', 0, Color(0xFFE53935)),
  CapItem('blue', 'Sky Blue', 200, Color(0xFF29B6F6)),
  CapItem('green', 'Lime Green', 250, Color(0xFF43D843)),
  CapItem('purple', 'Royal Purple', 300, Color(0xFFA020F0)),
  CapItem('gold', 'Gold', 500, Color(0xFFFFC928)),
];

CapItem capById(String id) =>
    kCaps.firstWhere((c) => c.id == id, orElse: () => kCaps.first);