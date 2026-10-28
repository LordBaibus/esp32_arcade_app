import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'esp32_service.dart';
import 'feedback_service.dart';
import 'game_attempt.dart';
import 'native_network.dart';

/// The ESP32 hotspot always hands itself this address.
const String defaultEsp32Ip = '192.168.4.1';

/// Hotspot name the firmware ships with (can be renamed from the app).
const String defaultApSsid = 'BitBallers-Arcade';

/// Hotspot password the firmware ships with (shown as a hint on the
/// connection screen until the name/password is changed).
const String defaultApPassword = 'arcade2026';

const String _kEsp32IpKey = 'esp32_ip';
const String _kDarkModeKey = 'dark_mode';
const String _kSoundKey = 'sound_on';
const String _kHapticsKey = 'haptics_on';
const String _kSsidKey = 'last_ssid';
const String _kLastGameIdKey = 'last_synced_game_id';

// ---------------- Persisted app settings (SharedPreferences) ----------------
// These live on the phone, not the ESP32.

Future<String> loadSavedEsp32Ip() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kEsp32IpKey) ?? defaultEsp32Ip;
}

Future<void> saveEsp32Ip(String ip) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kEsp32IpKey, ip);
}

Future<bool> loadSavedDarkMode() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kDarkModeKey) ?? true;
}

Future<void> saveDarkMode(bool isDark) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kDarkModeKey, isDark);
}

Future<bool> loadSavedSound() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kSoundKey) ?? true;
}

Future<void> saveSound(bool on) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kSoundKey, on);
}

Future<bool> loadSavedHaptics() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kHapticsKey) ?? true;
}

Future<void> saveHaptics(bool on) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kHapticsKey, on);
}

Future<String> loadSavedSsid() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kSsidKey) ?? defaultApSsid;
}

Future<void> saveSsid(String ssid) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kSsidKey, ssid);
}

Future<int> loadLastGameId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(_kLastGameIdKey) ?? 0;
}

Future<void> saveLastGameId(int id) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kLastGameIdKey, id);
}

// ---------------- Simple state ----------------

final esp32IpProvider = StateProvider<String>((ref) => defaultEsp32Ip);
final darkModeProvider = StateProvider<bool>((ref) => true);
final soundEnabledProvider = StateProvider<bool>((ref) => true);
final hapticsEnabledProvider = StateProvider<bool>((ref) => true);

/// Hotspot name the connection screen tells the person to join.
final knownSsidProvider = StateProvider<String>((ref) => defaultApSsid);

/// True once the person chose "Continue without the machine" on the first
/// connection screen (so they can still browse the saved game history).
final gateDismissedProvider = StateProvider<bool>((ref) => false);

/// Which Leaderboard tab is open: 0 Daily, 1 Weekly, 2 All Time, 3 History.
final leaderboardViewProvider = StateProvider<int>((ref) => 0);

/// Set when a game has just finished and its summary should be shown.
/// The root widget pushes the game-over screen and clears this again.
final pendingSummaryProvider = StateProvider<GameRecord?>((ref) => null);

final gameHistoryRepositoryProvider = Provider<GameHistoryRepository>((ref) {
  return GameHistoryRepository();
});

final feedbackProvider = Provider<FeedbackService>((ref) {
  final feedback = FeedbackService();
  feedback.soundEnabled = ref.read(soundEnabledProvider);
  feedback.hapticsEnabled = ref.read(hapticsEnabledProvider);
  ref.listen<bool>(soundEnabledProvider, (previous, next) {
    feedback.soundEnabled = next;
  });
  ref.listen<bool>(hapticsEnabledProvider, (previous, next) {
    feedback.hapticsEnabled = next;
  });
  ref.onDispose(feedback.dispose);
  return feedback;
});

// ---------------- HTTP service ----------------

/// The PIN is read at call time, so unlocking / changing the PIN never
/// rebuilds the service (which would restart the connection).
final esp32ServiceProvider = Provider<Esp32Service>((ref) {
  final ip = ref.watch(esp32IpProvider);
  return Esp32Service(
    baseIp: ip,
    adminKey: () => ref.read(adminProvider).pin,
  );
});

// ---------------- Admin PIN ----------------

class AdminState {
  /// The PIN the machine accepted this session (null = locked).
  final String? pin;
  final DateTime? unlockedAt;

