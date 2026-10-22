import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/format.dart';
import '../state/app_state.dart';
import 'common.dart';

class AlertItem {
  AlertItem(this.sev, this.when, this.title, this.subtitle, this.trailing);
  final Sev sev;
  final DateTime when;
  final String title, subtitle;
  final String trailing;
}

/// Tudo o que precisa de atenção: validades, stock baixo, contas a vencer.
List<AlertItem> buildAlerts(AppState app) {
  final s = app.s;
  final now = DateTime.now();
  final out = <AlertItem>[];

  for (final p in app.products) {
    final n = p.daysToExpiry(now);
    if (n != null && n <= 30 && p.qty > 0) {
      out.add(AlertItem(
        n <= 7 ? Sev.bad : Sev.warn,
        p.expiry!,
        p.name,
        '${s.t('expiry')}: ${fmtDate(p.expiry!, s.lang)} · ${p.qty} un.',
        n < 0 ? s.t('expired') : s.t('expiresIn').replaceAll('{n}', '$n'),
      ));
    }
    if (p.isLow) {
      out.add(AlertItem(Sev.warn, now, p.name, '${p.qty} / ${s.t('minQty')} ${p.minQty}', s.t('lowStock')));
    }
  }
  for (final b in app.bills.where((b) => b.isOpen)) {
    final n = daysFromToday(b.due);
    if (n > 7) continue;
    out.add(AlertItem(
      n < 0 ? Sev.bad : (n <= 1 ? Sev.warn : Sev.info),
      b.due,
      '${b.isReceivable ? s.t('receivable') : s.t('payable')} · ${b.party}',
      dueText(b.due, s),
      kz(b.remaining),
    ));
  }
  if (app.isOwner) {
    for (final r in app.dueReminders) {
      out.add(AlertItem(Sev.warn, r.at, s.t('notifSendReminder'), r.customer.name, kz(r.bill.remaining)));
    }
  }
  const rank = {Sev.bad: 0, Sev.warn: 1, Sev.info: 2, Sev.ok: 3};
  out.sort((a, b) => rank[a.sev]!.compareTo(rank[b.sev]!) != 0 ? rank[a.sev]!.compareTo(rank[b.sev]!) : a.when.compareTo(b.when));
  return out;
}

String dueText(DateTime due, S s) {
  final n = daysFromToday(due);
  if (n < 0) return '${-n} ${s.t('days')} ${s.t('overdue')} · ${fmtDate(due, s.lang)}';
  if (n == 0) return '${s.t('today')} · ${fmtTime(due)}';
  return fmtDateTime(due, s.lang);
}

Sev dueSev(DateTime due) {
  final n = daysFromToday(due);
  return n < 0 ? Sev.bad : (n <= 1 ? Sev.warn : Sev.info);
}

class AlertList extends StatelessWidget {
  const AlertList({super.key, required this.items, required this.emptyText});
  final List<AlertItem> items;
  final String emptyText;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return Empty(emptyText);
    return Column(children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const Divider(height: 1),
        StripeTile(
          sev: items[i].sev,
          title: items[i].title,
          subtitle: items[i].subtitle,
          trailing: Text(items[i].trailing, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
        ),
      ],
    ]);
  }
}
