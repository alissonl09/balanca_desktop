import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';

class AppAsset extends StatelessWidget {
  const AppAsset(
    this.name, {
    super.key,
    this.size = 28,
    this.color,
    this.label,
  });
  final String name;
  final double size;
  final Color? color;
  final String? label;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/images/$name.svg',
    width: size,
    height: size,
    semanticsLabel: label,
    colorFilter: color == null
        ? null
        : ColorFilter.mode(color!, BlendMode.srcIn),
  );
}

class VisualCard extends StatelessWidget {
  const VisualCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 10,
    this.shadow = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool shadow;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      border: shadow ? null : Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(radius),
      boxShadow: shadow
          ? const [
              BoxShadow(
                color: Color(0x14000000),
                offset: Offset(0, 3),
                blurRadius: 12,
              ),
            ]
          : null,
    ),
    child: child,
  );
}

/// Rótulo compartilhado também por campos de seleção da Pesagem.
class VisualFieldLabel extends StatelessWidget {
  const VisualFieldLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      fontSize: 14,
      height: 1,
      color: Color(0xff495057),
      fontWeight: FontWeight.w600,
    ),
  );
}

class VisualField extends StatelessWidget {
  const VisualField(
    this.label, {
    super.key,
    this.hint,
    this.readOnly = false,
    this.disabled = false,
    this.future = false,
    this.lines = 1,
    this.controller,
    this.maxLength,
    this.compact = false,
    this.fieldHeight,
    this.labelGap,
    this.focusNode,
    this.onSubmitted,
    this.suffixIcon,
    this.isDense,
  });
  static const fixedHeightContentPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 6,
  );
  final String label;
  final String? hint;
  final bool readOnly, disabled, future, compact;
  final int lines;
  final int? maxLength;
  final TextEditingController? controller;
  final double? fieldHeight, labelGap;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffixIcon;

  /// False fills a constrained decoration even when there is no suffix icon.
  /// Null preserves the existing theme for all other fields.
  final bool? isDense;

  @override
  Widget build(BuildContext context) {
    final input = TextField(
      controller: controller,
      focusNode: focusNode,
      onSubmitted: onSubmitted,
      readOnly: readOnly,
      enabled: !disabled,
      maxLines: lines,
      maxLength: maxLength,
      textAlignVertical: TextAlignVertical.center,
      style: TextStyle(
        fontSize: 14,
        color: disabled ? const Color(0xff7b858b) : AppColors.text,
      ),
      decoration: InputDecoration(
        isDense: isDense,
        hintText: hint,
        counterText: '',
        suffixIcon: suffixIcon,
        suffixIconConstraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 32,
        ),
        constraints: fieldHeight == null
            ? null
            : BoxConstraints.tightFor(height: fieldHeight),
        fillColor: disabled || future
            ? const Color(0xfff3f5f4)
            : readOnly
            ? const Color(0xfff8f9fa)
            : Colors.white,
        hintStyle: TextStyle(
          color: disabled ? const Color(0xff7b858b) : const Color(0xff9ca5aa),
          fontSize: 14,
        ),
        contentPadding: fieldHeight == null
            ? EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 8 : 11)
            : fixedHeightContentPadding,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VisualFieldLabel(label),
        SizedBox(height: labelGap ?? (compact ? 4 : 6)),
        input,
      ],
    );
  }
}

class PageHeading extends StatelessWidget {
  const PageHeading({
    super.key,
    required this.title,
    required this.subtitle,
    this.asset,
    this.icon,
  }) : assert((asset == null) != (icon == null));
  final String title, subtitle;
  final String? asset;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.paleGreen,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Center(
          child: Transform.scale(
            scale: asset == 'balanca_icon' ? 1.25 : 1,
            child: icon != null
                ? Icon(icon, size: 27, color: AppColors.green)
                : AppAsset(
                    asset!,
                    size: asset == 'balanca_icon' ? 38 : 27,
                    color: AppColors.green,
                  ),
          ),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xff212529),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ],
        ),
      ),
    ],
  );
}
