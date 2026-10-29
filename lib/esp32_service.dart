import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// Models -- one class per JSON shape the firmware (v2.1) sends.
// ---------------------------------------------------------------------------

/// The machine's run state, mirroring the `state` string in /api/status.
enum MachineRun {
  idle,
  roundLabel,
  ready,
  countdown,
  start,
  playing,
  roundGap,
  gameOver,
  unknown;

  static MachineRun parse(String? value) {
    switch (value) {
      case 'IDLE':
        return MachineRun.idle;
      case 'ROUND_LABEL':
        return MachineRun.roundLabel;
      case 'READY':
        return MachineRun.ready;
      case 'COUNTDOWN':
        return MachineRun.countdown;
      case 'START':
        return MachineRun.start;
      case 'PLAYING':
        return MachineRun.playing;
      case 'ROUND_GAP':
        return MachineRun.roundGap;
      case 'GAME_OVER':
        return MachineRun.gameOver;
      default:
        return MachineRun.unknown;
    }
  }

  /// True from the moment a game starts until it is completely over.
  bool get gameActive => this != idle && this != gameOver && this != unknown;
}

int _int(dynamic v, int fallback) => v is num ? v.toInt() : fallback;
bool _bool(dynamic v, bool fallback) => v is bool ? v : fallback;
String _str(dynamic v, String fallback) => v is String ? v : fallback;

/// Lifetime counters kept on the ESP32 (survive power-off).
class MachineStats {
  final int games;
  final int revenue;
  final int shots;

  const MachineStats({required this.games, required this.revenue, required this.shots});

  static const empty = MachineStats(games: 0, revenue: 0, shots: 0);

  factory MachineStats.fromJson(Map<String, dynamic> json) {
    return MachineStats(
      games: _int(json['games'], 0),
      revenue: _int(json['revenue'], 0),
      shots: _int(json['shots'], 0),
    );
  }
}

/// Snapshot of GET /api/status (also what the WebSocket pushes).
class MachineStatus {
  final String firmware;
  final String apSsid;
  final MachineRun run;
  final int round;
  final int timeLeft;
  final int countdown;
  final int score;
  final int highScore;
  final int pesoBalance;
  final int credits;
  final int pesoPerGame;
  final bool canStart;
  final int pointsPerShot;
  final int qualifyScore;
  final bool gateOpen;
  final int distanceCm;
  final bool sensorAlive;
  final bool shotArmed;
  final int gameShots;
  final int lastShotCm;
  final bool testMode;
  final int testShots;
  final int gameSeq;
  final int lastRecordedId;
  final bool adminPinSet;
  final bool wsEnabled;
  final int wsPort;
  final int clients;
  final int uptimeS;
  final int freeHeap;
  final MachineStats stats;

  const MachineStatus({
    required this.firmware,
    required this.apSsid,
    required this.run,
    required this.round,
    required this.timeLeft,
    required this.countdown,
    required this.score,
    required this.highScore,
    required this.pesoBalance,
    required this.credits,
    required this.pesoPerGame,
    required this.canStart,
    required this.pointsPerShot,
    required this.qualifyScore,
    required this.gateOpen,
    required this.distanceCm,
    required this.sensorAlive,
    required this.shotArmed,
    required this.gameShots,
    required this.lastShotCm,
    required this.testMode,
    required this.testShots,
    required this.gameSeq,
    required this.lastRecordedId,
    required this.adminPinSet,
    required this.wsEnabled,
    required this.wsPort,
    required this.clients,
    required this.uptimeS,
    required this.freeHeap,
    required this.stats,
  });

  static const empty = MachineStatus(
    firmware: '',
    apSsid: '',
    run: MachineRun.unknown,
    round: 1,
    timeLeft: 0,
    countdown: 0,
    score: 0,
    highScore: 0,
    pesoBalance: 0,
    credits: 0,
    pesoPerGame: 20,
    canStart: false,
    pointsPerShot: 2,
    qualifyScore: 50,
    gateOpen: false,
    distanceCm: -1,
    sensorAlive: false,
    shotArmed: false,
    gameShots: 0,
    lastShotCm: -1,
    testMode: false,
    testShots: 0,
    gameSeq: 0,
    lastRecordedId: 0,
    adminPinSet: false,
    wsEnabled: false,
    wsPort: 81,
    clients: 0,
    uptimeS: 0,
    freeHeap: 0,
    stats: MachineStats.empty,
  );

