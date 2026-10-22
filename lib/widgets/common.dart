import 'package:flutter/material.dart';

enum Sev { bad, warn, info, ok }

Color sevColor(BuildContext c, Sev s) {
  final dark = Theme.of(c).brightness == Brightness.dark;
  switch (s) {
    case Sev.bad:
      return dark ? const Color(0xFFF07F74) : const Color(0xFFB4322A);
    case Sev.warn:
      return dark ? const Color(0xFFE2A93B) : const Color(0xFFB7790A);
    case Sev.ok:
      return dark ? const Color(0xFF5BCB87) : const Color(0xFF1C7A43);
    case Sev.info:
      return Theme.of(c).colorScheme.primary;
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, this.sev, {super.key});
  final String text;
  final Sev sev;
  @override
  Widget build(BuildContext context) {
    final col = sevColor(context, sev);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: col.withValues(alpha: .14), borderRadius: BorderRadius.circular(99)),
      child: Text(text, style: TextStyle(color: col, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Linha de lista com uma faixa de cor à esquerda que indica a urgência.
class StripeTile extends StatelessWidget {
  const StripeTile({super.key, required this.sev, required this.title, this.subtitle, this.trailing, this.onTap});
  final Sev sev;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: IntrinsicHeight(
          child: Row(children: [
            Container(
                width: 4,
                decoration: BoxDecoration(color: sevColor(context, sev), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (subtitle != null)
                  Text(subtitle!, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ]),
        ),
      ),
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text(title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            if (action != null) action!,
          ]),
          const SizedBox(height: 6),
          child,
        ]),
      ),
    );
  }
}

class Kpi extends StatelessWidget {
  const Kpi({super.key, required this.label, required this.value, this.sub, this.highlight = false, this.subColor});
  final String label, value;
  final String? sub;
  final bool highlight;
  final Color? subColor;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = highlight ? cs.onPrimaryContainer : cs.onSurface;
    return Card(
      color: highlight ? cs.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              style: TextStyle(fontSize: 11, letterSpacing: .8, fontWeight: FontWeight.w600, color: fg.withValues(alpha: .7))),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w600, color: fg, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          if (sub != null) Text(sub!, style: TextStyle(fontSize: 13, color: subColor ?? fg.withValues(alpha: .7))),
        ]),
      ),
    );
  }
}

class Empty extends StatelessWidget {
  const Empty(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
      );
}

/// Grelha que passa a uma coluna em ecrãs estreitos (telemóvel).
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.minWidth = 200, this.spacing = 12});
  final List<Widget> children;
  final double minWidth, spacing;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / minWidth).floor().clamp(1, children.length);
      final w = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: children.map((e) => SizedBox(width: w, child: e)).toList(),
      );
    });
  }
}

Future<bool> confirmDialog(BuildContext context, String text, {required String ok, required String cancel}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(cancel)),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

void snack(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
