import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Sound and haptics for live game events. Both can be switched off from
/// Settings, and neither can ever crash the app: every call is wrapped.
///
/// The three clips live in assets/sounds/ (short generated tones).
class FeedbackService {
  FeedbackService();

  bool soundEnabled = true;
  bool hapticsEnabled = true;

  final AudioPlayer _score = AudioPlayer();
  final AudioPlayer _over = AudioPlayer();
  final AudioPlayer _best = AudioPlayer();

  Future<void> _play(AudioPlayer player, String asset) async {
    if (!soundEnabled) return;
    try {
      await player.stop();
      await player.play(AssetSource(asset));
    } catch (_) {
      // No audio device / asset missing: ignore, the game goes on.
    }
  }

  Future<void> _haptic(Future<void> Function() pattern) async {
    if (!hapticsEnabled) return;
    try {
      await pattern();
    } catch (_) {
      // Not supported on this device.
    }
  }

  /// A basket was scored.
  Future<void> shotScored() async {
    await _haptic(HapticFeedback.mediumImpact);
    await _play(_score, 'sounds/score.wav');
  }

  /// The game just ended.
  Future<void> gameOver() async {
    await _haptic(HapticFeedback.heavyImpact);
    await _play(_over, 'sounds/gameover.wav');
  }

  /// The game ended with a new high score.
  Future<void> newHighScore() async {
    await _haptic(() async {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 140));
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 140));
      await HapticFeedback.heavyImpact();
    });
    await _play(_best, 'sounds/highscore.wav');
  }

  /// A light tap for buttons (PIN keys, test shots).
  Future<void> tap() async {
    await _haptic(HapticFeedback.selectionClick);
  }

  void dispose() {
    _score.dispose();
    _over.dispose();
    _best.dispose();
  }
}
