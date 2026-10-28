import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'common_widgets.dart';
import 'game_attempt.dart';
import 'providers.dart';

/// Leaderboard (Daily / Weekly / All Time = the best games, highest first)
/// and History (every game, newest first). Tap a row to name the player or
/// delete the game.
class Leaderboard extends ConsumerWidget {
  const Leaderboard({super.key});

  static const _labels = ['Daily', 'Weekly', 'All Time', 'History'];
  static const _periods = [
    LeaderboardPeriod.daily,
    LeaderboardPeriod.weekly,
    LeaderboardPeriod.allTime,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(leaderboardViewProvider);
    final repo = ref.watch(gameHistoryRepositoryProvider);

    return GlassScaffold(
      appBar: GlassAppBar(title: const Text('Leaderboard')),
      appBarHeight: 44,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              // +44 clears the GlassAppBar itself, which floats over the
              // body instead of pushing it down.
              padding: const EdgeInsets.fromLTRB(16, 56, 16, 8),
              child: GlassTabBar.inline(
                tabs: _labels.map((l) => GlassTab(label: l)).toList(),
                selectedIndex: selected,
                onTabSelected: (i) {
                  ref.read(leaderboardViewProvider.notifier).state = i;
                },
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<Box<String>>(
                valueListenable: repo.listenable(),
                builder: (context, box, _) {
                  final isHistory = selected == 3;
                  final entries = isHistory
                      ? repo.newestFirst().take(200).toList()
                      : repo.topScoresForPeriod(_periods[selected], limit: 20);

                  if (entries.isEmpty) {
                    return _EmptyState(isHistory: isHistory);
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final game = entries[index];
                      return _GameRow(
                        rank: isHistory ? null : index + 1,
                        game: game,
                        onTap: () => _showActions(context, ref, game),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref, GameRecord game) async {
    final key = game.key;
    if (key == null) return;
    final repo = ref.read(gameHistoryRepositoryProvider);

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text('${game.displayName} - ${game.score} pts'),
        message: Text(DateFormat('MMM d, y - h:mm a').format(game.playedAt)),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              final name = await showTextPrompt(
                context,
                title: 'Player name',
                placeholder: 'Name',
                initial: game.name ?? '',
                maxLength: 20,
                confirmLabel: 'Save',
              );
              if (name != null) await repo.rename(key, name);
            },
            child: const Text('Edit player name'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              final ok = await confirmDialog(
                context,
                title: 'Delete this game?',
                message: 'It is removed from the leaderboard and history on this phone.',
                confirmLabel: 'Delete',
                destructive: true,
              );
              if (ok) await repo.delete(key);
            },
            child: const Text('Delete game'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isHistory});

  final bool isHistory;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          isHistory
              ? 'No games recorded yet.\nFinished games from the machine show up here.'
              : 'No scores yet for this period.\nPlay a game to get on the board!',
          textAlign: TextAlign.center,
          style: TextStyle(color: dimColor(context)),
        ),
      ),
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({required this.rank, required this.game, required this.onTap});

  /// null in History (no ranking there).
  final int? rank;
  final GameRecord game;
  final VoidCallback onTap;

  Color _rankColor(BuildContext context) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD54A);
      case 2:
        return const Color(0xFFC7CBD1);
      case 3:
        return const Color(0xFFD98A4B);
      default:
        return dimColor(context);
    }
  }

  String _details() {
    final parts = <String>[DateFormat('MMM d, h:mm a').format(game.playedAt)];
    if (game.shots > 0) parts.add('${game.shots} shots');
    if (game.rounds >= 2) parts.add('Round 2');
    return parts.join('  -  ');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: rank == null
                  ? const Icon(CupertinoIcons.gamecontroller_fill, size: 18, color: CupertinoColors.activeOrange)
                  : Text(
                      '#$rank',
                      style: TextStyle(fontWeight: FontWeight.bold, color: _rankColor(context), fontSize: 16),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    _details(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: dimColor(context)),
                  ),
                ],
              ),
            ),
            Text(
              '${game.score}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
