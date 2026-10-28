import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Box used by older versions of the app (one GameAttempt per finished game,
/// no player name). Only read once, to carry old games over -- see
/// [GameHistoryRepository.migrateLegacy].
const String gameAttemptsBoxName = 'game_attempts';

/// Box holding the current game log: one JSON string per finished game.
/// JSON (not a Hive adapter) so new fields can be added later without ever
/// breaking records that are already saved on the phone.
const String gameRecordsBoxName = 'game_records';

enum LeaderboardPeriod { daily, weekly, allTime }

// ---------------------------------------------------------------------------
// Legacy format (typeId 0) -- kept ONLY so old saved games can still be read.
// ---------------------------------------------------------------------------

class GameAttempt extends HiveObject {
  final int attemptNumber;
  final int score;
  final DateTime playedAt;

  GameAttempt({
    required this.attemptNumber,
    required this.score,
    required this.playedAt,
  });
}

/// Hand-written Hive adapter -- no build_runner / code generation needed.
/// Unchanged from earlier versions so existing data keeps loading.
class GameAttemptAdapter extends TypeAdapter<GameAttempt> {
  @override
  final int typeId = 0;

  @override
  GameAttempt read(BinaryReader reader) {
    final attemptNumber = reader.readInt();
    final score = reader.readInt();
    final playedAtMillis = reader.readInt();
    return GameAttempt(
      attemptNumber: attemptNumber,
      score: score,
      playedAt: DateTime.fromMillisecondsSinceEpoch(playedAtMillis),
    );
  }

  @override
  void write(BinaryWriter writer, GameAttempt obj) {
    writer.writeInt(obj.attemptNumber);
    writer.writeInt(obj.score);
    writer.writeInt(obj.playedAt.millisecondsSinceEpoch);
  }
}

// ---------------------------------------------------------------------------
// Current format
// ---------------------------------------------------------------------------

/// One finished game as stored on the phone. The ESP32 keeps only the high
/// score and its last 20 games and has no clock, so the phone stamps the time
/// and (via the game-over screen) the player name.
class GameRecord {
  /// Hive key; null until the record is stored.
  final int? key;

  /// Id the ESP32 gave the game (0 for games carried over from old versions).
  final int gameId;

  /// 1, 2, 3 ... in the order the phone logged them.
  final int attemptNumber;
  final int score;
  final int shots;

  /// 1 = ended after Round 1, 2 = played Round 2 as well (0 = unknown).
  final int rounds;
  final DateTime playedAt;
  final String? name;

  const GameRecord({
    this.key,
    required this.gameId,
    required this.attemptNumber,
    required this.score,
    required this.shots,
    required this.rounds,
    required this.playedAt,
    this.name,
  });

  /// Name to show in lists.
  String get displayName {
    final n = name?.trim();
    return (n == null || n.isEmpty) ? 'Player' : n;
  }

  GameRecord copyWith({String? name, bool clearName = false}) {
    return GameRecord(
      key: key,
      gameId: gameId,
      attemptNumber: attemptNumber,
      score: score,
      shots: shots,
      rounds: rounds,
      playedAt: playedAt,
      name: clearName ? null : (name ?? this.name),
    );
  }

  Map<String, dynamic> toJson() => {
        'gid': gameId,
        'n': attemptNumber,
        's': score,
        'sh': shots,
        'r': rounds,
        't': playedAt.millisecondsSinceEpoch,
        'name': name,
      };

  factory GameRecord.fromJson(int? key, Map<String, dynamic> json) {
    int asInt(dynamic v, int fallback) => v is num ? v.toInt() : fallback;
    final rawName = json['name'];
    return GameRecord(
      key: key,
      gameId: asInt(json['gid'], 0),
      attemptNumber: asInt(json['n'], 0),
      score: asInt(json['s'], 0),
      shots: asInt(json['sh'], 0),
      rounds: asInt(json['r'], 0),
      playedAt: DateTime.fromMillisecondsSinceEpoch(asInt(json['t'], 0)),
      name: rawName is String ? rawName : null,
    );
  }
}

/// All reads/writes to the local game log go through here.
class GameHistoryRepository {
  Box<String> get _box => Hive.box<String>(gameRecordsBoxName);

  /// UI widgets rebuild automatically on every change by listening to this
  /// with a ValueListenableBuilder.
  ValueListenable<Box<String>> listenable() => _box.listenable();

  int get count => _box.length;

  /// Every stored game, oldest first.
  List<GameRecord> all() {
    final out = <GameRecord>[];
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          out.add(GameRecord.fromJson(key is int ? key : null, decoded));
        }
      } catch (_) {
        // A damaged entry is skipped instead of breaking the whole list.
      }
    }
    out.sort((a, b) => a.playedAt.compareTo(b.playedAt));
    return out;
  }

  Future<GameRecord> add({
    required int gameId,
    required int score,
    required int shots,
    required int rounds,
    DateTime? playedAt,
    String? name,
  }) async {
    final record = GameRecord(
      gameId: gameId,
      attemptNumber: _box.length + 1,
      score: score,
      shots: shots,
      rounds: rounds,
      playedAt: playedAt ?? DateTime.now(),
      name: name,
    );
    final key = await _box.add(jsonEncode(record.toJson()));
    return GameRecord.fromJson(key, record.toJson());
  }

  Future<void> rename(int key, String? name) async {
    final raw = _box.get(key);
    if (raw == null) return;
    final current = GameRecord.fromJson(key, jsonDecode(raw) as Map<String, dynamic>);
    final trimmed = name?.trim();
    final updated = (trimmed == null || trimmed.isEmpty)
        ? current.copyWith(clearName: true)
        : current.copyWith(name: trimmed);
    await _box.put(key, jsonEncode(updated.toJson()));
  }

  Future<void> delete(int key) => _box.delete(key);

  Future<void> clear() async {
    await _box.clear();
  }

  /// Newest first.
  List<GameRecord> newestFirst() => all().reversed.toList();

  /// Top scores for a period, highest first (ties: older game ranks higher).
  List<GameRecord> topScoresForPeriod(LeaderboardPeriod period, {int limit = 20}) {
    final inPeriod = all().where((g) => _isInPeriod(g.playedAt, period)).toList();
    inPeriod.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.playedAt.compareTo(b.playedAt);
    });
    return inPeriod.take(limit).toList();
  }

  /// Most recent games, newest first.
  List<GameRecord> recentGames({int limit = 5}) => newestFirst().take(limit).toList();

  /// Count of games per calendar day for the last [days] days, oldest first
  /// (today is the last entry). Missing days are 0.
  List<int> gamesPerDayLast(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final counts = List<int>.filled(days, 0);
    for (final g in all()) {
      final playedDay = DateTime(g.playedAt.year, g.playedAt.month, g.playedAt.day);
      final daysAgo = today.difference(playedDay).inDays;
      if (daysAgo >= 0 && daysAgo < days) {
        counts[days - 1 - daysAgo]++;
      }
    }
    return counts;
  }

  /// Player names used before, most recent first, without duplicates -- the
  /// quick-pick chips on the game-over screen.
  List<String> recentNames({int limit = 8}) {
    final seen = <String>{};
    final names = <String>[];
    for (final g in newestFirst()) {
      final n = g.name?.trim();
      if (n == null || n.isEmpty) continue;
      if (seen.add(n.toLowerCase())) names.add(n);
      if (names.length >= limit) break;
    }
    return names;
  }

  /// Copies games saved by older versions of the app into the new log.
  /// Safe to call on every start: it only does anything when the old box
  /// still has data, and empties it afterwards.
  Future<void> migrateLegacy() async {
    if (!await Hive.boxExists(gameAttemptsBoxName)) return;
    final legacy = await Hive.openBox<GameAttempt>(gameAttemptsBoxName);
    if (legacy.isEmpty) {
      await legacy.close();
      return;
    }
    final old = legacy.values.toList()..sort((a, b) => a.playedAt.compareTo(b.playedAt));
    for (final a in old) {
      await add(
        gameId: 0,
        score: a.score,
        shots: 0,
        rounds: 0,
        playedAt: a.playedAt,
      );
    }
    await legacy.clear();
    await legacy.close();
  }

  bool _isInPeriod(DateTime playedAt, LeaderboardPeriod period) {
    final now = DateTime.now();
    switch (period) {
      case LeaderboardPeriod.daily:
        final startOfDay = DateTime(now.year, now.month, now.day);
        return !playedAt.isBefore(startOfDay);
      case LeaderboardPeriod.weekly:
        final startOfToday = DateTime(now.year, now.month, now.day);
        final startOfWeek = startOfToday.subtract(Duration(days: now.weekday - 1));
        return !playedAt.isBefore(startOfWeek);
      case LeaderboardPeriod.allTime:
        return true;
    }
  }
}
