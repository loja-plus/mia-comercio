import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/db.dart';
import '../services/format.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'customer_ledger_screen.dart';
import 'home_shell.dart';

class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    return PageScaffold(
      title: s.t('customers'),
      subtitle: '${app.customers.length}',
      actions: [
        FilledButton.icon(
            onPressed: () => openCustomerForm(context), icon: const Icon(Icons.person_add), label: Text(s.t('addCustomer'))),
      ],
      children: [
        Card(
          child: app.customers.isEmpty
              ? Empty(s.t('nothing'))
              : Column(children: [
                  for (var i = 0; i < app.customers.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _CustomerRow(c: app.customers[i]),
                  ],
                ]),
        ),
      ],
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.c});
  final Customer c;
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final s = app.s;
    final owes = app.owedBy(c.id);
    final overdue = app.openReceivables.any((b) => b.partyId == c.id && daysFromToday(b.due) < 0);
    final near = c.creditLimit > 0 && owes > c.creditLimit * .8;
    return ListTile(
      onTap: () => openLedger(context, c), // extrato do cliente
      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text([c.contact, c.phone, c.email].where((x) => x.isNotEmpty).join(' · ')),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(owes > 0 ? kz(owes) : '—', style: const TextStyle(fontWeight: FontWeight.w600)),
        if (overdue) Pill(s.t('overdue'), Sev.bad) else if (near) Pill(s.t('creditLimit'), Sev.warn),
      ]),
    );
  }
}

Future<void> openCustomerForm(BuildContext context, {Customer? customer}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CustomerForm(customer: customer),
    );

class _CustomerForm extends StatefulWidget {
  const _CustomerForm({this.customer});
  final Customer? customer;
  @override
  State<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<_CustomerForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.customer?.name);
  late final _contact = TextEditingController(text: widget.customer?.contact);
  late final _phone = TextEditingController(text: widget.customer?.phone ?? '+244 ');
  late final _email = TextEditingController(text: widget.customer?.email);
  late final _limit = TextEditingController(text: '${widget.customer?.creditLimit ?? 0}');
  late bool _optIn = widget.customer?.optIn ?? true;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>().s;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
          Text(widget.customer?.name ?? s.t('addCustomer'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            decoration: InputDecoration(labelText: s.t('name')),
            validator: (v) => (v ?? '').trim().isEmpty ? '!' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _contact, decoration: InputDecoration(labelText: s.t('contact'))),
          const SizedBox(height: 12),
          TextFormField(
              controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: s.t('phone'))),
          const SizedBox(height: 12),
          TextFormField(
              controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: s.t('email'))),
          const SizedBox(height: 12),
          TextFormField(
              controller: _limit, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.t('creditLimit'))),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _optIn,
            onChanged: (v) => setState(() => _optIn = v),
            title: Text(s.t('optIn')),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('cancel'))),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () async {
                if (!_form.currentState!.validate()) return;
                final phone = _phone.text.trim() == '+244' ? '' : _phone.text.trim();
                await Db.I.saveCustomer(Customer(
                  id: widget.customer?.id ?? '',
                  name: _name.text.trim(),
                  contact: _contact.text.trim(),
                  phone: phone,
                  email: _email.text.trim(),
                  creditLimit: int.tryParse(_limit.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
                  optIn: _optIn,
                ));
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(s.t('save')),
            ),
          ]),
        ]),
      ),
    );
  }
}