  factory MachineStatus.fromJson(Map<String, dynamic> json) {
    final statsJson = json['stats'];
    return MachineStatus(
      firmware: _str(json['fw'], ''),
      apSsid: _str(json['apSsid'], ''),
      run: MachineRun.parse(json['state'] as String?),
      round: _int(json['round'], 1),
      timeLeft: _int(json['timeLeft'], 0),
      countdown: _int(json['countdown'], 0),
      score: _int(json['score'], 0),
      highScore: _int(json['highScore'], 0),
      pesoBalance: _int(json['pesoBalance'], 0),
      credits: _int(json['credits'], 0),
      pesoPerGame: _int(json['pesoPerGame'], 20),
      canStart: _bool(json['canStart'], false),
      pointsPerShot: _int(json['pointsPerShot'], 2),
      qualifyScore: _int(json['qualifyScore'], 50),
      gateOpen: _bool(json['gateOpen'], false),
      distanceCm: _int(json['distanceCm'], -1),
      sensorAlive: _bool(json['sensorAlive'], false),
      shotArmed: _bool(json['shotArmed'], false),
      gameShots: _int(json['gameShots'], 0),
      lastShotCm: _int(json['lastShotCm'], -1),
      testMode: _bool(json['testMode'], false),
      testShots: _int(json['testShots'], 0),
      gameSeq: _int(json['gameSeq'], 0),
      lastRecordedId: _int(json['lastRecordedId'], 0),
      adminPinSet: _bool(json['adminPinSet'], false),
      wsEnabled: _bool(json['ws'], false),
      wsPort: _int(json['wsPort'], 81),
      clients: _int(json['clients'], 0),
      uptimeS: _int(json['uptimeS'], 0),
      freeHeap: _int(json['freeHeap'], 0),
      stats: statsJson is Map<String, dynamic> ? MachineStats.fromJson(statsJson) : MachineStats.empty,
    );
  }

  /// Pesos already inserted towards the next credit (e.g. 7 of 20).
  int get pesoTowardsNextCredit => pesoPerGame <= 0 ? 0 : pesoBalance % pesoPerGame;

  /// What the Time board shows right now, as plain text.
  String get timeBoardText {
    switch (run) {
      case MachineRun.playing:
        return '$timeLeft';
      case MachineRun.countdown:
        return '$countdown';
      case MachineRun.ready:
        return 'READY';
      case MachineRun.start:
        return 'START';
      case MachineRun.roundLabel:
        return 'ROUND $round';
      case MachineRun.roundGap:
        return '--';
      case MachineRun.gameOver:
        return 'OVER';
      case MachineRun.idle:
        return '$credits CR';
      case MachineRun.unknown:
        return '--';
    }
  }
}

/// GET /api/config -- every tunable setting stored on the ESP32.
class MachineConfig {
  final int round1Seconds;
  final int round2Seconds;
  final int round1Points;
  final int round2Points;
  final int qualifyScore;
  final int pesoPerGame;
  final int shotMinCm;
  final int shotMaxCm;
  final int shotCooldownMs;
  final int shotConfirmFrames;
  final int clearFramesToRearm;
  final int displayIntensity;
  final String apSsid;
  final String firmware;

  const MachineConfig({
    required this.round1Seconds,
    required this.round2Seconds,
    required this.round1Points,
    required this.round2Points,
    required this.qualifyScore,
    required this.pesoPerGame,
    required this.shotMinCm,
    required this.shotMaxCm,
    required this.shotCooldownMs,
    required this.shotConfirmFrames,
    required this.clearFramesToRearm,
    required this.displayIntensity,
    required this.apSsid,
    required this.firmware,
  });

