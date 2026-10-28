import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Page shell used by every screen reached from Settings: floating glass app
/// bar with a back button, and a scrolling body that clears the bar.
class SubScreen extends StatelessWidget {
  const SubScreen({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(
        title: Text(title),
        centerTitle: true,
        leading: SizedBox(
          width: 44,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            child: const Icon(CupertinoIcons.back),
          ),
        ),
        // Balances the leading back button so the title sits in the middle.
        actions: const [SizedBox(width: 44)],
      ),
      appBarHeight: 44,
      body: SafeArea(
        child: ListView(
          // GlassScaffold's app bar floats over the body, so the top inset
          // has to clear the bar's own 44 px.
          padding: const EdgeInsets.fromLTRB(16, 56, 16, 32),
          children: children,
        ),
      ),
    );
  }
}

const TextStyle kCardTitle = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);

/// Cupertino's label colours come in a light and a dark version, but a plain
/// `TextStyle(color: dimColor(context))` always paints the light
/// one - dark grey, almost invisible on a dark background. These resolve the
/// colour against the current theme, so use them instead of the raw constants.
Color dimColor(BuildContext context) => CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
Color mainColor(BuildContext context) => CupertinoDynamicColor.resolve(CupertinoColors.label, context);

/// Small grey helper text (captions, units, hints).
TextStyle captionStyle(BuildContext context, {double size = 12}) =>
    TextStyle(fontSize: size, color: dimColor(context));

/// A glass card with a title, an optional caption and any content.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    this.caption,
    required this.children,
    this.trailing,
  });

  final String title;
  final String? caption;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: kCardTitle)),
              if (trailing != null) trailing!,
            ],
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(caption!, style: captionStyle(context)),
          ],
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

/// Small coloured status dot.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.on, this.size = 8});

  final bool on;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? CupertinoColors.activeGreen : CupertinoColors.systemRed,
      ),
    );
  }
}

/// "Label ........ value" row for read-only facts.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 14, color: dimColor(context))),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rectangular glass button with an icon and a visible label. It can be
/// switched off and shows a spinner while busy.
///
/// It sizes itself to its content (so it works in a Wrap or a Row) and fills
/// the width it is given (inside an Expanded, or as a direct child of a list).
class GlassAction extends StatelessWidget {
  const GlassAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final color = mainColor(context);
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color),
    );
    return GlassButton.custom(
      onTap: onTap,
      enabled: enabled && !busy,
      label: label,
      height: 48,
      shape: const LiquidRoundedRectangle(borderRadius: 14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        // A Flexible child needs a bounded width: inside a Wrap / Expanded the
        // label can shrink with "...", in a bare Row it just takes its size.
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Center(
                  child: busy ? const CupertinoActivityIndicator(radius: 8) : Icon(icon, size: 19, color: color),
                ),
              ),
              const SizedBox(width: 8),
              if (constraints.hasBoundedWidth) Flexible(child: text) else text,
            ],
          ),
        ),
      ),
    );
  }
}

/// Tappable row for navigation lists (Settings).
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.locked = false,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Shows a small padlock (admin PIN needed).
  final bool locked;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: CupertinoColors.activeOrange),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: kCardTitle),
                  const SizedBox(height: 2),
                  Text(subtitle, style: captionStyle(context)),
                ],
              ),
            ),
            if (trailing != null) ...[trailing!, const SizedBox(width: 10)],
            if (locked) ...[
              Icon(CupertinoIcons.lock_fill, size: 14, color: dimColor(context)),
              const SizedBox(width: 10),
            ],
            Icon(CupertinoIcons.chevron_right, size: 16, color: dimColor(context)),
          ],
        ),
      ),
    );
  }
}

