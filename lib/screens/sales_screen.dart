import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/db.dart';
import '../services/format.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/scanner.dart';
import 'home_shell.dart';

const methods = ['cash', 'card', 'transfer', 'credit'];

class SalesScreen extends StatelessWidget {
  const SalesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final today = app.salesOn(DateTime.now());
    final byMethod = {for (final m in methods) m: today.where((x) => x.method == m).fold<int>(0, (a, x) => a + x.total)};
    return PageScaffold(
      title: s.t('sales'),
      subtitle: '${s.t('today')} · ${today.length} · ${kz(app.todayTotal)}',
      actions: [
        FilledButton.icon(
            onPressed: () => openNewSale(context), icon: const Icon(Icons.add_shopping_cart), label: Text(s.t('newSale'))),
      ],
      children: [
        ResponsiveGrid(minWidth: 170, children: [for (final m in methods) Kpi(label: s.t(m), value: kz(byMethod[m]!))]),
        const SizedBox(height: 16),
        Panel(
          title: s.t('salesToday'),
          child: today.isEmpty ? Empty(s.t('nothing')) : Column(children: [for (final x in today) SaleTile(sale: x)]),
        ),
      ],
    );
  }
}

class SaleTile extends StatelessWidget {
  const SaleTile({super.key, required this.sale});
  final Sale sale;
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>().s;
    final items = sale.lines.map((l) => '${l.qty}× ${l.name}').join(', ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('#${sale.number} · ${sale.customerName}', style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${fmtTime(sale.at)} · $items', maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(kz(sale.total), style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Pill(s.t(sale.method), sale.method == 'credit' ? Sev.warn : Sev.ok),
      ]),
    );
  }
}

Future<void> openNewSale(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _NewSaleSheet(),
    );

class _Line {
  _Line(this.product, this.qty);
  Product product;
  int qty;
}

class _NewSaleSheet extends StatefulWidget {
  const _NewSaleSheet();
  @override
  State<_NewSaleSheet> createState() => _NewSaleSheetState();
}

class _NewSaleSheetState extends State<_NewSaleSheet> {
  Customer? _customer;
  final _lines = <_Line>[];
  String _method = 'cash';
  DateTime _due = DateTime.now().add(const Duration(days: 7));
  bool _busy = false;

  int get _total => _lines.fold(0, (a, l) => a + l.product.price * l.qty);

  void _add(Product p) {
    setState(() {
      final existing = _lines.where((l) => l.product.id == p.id);
      if (existing.isNotEmpty) {
        existing.first.qty++;
      } else {
        _lines.add(_Line(p, 1));
      }
    });
  }

  Future<void> _scan(AppState app) async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    final p = app.productByBarcode(code);
    if (p == null) return snack(context, '$code ?');
    _add(p);
  }

  Future<void> _pickDue() async {
    final d = await showDatePicker(
        context: context, initialDate: _due, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    setState(() => _due = DateTime(d.year, d.month, d.day, t?.hour ?? 9, t?.minute ?? 0));
  }

  Future<void> _save(AppState app) async {
    final s = app.s;
    setState(() => _busy = true);
    try {
      final sale = await Db.I.recordSale(
        customer: _customer,
        walkInLabel: s.t('walkIn'),
        lines: _lines
            .map((l) => SaleLine(productId: l.product.id, name: l.product.name, qty: l.qty, price: l.product.price, cost: l.product.cost))
            .toList(),
        method: _method,
        sellerId: app.user?.uid ?? '',
        stockNow: {for (final p in app.products) p.id: p.qty},
        lastNumber: app.lastSaleNumber,
        creditDue: _due,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      final phone = _customer?.phone ?? '';
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('${s.t('saleSaved')} · #${sale.number} · ${kz(sale.total)}'),
        action: phone.isEmpty
            ? null
            : SnackBarAction(label: s.t('sendReceipt'), onPressed: () => _sendReceipt(sale, phone, app)),
      ));
    } on StockException catch (e) {
      if (mounted) snack(context, s.t('notEnough').replaceAll('{p}', e.product));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sendReceipt(Sale sale, String phone, AppState app) {
    final text = app
        .tx('tmplReceipt')
        .replaceAll('{n}', '${sale.number}')
        .replaceAll('{linhas}', sale.lines.map((l) => '${l.qty}× ${l.name} — ${kz(l.total)}').join('\n'))
        .replaceAll('{total}', kz(sale.total));
    launchUrl(Uri.parse('https://wa.me/${waNumber(phone)}?text=${Uri.encodeComponent(text)}'),
        mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final realCustomers = app.customers;
    final overLimit = _customer != null &&
        _method == 'credit' &&
        _customer!.creditLimit > 0 &&
        app.owedBy(_customer!.id) + _total > _customer!.creditLimit;
    final canSave = _lines.isNotEmpty && !_busy && (_method != 'credit' || _customer != null);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            Text(s.t('newSale'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _customer?.id ?? '',
              decoration: InputDecoration(labelText: s.t('customer')),
              items: [
                DropdownMenuItem(value: '', child: Text(s.t('walkIn'))),
                for (final c in realCustomers) DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _customer = v == null || v.isEmpty ? null : app.customerById(v)),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Autocomplete<Product>(
                  displayStringForOption: (p) => p.name,
                  optionsBuilder: (v) => app.products
                      .where((p) => p.qty > 0 && p.name.toLowerCase().contains(v.text.toLowerCase())),
                  onSelected: _add,
                  fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => TextField(
                    controller: ctrl,
                    focusNode: focus,
                    decoration: InputDecoration(labelText: s.t('addLine'), prefixIcon: const Icon(Icons.search)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                  tooltip: s.t('scan'), onPressed: () => _scan(app), icon: const Icon(Icons.qr_code_scanner)),
            ]),
            const SizedBox(height: 8),
            for (final l in _lines)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.product.name),
                subtitle: Text('${kz(l.product.price)} · ${l.product.qty} ${s.t('stock').toLowerCase()}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      onPressed: () => setState(() {
                            if (l.qty > 1) {
                              l.qty--;
                            } else {
                              _lines.remove(l);
                            }
                          }),
                      icon: const Icon(Icons.remove_circle_outline)),
                  Text('${l.qty}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  IconButton(
                      onPressed: l.qty < l.product.qty ? () => setState(() => l.qty++) : null,
                      icon: const Icon(Icons.add_circle_outline)),
                ]),
              ),
            const Divider(),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in methods)
                ChoiceChip(label: Text(s.t(m)), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
            ]),
            if (_method == 'credit') ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDue,
                icon: const Icon(Icons.event),
                label: Text('${s.t('dueDate')}: ${fmtDateTime(_due, s.lang)}'),
              ),
              if (_customer == null)
                Padding(padding: const EdgeInsets.only(top: 8), child: Pill(s.t('customer'), Sev.warn)),
              if (overLimit)
                Padding(padding: const EdgeInsets.only(top: 8), child: Pill(s.t('overLimit'), Sev.bad)),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: Text('${s.t('total')}: ${kz(_total)}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
              FilledButton(onPressed: canSave ? () => _save(app) : null, child: Text(s.t('save'))),
            ]),
          ],
        ),
      ),
    );
  }
}
