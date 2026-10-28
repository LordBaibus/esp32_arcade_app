import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_gate.dart';
import 'common_widgets.dart';
import 'esp32_service.dart';
import 'providers.dart';

/// Sensor calibration: a live distance readout with the scoring window drawn
/// on it, and a "test shot" mode where the machine detects shots (it beeps)
/// but never scores them, so the window can be tuned without playing a game.
///
/// Opening this screen turns test mode on; leaving it turns it off. While a
/// game is running the machine ignores test mode, and the screen says so.
class CalibrationScreen extends ConsumerStatefulWidget {
  const CalibrationScreen({super.key});

  @override
  ConsumerState<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends ConsumerState<CalibrationScreen> {
  late final Esp32Service _service;
  Timer? _keepAlive;
  Timer? _flashTimer;

  MachineConfig? _saved;
  int _min = 10;
  int _max = 28;
  int _cooldown = 400;
  int _confirm = 1;
  int _clear = 2;

  bool _loading = true;
  bool _saving = false;
  bool _flashing = false;
  int _baseline = 0;
  String? _loadError;
  String? _testError;
  String? _message;

  @override
  void initState() {
    super.initState();
    _service = ref.read(esp32ServiceProvider);
    _load();
    _enableTest();
    // The machine ends test mode by itself 5 minutes after the last request,
    // so keep asking while this screen is open.
    _keepAlive = Timer.periodic(const Duration(seconds: 30), (_) => _enableTest());
  }

  @override
  void dispose() {
    _keepAlive?.cancel();
    _flashTimer?.cancel();
    // Best effort: leave the machine in normal mode.
    _service.setTestMode(false).then((_) {}).catchError((_) {});
    super.dispose();
  }

  Future<void> _enableTest() async {
    try {
      final status = await _service.setTestMode(true);
      if (!mounted) return;
      ref.read(linkProvider.notifier).applyStatus(status);
      ref.read(adminProvider.notifier).touch();
      if (_testError != null) setState(() => _testError = null);
    } on Esp32Exception catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.busy) {
          _testError = 'A game is running. Test mode comes back by itself when it ends.';
        } else if (e.needsPin) {
          _testError = 'The admin PIN is no longer valid. Go back and unlock again.';
        } else {
          _testError = e.message;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _testError = "Couldn't reach the machine.");
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final cfg = await _service.fetchConfig();
      if (!mounted) return;
      setState(() {
        _applyConfig(cfg);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = "Couldn't read the settings from the machine.";
      });
    }
  }

  void _applyConfig(MachineConfig cfg) {
    _saved = cfg;
    _min = cfg.shotMinCm;
    _max = cfg.shotMaxCm;
    _cooldown = cfg.shotCooldownMs;
    _confirm = cfg.shotConfirmFrames;
    _clear = cfg.clearFramesToRearm;
  }

  bool get _valid => _min < _max;

  bool get _dirty {
    final s = _saved;
    if (s == null) return false;
    return _min != s.shotMinCm ||
        _max != s.shotMaxCm ||
        _cooldown != s.shotCooldownMs ||
        _confirm != s.shotConfirmFrames ||
        _clear != s.clearFramesToRearm;
  }

  Future<void> _save() async {
    if (_saving || !_valid) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    final cfg = await runAdmin<MachineConfig>(
      context,
      ref,
      (service) => service.saveConfig({
        'shotMinCm': _min,
        'shotMaxCm': _max,
        'shotCooldownMs': _cooldown,
        'shotConfirmFrames': _confirm,
        'clearFramesToRearm': _clear,
      }),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (cfg != null) {
        _applyConfig(cfg);
        _message = 'Saved on the machine.';
      }
    });
  }

  void _discard() {
    final s = _saved;
    if (s == null) return;
    setState(() {
      _applyConfig(s);
      _message = null;
    });
  }

  void _onTestShot() {
    ref.read(feedbackProvider).tap();
    _flashTimer?.cancel();
    setState(() => _flashing = true);
    _flashTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _flashing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(linkProvider.select((s) => s.status.testShots), (previous, next) {
      if (previous != null && next > previous) _onTestShot();
    });

    final link = ref.watch(linkProvider);
    final status = link.status;
    final online = link.isOnline;
    final gameRunning = status.run.gameActive;

    if (_loading) {
      return const SubScreen(
        title: 'Sensor Calibration',
        children: [
          Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CupertinoActivityIndicator(radius: 14)),
          ),
        ],
      );
    }
    if (_saved == null) {
      return SubScreen(
        title: 'Sensor Calibration',
        children: [
          NoticeCard(icon: CupertinoIcons.wifi_slash, text: _loadError ?? "Couldn't read the settings."),
          const SizedBox(height: 16),
          GlassAction(icon: CupertinoIcons.arrow_clockwise, label: 'Try again', onTap: _load),
        ],
      );
    }

    final distance = status.distanceCm;
    final hasReading = online && status.sensorAlive && distance >= 0;
    final inWindow = hasReading && distance >= _min && distance <= _max;
    final shown = status.testShots >= _baseline ? status.testShots - _baseline : status.testShots;
    final scaleMax = math.min(450, math.max(60, ((_max / 10).ceil() + 3) * 10));
    final canEdit = !_saving;

    return SubScreen(
      title: 'Sensor Calibration',
      children: [
        if (_testError != null)
          NoticeCard(
            icon: CupertinoIcons.exclamationmark_triangle_fill,
            color: CupertinoColors.systemOrange,
            text: _testError!,
          )
        else if (!online)
          const NoticeCard(icon: CupertinoIcons.wifi_slash, text: 'Connection lost. Reconnecting...')
        else if (status.testMode)
          const NoticeCard(
            icon: CupertinoIcons.checkmark_circle_fill,
            color: CupertinoColors.activeGreen,
            text: 'Test mode is ON. A shot through the hoop makes the machine beep but never scores.',
          )
        else
          const NoticeCard(
            icon: CupertinoIcons.hourglass,
            color: CupertinoColors.systemOrange,
            text: 'Starting test mode...',
          ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Live distance',
          caption: 'Green = the scoring window. Anything the sensor sees inside it counts as a shot.',
          trailing: _Chip(
            text: !hasReading ? 'NO SIGNAL' : (inWindow ? 'IN WINDOW' : 'OUTSIDE'),
            color: !hasReading
                ? CupertinoColors.systemGrey
                : (inWindow ? CupertinoColors.activeGreen : CupertinoColors.systemOrange),
          ),
          children: [
            Center(
              child: Text(
                hasReading ? '$distance cm' : '-- cm',
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  color: inWindow ? CupertinoColors.activeGreen : null,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 70,
              width: double.infinity,
              child: CustomPaint(
                painter: _GaugePainter(
                  distance: hasReading ? distance : -1,
                  windowMin: _min,
                  windowMax: _max,
                  scaleMax: scaleMax,
                  inWindow: inWindow,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GlassCardFlash(
          flashing: _flashing,
          child: SectionCard(
            title: 'Test shots',
            caption: 'Throw a few balls. Each one the machine detects counts here and beeps.',
            children: [
              Row(
                children: [
                  Text('$shown', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      status.lastShotCm >= 0 && status.testMode
                          ? 'Last detected at ${status.lastShotCm} cm'
                          : 'Nothing detected yet',
                      style: captionStyle(context, size: 13),
                    ),
                  ),
                  GlassAction(
                    icon: CupertinoIcons.arrow_counterclockwise,
                    label: 'Reset',
                    enabled: shown > 0,
                    onTap: () => setState(() => _baseline = status.testShots),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Scoring window',
          caption: 'The ball is counted when the sensor reads between From and To.',
          children: [
            NumberStepper(
              label: 'From',
              value: _min,
              min: 0,
              max: 450,
              suffix: ' cm',
              enabled: canEdit,
              onChanged: (v) => setState(() {
                _min = v;
                _message = null;
              }),
            ),
            NumberStepper(
              label: 'To',
              value: _max,
              min: 0,
              max: 450,
              suffix: ' cm',
              enabled: canEdit,
              onChanged: (v) => setState(() {
                _max = v;
                _message = null;
              }),
            ),
            if (!_valid) ...[
              const SizedBox(height: 6),
              const Text(
                '"From" must be smaller than "To".',
                style: TextStyle(fontSize: 12, color: CupertinoColors.systemRed),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                GlassAction(
                  icon: CupertinoIcons.arrow_down_to_line,
                  label: 'From = now',
                  enabled: canEdit && hasReading,
                  onTap: () => setState(() {
                    _min = distance.clamp(0, 450).toInt();
                    _message = null;
                  }),
                ),
                GlassAction(
                  icon: CupertinoIcons.arrow_up_to_line,
                  label: 'To = now',
                  enabled: canEdit && hasReading,
                  onTap: () => setState(() {
                    _max = distance.clamp(0, 450).toInt();
                    _message = null;
                  }),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Detection tuning',
          caption: 'Leave these alone unless shots are missed or counted twice.',
          children: [
            NumberStepper(
              label: 'Cooldown',
              value: _cooldown,
              min: 0,
              max: 5000,
              step: 50,
              suffix: ' ms',
              hint: 'Minimum time between two shots',
              enabled: canEdit,
              onChanged: (v) => setState(() {
                _cooldown = v;
                _message = null;
              }),
            ),
            NumberStepper(
              label: 'Confirm readings',
              value: _confirm,
              min: 1,
              max: 5,
              hint: 'Readings in the window needed to count (higher = fewer false hits)',
              enabled: canEdit,
              onChanged: (v) => setState(() {
                _confirm = v;
                _message = null;
              }),
            ),
            NumberStepper(
              label: 'Clear readings',
              value: _clear,
              min: 1,
              max: 10,
              hint: 'Readings outside the window before the next shot can count',
              enabled: canEdit,
              onChanged: (v) => setState(() {
                _clear = v;
                _message = null;
              }),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            GlassAction(
              icon: CupertinoIcons.check_mark,
              label: 'Save',
              busy: _saving,
              enabled: _dirty && _valid && !gameRunning,
              onTap: _save,
            ),
            GlassAction(
              icon: CupertinoIcons.arrow_uturn_left,
              label: 'Discard',
              enabled: _dirty && canEdit,
              onTap: _discard,
            ),
          ],
        ),
        if (gameRunning) ...[
          const SizedBox(height: 10),
          Text('Saving is locked while a game is running.', style: captionStyle(context)),
        ],
        if (_message != null) ...[
          const SizedBox(height: 10),
          Text(_message!, style: captionStyle(context)),
        ],
      ],
    );
  }
}

/// Briefly outlines its child in green (a test shot was just detected).
class GlassCardFlash extends StatelessWidget {
  const GlassCardFlash({super.key, required this.flashing, required this.child});

  final bool flashing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: flashing ? CupertinoColors.activeGreen : const Color(0x00000000),
          width: 2,
        ),
      ),
      child: child,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
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

/// Horizontal ruler 0..[scaleMax] cm with the scoring window shaded and a
/// marker at the current distance.
class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.distance,
    required this.windowMin,
    required this.windowMax,
    required this.scaleMax,
    required this.inWindow,
  });

  /// -1 = no reading.
  final int distance;
  final int windowMin;
  final int windowMax;
  final int scaleMax;
  final bool inWindow;

  @override
  void paint(Canvas canvas, Size size) {
    const trackTop = 14.0;
    const trackHeight = 26.0;
    final trackBottom = trackTop + trackHeight;

    double xFor(num cm) {
      final clamped = cm < 0 ? 0 : (cm > scaleMax ? scaleMax : cm);
      return clamped / scaleMax * size.width;
    }

    // Track.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, trackTop, size.width, trackHeight),
        const Radius.circular(8),
      ),
      Paint()..color = const Color(0x33808080),
    );

    // Scoring window.
    final left = xFor(windowMin);
    final right = xFor(windowMax);
    if (right > left) {
      canvas.drawRect(
        Rect.fromLTRB(left, trackTop, right, trackBottom),
        Paint()..color = CupertinoColors.activeGreen.withValues(alpha: 0.38),
      );
      final edge = Paint()
        ..color = CupertinoColors.activeGreen
        ..strokeWidth = 2;
      canvas.drawLine(Offset(left, trackTop), Offset(left, trackBottom), edge);
      canvas.drawLine(Offset(right, trackTop), Offset(right, trackBottom), edge);
    }

    // Ticks and numbers.
    final step = scaleMax <= 100 ? 10 : 50;
    final tick = Paint()
      ..color = const Color(0x99808080)
      ..strokeWidth = 1;
    for (int cm = 0; cm <= scaleMax; cm += step) {
      final x = xFor(cm);
      canvas.drawLine(Offset(x, trackBottom), Offset(x, trackBottom + 5), tick);
      final tp = TextPainter(
        text: TextSpan(
          text: '$cm',
          style: const TextStyle(fontSize: 10, color: Color(0xFF8E8E93)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = (x - tp.width / 2).clamp(0.0, math.max(0.0, size.width - tp.width)).toDouble();
      tp.paint(canvas, Offset(dx, trackBottom + 7));
    }

    // Current distance.
    if (distance >= 0) {
      final x = xFor(distance);
      final color = inWindow ? CupertinoColors.activeGreen : CupertinoColors.activeOrange;
      canvas.drawLine(
        Offset(x, trackTop - 8),
        Offset(x, trackBottom + 2),
        Paint()
          ..color = color
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(Offset(x, trackTop - 8), 5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) {
    return old.distance != distance ||
        old.windowMin != windowMin ||
        old.windowMax != windowMax ||
        old.scaleMax != scaleMax ||
        old.inWindow != inWindow;
  }
}
