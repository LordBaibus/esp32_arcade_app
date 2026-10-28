import 'package:esp32_arcade_app/esp32_service.dart';
import 'package:esp32_arcade_app/game_attempt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MachineStatus.fromJson', () {
    test('reads a full /api/status reply', () {
      final status = MachineStatus.fromJson({
        'ok': true,
        'fw': '2.1-wifi',
        'apSsid': 'BitBallers-Arcade',
        'state': 'PLAYING',
        'round': 2,
        'timeLeft': 21,
        'countdown': 0,
        'score': 64,
        'highScore': 90,
        'pesoBalance': 47,
        'credits': 2,
        'pesoPerGame': 20,
        'canStart': false,
        'pointsPerShot': 3,
        'qualifyScore': 50,
        'gateOpen': true,
        'distanceCm': 17,
        'sensorAlive': true,
        'shotArmed': true,
        'gameShots': 28,
        'lastShotCm': 15,
        'testMode': false,
        'testShots': 0,
        'gameSeq': 12,
        'lastRecordedId': 11,
        'adminPinSet': true,
        'ws': true,
        'wsPort': 81,
        'clients': 2,
        'uptimeS': 3600,
        'freeHeap': 150000,
        'stats': {'games': 12, 'revenue': 340, 'shots': 411},
      });

      expect(status.run, MachineRun.playing);
      expect(status.run.gameActive, isTrue);
      expect(status.round, 2);
      expect(status.timeBoardText, '21');
      expect(status.score, 64);
      expect(status.pesoTowardsNextCredit, 7);
      expect(status.adminPinSet, isTrue);
      expect(status.wsEnabled, isTrue);
      expect(status.stats.games, 12);
      expect(status.stats.revenue, 340);
      expect(status.stats.shots, 411);
    });

    test('falls back to safe defaults for missing fields', () {
      final status = MachineStatus.fromJson(const {});
      expect(status.run, MachineRun.unknown);
      expect(status.run.gameActive, isFalse);
      expect(status.credits, 0);
      expect(status.stats.games, 0);
      expect(status.pesoPerGame, 20);
    });

    test('maps every machine state string', () {
      expect(MachineRun.parse('IDLE'), MachineRun.idle);
      expect(MachineRun.parse('ROUND_LABEL'), MachineRun.roundLabel);
      expect(MachineRun.parse('COUNTDOWN'), MachineRun.countdown);
      expect(MachineRun.parse('GAME_OVER'), MachineRun.gameOver);
      expect(MachineRun.parse('nonsense'), MachineRun.unknown);
      expect(MachineRun.idle.gameActive, isFalse);
      expect(MachineRun.gameOver.gameActive, isFalse);
      expect(MachineRun.roundGap.gameActive, isTrue);
    });
  });

  group('API models', () {
    test('MachineConfig reads /api/config', () {
      final cfg = MachineConfig.fromJson({
        'round1Seconds': 45,
        'round2Seconds': 25,
        'round1Points': 2,
        'round2Points': 4,
        'qualifyScore': 40,
        'pesoPerGame': 10,
        'shotMinCm': 8,
        'shotMaxCm': 30,
        'shotCooldownMs': 350,
        'shotConfirmFrames': 2,
        'clearFramesToRearm': 3,
        'displayIntensity': 12,
        'apSsid': 'MyArcade',
        'fw': '2.1-wifi',
      });
      expect(cfg.round1Seconds, 45);
      expect(cfg.shotMaxCm, 30);
      expect(cfg.apSsid, 'MyArcade');
    });

    test('SensorReading keeps distance only for the ultrasonic sensor', () {
      final coin = SensorReading.fromJson({
        'id': 'coin',
        'label': 'Coin Slot',
        'connected': true,
        'secondsSinceLastSignal': 12,
      });
      final us = SensorReading.fromJson({
        'id': 'ultrasonic',
        'label': 'Shot Sensor',
        'connected': true,
        'secondsSinceLastSignal': -1,
        'distanceCm': 33,
      });
      expect(coin.distanceCm, isNull);
      expect(us.distanceCm, 33);
      expect(us.secondsSinceLastSignal, -1);
    });

    test('FinishedGame reads /api/games entries', () {
      final g = FinishedGame.fromJson({'id': 7, 'score': 88, 'shots': 40, 'rounds': 2});
      expect(g.id, 7);
      expect(g.score, 88);
      expect(g.rounds, 2);
    });
  });

  group('GameRecord', () {
    test('survives a JSON round trip', () {
      final original = GameRecord(
        gameId: 5,
        attemptNumber: 3,
        score: 72,
        shots: 30,
        rounds: 2,
        playedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        name: 'Jai',
      );
      final copy = GameRecord.fromJson(9, original.toJson());
      expect(copy.key, 9);
      expect(copy.gameId, 5);
      expect(copy.score, 72);
      expect(copy.name, 'Jai');
      expect(copy.playedAt, original.playedAt);
    });

    test('shows "Player" until a name is given, and can clear it again', () {
      final unnamed = GameRecord(
        gameId: 1,
        attemptNumber: 1,
        score: 10,
        shots: 5,
        rounds: 1,
        playedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(unnamed.displayName, 'Player');
      final named = unnamed.copyWith(name: '  Mia ');
      expect(named.displayName, 'Mia');
      expect(named.copyWith(clearName: true).displayName, 'Player');
    });
  });
}