  const AdminState({this.pin, this.unlockedAt});

  bool get unlocked => pin != null;
}

/// Holds the admin PIN in memory only (never written to the phone's storage)
/// and locks itself again after [autoLock] without use.
class AdminController extends Notifier<AdminState> {
  static const Duration autoLock = Duration(minutes: 5);
  Timer? _timer;

  @override
  AdminState build() {
    ref.onDispose(() => _timer?.cancel());
    return const AdminState();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer(autoLock, lock);
  }

  /// Asks the machine whether [pin] is right. Returns null on success, or a
  /// message to show the person.
  Future<String?> unlock(String pin) async {
    try {
      await ref.read(esp32ServiceProvider).checkPin(pin);
      state = AdminState(pin: pin, unlockedAt: DateTime.now());
      _restartTimer();
      return null;
    } on Esp32Exception catch (e) {
      if (e.lockedOut) return 'Too many wrong PINs. Try again in ${e.retryS ?? 30} seconds.';
      if (e.needsPin) return 'Wrong PIN.';
      return e.message;
    } catch (_) {
      return "Couldn't reach the machine.";
    }
  }

  void lock() {
    _timer?.cancel();
    state = const AdminState();
  }

  /// Call after every successful admin action so the auto-lock timer restarts.
  void touch() {
    if (state.unlocked) _restartTimer();
  }

  /// Sets, changes (needs the current PIN unlocked first) or removes the PIN
  /// (empty [newPin]). Returns null on success, or a message.
  Future<String?> changePin(String newPin) async {
    try {
      await ref.read(esp32ServiceProvider).setPin(newPin);
      if (newPin.isEmpty) {
        lock();
      } else {
        state = AdminState(pin: newPin, unlockedAt: DateTime.now());
        _restartTimer();
      }
      return null;
    } on Esp32Exception catch (e) {
      if (e.needsPin) {
        lock();
        return 'Unlock with the current PIN first.';
      }
      return e.message;
    } catch (_) {
      return "Couldn't reach the machine.";
    }
  }
}

final adminProvider = NotifierProvider<AdminController, AdminState>(AdminController.new);

/// True when admin screens may be used right now: either the machine has no
/// PIN at all, or the PIN was entered and hasn't timed out.
final adminAccessProvider = Provider<bool>((ref) {
  final pinSet = ref.watch(linkProvider.select((s) => s.status.adminPinSet));
  final unlocked = ref.watch(adminProvider.select((s) => s.unlocked));
  return !pinSet || unlocked;
});

// ---------------- Live link to the machine ----------------

enum LinkPhase { connecting, connected, offline }

enum LinkTransport { none, webSocket, polling }

class LinkState {
  final LinkPhase phase;
  final LinkTransport transport;
  final MachineStatus status;

  /// True once the machine has answered at least once since the app started.
  final bool everConnected;

  /// Failed attempts in a row since the last good answer.
  final int failedAttempts;
  final DateTime? lastSeen;
  final String? lastError;

  const LinkState({
    required this.phase,
    required this.transport,
    required this.status,
    required this.everConnected,
    required this.failedAttempts,
    this.lastSeen,
    this.lastError,
  });

  static const initial = LinkState(
    phase: LinkPhase.connecting,
    transport: LinkTransport.none,
    status: MachineStatus.empty,
    everConnected: false,
    failedAttempts: 0,
  );

  bool get isOnline => phase == LinkPhase.connected;
}

/// Keeps the phone connected to the ESP32 for as long as the app runs.
///
/// 1. Fetches /api/status over HTTP (proves the machine is reachable).
/// 2. If the firmware offers a WebSocket, switches to it: the machine then
///    pushes every change instantly (shots, countdown, score).
/// 3. Without a WebSocket (or if it keeps failing) it polls every second,
///    every 0.4 s while a game or calibration test is running.
/// 4. When the link drops it retries forever with a short back-off, so the
///    person never has to press "reconnect".
class LinkController extends Notifier<LinkState> {
  bool _disposed = false;
  int _generation = 0;
  int _wsFailures = 0;
  String _savedSsid = '';
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _wsSub;

