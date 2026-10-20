import 'package:flutter/material.dart';

import '../theme.dart';
import 'shell.dart';

enum BtnVariant { primary, gold, outline, ghost, destructive, light }

/// Pill button with a soft press-in, used everywhere in the app.
class Btn extends StatelessWidget {
  const Btn({super.key, required this.label, this.onTap, this.variant = BtnVariant.primary, this.expand = true, this.icon, this.loading = false, this.height = 52});
  final String label;
  final VoidCallback? onTap;
  final BtnVariant variant;
  final bool expand, loading;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null || loading;
    Color fg;
    BoxDecoration deco;
    switch (variant) {
      case BtnVariant.primary:
        fg = Colors.white;
        deco = BoxDecoration(color: AppColors.maroon, borderRadius: BorderRadius.circular(AppRadius.lg), boxShadow: AppShadows.lift);
      case BtnVariant.gold:
        fg = AppColors.maroon;
        deco = BoxDecoration(gradient: AppGradients.gold, borderRadius: BorderRadius.circular(AppRadius.lg), boxShadow: AppShadows.soft);
      case BtnVariant.outline:
        fg = AppColors.maroon;
        deco = BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: AppColors.border));
      case BtnVariant.ghost:
        fg = AppColors.maroon;
        deco = const BoxDecoration();
      case BtnVariant.destructive:
        fg = Colors.white;
        deco = BoxDecoration(color: AppColors.destructive, borderRadius: BorderRadius.circular(AppRadius.lg));
      case BtnVariant.light:
        fg = Colors.white;
        deco = BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: Colors.white54));
    }
    final child = AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: disabled && !loading ? 0.45 : 1,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: deco,
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
            else if (icon != null)
              Icon(icon, size: 19, color: fg),
            if (loading || icon != null) const SizedBox(width: 10),
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.sans(size: 15, weight: FontWeight.w600, color: fg)),
            ),
          ],
        ),
      ),
    );
    return Pressable(onTap: disabled ? null : onTap, child: child);
  }
}

/// Scales down slightly while pressed.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(scale: _down ? 0.97 : 1, duration: const Duration(milliseconds: 90), child: widget.child),
      );
}

/// A photo that never shows a broken icon — a maroon panel with the monogram
/// takes its place if the asset cannot be loaded.
class AuraImage extends StatelessWidget {
  const AuraImage(this.path, {super.key, this.fit = BoxFit.cover, this.alignment = Alignment.center, this.radius = 0, this.width, this.height});
  final String path;
  final BoxFit fit;
  final Alignment alignment;
  final double radius;
  final double? width, height;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      path,
      fit: fit,
      alignment: alignment,
      width: width,
      height: height,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => Container(
        width: width,
        height: height,
        decoration: const BoxDecoration(gradient: AppGradients.maroon),
        alignment: Alignment.center,
        child: const Logo(size: 36),
      ),
    );
    return radius == 0 ? image : ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
  }
}

class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 44, this.ring = true});
  final double size;
  final bool ring;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.08),
        decoration: BoxDecoration(
          color: AppColors.maroonInk,
          borderRadius: BorderRadius.circular(size * 0.28),
          border: ring ? Border.all(color: AppColors.gold.withValues(alpha: 0.55)) : null,
          boxShadow: AppShadows.soft,
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset('assets/images/aura-mark.png', fit: BoxFit.contain),
      );
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.size = 44, this.gold = false});
  final String name;
  final double size;
  final bool gold;
  @override
  Widget build(BuildContext context) {
    final initials = name.split(' ').where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join().toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gold ? AppGradients.gold : null,
        color: gold ? null : AppColors.secondary,
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Text(initials, style: AppText.display(size: size * 0.36, color: AppColors.maroon)),
    );
  }
}

