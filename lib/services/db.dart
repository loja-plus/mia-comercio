import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// Acesso à base de dados partilhada (Firestore).
/// Todos os aparelhos (iPad, telemóveis) veem os mesmos dados em tempo real,
/// e a app continua a funcionar sem internet: sincroniza quando a rede volta.
class Db {
  Db._();
  static final Db I = Db._();

  static const shopId = 'mia';
  final _fs = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get shop => _fs.collection('shops').doc(shopId);
  CollectionReference<Map<String, dynamic>> get _products => shop.collection('products');
  CollectionReference<Map<String, dynamic>> get _customers => shop.collection('customers');
  CollectionReference<Map<String, dynamic>> get _sales => shop.collection('sales');
  CollectionReference<Map<String, dynamic>> get _bills => shop.collection('bills');
  CollectionReference<Map<String, dynamic>> get _outbox => shop.collection('outbox');
  DocumentReference<Map<String, dynamic>> get settingsDoc => shop.collection('config').doc('settings');
  DocumentReference<Map<String, dynamic>> get _counters => shop.collection('config').doc('counters');

  // ---------- Leitura ----------
  Stream<List<Product>> products() =>
      _products.orderBy('name').snapshots().map((s) => s.docs.map(Product.fromDoc).toList());

  Stream<List<Customer>> customers() =>
      _customers.orderBy('name').snapshots().map((s) => s.docs.map(Customer.fromDoc).toList());

  Stream<List<Sale>> salesSince(DateTime from) => _sales
      .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .orderBy('at', descending: true)
      .snapshots()
      .map((s) => s.docs.map(Sale.fromDoc).toList());

  /// O caixa só pode ver contas a receber (regras de segurança).
  Stream<List<Bill>> bills({bool receivablesOnly = false}) {
    Query<Map<String, dynamic>> q = _bills;
    if (receivablesOnly) q = q.where('kind', isEqualTo: 'receivable');
    return q.snapshots().map((s) => s.docs.map(Bill.fromDoc).toList()..sort((a, b) => a.due.compareTo(b.due)));
  }