  @override
  LinkState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      _closeSocket();
    });
    ref.listen<String>(esp32IpProvider, (previous, next) {
      if (previous != next) reconnectNow();
    });
    Future<void>.microtask(reconnectNow);
    return LinkState.initial;
  }

  bool _alive(int gen) => !_disposed && gen == _generation;

  /// Drops whatever connection exists and starts again immediately.
  void reconnectNow() {
    if (_disposed) return;
    _generation++;
    _wsFailures = 0;
    _closeSocket();
    if (state.phase == LinkPhase.offline) {
      state = LinkState(
        phase: LinkPhase.connecting,
        transport: LinkTransport.none,
        status: state.status,
        everConnected: state.everConnected,
        failedAttempts: state.failedAttempts,
        lastSeen: state.lastSeen,
        lastError: state.lastError,
      );
    }
    unawaited(_run(_generation));
  }

  /// Fetches the status once, right now (used after a command so the screen
  /// doesn't wait for the next push / poll).
  Future<void> refreshNow() async {
    try {
      final s = await ref.read(esp32ServiceProvider).fetchStatus();
      if (_disposed) return;
      _applyOnline(s, state.transport == LinkTransport.none ? LinkTransport.polling : state.transport);
    } catch (_) {
      // The regular loop reports a lost connection.
    }
  }

  /// Puts a status the caller already has (e.g. from a command's reply) on screen.
  void applyStatus(MachineStatus status) {
    if (_disposed || !state.isOnline) return;
    _applyOnline(status, state.transport);
  }

  Future<void> _run(int gen) async {
    var failures = 0;
    while (_alive(gen)) {
      await NativeNetwork.bindToWifi();
      if (!_alive(gen)) return;
      final service = ref.read(esp32ServiceProvider);
      try {
        final first = await service.fetchStatus();
        if (!_alive(gen)) return;
        failures = 0;
        _applyOnline(first, LinkTransport.polling);

        var usedSocket = false;
        if (first.wsEnabled && _wsFailures < 3) {
          usedSocket = await _runSocket(gen, first.wsPort);
        }
        if (!_alive(gen)) return;
        if (!usedSocket) {
          final retrySocketSoon = first.wsEnabled && _wsFailures < 3;
          await _pollWhileOnline(
            gen,
            service,
            limit: retrySocketSoon ? const Duration(seconds: 5) : null,
          );
        } else {
          // The socket closed: breathe for a moment so a server that keeps
          // dropping us can't turn this loop into a hot spin.
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      } catch (e) {
        if (!_alive(gen)) return;
        failures++;
        _markOffline(failures, e);
        await Future<void>.delayed(Duration(milliseconds: min(1000 + failures * 500, 4000)));
      }
    }
  }

  Future<void> _pollWhileOnline(int gen, Esp32Service service, {Duration? limit}) async {
    final started = DateTime.now();
    var misses = 0;
    while (_alive(gen)) {
      final current = state.status;
      final fast = current.run == MachineRun.playing || current.testMode;
      await Future<void>.delayed(Duration(milliseconds: fast ? 400 : 1000));
      if (!_alive(gen)) return;
      try {
        final s = await service.fetchStatus();
        if (!_alive(gen)) return;
        misses = 0;
        _applyOnline(s, LinkTransport.polling);
      } catch (e) {
        if (!_alive(gen)) return;
        misses++;
        if (misses >= 3) {
          _markOffline(misses, e);
          return;
        }
      }
      if (limit != null && DateTime.now().difference(started) >= limit) return;
    }
  }

  /// Returns true if the socket opened (and has since closed), false if it
  /// could not be opened at all.
  Future<bool> _runSocket(int gen, int port) async {
    final ip = ref.read(esp32IpProvider);
    final channel = WebSocketChannel.connect(Uri.parse('ws://$ip:$port'));
    try {
      await channel.ready.timeout(const Duration(seconds: 3));
    } catch (_) {
      try {
        channel.sink.close();
      } catch (_) {}
      _wsFailures++;
      return false;
    }
    if (!_alive(gen)) {
      try {
        channel.sink.close();
      } catch (_) {}
      return false;
    }

    _wsFailures = 0;
    _channel = channel;
    final done = Completer<void>();
    var lastMessage = DateTime.now();

    _wsSub = channel.stream.listen(
      (dynamic data) {
        lastMessage = DateTime.now();
        if (!_alive(gen) || data is! String) return;
        try {
          final decoded = jsonDecode(data);
          if (decoded is Map<String, dynamic>) {
            _applyOnline(MachineStatus.fromJson(decoded), LinkTransport.webSocket);
          }
        } catch (_) {
          // Ignore a damaged message; the next one fixes it.
        }
      },
      onError: (Object error) {
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );

    // The machine pushes at least once a second; silence means the link died
    // without the socket noticing (phone left the Wi-Fi, ESP32 rebooted...).
    final watchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_alive(gen) ||
          DateTime.now().difference(lastMessage) > const Duration(seconds: 5)) {
        if (!done.isCompleted) done.complete();
      }
    });

    await done.future;
    watchdog.cancel();
    if (identical(_channel, channel)) _closeSocket();
    return true;
  }

  void _closeSocket() {
    final sub = _wsSub;
    final channel = _channel;
    _wsSub = null;
    _channel = null;
    sub?.cancel();
    try {
      channel?.sink.close();
    } catch (_) {}
  }

  void _applyOnline(MachineStatus s, LinkTransport transport) {
    if (_disposed) return;
    state = LinkState(
      phase: LinkPhase.connected,
      transport: transport,
      status: s,
      everConnected: true,
      failedAttempts: 0,
      lastSeen: DateTime.now(),
    );
    if (s.apSsid.isNotEmpty && s.apSsid != _savedSsid) {
      _savedSsid = s.apSsid;
      ref.read(knownSsidProvider.notifier).state = s.apSsid;
      unawaited(saveSsid(s.apSsid));
    }
  }

  void _markOffline(int failures, Object error) {
    if (_disposed) return;
    final text = error.toString();
    state = LinkState(
      phase: LinkPhase.offline,
      transport: LinkTransport.none,
      status: state.status,
      everConnected: state.everConnected,
      failedAttempts: failures,
      lastSeen: state.lastSeen,
      lastError: text.length > 120 ? text.substring(0, 120) : text,
    );
  }
}