class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.subtitle, this.trailing, this.back = false});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool back;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 12, 16, 12),
        decoration: const BoxDecoration(color: AppColors.background, border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(
          children: [
            if (back) ...[
              Pressable(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: AppColors.card, shape: BoxShape.circle, border: Border.all(color: AppColors.border), boxShadow: AppShadows.soft),
                  child: const Icon(Icons.chevron_left_rounded, color: AppColors.foreground),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.display(size: 20)),
                  if (subtitle != null)
                    Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: Text(title, style: AppText.display(size: 19))),
            if (action != null)
              GestureDetector(onTap: onAction, child: Text(action!, style: AppText.sans(size: 12.5, weight: FontWeight.w600, color: AppColors.maroon))),
          ],
        ),
      );
}

class AuraCard extends StatelessWidget {
  const AuraCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color = AppColors.card, this.borderColor, this.radius = AppRadius.xl});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color color;
  final Color? borderColor;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: child,
    );
    return onTap == null ? box : Pressable(onTap: onTap, child: box);
  }
}

class ChipPill extends StatelessWidget {
  const ChipPill(this.label, {super.key, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.maroon : AppColors.card,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? AppColors.maroon : AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 15, color: selected ? AppColors.goldLight : AppColors.maroon), const SizedBox(width: 6)],
            Text(label, style: AppText.sans(size: 12.5, weight: FontWeight.w600, color: selected ? Colors.white : AppColors.foreground)),
          ]),
        ),
      );
}

class Badge2 extends StatelessWidget {
  const Badge2(this.label, {super.key, this.bg = AppColors.goldSoft, this.fg = AppColors.maroon});
  final String label;
  final Color bg, fg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: AppText.sans(size: 10.5, weight: FontWeight.w700, color: fg)),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.action});
  final IconData icon;
  final String title, body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(color: AppColors.goldSoft, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.maroon, size: 32),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: AppText.display(size: 18)),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: AppText.sans(size: 13.5, color: AppColors.mutedForeground, height: 1.4)),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ]),
      );
}

/// Rounded bottom sheet with a grab handle, sized to its content.
Future<T?> showAuraSheet<T>(BuildContext context, {required WidgetBuilder builder, bool scroll = true}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 480, maxHeight: MediaQuery.of(ctx).size.height * 0.92),
          child: Container(
            decoration: const BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl))),
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 10),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(9))),
                Flexible(
                  child: scroll
                      ? SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 20), child: builder(ctx))
                      : Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 20), child: builder(ctx)),
                ),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
}

void toast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    content: Row(children: [
      Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded, color: error ? const Color(0xFFFF9AA2) : AppColors.goldLight, size: 19),
      const SizedBox(width: 10),
      Expanded(child: Text(message)),
    ]),
    duration: const Duration(milliseconds: 2400),
  ));
}

Future<bool> confirmDialog(BuildContext context, {required String title, required String body, required String confirm, bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      title: Text(title, style: AppText.display(size: 18)),
      content: Text(body, style: AppText.sans(size: 14, color: AppColors.mutedForeground, height: 1.4)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Keep', style: AppText.sans(weight: FontWeight.w600, color: AppColors.mutedForeground))),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirm, style: AppText.sans(weight: FontWeight.w700, color: danger ? AppColors.destructive : AppColors.maroon))),
      ],
    ),
  );
  return r ?? false;
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.bold = false, this.valueColor});
  final String label, value;
  final bool bold;
  final Color? valueColor;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: AppText.sans(size: 13.5, color: AppColors.mutedForeground))),
          Text(value, style: AppText.sans(size: 13.5, weight: bold ? FontWeight.w700 : FontWeight.w500, color: valueColor ?? AppColors.foreground)),
        ]),
      );
}

/// Standard pushed page: phone frame, header with back button, scrolling body.
class AuraPage extends StatelessWidget {
  const AuraPage({super.key, required this.title, this.subtitle, this.trailing, required this.body, this.bottom, this.scroll = true, this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 32)});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget body;
  final Widget? bottom;
  final bool scroll;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => PhoneFrame(
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: Column(children: [
            ScreenHeader(title: title, subtitle: subtitle, trailing: trailing, back: true),
            Expanded(child: scroll ? SingleChildScrollView(padding: padding, child: body) : body),
          ]),
          bottomNavigationBar: bottom == null
              ? null
              : Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: const BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.border))),
                  child: SafeArea(top: false, child: bottom!),
                ),
        ),
      );
}
