import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'common_widgets.dart';
import 'native_network.dart';
import 'providers.dart';

/// Shows whether the phone is talking to the machine, helps the person join
/// the machine's Wi-Fi, and reconnects on its own the moment the phone is on
/// that network -- nothing to press.
///
/// [isGate] = true: the full-screen version shown when the app starts
/// before the machine has ever answered (it disappears by itself once
/// connected). false: the normal page opened from Settings or the offline
/// banner, with a back button.
class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key, this.isGate = false});

  final bool isGate;

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Re-draw once a second so "last seen 5s ago" keeps counting.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _openWifiSettings() async {
    final opened = await NativeNetwork.openWifiSettings();
    if (!opened && mounted) {
      await showInfoDialog(
        context,
        title: 'Open Wi-Fi settings',
        message: "Open your phone's Settings > Wi-Fi and join the machine's network, then come back here.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = ref.watch(linkProvider);
    final ssid = ref.watch(knownSsidProvider);
    final ip = ref.watch(esp32IpProvider);

    final children = <Widget>[
      _HeroCard(link: link, ssid: ssid),
      const SizedBox(height: 16),
      if (link.isOnline)
        SectionCard(
          title: 'Connection details',
          children: [
            InfoRow(label: 'Machine address', value: ip),
            InfoRow(label: 'Wi-Fi name', value: link.status.apSsid.isEmpty ? ssid : link.status.apSsid),
            InfoRow(label: 'Firmware', value: link.status.firmware.isEmpty ? '-' : link.status.firmware),
            InfoRow(
              label: 'Updates',
              value: link.transport == LinkTransport.webSocket ? 'Live (WebSocket)' : 'Refreshing every second',
            ),
            InfoRow(label: 'Phones on the hotspot', value: '${link.status.clients}'),
          ],
        )
      else
        SectionCard(
          title: 'How to connect',
          caption: 'The machine makes its own Wi-Fi network. No router or internet is needed.',
          children: [
            _Step(number: 1, text: 'Tap "Open Wi-Fi settings" below.'),
            _Step(
              number: 2,
              text: 'Join the network "$ssid".'
                  '${ssid == defaultApSsid ? ' Default password: $defaultApPassword.' : ' Use the password you set for it.'}',
            ),
            const _Step(
              number: 3,
              text: 'If the phone says "No internet connection - stay connected?", choose Stay connected / Yes.',
            ),
            const _Step(
              number: 4,
              text: 'Come back to this app. It connects by itself within a few seconds.',
            ),
          ],
        ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: GlassAction(
              icon: CupertinoIcons.wifi,
              label: 'Wi-Fi settings',
              onTap: _openWifiSettings,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GlassAction(
              icon: CupertinoIcons.arrow_clockwise,
              label: 'Try now',
              onTap: () => ref.read(linkProvider.notifier).reconnectNow(),
            ),
          ),
        ],
      ),
      if (widget.isGate) ...[
        const SizedBox(height: 12),
        Center(
          child: CupertinoButton(
            onPressed: () => ref.read(gateDismissedProvider.notifier).state = true,
            child: const Text('Continue without the machine'),
          ),
        ),
      ],
    ];

    if (!widget.isGate) {
      return SubScreen(title: 'Connection', children: children);
    }

    return GlassScaffold(
      appBar: GlassAppBar(title: const Text('The Bit Ballers')),
      appBarHeight: 44,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 56, 16, 32),
          children: children,
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.link, required this.ssid});

  final LinkState link;
  final String ssid;

  @override
  Widget build(BuildContext context) {
    final Widget icon;
    final String title;
    final String subtitle;

    if (link.isOnline) {
      icon = const Icon(CupertinoIcons.checkmark_circle_fill, size: 54, color: CupertinoColors.activeGreen);
      title = 'Connected';
      subtitle = link.transport == LinkTransport.webSocket
          ? 'Live updates from "$ssid"'
          : 'Linked to "$ssid"';
    } else {
      icon = const SizedBox(
        height: 54,
        child: Center(child: CupertinoActivityIndicator(radius: 20)),
      );
      title = link.everConnected ? 'Connection lost' : 'Looking for the machine...';
      final lastSeen = link.lastSeen;
      final seen = lastSeen == null
          ? 'not seen yet'
          : 'last seen ${ago(DateTime.now().difference(lastSeen).inSeconds)}';
      subtitle = 'Retrying automatically - $seen'
          '${link.failedAttempts > 1 ? ' (try ${link.failedAttempts})' : ''}';
    }

    return GlassCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          icon,
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: dimColor(context)),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CupertinoColors.activeOrange.withValues(alpha: 0.2),
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: CupertinoColors.activeOrange,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
