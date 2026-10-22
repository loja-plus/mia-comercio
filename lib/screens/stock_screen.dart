import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/db.dart';
import '../services/format.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/scanner.dart';
import 'broadcast_screen.dart';
import 'home_shell.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});
  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  String _q = '';
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final now = DateTime.now();
    final cats = {for (final p in app.products) p.category}.toList()..sort();
    final list = app.products.where((p) {
      final okQ = p.name.toLowerCase().contains(_q.toLowerCase()) || p.barcode == _q;
      final okF = _filter == 'all' ||
          (_filter == '_low' && p.isLow) ||
          (_filter == '_exp' && (p.daysToExpiry(now) ?? 999) <= 30) ||
          p.category == _filter;
      return okQ && okF;
    }).toList();

    return PageScaffold(
      title: s.t('stock'),
      subtitle: '${app.products.length} · ${app.isOwner ? kz(app.stockValue) : ''}',
      actions: [
        SizedBox(
          width: 260,
          child: TextField(
            decoration: InputDecoration(
              hintText: s.t('search'),
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: IconButton(
                tooltip: s.t('scan'),
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: () async {
                  final c = await scanBarcode(context);
                  if (c != null) setState(() => _q = c);
                },
              ),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        if (app.isOwner)
          FilledButton.icon(
              onPressed: () => openProductForm(context), icon: const Icon(Icons.add), label: Text(s.t('addProduct'))),
      ],
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final f in ['all', '_low', '_exp', ...cats])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f == 'all'
                      ? s.t('all')
                      : f == '_low'
                          ? s.t('lowStock')
                          : f == '_exp'
                              ? s.t('expiry')
                              : f),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        Card(
          child: list.isEmpty
              ? Empty(s.t('nothing'))
              : Column(children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _ProductRow(p: list[i], canEdit: app.isOwner),
                  ],
                ]),
        ),
      ],
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.p, required this.canEdit});
  final Product p;
  final bool canEdit;
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>().s;
    final n = p.daysToExpiry(DateTime.now());
    final ratio = p.minQty == 0 ? 1.0 : (p.qty / (p.minQty * 3)).clamp(0.0, 1.0);
    return ListTile(
      onTap: canEdit ? () => openProductForm(context, product: p) : null,
      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          SizedBox(
            width: 90,
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              color: p.isLow ? sevColor(context, Sev.bad) : null,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(child: Text('${p.qty} un. · ${kz(p.price)}', overflow: TextOverflow.ellipsis)),
        ]),
      ),
      trailing: n == null
          ? null
          : Pill(
              n < 0 ? s.t('expired') : fmtDate(p.expiry!, s.lang),
              n <= 7 ? Sev.bad : (n <= 30 ? Sev.warn : Sev.ok),
            ),
    );
  }
}

Future<void> openProductForm(BuildContext context, {Product? product}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ProductForm(product: product),
    );

class _ProductForm extends StatefulWidget {
  const _ProductForm({this.product});
  final Product? product;
  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product?.name);
  late final _cat = TextEditingController(text: widget.product?.category ?? 'Mercearia');
  late final _code = TextEditingController(text: widget.product?.barcode);
  late final _qty = TextEditingController(text: '${widget.product?.qty ?? ''}');
  late final _min = TextEditingController(text: '${widget.product?.minQty ?? 5}');
  late final _cost = TextEditingController(text: '${widget.product?.cost ?? ''}');
  late final _price = TextEditingController(text: '${widget.product?.price ?? ''}');
  late DateTime? _exp = widget.product?.expiry;
  late bool _announce = widget.product == null;

  int _n(TextEditingController c) => int.tryParse(c.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  Future<void> _save(AppState app) async {
    if (!_form.currentState!.validate()) return;
    final p = Product(
      id: widget.product?.id ?? '',
      name: _name.text.trim(),
      category: _cat.text.trim(),
      barcode: _code.text.trim(),
      qty: _n(_qty),
      minQty: _n(_min),
      cost: _n(_cost),
      price: _n(_price),
      expiry: _exp,
    );
    final nav = Navigator.of(context);
    await Db.I.saveProduct(p);
    nav.pop();
    // Plano gratuito: abre o ecrã de anúncio já preenchido; a pessoa envia com um toque.
    if (_announce && app.isOwner) {
      nav.push(MaterialPageRoute(
        builder: (_) => Scaffold(appBar: AppBar(), body: BroadcastScreen(initialProduct: p)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final s = app.s;
    String? req(String? v) => (v == null || v.trim().isEmpty) ? '!' : null;
    Widget numField(TextEditingController c, String label) => TextFormField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label),
          validator: req,
        );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
          Text(widget.product == null ? s.t('addProduct') : s.t('editProduct'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextFormField(controller: _name, decoration: InputDecoration(labelText: s.t('product')), validator: req),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextFormField(controller: _cat, decoration: InputDecoration(labelText: s.t('category')))),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _code,
                decoration: InputDecoration(
                  labelText: s.t('barcode'),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: () async {
                      final c = await scanBarcode(context);
                      if (c != null) _code.text = c;
                    },
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: numField(_qty, s.t('qty'))),
            const SizedBox(width: 12),
            Expanded(child: numField(_min, s.t('minQty'))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: numField(_cost, s.t('cost'))),
            const SizedBox(width: 12),
            Expanded(child: numField(_price, s.t('price'))),
          ]),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text(_exp == null ? s.t('noExpiry') : '${s.t('expiry')}: ${fmtDate(_exp!, s.lang)}'),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _exp ?? DateTime.now().add(const Duration(days: 180)),
                firstDate: DateTime(2020),
                lastDate: DateTime(2040),
              );
              if (d != null) setState(() => _exp = d);
            },
          ),
          if (app.isOwner)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _announce,
              onChanged: (v) => setState(() => _announce = v),
              title: Text(s.t('announce')),
            ),
          const SizedBox(height: 12),
          Row(children: [
            if (widget.product != null)
              TextButton(
                onPressed: () async {
                  final ok = await confirmDialog(context, '${s.t('delete')}: ${widget.product!.name}?',
                      ok: s.t('delete'), cancel: s.t('cancel'));
                  if (!ok) return;
                  await Db.I.deleteProduct(widget.product!.id);
                  if (context.mounted) Navigator.pop(context);
                },
                child: Text(s.t('delete'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('cancel'))),
            const SizedBox(width: 8),
            FilledButton(onPressed: () => _save(app), child: Text(s.t('save'))),
          ]),
        ]),
      ),
    );
  }
}
