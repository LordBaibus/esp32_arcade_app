import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'common_widgets.dart' show dimColor;
import 'providers.dart';
import 'esp32_service.dart';

/// Full connectivity breakdown, reached from Settings' "Connection Test"
/// tile: the ESP32 link itself, plus every *two-way* sensor that can
/// report a live signal back to it (Coin Slot, Start Button, Shot
/// Sensor). A pure output like an LED matrix has no way to report its
/// own state, so it never appears here.
///
/// Sensor polling runs only while this screen is on screen -- it's a
/// deliberate one-off check, not something that needs to run in the
/// background.
class ConnectionTestScreen extends ConsumerStatefulWidget {
  const ConnectionTestScreen({super.key});

  @override
  ConsumerState<ConnectionTestScreen> createState() => _ConnectionTestScreenState();
}

/// The sensors the firmware can ever report on (matches its /api/sensors
/// ids/labels exactly). Fixed and known ahead of time, so the list below
/// always shows all three -- never a blanket "couldn't reach" placeholder
/// standing in for them.
const List<({String id, String label})> _knownSensors = [
  (id: 'coin', label: 'Coin Slot'),
  (id: 'start_button', label: 'Start Button'),
  (id: 'ultrasonic', label: 'Shot Sensor (Ultrasonic)'),
];

