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

/// Formas de pagamento na venda: inclui "parte agora, resto fiado".
const saleMethods = ['cash', 'card', 'transfer', 'credit', 'partial'];

class SalesScreen extends StatelessWidget {
  const SalesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final today = app.salesOn(DateTime.now());
    final byMethod = app.todayByMethod; // vendas pagas na hora (e a parte paga das vendas parciais)
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
    final items = sale.lines.map(lineLabel).join(', ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('#${sale.number} · ${sale.customerName}', style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${fmtTime(sale.at)} · $items', maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(kz(sale.total), style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Pill(s.t(sale.method), sale.method == 'credit' || sale.method == 'partial' ? Sev.warn : Sev.ok),
      ]),
    );
  }
}

/// "3× Arroz", "2,5 kg Carne de vaca", "Caixa 18,4 kg Frango".
String lineLabel(SaleLine l) {
  if (!l.byWeight) return '${fmtQty(l.qty)}× ${l.name}';
  if (l.box != null) return 'Cx ${fmtQty(l.qty, 'kg')} ${l.name}';
  return '${fmtQty(l.qty, 'kg')} ${l.name}';
}

Future<void> openNewSale(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _NewSaleSheet(),
    );

class _Line {
  _Line(this.product, this.qty, {this.box});
  Product product;
  double qty; // unidades ou kg
  final MeatBox? box; // caixa inteira (produtos ao peso)

  int get price => box != null ? product.wholeBoxPrice : product.price;
  int get total => (qty * price).round();
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
  final _paidNow = TextEditingController();
  String _paidMethod = 'cash';

