import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/db.dart';
import '../services/format.dart';
import '../state/app_state.dart';
import '../widgets/alerts.dart';
import '../widgets/common.dart';
import 'home_shell.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});
  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  String _tab = 'receivable';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final List<Bill> rows;
    switch (_tab) {
      case 'payable':
        rows = app.openPayables;
      case 'received':
        rows = app.bills.where((b) => !b.isOpen && b.isReceivable).toList()
          ..sort((a, b) => (b.paidAt ?? b.due).compareTo(a.paidAt ?? a.due));
      case 'paid':
        rows = app.bills.where((b) => !b.isOpen && !b.isReceivable).toList()
          ..sort((a, b) => (b.paidAt ?? b.due).compareTo(a.paidAt ?? a.due));
      default:
        rows = app.openReceivables;
    }

    return PageScaffold(
      title: s.t('accounts'),
      actions: [
        OutlinedButton.icon(
            onPressed: () => _openBillForm(context, 'receivable'),
            icon: const Icon(Icons.call_received),
            label: Text(s.t('newReceivable'))),
        FilledButton.icon(
            onPressed: () => _openBillForm(context, 'payable'),
            icon: const Icon(Icons.call_made),
            label: Text(s.t('newPayable'))),
      ],
      children: [
        ResponsiveGrid(minWidth: 200, children: [
          Kpi(label: s.t('toReceive'), value: kz(app.sumRemaining(app.openReceivables))),
          Kpi(label: s.t('toPay'), value: kz(app.sumRemaining(app.openPayables))),
        ]),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: [
            for (final k in ['receivable', 'payable', 'received', 'paid']) ButtonSegment(value: k, label: Text(s.t(k))),
          ],
          selected: {_tab},
          onSelectionChanged: (v) => setState(() => _tab = v.first),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: rows.isEmpty
                ? Empty(s.t('nothing'))
                : Column(children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _BillRow(b: rows[i]),
                    ],
                  ]),
          ),
        ),
      ],
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({required this.b});
  final Bill b;
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>().s;
    if (!b.isOpen) {
      return StripeTile(
        sev: Sev.ok,
        title: b.party,
        subtitle: '${b.note} · ${b.paidAt == null ? '' : fmtDateTime(b.paidAt!, s.lang)}',
        trailing: Text(kz(b.amount)),
      );
    }
    final partial = b.paidAmount > 0 ? ' · ${s.t('partial')}: ${kz(b.paidAmount)}' : '';
    return StripeTile(
      sev: dueSev(b.due),
      title: b.party,
      subtitle: '${b.note.isEmpty ? '' : '${b.note} · '}${s.t('due')} ${dueText(b.due, s)}$partial',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(kz(b.remaining), style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        FilledButton.tonal(
          onPressed: () => _registerPayment(context, b),
          child: Text(b.isReceivable ? s.t('markReceived') : s.t('markPaid')),
        ),
      ]),
    );
  }
}

Future<void> _registerPayment(BuildContext context, Bill b) async {
  final s = context.read<AppState>().s;
  final ctrl = TextEditingController(text: '${b.remaining}');
  final value = await showDialog<int>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(b.party),
      content: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: InputDecoration(labelText: s.t('amount'), helperText: '${s.t('total')}: ${kz(b.remaining)}'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(s.t('cancel'))),
        FilledButton(
          onPressed: () => Navigator.pop(c, int.tryParse(ctrl.text.replaceAll(RegExp(r'[^0-9]'), ''))),
          child: Text(s.t('save')),
        ),
      ],
    ),
  );
  if (value == null || value <= 0) return;
  await Db.I.registerPayment(b, value);
}

Future<void> _openBillForm(BuildContext context, String kind) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _BillForm(kind: kind),
    );

class _BillForm extends StatefulWidget {
  const _BillForm({required this.kind});
  final String kind;
  @override
  State<_BillForm> createState() => _BillFormState();
}

class _BillFormState extends State<_BillForm> {
  final _party = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  Customer? _customer;
  DateTime _due = DateTime.now().add(const Duration(days: 7));

  Future<void> _pick() async {
    final d = await showDatePicker(
        context: context, initialDate: _due, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 730)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_due));
    setState(() => _due = DateTime(d.year, d.month, d.day, t?.hour ?? 9, t?.minute ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final s = app.s;
    final recv = widget.kind == 'receivable';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
        Text(recv ? s.t('newReceivable') : s.t('newPayable'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        if (recv)
          DropdownButtonFormField<String>(
            decoration: InputDecoration(labelText: s.t('customer')),
            items: [for (final c in app.customers) DropdownMenuItem(value: c.id, child: Text(c.name))],
            onChanged: (v) => setState(() => _customer = v == null ? null : app.customerById(v)),
          )
        else
          TextField(controller: _party, decoration: InputDecoration(labelText: s.t('supplier'))),
        const SizedBox(height: 12),
        TextField(controller: _amount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.t('amount'))),
        const SizedBox(height: 12),
        TextField(controller: _note, decoration: InputDecoration(labelText: s.t('note'))),
        const SizedBox(height: 12),
        OutlinedButton.icon(
            onPressed: _pick, icon: const Icon(Icons.event), label: Text('${s.t('dueDate')}: ${fmtDateTime(_due, s.lang)}')),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('cancel'))),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () async {
              final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
              final party = recv ? (_customer?.name ?? '') : _party.text.trim();
              if (amount <= 0 || party.isEmpty) return;
              await Db.I.saveBill(Bill(
                kind: widget.kind,
                party: party,
                partyId: _customer?.id ?? '',
                amount: amount,
                due: _due,
                note: _note.text.trim(),
              ));
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(s.t('save')),
          ),
        ]),
      ]),
    );
  }
}
