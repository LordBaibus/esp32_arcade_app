import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'common_widgets.dart';
import 'esp32_service.dart';
import 'providers.dart';

const Color _ledColor = Color(0xFFFF9F0A);
const Color _ledOff = Color(0xFF5B4A2C);

/// Phone copy of the three LED boards on the machine (Time, Score, High
/// Score). It follows the live status, and every time a basket is scored the
/// score board flashes and a "+2" floats up from it.
class Scoreboard extends ConsumerStatefulWidget {
  const Scoreboard({super.key});

  @override
  ConsumerState<Scoreboard> createState() => _ScoreboardState();
}

class _ScoreboardState extends ConsumerState<Scoreboard> with SingleTickerProviderStateMixin {
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  int _burstPoints = 2;

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  void _onShot() {
    _burstPoints = ref.read(linkProvider).status.pointsPerShot;
    _burst.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    // A shot = the machine's per-game shot counter went up by a little.
    ref.listen<int>(linkProvider.select((s) => s.status.gameShots), (previous, next) {
      if (previous != null && next > previous && next - previous <= 3) _onShot();
    });

    final link = ref.watch(linkProvider);
    final status = link.status;
    final online = link.isOnline;

    final timeText = online ? status.timeBoardText : '--';
    final scoreText = online ? '${status.score}' : '--';
    final highText = online ? '${status.highScore}' : '--';

    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Live Scoreboard', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              _RunBadge(status: status, online: online),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: _burst,
            builder: (context, _) {
              final t = _burst.value;
              // 0 -> 1 -> 0 pulse over the animation, used for the flash/scale.
              final pulse = t == 0 ? 0.0 : math.sin(math.pi * t);
              return Row(
                children: [
                  Expanded(
                    child: _LedBoard(
                      label: 'TIME',
                      text: timeText,
                      fontSize: 40,
                      lit: online,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Transform.scale(
                          scale: 1 + 0.08 * pulse,
                          child: _LedBoard(
                            label: 'SCORE',
                            text: scoreText,
                            fontSize: 40,
                            lit: online,
                            glow: pulse,
                          ),
                        ),
                        if (t > 0 && t < 1)
                          Positioned(
                            right: 10,
                            top: 4 - 44 * Curves.easeOut.transform(t),
                            child: Opacity(
                              opacity: (1 - t).clamp(0.0, 1.0),
                              child: Text(
                                '+$_burstPoints',
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  color: CupertinoColors.activeGreen,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          _LedBoard(
            label: 'HIGH SCORE',
            text: highText,
            fontSize: 28,
            lit: online,
            compact: true,
          ),
          const SizedBox(height: 14),
          _ProgressLine(status: status, online: online),
        ],
      ),
    );
  }
}

/// One dot-matrix style board: dark panel, glowing digits.
class _LedBoard extends StatelessWidget {
  const _LedBoard({
    required this.label,
    required this.text,
    required this.fontSize,
    required this.lit,
    this.glow = 0,
    this.compact = false,
  });

  final String label;
  final String text;
  final double fontSize;
  final bool lit;

  /// 0..1 extra brightness (the flash when a shot scores).
  final double glow;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = lit ? Color.lerp(_ledColor, const Color(0xFFFFE0A3), glow)! : _ledOff;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 8 : 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B0D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2B2B30)),
        boxShadow: [
          if (lit && glow > 0)
            BoxShadow(color: _ledColor.withValues(alpha: 0.55 * glow), blurRadius: 22, spreadRadius: 1),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: Color(0xFF8E8E93),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                text,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  shadows: lit
                      ? [Shadow(color: color.withValues(alpha: 0.75), blurRadius: 10)]
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Coloured pill: what the machine is doing right now.
class _RunBadge extends StatelessWidget {
  const _RunBadge({required this.status, required this.online});

  final MachineStatus status;
  final bool online;

  @override
  Widget build(BuildContext context) {
    late final String text;
    late final Color color;
    if (!online) {
      text = 'OFFLINE';
      color = CupertinoColors.systemGrey;
    } else if (status.testMode) {
      text = 'SENSOR TEST';
      color = CupertinoColors.systemPurple;
    } else {
      switch (status.run) {
        case MachineRun.playing:
          text = 'ROUND ${status.round} LIVE';
          color = CupertinoColors.systemRed;
        case MachineRun.roundLabel:
        case MachineRun.ready:
        case MachineRun.countdown:
        case MachineRun.start:
          text = 'GET READY';
          color = CupertinoColors.activeOrange;
        case MachineRun.roundGap:
          text = 'ROUND 2 NEXT';
          color = CupertinoColors.activeOrange;
        case MachineRun.gameOver:
          text = 'GAME OVER';
          color = CupertinoColors.systemBlue;
        case MachineRun.idle:
          text = status.credits > 0 ? 'READY TO PLAY' : 'INSERT COIN';
          color = status.credits > 0 ? CupertinoColors.activeGreen : CupertinoColors.systemGrey;
        case MachineRun.unknown:
          text = '...';
          color = CupertinoColors.systemGrey;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4, color: color),
      ),
    );
  }
}

/// Line under the boards: coin progress while idle, qualification progress
/// during Round 1, the points-per-shot reminder during Round 2.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.status, required this.online});

  final MachineStatus status;
  final bool online;

  @override
  Widget build(BuildContext context) {
    if (!online) {
      return Text(
        'Waiting for the machine...',
        style: TextStyle(fontSize: 13, color: dimColor(context)),
      );
    }

    final inGame = status.run.gameActive;
    String left;
    String right;
    double progress;

    if (inGame && status.round == 1) {
      left = 'Reach ${status.qualifyScore} for Round 2';
      right = '${status.score} / ${status.qualifyScore}';
      progress = status.qualifyScore <= 0 ? 1.0 : (status.score / status.qualifyScore).clamp(0.0, 1.0);
    } else if (inGame) {
      left = 'Round 2: +${status.pointsPerShot} per shot';
      right = '${status.gameShots} shots';
      progress = 1.0;
    } else {
      left = status.credits > 0
          ? '${status.credits} credit${status.credits == 1 ? '' : 's'} ready'
          : 'Next credit';
      right = '₱${status.pesoTowardsNextCredit} / ₱${status.pesoPerGame}';
      progress = status.pesoPerGame <= 0
          ? 0.0
          : (status.pesoTowardsNextCredit / status.pesoPerGame).clamp(0.0, 1.0);
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(left, style: captionStyle(context, size: 13)),
            Text(right, style: captionStyle(context, size: 13)),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: GlassProgressIndicator.linear(
            value: progress,
            color: CupertinoColors.activeOrange,
          ),
        ),
      ],
    );
  }
}
