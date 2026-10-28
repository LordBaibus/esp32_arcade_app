import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'admin_gate.dart';
import 'calibration_screen.dart';
import 'common_widgets.dart';
import 'connection_screen.dart';
import 'connection_test_screen.dart';
import 'game_settings_screen.dart';
import 'maintenance_screen.dart';
import 'providers.dart';
import 'wifi_settings_screen.dart';

class Settings extends ConsumerWidget {
  const Settings({super.key});

  /// Opens an admin-only screen: asks for the PIN first when needed.
  Future<void> _openAdmin(BuildContext context, WidgetRef ref, Widget screen) async {
    if (!await ensureAdmin(context, ref)) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _setPin(BuildContext context, WidgetRef ref, {required bool alreadySet}) async {
    // Changing an existing PIN needs the current one first.
    if (alreadySet && !await ensureAdmin(context, ref)) return;
    if (!context.mounted) return;
    if (!alreadySet && !ref.read(linkProvider).isOnline) {
      await showInfoDialog(context, title: 'Not connected', message: "Join the machine's Wi-Fi first.");
      return;
    }

    final first = await showTextPrompt(
      context,
      title: alreadySet ? 'New PIN' : 'Set an admin PIN',
      message: '4 to 8 digits. It is stored on the machine and asked for before settings can be changed.',
      placeholder: 'PIN',
      obscure: true,
      maxLength: 8,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      confirmLabel: 'Next',
    );
    if (first == null || !context.mounted) return;
    if (first.length < 4) {
      await showInfoDialog(context, title: 'PIN too short', message: 'Use at least 4 digits.');
      return;
    }

    final second = await showTextPrompt(
      context,
      title: 'Repeat the PIN',
      placeholder: 'PIN again',
      obscure: true,
      maxLength: 8,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      confirmLabel: 'Save',
    );
    if (second == null || !context.mounted) return;
    if (second != first) {
      await showInfoDialog(context, title: "PINs don't match", message: 'Nothing was changed. Try again.');
      return;
    }

    final error = await ref.read(adminProvider.notifier).changePin(first);
    if (!context.mounted) return;
    await showInfoDialog(
      context,
      title: error == null ? 'PIN saved' : "Couldn't save the PIN",
      message: error ?? 'Settings, calibration, maintenance and Wi-Fi changes now ask for this PIN.',
    );
    if (error == null) await ref.read(linkProvider.notifier).refreshNow();
  }

  Future<void> _removePin(BuildContext context, WidgetRef ref) async {
    if (!await ensureAdmin(context, ref)) return;
    if (!context.mounted) return;
    final ok = await confirmDialog(
      context,
      title: 'Remove the PIN?',
      message: 'Anyone on the machine\'s Wi-Fi will be able to change its settings.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final error = await ref.read(adminProvider.notifier).changePin('');
    if (!context.mounted) return;
    if (error != null) {
      await showInfoDialog(context, title: "Couldn't remove the PIN", message: error);
    } else {
      await ref.read(linkProvider.notifier).refreshNow();
    }
  }

  Future<void> _clearHistory(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(gameHistoryRepositoryProvider);
    final ok = await confirmDialog(
      context,
      title: 'Clear game history?',
      message: 'Deletes all ${repo.count} saved games (names, scores, leaderboard) from this phone. '
          'The machine\'s own high score is not changed.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (ok) await repo.clear();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(linkProvider);
    final online = link.isOnline;
    final pinSet = link.status.adminPinSet;
    final access = ref.watch(adminAccessProvider);
    final unlocked = ref.watch(adminProvider.select((s) => s.unlocked));
    final isDark = ref.watch(darkModeProvider);
    final soundOn = ref.watch(soundEnabledProvider);
    final hapticsOn = ref.watch(hapticsEnabledProvider);

    // The padlock shows on admin tiles only while they'd ask for the PIN.
    final lockIcon = online && !access;

    return GlassScaffold(
      appBar: GlassAppBar(title: const Text('Settings')),
      appBarHeight: 44,
      body: SafeArea(
        child: ListView(
          // +44 clears the GlassAppBar itself, which floats over the body
          // instead of pushing it down.
          padding: const EdgeInsets.fromLTRB(16, 56, 16, 32),
          children: [
            ActionTile(
              icon: CupertinoIcons.wifi,
              title: 'Connection',
              subtitle: online
                  ? (link.transport == LinkTransport.webSocket ? 'Connected - live updates' : 'Connected')
                  : 'Offline - reconnecting automatically',
              trailing: StatusDot(on: online),
              onTap: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(builder: (_) => const ConnectionScreen()),
              ),
            ),
            const SizedBox(height: 12),
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _SwitchRow(
                    label: 'Dark Mode',
                    value: isDark,
                    onChanged: (value) async {
                      ref.read(darkModeProvider.notifier).state = value;
                      await saveDarkMode(value);
                    },
                  ),
                  const SizedBox(height: 14),
                  _SwitchRow(
                    label: 'Sound on each shot',
                    value: soundOn,
                    onChanged: (value) async {
                      ref.read(soundEnabledProvider.notifier).state = value;
                      await saveSound(value);
                    },
                  ),
                  const SizedBox(height: 14),
                  _SwitchRow(
                    label: 'Vibration on each shot',
                    value: hapticsOn,
                    onChanged: (value) async {
                      ref.read(hapticsEnabledProvider.notifier).state = value;
                      await saveHaptics(value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _AdminCard(
              online: online,
              pinSet: pinSet,
              unlocked: unlocked,
              onUnlock: () => ensureAdmin(context, ref),
              onLock: () => ref.read(adminProvider.notifier).lock(),
              onSetPin: () => _setPin(context, ref, alreadySet: false),
              onChangePin: () => _setPin(context, ref, alreadySet: true),
              onRemovePin: () => _removePin(context, ref),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text('MACHINE', style: TextStyle(fontSize: 12, color: dimColor(context))),
            ),
            ActionTile(
              icon: CupertinoIcons.slider_horizontal_3,
              title: 'Game Settings',
              subtitle: 'Round times, points, qualify score, price, brightness',
              locked: lockIcon,
              onTap: () => _openAdmin(context, ref, const GameSettingsScreen()),
            ),
            const SizedBox(height: 10),
            ActionTile(
              icon: CupertinoIcons.scope,
              title: 'Sensor Calibration',
              subtitle: 'Live distance, scoring window, test shots',
              locked: lockIcon,
              onTap: () => _openAdmin(context, ref, const CalibrationScreen()),
            ),
            const SizedBox(height: 10),
            ActionTile(
              icon: CupertinoIcons.wrench,
              title: 'Maintenance',
              subtitle: 'Gate, buzzer, displays, memory, uptime, reboot',
              locked: lockIcon,
              onTap: () => _openAdmin(context, ref, const MaintenanceScreen()),
            ),
            const SizedBox(height: 10),
            ActionTile(
              icon: CupertinoIcons.antenna_radiowaves_left_right,
              title: 'Wi-Fi Network',
              subtitle: 'Change the hotspot name and password',
              locked: lockIcon,
              onTap: () => _openAdmin(context, ref, const WifiSettingsScreen()),
            ),
            const SizedBox(height: 10),
            ActionTile(
              icon: CupertinoIcons.checkmark_shield,
              title: 'Sensor Test',
              subtitle: 'Check the coin slot, start button and shot sensor',
              onTap: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(builder: (_) => const ConnectionTestScreen()),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text('DATA', style: TextStyle(fontSize: 12, color: dimColor(context))),
            ),
            ActionTile(
              icon: CupertinoIcons.trash,
              title: 'Clear Game History',
              subtitle: 'Delete the saved games and leaderboard on this phone',
              onTap: () => _clearHistory(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: kCardTitle),
        GlassSwitch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _AdminCard extends StatelessWidget {
  const _AdminCard({
    required this.online,
    required this.pinSet,
    required this.unlocked,
    required this.onUnlock,
    required this.onLock,
    required this.onSetPin,
    required this.onChangePin,
    required this.onRemovePin,
  });

  final bool online;
  final bool pinSet;
  final bool unlocked;
  final VoidCallback onUnlock;
  final VoidCallback onLock;
  final VoidCallback onSetPin;
  final VoidCallback onChangePin;
  final VoidCallback onRemovePin;

  @override
  Widget build(BuildContext context) {
    final String status;
    final IconData icon;
    final Color color;

    if (!online) {
      status = 'Connect to the machine to manage the PIN.';
      icon = CupertinoIcons.lock_slash;
      color = CupertinoColors.systemGrey;
    } else if (!pinSet) {
      status = 'No PIN set - anyone on the machine\'s Wi-Fi can change its settings.';
      icon = CupertinoIcons.lock_open_fill;
      color = CupertinoColors.systemOrange;
    } else if (unlocked) {
      status = 'Unlocked. Locks again after 5 minutes without use.';
      icon = CupertinoIcons.lock_open_fill;
      color = CupertinoColors.activeGreen;
    } else {
      status = 'Locked. Settings, calibration, maintenance and Wi-Fi need the PIN.';
      icon = CupertinoIcons.lock_fill;
      color = CupertinoColors.activeOrange;
    }

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(width: 12),
              const Expanded(child: Text('Admin Access', style: kCardTitle)),
            ],
          ),
          const SizedBox(height: 6),
          Text(status, style: captionStyle(context)),
          if (online) ...[
            const SizedBox(height: 14),
            if (!pinSet)
              GlassAction(icon: CupertinoIcons.lock, label: 'Set a PIN', onTap: onSetPin)
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (unlocked)
                    GlassAction(icon: CupertinoIcons.lock_fill, label: 'Lock now', onTap: onLock)
                  else
                    GlassAction(icon: CupertinoIcons.lock_open, label: 'Unlock', onTap: onUnlock),
                  GlassAction(icon: CupertinoIcons.pencil, label: 'Change PIN', onTap: onChangePin),
                  GlassAction(icon: CupertinoIcons.delete, label: 'Remove PIN', onTap: onRemovePin),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
