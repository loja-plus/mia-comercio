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
  Future<void> saveProduct(Product p) {
    if (p.id.isEmpty) {
      return _write(_products.doc().set({...p.toMap(), 'createdAt': FieldValue.serverTimestamp()}));
    }
    return _write(_products.doc(p.id).set(p.toMap(), SetOptions(merge: true)));
  }

  Future<void> deleteProduct(String id) => _write(_products.doc(id).delete());

  // ---------- Clientes ----------
  Future<void> saveCustomer(Customer c) => _write(c.id.isEmpty
      ? _customers.doc().set(c.toMap())
      : _customers.doc(c.id).set(c.toMap(), SetOptions(merge: true)));

  // ---------- Vendas ----------
  /// Regista a venda (funciona com ou sem internet):
  ///  - confirma o stock com os dados guardados no aparelho,
  ///  - desconta o stock com "increment" (somas e subtrações de vários aparelhos
  ///    juntam-se corretamente quando sincronizam),
  ///  - se for a crédito, cria a conta a receber com data e hora limite.
  Future<Sale> recordSale({
    required Customer? customer,
    required String walkInLabel,
    required List<SaleLine> lines,
    required String method,
    required String sellerId,
    required Map<String, int> stockNow,
    required int lastNumber,
    DateTime? creditDue,
  }) {
    for (final l in lines) {
      if ((stockNow[l.productId] ?? 0) < l.qty) throw StockException(l.name);
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
    );
    final batch = _fs.batch();
    final saleRef = _sales.doc();
    for (final l in lines) {
      batch.update(_products.doc(l.productId), {'qty': FieldValue.increment(-l.qty)});
    }
    batch.set(saleRef, sale.toMap());
    batch.set(_counters, {'sale': FieldValue.increment(1)}, SetOptions(merge: true));
    if (method == 'credit' && customer != null) {
      batch.set(
        _bills.doc(),
        Bill(
          kind: 'receivable',
          party: customer.name,
          partyId: customer.id,
          amount: sale.total,
          due: creditDue ?? DateTime.now().add(const Duration(days: 7)),
          note: 'Venda #$number',
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

  /// Regista um pagamento (total ou parcial). Quando fica tudo pago, a conta fecha
  /// e o servidor deixa de enviar lembretes ao cliente.
  Future<void> registerPayment(Bill b, int value) {
    final paid = (b.paidAmount + value).clamp(0, b.amount);
    final done = paid >= b.amount;
    return _write(_bills.doc(b.id).update({
      'paidAmount': FieldValue.increment(value),
      'status': done ? 'done' : 'open',
      'paidAt': done ? Timestamp.now() : null,
      'payments': FieldValue.arrayUnion([
        {'value': value, 'at': Timestamp.now()}
      ]),
    }));
  }

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

  /// Marca lembretes de uma conta como enviados (não voltam a aparecer).
  Future<void> markRemindersSent(String billId, List<String> keys) =>
      _write(_bills.doc(billId).update({'remindersSent': FieldValue.arrayUnion(keys)}));

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
