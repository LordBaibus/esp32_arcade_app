import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app_nav.dart';
import 'connection_screen.dart';
import 'game_attempt.dart';
import 'game_over_screen.dart';
import 'homepage.dart';
import 'leaderboard.dart';
import 'providers.dart';
import 'settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local database -- the game log (score, shots, player name, time) that the
  // leaderboard and history are built from.
  await Hive.initFlutter();
  Hive.registerAdapter(GameAttemptAdapter()); // only to read games saved by older app versions
  await Hive.openBox<String>(gameRecordsBoxName);
  try {
    await GameHistoryRepository().migrateLegacy();
  } catch (_) {
    // Old data that can't be read must never stop the app from starting.
  }

  await LiquidGlassWidgets.initialize();

  // ProviderScope must wrap everything that reads a provider.
  runApp(
    ProviderScope(
      child: LiquidGlassWidgets.wrap(child: const MyApp()),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  int selectedIndex = 0;
  final List<Widget> pages = const [
    Homepage(),
    Leaderboard(),
    Settings(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedAppSettings();
    // Start the live link to the machine and the game-log sync right away,
    // whichever screen is showing.
    ref.read(linkProvider);
    ref.read(gameSyncProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the phone's Wi-Fi settings (or from sleep): don't wait
    // for the next retry, look for the machine immediately.
    if (state == AppLifecycleState.resumed && !ref.read(linkProvider).isOnline) {
      ref.read(linkProvider.notifier).reconnectNow();
    }
  }

  Future<void> _loadSavedAppSettings() async {
    final savedIp = await loadSavedEsp32Ip();
    final savedDark = await loadSavedDarkMode();
    final savedSound = await loadSavedSound();
    final savedHaptics = await loadSavedHaptics();
    final savedSsid = await loadSavedSsid();
    if (!mounted) return;
    ref.read(esp32IpProvider.notifier).state = savedIp;
    ref.read(darkModeProvider.notifier).state = savedDark;
    ref.read(soundEnabledProvider.notifier).state = savedSound;
    ref.read(hapticsEnabledProvider.notifier).state = savedHaptics;
    ref.read(knownSsidProvider.notifier).state = savedSsid;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(darkModeProvider);
    final everConnected = ref.watch(linkProvider.select((s) => s.everConnected));
    final gateDismissed = ref.watch(gateDismissedProvider);

    // A game just ended: open its summary (final score, name entry).
    ref.listen<GameRecord?>(pendingSummaryProvider, (previous, next) {
      if (next == null) return;
      ref.read(pendingSummaryProvider.notifier).state = null;
      rootNavigatorKey.currentState?.push(
        CupertinoPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => GameOverScreen(record: next),
        ),
      );
    });

    // Vibrate / play a sound on every scored shot, on any screen.
    ref.listen<int>(linkProvider.select((s) => s.status.gameShots), (previous, next) {
      if (previous != null && next > previous && next - previous <= 3) {
        ref.read(feedbackProvider).shotScored();
      }
    });

    final showGate = !everConnected && !gateDismissed;

    return CupertinoApp(
      navigatorKey: rootNavigatorKey,
      theme: CupertinoThemeData(
        primaryColor: CupertinoColors.label,
        brightness: isDark ? Brightness.dark : Brightness.light,
      ),
      debugShowCheckedModeBanner: false,
      home: showGate
          ? const ConnectionScreen(isGate: true)
          : GlassScaffold(
              body: SafeArea(child: pages[selectedIndex]),
              bottomBar: GlassTabBar.bottom(
                tabs: [
                  GlassTab(icon: Icon(CupertinoIcons.home)),
                  GlassTab(icon: Icon(CupertinoIcons.chart_bar_circle)),
                  GlassTab(icon: Icon(CupertinoIcons.settings)),
                ],
                selectedIndex: selectedIndex,
                onTabSelected: (selectedTab) {
                  setState(() {
                    selectedIndex = selectedTab;
                  });
                },
              ),
            ),
    );
  }
}