  Stream<List<OutMessage>> outbox() => _outbox
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(OutMessage.fromDoc).toList());

  Stream<Map<String, dynamic>> settings() => settingsDoc.snapshots().map((d) => d.data() ?? {});

  // ---------- Modo offline ----------
  /// Número de alterações feitas neste aparelho que ainda não chegaram ao servidor.
  final pending = ValueNotifier<int>(0);

  /// true = ligado ao servidor; false = a trabalhar só com os dados guardados no aparelho.
  Stream<bool> online() => settingsDoc
      .snapshots(includeMetadataChanges: true)
      .map((d) => !d.metadata.isFromCache)
      .distinct();

  /// Sem internet, o Firestore guarda a alteração no aparelho e envia-a sozinho
  /// quando a rede voltar (mesmo que a app seja fechada entretanto).
  /// Por isso NUNCA esperamos pela resposta do servidor: o ecrã continua logo.
  Future<void> _write(Future<dynamic> f) {
    pending.value++;
    f.then((_) {}, onError: (Object e) => debugPrint('Erro ao sincronizar: $e')).whenComplete(() => pending.value--);
    return Future.value();
  }

  // ---------- Produtos ----------
  /// Novo produto ou edição. O stock nunca é escrito como valor fixo numa edição:
  /// usam-se somas/subtrações, para não apagar vendas feitas noutro aparelho.
  Future<void> saveProduct(Product p, {Product? old}) {
    if (p.id.isEmpty) {
      return _write(_products.doc().set({
        ...p.toMap(),
        'qty': p.byWeight ? p.looseKg : p.qty,
        'looseKg': p.byWeight ? p.looseKg : 0,
        'boxes': [],
        'createdAt': FieldValue.serverTimestamp(),
      }));
    }
    final m = p.toMap();
    if (old != null) {
      final delta = p.byWeight ? p.looseKg - old.looseKg : p.qty - old.qty;
      if (delta != 0) {
        m['qty'] = FieldValue.increment(delta);
        if (p.byWeight) m['looseKg'] = FieldValue.increment(delta);
      }
    }
    return _write(_products.doc(p.id).set(m, SetOptions(merge: true)));
  }

  /// Entrada de caixas (produtos ao peso): cada caixa com o seu peso e validade.
  Future<void> receiveBoxes(Product p, List<double> kgs, {DateTime? exp, int? newCost}) {
    final boxes = [for (final kg in kgs) MeatBox(id: _products.doc().id, kg: kg, exp: exp).raw];
    final total = kgs.fold<double>(0, (a, b) => a + b);
    return _write(_products.doc(p.id).update({
      'boxes': FieldValue.arrayUnion(boxes),
      'qty': FieldValue.increment(total),
      if (newCost != null && newCost > 0) 'cost': newCost,
    }));
  }

  /// Entrada de unidades (produtos à unidade).
  Future<void> receiveUnits(Product p, double qty, {int? newCost}) => _write(_products.doc(p.id).update({
        'qty': FieldValue.increment(qty),
        if (newCost != null && newCost > 0) 'cost': newCost,
      }));

  Future<void> deleteProduct(String id) => _write(_products.doc(id).delete());

  // ---------- Clientes ----------
  Future<void> saveCustomer(Customer c) => _write(c.id.isEmpty
      ? _customers.doc().set(c.toMap())
      : _customers.doc(c.id).set(c.toMap(), SetOptions(merge: true)));

  // ---------- Vendas ----------
  /// Regista a venda (funciona com ou sem internet):
  ///  - confirma o stock com os dados guardados no aparelho,
  ///  - à unidade: desconta unidades;
  ///  - ao peso, caixa inteira: retira essa caixa e o seu peso;
  ///  - ao peso, por kg: desconta dos kg soltos e, se faltar, abre a próxima caixa
  ///    (a que expira primeiro);
  ///  - usa somas/subtrações, para vendas de vários aparelhos se juntarem bem;
  ///  - se for a crédito, cria a conta a receber com data e hora limite.
  Future<Sale> recordSale({
    required Customer? customer,
    required String walkInLabel,
    required List<SaleLine> lines,
    required String method,
    required String sellerId,
    required Map<String, Product> productsNow,
    required int lastNumber,
    DateTime? creditDue,
    int paidNow = 0,
    String paidMethod = 'cash',
  }) {
    // Junta tudo por produto: uma só atualização por produto.
    final qtyDelta = <String, double>{};
    final looseDelta = <String, double>{};
    final removeBoxes = <String, List<MeatBox>>{};
    final looseWanted = <String, double>{};

    for (final l in lines) {
      final p = productsNow[l.productId];
      if (p == null) throw StockException(l.name);
      qtyDelta[p.id] = (qtyDelta[p.id] ?? 0.0) - l.qty;
      if (!p.byWeight) continue;
      if (l.box != null) {
        if (!p.boxes.any((b) => b.id == l.box!.id)) throw StockException(l.name);
        (removeBoxes[p.id] ??= []).add(l.box!);
      } else {
        looseWanted[p.id] = (looseWanted[p.id] ?? 0.0) + l.qty;
      }
    }

    // Verifica stock e decide que caixas abrir.
    for (final entry in qtyDelta.entries) {
      final p = productsNow[entry.key]!;
      if (p.qty + entry.value < -0.0005) throw StockException(p.name);
      if (!p.byWeight) continue;
      var loose = p.looseKg;
      final double want = looseWanted[p.id] ?? 0.0;
      final taken = removeBoxes[p.id] ?? [];
      final opened = <MeatBox>[];
      for (final b in p.boxesByExpiry) {
        if (loose >= want - 0.0005) break;
        if (taken.any((t) => t.id == b.id)) continue;
        opened.add(b);
        loose += b.kg;
      }
      if (loose < want - 0.0005) throw StockException(p.name);
      looseDelta[p.id] = opened.fold<double>(0, (a, b) => a + b.kg) - want;
      (removeBoxes[p.id] ??= []).addAll(opened);
    }

    final number = lastNumber + 1;
    final sale = Sale(
      number: number,
      at: DateTime.now(),
      customerId: customer?.id ?? '',
      customerName: customer?.name ?? walkInLabel,
      lines: lines,
      method: method,
      sellerId: sellerId,
      paidNow: method == 'partial' ? paidNow : 0,
      paidMethod: method == 'partial' ? paidMethod : '',
    );
    final batch = _fs.batch();
    final saleRef = _sales.doc();
    for (final entry in qtyDelta.entries) {
      final id = entry.key;
      batch.update(_products.doc(id), {
        'qty': FieldValue.increment(entry.value),
        if ((looseDelta[id] ?? 0.0) != 0) 'looseKg': FieldValue.increment(looseDelta[id]!),
        if ((removeBoxes[id] ?? []).isNotEmpty) 'boxes': FieldValue.arrayRemove(removeBoxes[id]!.map((b) => b.raw).toList()),
      });
    }
    batch.set(saleRef, sale.toMap());
    batch.set(_counters, {'sale': FieldValue.increment(1)}, SetOptions(merge: true));
    // A crédito (tudo) ou parte agora: o que falta fica como conta a receber.
    final owed = method == 'credit' ? sale.total : (method == 'partial' ? sale.total - paidNow : 0);
    if (owed > 0 && customer != null) {
      batch.set(
        _bills.doc(),
        Bill(
          kind: 'receivable',
          party: customer.name,
          partyId: customer.id,
          amount: owed,
          due: creditDue ?? DateTime.now().add(const Duration(days: 7)),
          note: method == 'partial' ? 'Venda #$number (total ${sale.total} Kz, pago $paidNow Kz)' : 'Venda #$number',
          saleId: saleRef.id,
        ).toMap(),
      );
    }
    _write(batch.commit());
    return Future.value(sale);
  }

  // ---------- Contas ----------
  Future<void> saveBill(Bill b) => _write(
      b.id.isEmpty ? _bills.doc().set(b.toMap()) : _bills.doc(b.id).set(b.toMap(), SetOptions(merge: true)));

  Map<String, dynamic> _paymentUpdate(Bill b, int value, String method) {
    final int v = value < 0 ? 0 : (value > b.remaining ? b.remaining : value);
    final done = b.paidAmount + v >= b.amount;
    return {
      'paidAmount': FieldValue.increment(v),
      'status': done ? 'done' : 'open',
      'paidAt': done ? Timestamp.now() : null,
      'payments': FieldValue.arrayUnion([
        Payment(value: v, at: DateTime.now(), method: method).toMap(),
      ]),
    };
  }

  /// Regista um pagamento (total ou parcial) de UMA conta. Nunca passa do que falta.
  /// Quando fica tudo pago, a conta fecha e os lembretes param.
  Future<void> registerPayment(Bill b, int value, {String method = 'cash'}) =>
      _write(_bills.doc(b.id).update(_paymentUpdate(b, value, method)));

  /// O cliente paga um valor sobre o total que deve: paga primeiro as contas mais antigas.
  /// Devolve quanto foi usado (nunca mais do que a dívida).
  Future<int> receiveFromCustomer(List<Bill> openBills, int amount, {String method = 'cash'}) {
    final ordered = [...openBills.where((b) => b.isOpen && b.remaining > 0)]..sort((a, b) => a.due.compareTo(b.due));
    var left = amount;
    final batch = _fs.batch();
    for (final b in ordered) {
      if (left <= 0) break;
      final take = left < b.remaining ? left : b.remaining;
      batch.update(_bills.doc(b.id), _paymentUpdate(b, take, method));
      left -= take;
    }
    _write(batch.commit());
    return Future.value(amount - left);
  }

  /// Muda a data (e hora) de pagamento. A data antiga fica no histórico;
  /// os lembretes passam a seguir a data nova.
  Future<void> changeDue(Bill b, DateTime newDue) => _write(_bills.doc(b.id).update({
        'due': Timestamp.fromDate(newDue),
        'dueChanges': FieldValue.arrayUnion([
          {'from': Timestamp.fromDate(b.due), 'to': Timestamp.fromDate(newDue), 'at': Timestamp.now()}
        ]),
      }));

  /// Todas as vendas de um cliente (para o extrato).
  Stream<List<Sale>> salesOfCustomer(String customerId) => _sales
      .where('customerId', isEqualTo: customerId)
      .snapshots()
      .map((s) => s.docs.map(Sale.fromDoc).toList()..sort((a, b) => b.at.compareTo(a.at)));

  // ---------- Mensagens para clientes ----------
  /// Plano gratuito: as mensagens são enviadas pelo WhatsApp/email do próprio aparelho.
  /// Aqui só guardamos o histórico do que foi enviado.
  Future<void> logMessage({
    required String type,
    required String text,
    required String toLabel,
    required List<String> channels,
    String billId = '',
  }) =>
      _write(_outbox.doc().set({
        'type': type,
        'text': text,
        'toLabel': toLabel,
        'channels': channels,
        'billId': billId,
        'status': 'sent',
        'createdAt': FieldValue.serverTimestamp(),
        'localAt': Timestamp.now(),
      }));

  /// Conta mais um lembrete enviado em cada conta incluída (o lembrete fica na lista até ser apagado).
  Future<void> countReminder(List<String> billIds) {
    final batch = _fs.batch();
    for (final id in billIds) {
      batch.update(_bills.doc(id), {'remindCount': FieldValue.increment(1), 'lastRemindedAt': Timestamp.now()});
    }
    return _write(batch.commit());
  }

  /// Apaga o lembrete da lista (volta só no próximo horário programado, se continuar por pagar).
  Future<void> dismissReminders(Map<String, List<String>> keysByBill) {
    final batch = _fs.batch();
    keysByBill.forEach((id, keys) => batch.update(_bills.doc(id), {'remindersSent': FieldValue.arrayUnion(keys)}));
    return _write(batch.commit());
  }

  /// Lê TODAS as vendas (para exportar para Excel).
  Future<List<Sale>> allSales() async =>
      (await _sales.orderBy('at', descending: true).get()).docs.map(Sale.fromDoc).toList();

  Future<void> saveSettings(Map<String, dynamic> m) => _write(settingsDoc.set(m, SetOptions(merge: true)));

  Future<void> saveCashClose({required int expected, required int counted, required String by}) =>
      _write(shop.collection('cashCloses').doc().set({
        'at': Timestamp.now(),
        'expected': expected,
        'counted': counted,
        'difference': counted - expected,
        'by': by,
      }));
}

class StockException implements Exception {
  StockException(this.product);
  final String product;
}
