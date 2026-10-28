import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'common_widgets.dart';
import 'esp32_service.dart';
import 'providers.dart';

/// Makes sure the person may use admin screens. Returns true when:
///  * the machine has no PIN set, or
///  * the PIN was already entered and hasn't timed out, or
///  * the person just typed the right PIN.
Future<bool> ensureAdmin(BuildContext context, WidgetRef ref) async {
  if (!ref.read(linkProvider).isOnline) {
    await showInfoDialog(
      context,
      title: 'Not connected',
      message: "Join the machine's Wi-Fi first, then try again.",
    );
    return false;
  }
  if (ref.read(adminAccessProvider)) {
    ref.read(adminProvider.notifier).touch();
    return true;
  }
  if (!context.mounted) return false;
  final ok = await showCupertinoDialog<bool>(
    context: context,
    builder: (dialogContext) => const _PinDialog(),
  );
  return ok == true;
}

class _PinDialog extends ConsumerStatefulWidget {
  const _PinDialog();

  @override
  ConsumerState<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends ConsumerState<_PinDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final pin = _controller.text.trim();
    if (pin.length < 4) {
      setState(() => _error = 'Enter your 4 to 8 digit PIN.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref.read(adminProvider.notifier).unlock(pin);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = error;
        _controller.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: const Text('Admin PIN'),
      content: Column(
        children: [
          const SizedBox(height: 8),
          const Text('Enter the PIN to change machine settings.'),
          const SizedBox(height: 12),
          CupertinoTextField(
            controller: _controller,
            placeholder: 'PIN',
            obscureText: true,
            maxLength: 8,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(fontSize: 13, color: CupertinoColors.systemRed),
            ),
          ],
        ],
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: _submit,
          child: _busy ? const CupertinoActivityIndicator() : const Text('Unlock'),
        ),
      ],
    );
  }
}

/// Runs one call against the machine and deals with every way it can fail,
/// so each screen doesn't repeat that code:
///  * wrong / expired PIN  -> locks the admin session and says so
///  * game running (409)   -> tells the person to wait
///  * anything else        -> shows the machine's own message
/// Returns the result, or null if the call failed (an explanation was shown).
Future<T?> runAdmin<T>(
  BuildContext context,
  WidgetRef ref,
  Future<T> Function(Esp32Service service) action, {
  String failTitle = "Couldn't do that",
}) async {
  String message;
  try {
    final result = await action(ref.read(esp32ServiceProvider));
    ref.read(adminProvider.notifier).touch();
    return result;
  } on Esp32Exception catch (e) {
    if (e.needsPin) {
      ref.read(adminProvider.notifier).lock();
      message = 'The admin PIN is missing or no longer valid. Unlock again.';
    } else if (e.lockedOut) {
      message = 'Too many wrong PINs. Wait ${e.retryS ?? 30} seconds.';
    } else if (e.busy) {
      message = 'A game is in progress. Try again when it ends.';
    } else {
      message = e.message;
    }
  } catch (_) {
    message = "Couldn't reach the machine. Check the Wi-Fi connection.";
  }
  if (context.mounted) {
    await showInfoDialog(context, title: failTitle, message: message);
  }
  return null;
}

/// Same as [runAdmin] for calls that return nothing. True = it worked.
Future<bool> runAdminVoid(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function(Esp32Service service) action, {
  String failTitle = "Couldn't do that",
}) async {
  final result = await runAdmin<bool>(
    context,
    ref,
    (service) async {
      await action(service);
      return true;
    },
    failTitle: failTitle,
  );
  return result == true;
}
