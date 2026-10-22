import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/db.dart';
import '../services/format.dart';
import '../services/messaging.dart';
import '../state/app_state.dart';
import '../widgets/alerts.dart';
import '../widgets/common.dart';
import '../widgets/payment_dialogs.dart';
import 'customers_screen.dart';
import 'home_shell.dart';
import 'sales_screen.dart';

Future<void> openLedger(BuildContext context, Customer c) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(appBar: AppBar(), body: CustomerLedgerScreen(customerId: c.id)),
    ));

/// Extrato do cliente: o que deve agora, contas em aberto, e todo o histórico
/// (compras, pagamentos, mudanças de data).
class CustomerLedgerScreen extends StatelessWidget {
  const CustomerLedgerScreen({super.key, required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final c = app.customerById(customerId);
    if (c == null) return Empty(s.t('nothing'));
    final open = app.openBillsOf(c.id);
    final owed = open.fold<int>(0, (a, b) => a + b.remaining);
    final overdue = open.where((b) => daysFromToday(b.due) < 0).fold<int>(0, (a, b) => a + b.remaining);
    final allBills = app.bills.where((b) => b.isReceivable && b.partyId == c.id).toList();

    return PageScaffold(
      title: c.name,
      subtitle: [c.contact, c.phone, c.email].where((x) => x.isNotEmpty).join(' · '),
      actions: [
        OutlinedButton.icon(
          icon: const Icon(Icons.edit_outlined),
          label: Text(s.t('editCustomer')),
          onPressed: () => openCustomerForm(context, customer: c),
        ),
        if (c.phone.isNotEmpty && owed > 0)
          OutlinedButton.icon(
            icon: const Icon(Icons.chat),
            label: Text(s.t('sendStatement')),
            onPressed: () => Messaging.whatsapp(c.phone, app.statementText(c)),
          ),
        FilledButton.icon(
          icon: const Icon(Icons.payments_outlined),
          label: Text(s.t('receivePayment')),
          onPressed: owed <= 0
              ? null
              : () async {
                  final r = await askPayment(context, title: c.name, max: owed);
                  if (r == null) return;
                  final used = await Db.I.receiveFromCustomer(open, r.$1, method: r.$2);
                  if (context.mounted) snack(context, '${s.t('markedRecv')}: ${kz(used)}');
                },
        ),
      ],
      children: [
        ResponsiveGrid(minWidth: 200, children: [
          Kpi(label: s.t('totalOwed'), value: kz(owed), highlight: true),
          Kpi(
            label: s.t('overdue'),
            value: kz(overdue),
            subColor: overdue > 0 ? sevColor(context, Sev.bad) : null,
          ),
          Kpi(label: s.t('creditLimit'), value: c.creditLimit > 0 ? kz(c.creditLimit) : '—'),
        ]),
        const SizedBox(height: 16),
        Panel(
          title: '${s.t('openBills')} (${open.length})',
          child: open.isEmpty
              ? Empty(s.t('nothing'))
              : Column(children: [
                  for (final b in open)
                    StripeTile(
                      sev: dueSev(b.due),
                      title: '${b.note.isEmpty ? s.t('receivable') : b.note} · ${kz(b.remaining)}',
                      subtitle: '${s.t('due')} ${dueText(b.due, s)}${dueMovedText(b, s.lang, s.t('dueMovedFrom'))}'
                          '${b.paidAmount > 0 ? ' · ${s.t('partial')}: ${kz(b.paidAmount)} / ${kz(b.amount)}' : ''}',
                      trailing: app.isOwner
                          ? IconButton(
                              tooltip: s.t('changeDue'),
                              icon: const Icon(Icons.edit_calendar_outlined),
                              onPressed: () => changeDueDialog(context, b),
                            )
                          : null,
                    ),
                ]),
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<Sale>>(
          stream: Db.I.salesOfCustomer(c.id),
          builder: (context, snap) => Panel(
            title: s.t('history'),
            child: _History(sales: snap.data ?? const [], bills: allBills),
          ),
        ),
      ],
    );
  }
}

class _Entry {
  _Entry(this.at, this.icon, this.sev, this.title, this.subtitle, this.amount);
  final DateTime at;
  final IconData icon;
  final Sev sev;
  final String title, subtitle, amount;
}

class _History extends StatelessWidget {
  const _History({required this.sales, required this.bills});
  final List<Sale> sales;
  final List<Bill> bills;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>().s;
    final items = <_Entry>[
      for (final x in sales)
        _Entry(
          x.at,
          Icons.shopping_bag_outlined,
          x.method == 'credit' || x.method == 'partial' ? Sev.warn : Sev.info,
          '${s.t('purchase')} #${x.number} · ${s.t(x.method)}',
          x.lines.map(lineLabel).join(', '),
          '+${kz(x.total)}',
        ),
      for (final b in bills)
        for (final p in b.payments)
          _Entry(
            p.at,
            Icons.payments_outlined,
            Sev.ok,
            '${s.t('paymentWord')}${p.method.isEmpty ? '' : ' · ${s.t(p.method)}'}',
            b.note,
            '−${kz(p.value)}',
          ),
      for (final b in bills)
        for (final d in b.dueChanges)
          _Entry(
            d.at,
            Icons.edit_calendar_outlined,
            Sev.info,
            s.t('dueChanged'),
            '${b.note} · ${fmtDate(d.from, s.lang)} → ${fmtDateTime(d.to, s.lang)}',
            '',
          ),
    ]..sort((a, b) => b.at.compareTo(a.at));

    if (items.isEmpty) return Empty(s.t('nothing'));
    return Column(children: [
      for (final e in items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(e.icon, color: sevColor(context, e.sev)),
          title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${fmtDateTime(e.at, s.lang)}${e.subtitle.isEmpty ? '' : ' · ${e.subtitle}'}',
              maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: Text(e.amount, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
    ]);
  }
}
