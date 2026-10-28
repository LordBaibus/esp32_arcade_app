import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_gate.dart';
import 'common_widgets.dart';
import 'esp32_service.dart';
import 'providers.dart';

/// Hardware tests and machine health: gate, buzzer and LED boards, hotspot
/// clients, free memory, uptime, plus reboot and high-score reset.
class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  String? _busy;

  /// Runs one hardware action, showing a spinner on its button meanwhile.
  Future<bool> _run(String id, Future<void> Function(Esp32Service service) action) async {
    if (_busy != null) return false;
    setState(() => _busy = id);
    final ok = await runAdminVoid(context, ref, action);
    if (mounted) setState(() => _busy = null);
    if (ok) await ref.read(linkProvider.notifier).refreshNow();
    return ok;
  }

  Future<void> _reboot() async {
    final ok = await confirmDialog(
      context,
      title: 'Reboot the machine?',
      message: 'The ESP32 restarts and the app reconnects by itself after about 10 seconds. '
          'Credits and settings are kept.',
      confirmLabel: 'Reboot',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final done = await _run('reboot', (service) => service.reboot());
    if (done && mounted) {
      await showInfoDialog(
        context,
        title: 'Rebooting',
        message: 'The app will reconnect automatically.',
      );
    }
  }

  Future<void> _resetHighScore() async {
    final ok = await confirmDialog(
      context,
      title: 'Reset the high score?',
      message: 'The High Score board on the machine goes back to 0. Games saved on this phone stay.',
      confirmLabel: 'Reset',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run('highscore', (service) => service.resetHighScore());
  }

  @override
  Widget build(BuildContext context) {
    final link = ref.watch(linkProvider);
    final status = link.status;
    final online = link.isOnline;
    final gameRunning = status.run.gameActive;
    final enabled = online && !gameRunning;

    final heapKb = status.freeHeap / 1024;
    final lowMemory = online && status.freeHeap > 0 && heapKb < 50;

    return SubScreen(
      title: 'Maintenance',
      children: [
        if (!online) ...[
          const NoticeCard(icon: CupertinoIcons.wifi_slash, text: 'Connection lost. Reconnecting...'),
          const SizedBox(height: 12),
        ] else if (gameRunning) ...[
          const NoticeCard(
            icon: CupertinoIcons.game_controller_solid,
            color: CupertinoColors.systemOrange,
            text: 'A game is in progress. Hardware tests are locked until it ends.',
          ),
          const SizedBox(height: 12),
        ],
        SectionCard(
          title: 'Machine health',
          children: [
            InfoRow(label: 'Firmware', value: online && status.firmware.isNotEmpty ? status.firmware : '-'),
            InfoRow(label: 'Wi-Fi name', value: online && status.apSsid.isNotEmpty ? status.apSsid : '-'),
            InfoRow(label: 'Phones on the hotspot', value: online ? '${status.clients} of 4' : '-'),
            InfoRow(
              label: 'Free memory',
              value: online && status.freeHeap > 0 ? '${heapKb.toStringAsFixed(0)} KB' : '-',
              valueColor: lowMemory ? CupertinoColors.systemRed : null,
            ),
            InfoRow(label: 'Uptime', value: online ? formatUptime(status.uptimeS) : '-'),
            InfoRow(
              label: 'Shot sensor',
              value: !online ? '-' : (status.sensorAlive ? 'Sending data' : 'No signal'),
              valueColor: online && !status.sensorAlive ? CupertinoColors.systemRed : null,
            ),
            InfoRow(
              label: 'Gate',
              value: !online ? '-' : (status.gateOpen ? 'Down (open)' : 'Up (closed)'),
            ),
            InfoRow(
              label: 'Live updates',
              value: !online
                  ? '-'
                  : (link.transport == LinkTransport.webSocket ? 'WebSocket' : 'Polling'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Hardware tests',
          caption: 'Try each part without starting a game.',
          children: [
            const Text('Gate servo', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                GlassAction(
                  icon: CupertinoIcons.arrow_up_to_line,
                  label: 'Gate up',
                  enabled: enabled,
                  busy: _busy == 'gate-up',
                  onTap: () => _run('gate-up', (service) => service.setGate(down: false)),
                ),
                GlassAction(
                  icon: CupertinoIcons.arrow_down_to_line,
                  label: 'Gate down',
                  enabled: enabled,
                  busy: _busy == 'gate-down',
                  onTap: () => _run('gate-down', (service) => service.setGate(down: true)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Buzzer and LED boards', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                GlassAction(
                  icon: CupertinoIcons.speaker_2_fill,
                  label: 'Buzzer',
                  enabled: online,
                  busy: _busy == 'beep',
                  onTap: () => _run('beep', (service) => service.beep()),
                ),
                GlassAction(
                  icon: CupertinoIcons.lightbulb_fill,
                  label: 'Light all LEDs',
                  enabled: enabled,
                  busy: _busy == 'display-test',
                  onTap: () => _run('display-test', (service) => service.testDisplays()),
                ),
                GlassAction(
                  icon: CupertinoIcons.arrow_2_circlepath,
                  label: 'Reset displays',
                  enabled: online,
                  busy: _busy == 'display-reset',
                  onTap: () => _run('display-reset', (service) => service.resetDisplays()),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '"Light all LEDs" turns every LED on the three boards on for 2 seconds - a dead or dim segment shows up straight away.',
              style: captionStyle(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Careful',
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                GlassAction(
                  icon: CupertinoIcons.star_slash,
                  label: 'Reset high score',
                  enabled: enabled,
                  busy: _busy == 'highscore',
                  onTap: _resetHighScore,
                ),
                GlassAction(
                  icon: CupertinoIcons.power,
                  label: 'Reboot',
                  enabled: enabled,
                  busy: _busy == 'reboot',
                  onTap: _reboot,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