/// Banner for a problem the person needs to know about (offline, game running...).
class NoticeCard extends StatelessWidget {
  const NoticeCard({
    super.key,
    required this.icon,
    required this.text,
    this.color = CupertinoColors.systemRed,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: CupertinoColors.activeOrange.withValues(alpha: active ? 0.18 : 0.06),
        ),
        child: Icon(
          icon,
          size: 18,
          color: active ? CupertinoColors.activeOrange : CupertinoColors.systemGrey,
        ),
      ),
    );
  }
}

/// "Label   (-)  60 s  (+)" control for whole-number settings.
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.suffix = '',
    this.hint,
    this.enabled = true,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final String suffix;
  final String? hint;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final canDown = enabled && value > min;
    final canUp = enabled && value < max;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(hint!, style: TextStyle(fontSize: 11, color: dimColor(context))),
                ],
              ],
            ),
          ),
          _RoundButton(
            icon: CupertinoIcons.minus,
            onTap: canDown ? () => onChanged((value - step).clamp(min, max).toInt()) : null,
          ),
          SizedBox(
            width: 74,
            child: Text(
              '$value$suffix',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          _RoundButton(
            icon: CupertinoIcons.plus,
            onTap: canUp ? () => onChanged((value + step).clamp(min, max).toInt()) : null,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialogs
// ---------------------------------------------------------------------------

Future<void> showInfoDialog(BuildContext context, {required String title, required String message}) {
  return showCupertinoDialog<void>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(message),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Yes / No question. Returns true only when the person confirms.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showCupertinoDialog<bool>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(message),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        CupertinoDialogAction(
          isDestructiveAction: destructive,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

/// Single text-field prompt. Returns the typed text, or null if cancelled.
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  String? message,
  String placeholder = '',
  String initial = '',
  bool obscure = false,
  int? maxLength,
  TextInputType keyboardType = TextInputType.text,
  String confirmLabel = 'OK',
  List<TextInputFormatter> inputFormatters = const [],
}) {
  return showCupertinoDialog<String>(
    context: context,
    builder: (dialogContext) => _TextPromptDialog(
      title: title,
      message: message,
      placeholder: placeholder,
      initial: initial,
      obscure: obscure,
      maxLength: maxLength,
      keyboardType: keyboardType,
      confirmLabel: confirmLabel,
      inputFormatters: inputFormatters,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.message,
    required this.placeholder,
    required this.initial,
    required this.obscure,
    required this.maxLength,
    required this.keyboardType,
    required this.confirmLabel,
    required this.inputFormatters,
  });

  final String title;
  final String? message;
  final String placeholder;
  final String initial;
  final bool obscure;
  final int? maxLength;
  final TextInputType keyboardType;
  final String confirmLabel;
  final List<TextInputFormatter> inputFormatters;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text(widget.title),
      content: Column(
        children: [
          if (widget.message != null) ...[
            const SizedBox(height: 8),
            Text(widget.message!),
          ],
          const SizedBox(height: 12),
          CupertinoTextField(
            controller: _controller,
            placeholder: widget.placeholder,
            obscureText: widget.obscure,
            maxLength: widget.maxLength,
            keyboardType: widget.keyboardType,
            inputFormatters: widget.inputFormatters,
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// "5s ago" / "3m ago" style text.
String ago(int seconds) {
  if (seconds < 0) return 'never';
  if (seconds < 3) return 'just now';
  if (seconds < 60) return '${seconds}s ago';
  if (seconds < 3600) return '${seconds ~/ 60}m ago';
  return '${seconds ~/ 3600}h ago';
}

/// 93784 -> "1d 2h 3m" / "2h 3m" / "3m 4s".
String formatUptime(int seconds) {
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (d > 0) return '${d}d ${h}h ${m}m';
  if (h > 0) return '${h}h ${m}m';
  return '${m}m ${s}s';
}

/// 1234 -> "₱1,234".
String formatPeso(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    final posFromEnd = digits.length - i;
    buffer.write(digits[i]);
    if (posFromEnd > 1 && posFromEnd % 3 == 1) buffer.write(',');
  }
  return '${amount < 0 ? '-' : ''}₱$buffer';
}
