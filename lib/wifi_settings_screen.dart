import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_gate.dart';
import 'common_widgets.dart';
import 'providers.dart';

/// Change the machine's Wi-Fi name and password. The machine saves them,
/// restarts its hotspot, and the phone has to join the new network.
class WifiSettingsScreen extends ConsumerStatefulWidget {
  const WifiSettingsScreen({super.key});

  @override
  ConsumerState<WifiSettingsScreen> createState() => _WifiSettingsScreenState();
}

class _WifiSettingsScreenState extends ConsumerState<WifiSettingsScreen> {
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _show = false;
  bool _saving = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  /// null = fine, otherwise what to fix.
  String? _validate() {
    final name = _ssid.text.trim();
    final pass = _password.text;
    if (name.isEmpty) return 'Enter a Wi-Fi name.';
    if (name.length > 32) return 'The Wi-Fi name can be at most 32 characters.';
    if (pass.length < 8) return 'The password needs at least 8 characters.';
    if (pass.length > 63) return 'The password can be at most 63 characters.';
    if (!_isSafe(name) || !_isSafe(pass)) {
      return 'Use letters, numbers and common symbols only (no quotes or backslash).';
    }
    if (pass != _repeat.text) return "The two passwords don't match.";
    return null;
  }

  bool _isSafe(String text) {
    for (final unit in text.codeUnits) {
      if (unit < 32 || unit > 126 || unit == 34 || unit == 92) return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (_saving) return;
    final problem = _validate();
    if (problem != null) {
      await showInfoDialog(context, title: 'Check the details', message: problem);
      return;
    }
    final name = _ssid.text.trim();
    final pass = _password.text;

    if (!mounted) return;
    final ok = await confirmDialog(
      context,
      title: 'Change the Wi-Fi?',
      message: 'The machine saves "$name" and restarts. This phone will lose the connection and '
          'must join the new network (forget the old one first if the phone keeps trying it).',
      confirmLabel: 'Change & restart',
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() => _saving = true);
    final done = await runAdminVoid(context, ref, (service) => service.setWifi(ssid: name, password: pass));
    if (!mounted) return;
    setState(() => _saving = false);

    if (done) {
      ref.read(knownSsidProvider.notifier).state = name;
      await saveSsid(name);
      if (!mounted) return;
      await showInfoDialog(
        context,
        title: 'Saved - machine restarting',
        message: 'Open your phone\'s Wi-Fi settings and join "$name" with the new password. '
            'The app reconnects by itself once you are on it.',
      );
      _password.clear();
      _repeat.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = ref.watch(linkProvider);
    final online = link.isOnline;
    final current = link.status.apSsid.isEmpty ? ref.watch(knownSsidProvider) : link.status.apSsid;
    final gameRunning = link.status.run.gameActive;

    // Pre-fill the name field with the current network name once.
    if (!_prefilled && current.isNotEmpty) {
      _ssid.text = current;
      _prefilled = true;
    }

    final enabled = online && !gameRunning && !_saving;

    return SubScreen(
      title: 'Wi-Fi Network',
      children: [
        if (!online) ...[
          const NoticeCard(icon: CupertinoIcons.wifi_slash, text: 'Connection lost. Reconnecting...'),
          const SizedBox(height: 12),
        ] else if (gameRunning) ...[
          const NoticeCard(
            icon: CupertinoIcons.game_controller_solid,
            color: CupertinoColors.systemOrange,
            text: 'A game is in progress. Try again when it ends.',
          ),
          const SizedBox(height: 12),
        ],
        SectionCard(
          title: 'Current network',
          children: [
            InfoRow(label: 'Wi-Fi name', value: current),
            InfoRow(label: 'Address', value: ref.watch(esp32IpProvider)),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'New name and password',
          caption: 'Stored on the machine. If you forget them, hold the START button while powering '
              'the machine on for 3 seconds (3 beeps) to go back to the defaults.',
          children: [
            _Field(label: 'Wi-Fi name', controller: _ssid, placeholder: 'BitBallers-Arcade', maxLength: 32, enabled: enabled),
            const SizedBox(height: 10),
            _Field(
              label: 'Password (8 or more characters)',
              controller: _password,
              placeholder: 'New password',
              maxLength: 63,
              obscure: !_show,
              enabled: enabled,
            ),
            const SizedBox(height: 10),
            _Field(
              label: 'Repeat password',
              controller: _repeat,
              placeholder: 'Repeat password',
              maxLength: 63,
              obscure: !_show,
              enabled: enabled,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                CupertinoSwitch(value: _show, onChanged: (v) => setState(() => _show = v)),
                const SizedBox(width: 10),
                const Text('Show password', style: TextStyle(fontSize: 13)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        GlassAction(
          icon: CupertinoIcons.check_mark,
          label: 'Save & restart machine',
          busy: _saving,
          enabled: enabled,
          onTap: _save,
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.placeholder,
    required this.maxLength,
    required this.enabled,
    this.obscure = false,
  });

  final String label;
  final TextEditingController controller;
  final String placeholder;
  final int maxLength;
  final bool enabled;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: captionStyle(context)),
        const SizedBox(height: 4),
        CupertinoTextField(
          controller: controller,
          placeholder: placeholder,
          obscureText: obscure,
          maxLength: maxLength,
          enabled: enabled,
          autocorrect: false,
          enableSuggestions: false,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ],
    );
  }
}