  int get _paidNowValue => int.tryParse(_paidNow.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  int get _total => _lines.fold(0, (a, l) => a + l.total);

  /// Quanto deste produto já está no carrinho (unidades ou kg).
  double _inCart(Product p) => _lines.where((l) => l.product.id == p.id).fold(0.0, (a, l) => a + l.qty);

  Future<void> _add(Product p) async {
    if (p.byWeight) {
      final line = await _askWeight(p);
      if (line != null && mounted) setState(() => _lines.add(line));
      return;
    }
    setState(() {
      final existing = _lines.where((l) => l.product.id == p.id);
      if (existing.isNotEmpty) {
        if (existing.first.qty < p.qty) existing.first.qty++;
      } else {
        _lines.add(_Line(p, 1));
      }
    });
  }

  /// Produto ao peso: vender uma caixa inteira ou uma quantidade em kg.
  Future<_Line?> _askWeight(Product p) {
    final s = context.read<AppState>().s;
    final used = _lines.where((l) => l.box != null).map((l) => l.box!.id).toSet();
    final freeBoxes = p.boxesByExpiry.where((b) => !used.contains(b.id)).toList();
    final available = p.qty - _inCart(p);
    final kgCtrl = TextEditingController();
    var wholeBox = freeBoxes.isNotEmpty;
    MeatBox? chosen;
    return showDialog<_Line>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final kg = parseNum(kgCtrl.text) ?? 0;
        final ok = wholeBox ? chosen != null : (kg > 0 && kg <= available + 0.0005);
        final preview = wholeBox
            ? (chosen == null ? 0 : (chosen!.kg * p.wholeBoxPrice).round())
            : (kg * p.price).round();
        return AlertDialog(
          title: Text(p.name),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s.t('inStockLabel')}: ${fmtQty(p.qty, 'kg')} · ${p.boxCount} ${s.t('boxesWord')}'),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text(s.t('wholeBox')), enabled: freeBoxes.isNotEmpty),
                  ButtonSegment(value: false, label: Text(s.t('byKg'))),
                ],
                selected: {wholeBox},
                onSelectionChanged: (v) => set(() => wholeBox = v.first),
              ),
              const SizedBox(height: 12),
              if (wholeBox) ...[
                Text(s.t('chooseBox'), style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final b in freeBoxes)
                    ChoiceChip(
                      label: Text([
                        fmtQty(b.kg, 'kg'),
                        if (b.exp != null) fmtDate(b.exp!, s.lang),
                      ].join(' · ')),
                      selected: chosen?.id == b.id,
                      onSelected: (_) => set(() => chosen = b),
                    ),
                ]),
                const SizedBox(height: 8),
                Text('${kz(p.wholeBoxPrice)}/kg'),
              ] else ...[
                TextField(
                  controller: kgCtrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => set(() {}),
                  decoration: InputDecoration(
                    labelText: s.t('kgAmount'),
                    suffixText: 'kg',
                    helperText: '${kz(p.price)}/kg · máx. ${fmtQty(available, 'kg')}',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text('${s.t('total')}: ${kz(preview)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(s.t('cancel'))),
            FilledButton(
              onPressed: !ok
                  ? null
                  : () => Navigator.pop(c, wholeBox ? _Line(p, chosen!.kg, box: chosen) : _Line(p, kg)),
              child: Text(s.t('addLine')),
            ),
          ],
        );
      }),
    );
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
            .map((l) => SaleLine(
                  productId: l.product.id,
                  name: l.product.name,
                  qty: l.qty,
                  price: l.price,
                  cost: l.product.cost,
                  unit: l.product.unit,
                  box: l.box,
                ))
            .toList(),
        method: _method,
        sellerId: app.user?.uid ?? '',
        productsNow: {for (final p in app.products) p.id: p},
        lastNumber: app.lastSaleNumber,
        creditDue: _due,
        paidNow: _paidNowValue,
        paidMethod: _paidMethod,
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
        .replaceAll('{linhas}', sale.lines.map((l) => '${lineLabel(l)} — ${kz(l.total)}').join('\n'))
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
        (_method == 'credit' || _method == 'partial') &&
        _customer!.creditLimit > 0 &&
        app.owedBy(_customer!.id) + (_method == 'partial' ? _total - _paidNowValue : _total) > _customer!.creditLimit;
    final onCredit = _method == 'credit' || _method == 'partial';
    final partialOk = _method != 'partial' || (_paidNowValue > 0 && _paidNowValue < _total);
    final canSave = _lines.isNotEmpty && !_busy && (!onCredit || _customer != null) && partialOk;

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
              if (l.product.byWeight)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.product.name),
                  subtitle: Text(
                      '${l.box != null ? '${s.t('wholeBox')} · ' : ''}${fmtQty(l.qty, 'kg')} × ${kz(l.price)}/kg'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(kz(l.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                    IconButton(onPressed: () => setState(() => _lines.remove(l)), icon: const Icon(Icons.delete_outline)),
                  ]),
                )
              else
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.product.name),
                subtitle: Text('${kz(l.product.price)} · ${fmtQty(l.product.qty)} ${s.t('stock').toLowerCase()}'),
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
                  Text(fmtQty(l.qty), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  IconButton(
                      onPressed: l.qty < l.product.qty ? () => setState(() => l.qty++) : null,
                      icon: const Icon(Icons.add_circle_outline)),
                ]),
              ),
            const Divider(),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in saleMethods)
                ChoiceChip(label: Text(s.t(m)), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
            ]),
            if (_method == 'partial') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _paidNow,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: s.t('paidNowLabel'),
                  helperText: _paidNowValue > 0 && _paidNowValue < _total
                      ? '${s.t('stillOwes')}: ${kz(_total - _paidNowValue)}'
                      : null,
                  errorText: _paidNowValue >= _total && _total > 0 ? s.t('partialTooMuch') : null,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(s.t('paidHow')),
                for (final m in const ['cash', 'card', 'transfer'])
                  ChoiceChip(
                      label: Text(s.t(m)), selected: _paidMethod == m, onSelected: (_) => setState(() => _paidMethod = m)),
              ]),
            ],
            if (onCredit) ...[
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