final linkProvider = NotifierProvider<LinkController, LinkState>(LinkController.new);

// ---------------- Game log sync ----------------

/// Copies finished games from the ESP32 (which keeps only the last 20) into
/// the phone's own log, and raises [pendingSummaryProvider] for a game that
/// ends while the app is open. State = id of the last game copied.
class GameSyncController extends Notifier<int> {
  bool _busy = false;
  bool _primed = false;
  bool _loaded = false;
  int _lastSynced = 0;

  @override
  int build() {
    ref.listen<LinkState>(linkProvider, (previous, next) {
      if (!next.isOnline) return;
      final wasOnline = previous?.isOnline ?? false;
      final idChanged =
          previous == null || previous.status.lastRecordedId != next.status.lastRecordedId;
      if (!wasOnline || idChanged) unawaited(sync());
    });
    return 0;
  }

  Future<void> sync() async {
    if (_busy) return;
    _busy = true;
    var again = false;
    try {
      if (!_loaded) {
        _lastSynced = await loadLastGameId();
        _loaded = true;
      }
      var since = _lastSynced;
      // The machine's counter went backwards: its memory was wiped, so its
      // ids start over from 1.
      if (ref.read(linkProvider).status.lastRecordedId < since) since = 0;

      final games = await ref.read(esp32ServiceProvider).fetchGames(since: since);
      if (games.isEmpty) {
        _primed = true;
        return;
      }

      final repo = ref.read(gameHistoryRepositoryProvider);
      GameRecord? newest;
      for (final g in games) {
        newest = await repo.add(
          gameId: g.id,
          score: g.score,
          shots: g.shots,
          rounds: g.rounds,
        );
      }
      _lastSynced = games.last.id;
      state = _lastSynced;
      await saveLastGameId(_lastSynced);

      // The first sync after the app starts only catches up on old games
      // quietly; after that every new game gets its summary screen.
      if (_primed && newest != null) {
        ref.read(pendingSummaryProvider.notifier).state = newest;
      }
      _primed = true;

      again = ref.read(linkProvider).status.lastRecordedId > _lastSynced;
    } catch (_) {
      // Try again on the next change.
    } finally {
      _busy = false;
    }
    if (again) unawaited(sync());
  }
}

final gameSyncProvider = NotifierProvider<GameSyncController, int>(GameSyncController.new);