  /// Factory values (same as the firmware's setConfigDefaults()).
  static const factory = MachineConfig(
    round1Seconds: 60,
    round2Seconds: 30,
    round1Points: 2,
    round2Points: 3,
    qualifyScore: 50,
    pesoPerGame: 20,
    shotMinCm: 10,
    shotMaxCm: 28,
    shotCooldownMs: 400,
    shotConfirmFrames: 1,
    clearFramesToRearm: 2,
    displayIntensity: 8,
    apSsid: '',
    firmware: '',
  );

  factory MachineConfig.fromJson(Map<String, dynamic> json) {
    return MachineConfig(
      round1Seconds: _int(json['round1Seconds'], 60),
      round2Seconds: _int(json['round2Seconds'], 30),
      round1Points: _int(json['round1Points'], 2),
      round2Points: _int(json['round2Points'], 3),
      qualifyScore: _int(json['qualifyScore'], 50),
      pesoPerGame: _int(json['pesoPerGame'], 20),
      shotMinCm: _int(json['shotMinCm'], 10),
      shotMaxCm: _int(json['shotMaxCm'], 28),
      shotCooldownMs: _int(json['shotCooldownMs'], 400),
      shotConfirmFrames: _int(json['shotConfirmFrames'], 1),
      clearFramesToRearm: _int(json['clearFramesToRearm'], 2),
      displayIntensity: _int(json['displayIntensity'], 8),
      apSsid: _str(json['apSsid'], ''),
      firmware: _str(json['fw'], ''),
    );
  }
}

/// One entry from GET /api/sensors.
///
/// `connected` means the wiring looks alive right now. `secondsSinceLastSignal`
/// is how long since the sensor last actually fired (-1 = never since the
/// ESP32 booted). `distanceCm` is only sent for the ultrasonic sensor.
class SensorReading {
  final String id;
  final String label;
  final bool connected;
  final int secondsSinceLastSignal;
  final int? distanceCm;

  const SensorReading({
    required this.id,
    required this.label,
    required this.connected,
    required this.secondsSinceLastSignal,
    this.distanceCm,
  });

  factory SensorReading.fromJson(Map<String, dynamic> json) {
    final dist = json['distanceCm'];
    return SensorReading(
      id: _str(json['id'], ''),
      label: _str(json['label'], ''),
      connected: _bool(json['connected'], false),
      secondsSinceLastSignal: _int(json['secondsSinceLastSignal'], -1),
      distanceCm: dist is num ? dist.toInt() : null,
    );
  }
}

/// One finished game from GET /api/games (the ESP32 keeps the last 20).
class FinishedGame {
  final int id;
  final int score;
  final int shots;
  final int rounds;

  const FinishedGame({
    required this.id,
    required this.score,
    required this.shots,
    required this.rounds,
  });

  factory FinishedGame.fromJson(Map<String, dynamic> json) {
    return FinishedGame(
      id: _int(json['id'], 0),
      score: _int(json['score'], 0),
      shots: _int(json['shots'], 0),
      rounds: _int(json['rounds'], 1),
    );
  }
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

class Esp32Exception implements Exception {
  final String message;
  final int? statusCode;

  /// Seconds until the PIN lock ends (only set on a 429 reply).
  final int? retryS;

  Esp32Exception(this.message, {this.statusCode, this.retryS});

  /// True when the machine wants the admin PIN (missing or wrong).
  bool get needsPin => statusCode == 401;

  /// True when too many wrong PINs were entered.
  bool get lockedOut => statusCode == 429;

  /// True when a game is running and the machine refused the change.
  bool get busy => statusCode == 409;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// HTTP client
// ---------------------------------------------------------------------------

/// Talks to the REST API in arcade_basketball_final_code.ino. The ESP32 hosts
/// its own Wi-Fi hotspot (default http://192.168.4.1), so no router is needed.
///
/// [adminKey] is read on every call, so the PIN can change without building a
/// new service.
class Esp32Service {
  Esp32Service({
    required this.baseIp,
    this.adminKey,
    this.timeout = const Duration(seconds: 3),
  });

