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
    final info = p.byWeight
        ? '${p.boxCount} ${s.t('boxesWord')} · ${fmtQty(p.qty, 'kg')}'
            '${p.looseKg > 0 ? ' (${fmtQty(p.looseKg, 'kg')} ${s.t('looseWord')})' : ''} · ${kz(p.price)}/kg'
        : '${fmtQty(p.qty)} un. · ${kz(p.price)}';
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
          Flexible(child: Text(info, overflow: TextOverflow.ellipsis, maxLines: 2)),
        ]),
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (n != null)
          Pill(
            n < 0 ? s.t('expired') : fmtDate(p.nextExpiry!, s.lang),
            n <= 7 ? Sev.bad : (n <= 30 ? Sev.warn : Sev.ok),
          ),
        if (canEdit)
          IconButton(
            tooltip: p.byWeight ? s.t('receiveBoxes') : s.t('receive'),
            icon: const Icon(Icons.add_box_outlined),
            onPressed: () => openReceive(context, p),
          ),
      ]),
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
  Product? get _old => widget.product;
  late final _name = TextEditingController(text: _old?.name);
  late final _cat = TextEditingController(text: _old?.category ?? 'Mercearia');
  late final _code = TextEditingController(text: _old?.barcode);
  late final _qty = TextEditingController(text: _old == null ? '' : plainNum(_old!.byWeight ? _old!.looseKg : _old!.qty));
  late final _min = TextEditingController(text: plainNum(_old?.minQty ?? 5));
  late final _cost = TextEditingController(text: '${_old?.cost ?? ''}');
  late final _price = TextEditingController(text: '${_old?.price ?? ''}');
  late final _boxPrice = TextEditingController(text: (_old?.boxPrice ?? 0) > 0 ? '${_old!.boxPrice}' : '');
  late DateTime? _exp = _old?.expiry;
  late String _unit = _old?.unit ?? 'un';
  late bool _announce = _old == null;

  int _int(TextEditingController c) => int.tryParse(c.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  double _dec(TextEditingController c) => parseNum(c.text) ?? 0.0;

  Future<void> _save(AppState app) async {
    if (!_form.currentState!.validate()) return;
    final kg = _unit == 'kg';
    final p = Product(
      id: _old?.id ?? '',
      name: _name.text.trim(),
      category: _cat.text.trim(),
      barcode: _code.text.trim(),
      unit: _unit,
      qty: kg ? (_old?.qty ?? 0.0) : _dec(_qty),
      looseKg: kg ? _dec(_qty) : 0,
      minQty: _dec(_min),
      cost: _int(_cost),
      price: _int(_price),
      boxPrice: kg ? _int(_boxPrice) : 0,
      boxes: _old?.boxes ?? const [],
      expiry: _exp,
    );
    final nav = Navigator.of(context);
    await Db.I.saveProduct(p, old: _old);
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
    final kg = _unit == 'kg';
    String? req(String? v) => (v == null || v.trim().isEmpty) ? '!' : null;
    Widget numField(TextEditingController c, String label, {bool required = true, bool decimal = false, String? help}) =>
        TextFormField(
          controller: c,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          decoration: InputDecoration(labelText: label, helperText: help, helperMaxLines: 2),
          validator: required ? req : null,
        );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
          Text(_old == null ? s.t('addProduct') : s.t('editProduct'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextFormField(controller: _name, decoration: InputDecoration(labelText: s.t('product')), validator: req),
          const SizedBox(height: 12),
          Text(s.t('sellBy'), style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'un', label: Text(s.t('unitUn')), icon: const Icon(Icons.inventory_2_outlined)),
              ButtonSegment(value: 'kg', label: Text(s.t('unitKg')), icon: const Icon(Icons.scale_outlined)),
            ],
            selected: {_unit},
            // O tipo só se escolhe ao criar (mudar depois baralharia o stock).
            onSelectionChanged: _old == null ? (v) => setState(() => _unit = v.first) : null,
          ),
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
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: kg
                  ? numField(_qty, s.t('looseKgLabel'), required: false, decimal: true, help: s.t('boxesHelp'))
                  : numField(_qty, s.t('qty'), decimal: true),
            ),
            const SizedBox(width: 12),
            Expanded(child: numField(_min, kg ? s.t('minKg') : s.t('minQty'), decimal: true)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: numField(_cost, kg ? s.t('costKg') : s.t('cost'))),
            const SizedBox(width: 12),
            Expanded(child: numField(_price, kg ? s.t('priceKg') : s.t('price'))),
          ]),
          if (kg) ...[
            const SizedBox(height: 12),
            numField(_boxPrice, s.t('boxPriceLabel'), required: false),
          ],
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
            if (_old != null)
              TextButton(
                onPressed: () async {
                  final ok = await confirmDialog(context, '${s.t('delete')}: ${_old!.name}?',
                      ok: s.t('delete'), cancel: s.t('cancel'));
                  if (!ok) return;
                  await Db.I.deleteProduct(_old!.id);
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

/// Entrada de mercadoria: caixas com o peso de cada uma (ao peso) ou unidades.
Future<void> openReceive(BuildContext context, Product p) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ReceiveSheet(p: p),
    );

class _ReceiveSheet extends StatefulWidget {
  const _ReceiveSheet({required this.p});
  final Product p;
  @override
  State<_ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends State<_ReceiveSheet> {
  final _weights = <TextEditingController>[TextEditingController()];
  final _units = TextEditingController();
  late final _cost = TextEditingController(text: widget.p.cost > 0 ? '${widget.p.cost}' : '');
  DateTime? _exp;

  List<double> get _kgs => _weights.map<double>((c) => parseNum(c.text) ?? 0.0).where((v) => v > 0).toList();

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>().s;
    final p = widget.p;
    final total = _kgs.fold<double>(0, (a, b) => a + b);
    final ok = p.byWeight ? _kgs.isNotEmpty : (parseNum(_units.text) ?? 0.0) > 0;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
        Text('${p.byWeight ? s.t('receiveBoxes') : s.t('receive')} · ${p.name}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        if (p.byWeight) ...[
          Text(s.t('boxWeightsHelp'), style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          for (var i = 0; i < _weights.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _weights[i],
                    autofocus: i == _weights.length - 1,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => setState(() => _weights.add(TextEditingController())),
                    decoration: InputDecoration(labelText: '${s.t('box')} ${i + 1}', suffixText: 'kg', isDense: true),
                  ),
                ),
                if (_weights.length > 1)
                  IconButton(
                    onPressed: () => setState(() => _weights.removeAt(i)),
                    icon: const Icon(Icons.close),
                  ),
              ]),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _weights.add(TextEditingController())),
              icon: const Icon(Icons.add),
              label: Text(s.t('addBox')),
            ),
          ),
          Text('${_kgs.length} ${s.t('boxesWord')} · ${fmtQty(total, 'kg')}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text(_exp == null ? s.t('noExpiry') : '${s.t('expiry')}: ${fmtDate(_exp!, s.lang)}'),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _exp ?? DateTime.now().add(const Duration(days: 30)),
                firstDate: DateTime(2020),
                lastDate: DateTime(2040),
              );
              if (d != null) setState(() => _exp = d);
            },
          ),
        ] else
          TextField(
            controller: _units,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: s.t('qty')),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _cost,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: p.byWeight ? s.t('costKg') : s.t('cost')),
        ),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('cancel'))),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: !ok
                ? null
                : () async {
                    final cost = int.tryParse(_cost.text.replaceAll(RegExp(r'[^0-9]'), ''));
                    final messenger = ScaffoldMessenger.of(context);
                    final nav = Navigator.of(context);
                    if (p.byWeight) {
                      await Db.I.receiveBoxes(p, _kgs, exp: _exp, newCost: cost);
                    } else {
                      await Db.I.receiveUnits(p, parseNum(_units.text)!, newCost: cost);
                    }
                    nav.pop();
                    messenger.showSnackBar(
                        SnackBar(content: Text(s.t('received')), behavior: SnackBarBehavior.floating));
                  },
            child: Text(s.t('save')),
          ),
        ]),
      ]),
    );
  }
}
