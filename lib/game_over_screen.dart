import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'common_widgets.dart';
import 'game_attempt.dart';
import 'providers.dart';

/// Shown right after a game ends: final score (counting up), shots, whether
/// it is a new best, today's rank -- and a place to type the player's name
/// so the game shows up on the leaderboard under it.
class GameOverScreen extends ConsumerStatefulWidget {
  const GameOverScreen({super.key, required this.record});

  final GameRecord record;

  @override
  ConsumerState<GameOverScreen> createState() => _GameOverScreenState();
}

class _GameOverScreenState extends ConsumerState<GameOverScreen> {
  final _name = TextEditingController();
  late final bool _newBest;
  late final int? _rankToday;
  late final List<String> _recentNames;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(gameHistoryRepositoryProvider);
    final record = widget.record;

    // "New best" = no other game on this phone scored as much.
    _newBest = record.score > 0 && repo.all().where((g) => g.key != record.key).every((g) => g.score < record.score);

    final today = repo.topScoresForPeriod(LeaderboardPeriod.daily, limit: 1000);
    final index = today.indexWhere((g) => g.key == record.key);
    _rankToday = index < 0 ? null : index + 1;

    _recentNames = repo.recentNames(limit: 6);

    Future<void>.microtask(() {
      if (!mounted) return;
      final feedback = ref.read(feedbackProvider);
      if (_newBest) {
        feedback.newHighScore();
      } else {
        feedback.gameOver();
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _saveAndClose() async {
    if (_saving) return;
    setState(() => _saving = true);
    final key = widget.record.key;
    final text = _name.text.trim();
    if (key != null && text.isNotEmpty) {
      await ref.read(gameHistoryRepositoryProvider).rename(key, text);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GlassScaffold(
      appBar: GlassAppBar(title: const Text('Game Over')),
      appBarHeight: 44,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 56, 16, 32 + bottomInset),
          children: [
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
              child: Column(
                children: [
                  Text(
                    'FINAL SCORE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      color: dimColor(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TweenAnimationBuilder<int>(
                    tween: IntTween(begin: 0, end: record.score),
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.easeOut,
                    builder: (context, value, _) => Text(
                      '$value',
                      style: const TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        color: CupertinoColors.activeOrange,
                      ),
                    ),
                  ),
                  if (_newBest) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD54A).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'NEW HIGH SCORE!',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: Color(0xFFFFB800),
                        ),
                      ),
                    ),
                  ] else if (_rankToday != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '#$_rankToday today',
                      style: TextStyle(fontSize: 14, color: dimColor(context)),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _Fact(label: 'Shots', value: '${record.shots}'),
                      _Fact(
                        label: 'Rounds',
                        value: record.rounds >= 2 ? 'Round 2' : (record.rounds == 1 ? 'Round 1' : '-'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: "Who's playing?",
              caption: 'Add a name to put this game on the leaderboard under it.',
              children: [
                GlassTextField(
                  controller: _name,
                  placeholder: 'Player name',
                ),
                if (_recentNames.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final name in _recentNames)
                        GestureDetector(
                          onTap: () => setState(() => _name.text = name),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: CupertinoColors.activeOrange.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Text(name, style: const TextStyle(fontSize: 13)),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    GlassAction(
                      icon: CupertinoIcons.check_mark,
                      label: 'Save',
                      busy: _saving,
                      onTap: _saveAndClose,
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(),
                      child: const Text('Skip'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: captionStyle(context)),
      ],
    );
  }
}
