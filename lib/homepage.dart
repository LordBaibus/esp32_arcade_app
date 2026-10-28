import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'admin_gate.dart';
import 'common_widgets.dart';
import 'connection_screen.dart';
import 'game_attempt.dart';
import 'providers.dart';
import 'scoreboard.dart';

class Homepage extends ConsumerWidget {
  const Homepage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(linkProvider.select((s) => s.isOnline));
    final repo = ref.watch(gameHistoryRepositoryProvider);

    return GlassScaffold(
      appBar: GlassAppBar(title: const Text('Dashboard')),
      appBarHeight: 44,
      body: SafeArea(
        child: ValueListenableBuilder<Box<String>>(
          // Recent Games and the activity chart both read from the local
          // game log, so both refresh the instant a game is recorded.
          valueListenable: repo.listenable(),
          builder: (context, box, _) {
            return ListView(
              // GlassScaffold's appBar floats over the body rather than
              // pushing it down, so the top inset has to clear the bar's
              // own height (44) itself.
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
              children: [
                if (!online) ...[
                  _OfflineBanner(
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute<void>(builder: (_) => const ConnectionScreen()),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const Scoreboard(),
                const SizedBox(height: 12),
                const _TotalsCard(),
                const SizedBox(height: 12),
                _ActivityChartCard(repo: repo),
                const SizedBox(height: 12),
                _RecentGamesCard(repo: repo),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(CupertinoIcons.wifi_slash, color: CupertinoColors.systemRed),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                "Can't reach the machine. Reconnecting automatically - tap for help joining its Wi-Fi.",
                style: TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            Icon(CupertinoIcons.chevron_right, size: 16, color: dimColor(context)),
          ],
        ),
      ),
    );
  }
}

/// Lifetime counters kept on the ESP32: games played, pesos collected,
/// shots scored -- with a (PIN-protected) reset.
class _TotalsCard extends ConsumerWidget {
  const _TotalsCard();

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    if (!await ensureAdmin(context, ref)) return;
    if (!context.mounted) return;
    final ok = await confirmDialog(
      context,
      title: 'Reset totals?',
      message: 'Games played, pesos collected and shots scored on the machine go back to zero. '
          'The high score and the game history on this phone stay.',
      confirmLabel: 'Reset',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final done = await runAdminVoid(context, ref, (service) => service.resetStats());
    if (done) await ref.read(linkProvider.notifier).refreshNow();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(linkProvider.select((s) => s.status.stats));
    final online = ref.watch(linkProvider.select((s) => s.isOnline));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 0, 6),
          child: Row(
            children: [
              const Expanded(
                child: Text('Machine Totals', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: online ? () => _reset(context, ref) : null,
                child: const Text('Reset', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: CupertinoIcons.number_circle_fill,
                label: 'Games played',
                value: online ? '${stats.games}' : '--',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: CupertinoIcons.money_dollar_circle_fill,
                label: 'Pesos collected',
                value: online ? formatPeso(stats.revenue) : '--',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: CupertinoIcons.sportscourt_fill,
                label: 'Shots scored',
                value: online ? '${stats.shots}' : '--',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Compact stat tile. The value uses FittedBox so a long peso figure
/// shrinks to fit instead of overflowing the narrower tile.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: CupertinoColors.activeOrange),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: dimColor(context)),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

/// 7-day "games played" activity chart. A single series (one bar per day),
/// so it carries one hue and no legend: today's bar is the full accent
/// colour, the other six days a lighter tint of the same hue. Tapping a bar
/// swaps the caption above the chart to that day's count and date.
class _ActivityChartCard extends StatefulWidget {
  const _ActivityChartCard({required this.repo});

  final GameHistoryRepository repo;

  @override
  State<_ActivityChartCard> createState() => _ActivityChartCardState();
}

class _ActivityChartCardState extends State<_ActivityChartCard> {
  static const int _days = 7;
  int _selectedIndex = _days - 1; // today, last bar

  @override
  Widget build(BuildContext context) {
    final counts = widget.repo.gamesPerDayLast(_days);
    final maxCount = counts.fold<int>(0, (a, b) => a > b ? a : b);
    final now = DateTime.now();
    final dayLabels = List<DateTime>.generate(
      _days,
      (i) => DateTime(now.year, now.month, now.day).subtract(Duration(days: _days - 1 - i)),
    );

    final selectedDate = dayLabels[_selectedIndex];
    final selectedCount = counts[_selectedIndex];
    final isToday = _selectedIndex == _days - 1;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Last 7 Days', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            '$selectedCount game${selectedCount == 1 ? '' : 's'} '
            '${isToday ? "today" : "on ${DateFormat('EEE, MMM d').format(selectedDate)}"}',
            style: TextStyle(fontSize: 13, color: dimColor(context)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 96,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(_days, (i) {
                final isSelected = i == _selectedIndex;
                // Bar height maps count -> pixels; a day with 0 games still
                // gets a hairline stub so the baseline reads as continuous.
                final heightFraction = maxCount == 0 ? 0.0 : counts[i] / maxCount;
                final barHeight = 6.0 + heightFraction * 58.0;

                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _selectedIndex = i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            height: barHeight,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? CupertinoColors.activeOrange
                                  : CupertinoColors.activeOrange.withValues(alpha: 0.28),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(4),
                                topRight: Radius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            // Two letters, not one -- Tue/Thu and Sat/Sun
                            // both start with the same single letter.
                            DateFormat('E').format(dayLabels[i]).substring(0, 2),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected
                                  ? mainColor(context)
                                  : dimColor(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// Last 5 finished games, most recent first, with the player's name.
class _RecentGamesCard extends StatelessWidget {
  const _RecentGamesCard({required this.repo});

  final GameHistoryRepository repo;

  @override
  Widget build(BuildContext context) {
    final recent = repo.recentGames(limit: 5);

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Games', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (recent.isEmpty)
            Text(
              'No games recorded yet.',
              style: TextStyle(fontSize: 13, color: dimColor(context)),
            )
          else
            Column(
              children: [
                for (int i = 0; i < recent.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _RecentGameRow(game: recent[i]),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _RecentGameRow extends StatelessWidget {
  const _RecentGameRow({required this.game});

  final GameRecord game;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(CupertinoIcons.gamecontroller_fill, size: 18, color: CupertinoColors.activeOrange),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                game.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              Text(
                DateFormat('MMM d, h:mm a').format(game.playedAt),
                style: TextStyle(fontSize: 11, color: dimColor(context)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${game.score}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
