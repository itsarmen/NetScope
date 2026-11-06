/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../models.dart';
import 'app_theme.dart';

export 'app_theme.dart';

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color kBorder(BuildContext context) =>
    _isDark(context) ? AppColors.darkBorder : AppColors.border;

Color kDivider(BuildContext context) =>
    _isDark(context) ? AppColors.darkDivider : AppColors.divider;

Color kBorderField(BuildContext context) =>
    _isDark(context) ? AppColors.darkBorderField : AppColors.borderField;

Color kBorderHover(BuildContext context) =>
    _isDark(context) ? AppColors.darkBorderHover : AppColors.borderHover;

Color kBorderSelected(BuildContext context) =>
    _isDark(context) ? AppColors.darkBorderSelected : AppColors.borderSelected;

Color kSurface(BuildContext context) => Theme.of(context).colorScheme.surface;

Color severityColor(Severity severity) => switch (severity) {
      Severity.info => AppColors.secondary,
      Severity.low => AppColors.info,
      Severity.medium => AppColors.warning,
      Severity.high => AppColors.error,
      Severity.critical => AppColors.error,
    };

Color directionColor(Direction direction) => switch (direction) {
      Direction.outbound => AppColors.info,
      Direction.inbound => AppColors.warning,
      Direction.loopback => AppColors.secondary,
      Direction.listening => AppColors.success,
    };

Color protocolColor(String protocol) => switch (protocol.toLowerCase()) {
      'tcp' => AppColors.info,
      'udp' => AppColors.purple,
      'dns' => AppColors.success,
      _ => AppColors.secondary,
    };

// ---------------------------------------------------------------------------
// Badges
// ---------------------------------------------------------------------------

class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    required this.color,
    this.width,
    this.height = AppSizes.badgeH,
  });

  final String label;
  final Color color;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: width,
      child: Center(
        child: Container(
          height: height,
          width: width,
          alignment: Alignment.center,
          padding: width == null
              ? const EdgeInsets.symmetric(horizontal: 8)
              : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: kSurface(context),
            borderRadius: BorderRadius.circular(AppSizes.radiusBadge),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: AppSizes.fontBadge,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

class DirectionBadge extends StatelessWidget {
  const DirectionBadge(this.direction, {super.key});

  final Direction direction;

  @override
  Widget build(BuildContext context) => AppBadge(
        label: direction.label,
        color: directionColor(direction),
        width: AppSizes.badgeMethodW,
      );
}

class ProtocolBadge extends StatelessWidget {
  const ProtocolBadge(this.protocol, {super.key});

  final String protocol;

  @override
  Widget build(BuildContext context) => AppBadge(
        label: protocol.isEmpty ? '?' : protocol.toUpperCase(),
        color: protocolColor(protocol),
        width: AppSizes.badgeMethodW,
      );
}

class RiskBadge extends StatelessWidget {
  const RiskBadge({super.key, required this.severity, required this.score});

  final Severity severity;
  final int score;

  @override
  Widget build(BuildContext context) => AppBadge(
        label: score > 0 ? '$score' : severity.label,
        color: severityColor(severity),
        width: AppSizes.badgeStatusW,
      );
}

class CountPill extends StatelessWidget {
  const CountPill(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSizes.countBadgeH,
      constraints: const BoxConstraints(minWidth: AppSizes.countBadgeMinW),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kSurface(context),
        borderRadius: BorderRadius.circular(AppSizes.radiusCount),
        border: Border.all(color: kBorder(context)),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: AppColors.secondary,
          fontSize: AppSizes.fontBadge,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Copy
// ---------------------------------------------------------------------------

class CopyButton extends StatefulWidget {
  const CopyButton({
    super.key,
    required this.text,
    this.size = AppSizes.iconButton,
    this.iconSize = AppSizes.iconButtonIcon,
    this.tooltip = 'Copy',
    this.bordered = true,
  });

  final String text;
  final double size;
  final double iconSize;
  final String tooltip;
  final bool bordered;

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _done = false;
  bool _hovered = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _copy() {
    if (widget.text.isEmpty) {
      copyToClipboard(context, '', widget.tooltip);
      return;
    }
    Clipboard.setData(ClipboardData(text: widget.text));
    setState(() => _done = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _done = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppSizes.radius);
    return Tooltip(
      message: widget.tooltip,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              onTap: _copy,
              borderRadius: radius,
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: widget.bordered
                      ? Border.all(
                          color: _hovered
                              ? kBorderHover(context)
                              : kBorder(context),
                        )
                      : null,
                ),
                child: Icon(
                  _done ? Icons.check : Icons.copy_outlined,
                  size: widget.iconSize,
                  color: _done ? AppColors.success : AppColors.secondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Layout helpers
// ---------------------------------------------------------------------------

class Card2 extends StatelessWidget {
  const Card2({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? kSurface(context),
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: kBorder(context)),
      ),
      child: child,
    );
  }
}

InputDecoration softDecoration(
  BuildContext context, {
  String? label,
  String? hint,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radius),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    isDense: true,
    filled: false,
    fillColor: Colors.transparent,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    border: border(Colors.transparent, 0),
    enabledBorder: border(kBorderField(context), 1),
    focusedBorder: border(AppColors.accent, 1.5),
    errorBorder: border(const Color(0xFFD9534F), 1),
    focusedErrorBorder: border(const Color(0xFFD9534F), 1),
    hintStyle: const TextStyle(
      color: AppColors.placeholder,
      fontSize: AppSizes.fontBody,
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.secondary,
                fontSize: AppSizes.fontSection,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class MonoBox extends StatelessWidget {
  const MonoBox({
    super.key,
    required this.text,
    this.height,
    this.selectable = true,
  });

  final String text;
  final double? height;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final style = const TextStyle(
      fontFamily: 'monospace',
      fontSize: AppSizes.fontMono,
      height: 1.5,
      color: AppColors.text,
    );
    final content = text.isEmpty ? '(none)' : text;
    return Container(
      width: double.infinity,
      height: height,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurface(context),
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: kBorder(context)),
      ),
      child: SingleChildScrollView(
        child: selectable
            ? SelectableText(content, style: style)
            : Text(content, style: style),
      ),
    );
  }
}

void copyToClipboard(BuildContext context, String text, String label) {
  if (text.isEmpty) {
    Fluttertoast.showToast(
      msg: 'Nothing to copy ($label)',
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM_RIGHT,
      timeInSecForIosWeb: 2,
      backgroundColor: Colors.black87,
      textColor: Colors.white,
    );
    return;
  }
  Clipboard.setData(ClipboardData(text: text));
  Fluttertoast.showToast(
    msg: 'Copied $label (${text.length} chars)',
    toastLength: Toast.LENGTH_SHORT,
    gravity: ToastGravity.BOTTOM_RIGHT,
    timeInSecForIosWeb: 2,
    backgroundColor: Colors.black87,
    textColor: Colors.white,
  );
}