  final String baseIp;
  final String? Function()? adminKey;
  final Duration timeout;

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('http://$baseIp$path').replace(queryParameters: query);
  }

  Map<String, String> _headers({bool json = false}) {
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    final key = adminKey?.call();
    if (key != null && key.isNotEmpty) headers['X-Admin-Key'] = key;
    return headers;
  }

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {
      // Non-JSON reply: handled by the status-code check below.
    }
    if (res.statusCode < 200 || res.statusCode >= 300 || body['ok'] == false) {
      final error = body['error'];
      throw Esp32Exception(
        error is String ? error : 'Machine responded with ${res.statusCode}',
        statusCode: res.statusCode,
        retryS: body['retryS'] is num ? (body['retryS'] as num).toInt() : null,
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> _get(String path, [Map<String, String>? query]) async {
    final res = await http.get(_uri(path, query), headers: _headers()).timeout(timeout);
    return _decode(res);
  }

  Future<Map<String, dynamic>> _post(String path, [Map<String, dynamic>? body]) async {
    final res = await http
        .post(
          _uri(path),
          headers: _headers(json: true),
          body: jsonEncode(body ?? const <String, dynamic>{}),
        )
        .timeout(timeout);
    return _decode(res);
  }

  // ---- read ----

  Future<MachineStatus> fetchStatus() async => MachineStatus.fromJson(await _get('/api/status'));

  Future<MachineConfig> fetchConfig() async => MachineConfig.fromJson(await _get('/api/config'));

  Future<List<SensorReading>> fetchSensors() async {
    final body = await _get('/api/sensors');
    final list = body['sensors'];
    if (list is! List) return const [];
    return list.whereType<Map<String, dynamic>>().map(SensorReading.fromJson).toList();
  }

  /// Finished games with an id greater than [since], oldest first.
  Future<List<FinishedGame>> fetchGames({int since = 0}) async {
    final body = await _get('/api/games', {'since': '$since'});
    final list = body['games'];
    if (list is! List) return const [];
    return list.whereType<Map<String, dynamic>>().map(FinishedGame.fromJson).toList();
  }

  // ---- settings (admin) ----

  /// Pass any subset of the config keys; the machine validates every value and
  /// changes nothing if one is bad. Returns the stored config.
  Future<MachineConfig> saveConfig(Map<String, int> values) async {
    return MachineConfig.fromJson(await _post('/api/config', values));
  }

  Future<MachineConfig> resetConfig() async => MachineConfig.fromJson(await _post('/api/config/reset'));

  // ---- calibration / maintenance (admin) ----

  /// Turns sensor test mode on or off. Returns the fresh status.
  Future<MachineStatus> setTestMode(bool on) async {
    return MachineStatus.fromJson(await _post('/api/test', {'on': on}));
  }

  Future<void> setGate({required bool down}) async {
    await _post('/api/gate', {'pos': down ? 'down' : 'up'});
  }

  Future<void> beep() async {
    await _post('/api/beep');
  }

  Future<void> resetStats() async {
    await _post('/api/stats/reset');
  }

  Future<void> resetHighScore() async {
    await _post('/api/highscore/reset');
  }

  Future<void> reboot() async {
    await _post('/api/reboot');
  }

  /// Renames the hotspot. The machine restarts, so the phone has to rejoin.
  Future<void> setWifi({required String ssid, required String password}) async {
    await _post('/api/wifi', {'ssid': ssid, 'password': password});
  }

  // ---- admin PIN ----

  /// Throws [Esp32Exception] (needsPin / lockedOut) when [pin] is wrong.
  Future<void> checkPin(String pin) async {
    final res = await http
        .post(
          _uri('/api/admin/check'),
          headers: {'Content-Type': 'application/json', 'X-Admin-Key': pin},
          body: '{}',
        )
        .timeout(timeout);
    _decode(res);
  }

  /// Empty [newPin] removes the PIN. The current PIN (if any) is sent as header.
  Future<void> setPin(String newPin) async {
    await _post('/api/admin/pin', {'newPin': newPin});
  }
}