class _ConnectionTestScreenState extends ConsumerState<ConnectionTestScreen> {
  List<SensorReading>? _sensors;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollSensors();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollSensors());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollSensors() async {
    try {
      final sensors = await ref.read(esp32ServiceProvider).fetchSensors();
      if (mounted) setState(() => _sensors = sensors);
    } catch (_) {
      // Machine unreachable -- leave _sensors as whatever it last was.
      // The known-sensor list below always renders regardless, falling
      // back to "disconnected" for any id it can't find data for, so
      // there's never a generic error message standing in for the list.
      if (mounted) setState(() => _sensors = null);
    }
  }

  /// Looks up a known sensor's live reading, if any -- defaults to
  /// "disconnected, never triggered" when the machine hasn't answered
  /// yet or the last poll failed, so every row always has a definite
  /// status rather than a placeholder.
  SensorReading _readingFor(String id, String label) {
    for (final s in _sensors ?? const <SensorReading>[]) {
      if (s.id == id) return s;
    }
    return SensorReading(id: id, label: label, connected: false, secondsSinceLastSignal: -1);
  }

  String _lastSignalText(int secondsSinceLastSignal) {
    if (secondsSinceLastSignal < 0) return 'never triggered';
    if (secondsSinceLastSignal < 3) return 'just now';
    if (secondsSinceLastSignal < 60) return '${secondsSinceLastSignal}s ago';
    return '${secondsSinceLastSignal ~/ 60}m ago';
  }

  /// Does a fresh GET /api/sensors right now (not waiting for the next
  /// periodic poll) so the ultrasonic row's "tap to check" always reflects
  /// the sensor's current state rather than a stale cached one -- also
  /// refreshes the whole card, since this is a real round trip anyway.
  Future<SensorReading> _checkUltrasonicNow() async {
    final sensors = await ref.read(esp32ServiceProvider).fetchSensors();
    if (mounted) setState(() => _sensors = sensors);
    for (final s in sensors) {
      if (s.id == 'ultrasonic') return s;
    }
    return const SensorReading(
      id: 'ultrasonic',
      label: 'Shot Sensor (Ultrasonic)',
      connected: false,
      secondsSinceLastSignal: -1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(linkProvider).isOnline;

    return GlassScaffold(
      appBar: GlassAppBar(
        title: const Text('Connection Test'),
        centerTitle: true,
        leading: SizedBox(
          width: 44,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            child: const Icon(CupertinoIcons.back),
          ),
        ),
        // Balances the leading back button's width so the title lands in
        // the true center instead of drifting toward the empty side.
        actions: const [SizedBox(width: 44)],
      ),
      appBarHeight: 44,
      body: SafeArea(
        child: ListView(
          // +44 clears the GlassAppBar itself, which floats over the body
          // instead of pushing it down.
          padding: const EdgeInsets.fromLTRB(16, 56, 16, 24),
          children: [
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Machine Link', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    "Whether the phone is currently reaching the ESP32 over its own WiFi network.",
                    style: TextStyle(fontSize: 12, color: dimColor(context)),
                  ),
                  const SizedBox(height: 14),
                  _ConnectionRow(label: 'ESP32', connected: isOnline, connectedDetail: 'connected'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sensors', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'Only sensors that can report back to the machine are listed. Trigger one physically '
                        '(pass the ball through, press the button) to confirm it still responds, or tap the '
                        'Shot Sensor for its live distance reading.',
                    style: TextStyle(fontSize: 12, color: dimColor(context)),
                  ),
                  const SizedBox(height: 14),
                  // Always all three known sensors, each resolved to a
                  // definite Connected/Disconnected status -- never a
                  // generic "couldn't reach" placeholder standing in for
                  // the list itself.
                  Column(
                    children: [
                      for (int i = 0; i < _knownSensors.length; i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        Builder(builder: (context) {
                          final known = _knownSensors[i];
                          final reading = _readingFor(known.id, known.label);
                          if (known.id == 'ultrasonic') {
                            // The only sensor with a meaningful live value
                            // beyond connected/disconnected -- tappable so
                            // the user can pull an on-demand cm reading.
                            return _UltrasonicRow(
                              label: known.label,
                              connected: reading.connected,
                              statusText: _lastSignalText(reading.secondsSinceLastSignal),
                              onCheck: _checkUltrasonicNow,
                            );
                          }
                          return _ConnectionRow(
                            label: known.label,
                            connected: reading.connected,
                            connectedDetail: _lastSignalText(reading.secondsSinceLastSignal),
                          );
                        }),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One "Label ------ Status" row: green dot + last-signal text when
/// connected, red dot + "disconnected" when not.
class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({
    required this.label,
    required this.connected,
    required this.connectedDetail,
  });
  final String label;
  final bool connected;
  final String connectedDetail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: connected ? CupertinoColors.activeGreen : CupertinoColors.systemRed,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ),
        Text(
          connected ? connectedDetail : 'disconnected',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: connected ? CupertinoColors.activeGreen : CupertinoColors.systemRed,
          ),
        ),
      ],
    );
  }
}

/// Same "dot + label + status" shape as [_ConnectionRow], but tappable:
/// tapping does a fresh check against the ESP32 right now and shows the
/// sensor's live distance in cm, rather than just its connected status.
class _UltrasonicRow extends StatefulWidget {
  const _UltrasonicRow({
    required this.label,
    required this.connected,
    required this.statusText,
    required this.onCheck,
  });

  final String label;
  final bool connected;
  final String statusText;
  final Future<SensorReading> Function() onCheck;

  @override
  State<_UltrasonicRow> createState() => _UltrasonicRowState();
}

class _UltrasonicRowState extends State<_UltrasonicRow> {
  bool _checking = false;

  Future<void> _handleTap() async {
    if (_checking) return;
    setState(() => _checking = true);

    String message;
    try {
      final reading = await widget.onCheck();
      final distance = reading.distanceCm;
      message = (distance == null || distance < 0)
          ? "No reading yet -- nothing has passed in front of the sensor since it powered on."
          : '$distance cm away right now.';
    } catch (_) {
      message = "Couldn't reach the machine to take a reading.";
    }

    if (!mounted) return;
    setState(() => _checking = false);

    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Shot Sensor (Ultrasonic)'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(message),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.connected ? CupertinoColors.activeGreen : CupertinoColors.systemRed,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  'Tap to check the live reading',
                  style: TextStyle(fontSize: 11, color: dimColor(context)),
                ),
              ],
            ),
          ),
          if (_checking)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: CupertinoActivityIndicator(radius: 8),
            )
          else ...[
            Text(
              widget.connected ? widget.statusText : 'disconnected',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: widget.connected ? CupertinoColors.activeGreen : CupertinoColors.systemRed,
              ),
            ),
            const SizedBox(width: 6),
            Icon(CupertinoIcons.chevron_right, size: 14, color: dimColor(context)),
          ],
        ],
      ),
    );
  }
}