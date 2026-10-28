import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_gate.dart';
import 'common_widgets.dart';
import 'esp32_service.dart';
import 'providers.dart';

/// Round times, points per shot, the score needed for Round 2, the price of
/// a game and the LED brightness. Values are read from the machine, edited
/// here and saved back to its flash memory (they survive power-off).
class GameSettingsScreen extends ConsumerStatefulWidget {
  const GameSettingsScreen({super.key});

  @override
  ConsumerState<GameSettingsScreen> createState() => _GameSettingsScreenState();
}

class _GameSettingsScreenState extends ConsumerState<GameSettingsScreen> {
  MachineConfig? _saved;
  Map<String, int> _edit = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, int> _valuesOf(MachineConfig c) => {
        'round1Seconds': c.round1Seconds,
        'round2Seconds': c.round2Seconds,
        'round1Points': c.round1Points,
        'round2Points': c.round2Points,
        'qualifyScore': c.qualifyScore,
        'pesoPerGame': c.pesoPerGame,
        'displayIntensity': c.displayIntensity,
      };

  bool get _dirty {
    final saved = _saved;
    if (saved == null) return false;
    for (final entry in _valuesOf(saved).entries) {
      if (_edit[entry.key] != entry.value) return true;
    }
    return false;
  }

  int _v(String key) => _edit[key] ?? 0;

  void _set(String key, int value) {
    setState(() {
      _edit = {..._edit, key: value};
      _message = null;
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cfg = await ref.read(esp32ServiceProvider).fetchConfig();
      if (!mounted) return;
      setState(() {
        _saved = cfg;
        _edit = _valuesOf(cfg);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't read the settings from the machine.";
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    final cfg = await runAdmin<MachineConfig>(context, ref, (service) => service.saveConfig(_edit));
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (cfg != null) {
        _saved = cfg;
        _edit = _valuesOf(cfg);
        _message = 'Saved on the machine.';
      }
    });
    if (cfg != null) await ref.read(linkProvider.notifier).refreshNow();
  }

  void _discard() {
    final saved = _saved;
    if (saved == null) return;
    setState(() {
      _edit = _valuesOf(saved);
      _message = null;
    });
  }

  Future<void> _factoryReset() async {
    final ok = await confirmDialog(
      context,
      title: 'Restore factory settings?',
      message: 'Round times, points, qualify score, price, brightness AND the sensor window / '
          'detection settings go back to the values the machine shipped with.',
      confirmLabel: 'Restore',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    final cfg = await runAdmin<MachineConfig>(context, ref, (service) => service.resetConfig());
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (cfg != null) {
        _saved = cfg;
        _edit = _valuesOf(cfg);
        _message = 'Factory settings restored.';
      }
    });
    if (cfg != null) await ref.read(linkProvider.notifier).refreshNow();
  }

  @override
  Widget build(BuildContext context) {
    final gameRunning = ref.watch(linkProvider.select((s) => s.status.run.gameActive));
    final enabled = !gameRunning && !_saving;

    if (_loading) {
      return const SubScreen(
        title: 'Game Settings',
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
        title: 'Game Settings',
        children: [
          NoticeCard(icon: CupertinoIcons.wifi_slash, text: _error ?? "Couldn't read the settings."),
          const SizedBox(height: 16),
          GlassAction(icon: CupertinoIcons.arrow_clockwise, label: 'Try again', onTap: _load),
        ],
      );
    }

    final r1Points = _v('round1Points');
    final shotsNeeded = r1Points <= 0 ? 0 : (_v('qualifyScore') / r1Points).ceil();

    return SubScreen(
      title: 'Game Settings',
      children: [
        if (gameRunning) ...[
          const NoticeCard(
            icon: CupertinoIcons.game_controller_solid,
            color: CupertinoColors.systemOrange,
            text: 'A game is in progress. Settings are locked until it ends.',
          ),
          const SizedBox(height: 12),
        ],
        SectionCard(
          title: 'Round 1',
          children: [
            NumberStepper(
              label: 'Duration',
              value: _v('round1Seconds'),
              min: 10,
              max: 300,
              step: 5,
              suffix: ' s',
              enabled: enabled,
              onChanged: (v) => _set('round1Seconds', v),
            ),
            NumberStepper(
              label: 'Points per shot',
              value: _v('round1Points'),
              min: 1,
              max: 10,
              suffix: ' pts',
              enabled: enabled,
              onChanged: (v) => _set('round1Points', v),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Round 2',
          caption: "Only played when Round 1's score reaches the qualify score. Round 2 is the last round.",
          children: [
            NumberStepper(
              label: 'Duration',
              value: _v('round2Seconds'),
              min: 10,
              max: 300,
              step: 5,
              suffix: ' s',
              enabled: enabled,
              onChanged: (v) => _set('round2Seconds', v),
            ),
            NumberStepper(
              label: 'Points per shot',
              value: _v('round2Points'),
              min: 1,
              max: 10,
              suffix: ' pts',
              enabled: enabled,
              onChanged: (v) => _set('round2Points', v),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Qualifying',
          children: [
            NumberStepper(
              label: 'Score needed for Round 2',
              value: _v('qualifyScore'),
              min: 0,
              max: 500,
              step: 5,
              suffix: ' pts',
              hint: shotsNeeded == 0
                  ? 'Everyone reaches Round 2'
                  : 'About $shotsNeeded shots in Round 1 (at +$r1Points each)',
              enabled: enabled,
              onChanged: (v) => _set('qualifyScore', v),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Price & display',
          children: [
            NumberStepper(
              label: 'Price per game',
              value: _v('pesoPerGame'),
              min: 1,
              max: 1000,
              step: 5,
              suffix: ' ₱',
              hint: 'Coins needed for one credit',
              enabled: enabled,
              onChanged: (v) => _set('pesoPerGame', v),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(
                  child: Text('LED brightness', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                ),
                Text(
                  '${_v('displayIntensity')} / 15',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            CupertinoSlider(
              value: _v('displayIntensity').toDouble(),
              min: 0,
              max: 15,
              divisions: 15,
              onChanged: enabled ? (v) => _set('displayIntensity', v.round()) : null,
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
              enabled: enabled && _dirty,
              onTap: _save,
            ),
            GlassAction(
              icon: CupertinoIcons.arrow_uturn_left,
              label: 'Discard',
              enabled: enabled && _dirty,
              onTap: _discard,
            ),
            GlassAction(
              icon: CupertinoIcons.refresh_bold,
              label: 'Factory reset',
              enabled: enabled,
              onTap: _factoryReset,
            ),
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, style: captionStyle(context)),
        ],
      ],
    );
  }
}
