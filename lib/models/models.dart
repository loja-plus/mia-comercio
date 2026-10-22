import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _dt(dynamic v) => v is Timestamp ? v.toDate() : null;
int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
double _n(dynamic v) => (v as num?)?.toDouble() ?? 0;

/// Uma caixa fechada (ex.: carne), com o peso da etiqueta e a validade.
class MeatBox {
  MeatBox({required this.id, required this.kg, this.exp, Map<String, dynamic>? raw})
      : raw = raw ?? {'id': id, 'kg': kg, 'exp': exp == null ? null : Timestamp.fromDate(exp!)};
  final String id;
  final double kg;
  final DateTime? exp;

  /// Exatamente como está guardado (necessário para a retirar da lista).
  final Map<String, dynamic> raw;

  factory MeatBox.fromMap(Map<String, dynamic> m) =>
      MeatBox(id: m['id'] ?? '', kg: _n(m['kg']), exp: _dt(m['exp']), raw: m);
}

class Product {
  Product({
    this.id = '',
    required this.name,
    this.category = 'Mercearia',
    this.barcode = '',
    this.unit = 'un',
    this.qty = 0,
    this.minQty = 0,
    this.cost = 0,
    this.price = 0,
    this.boxPrice = 0,
    this.looseKg = 0,
    this.boxes = const [],
    this.expiry,
  });

  final String id;
  final String name, category, barcode;

  /// 'un' = vende-se à unidade; 'kg' = vende-se ao peso (caixas de peso variável).
  final String unit;

  /// Quantidade em stock: unidades, ou kg no total (caixas fechadas + kg soltos).
  final double qty, minQty;

  /// Kwanza por unidade, ou por kg se [unit] == 'kg'.
  final int cost, price;

  /// Preço por kg ao vender a caixa inteira (0 = igual a [price]).
  final int boxPrice;

  /// Kg soltos (da caixa aberta).
  final double looseKg;

  /// Caixas fechadas.
  final List<MeatBox> boxes;
  final DateTime? expiry;

  bool get byWeight => unit == 'kg';
  bool get isLow => qty < minQty;
  int get boxCount => boxes.length;
  int get wholeBoxPrice => boxPrice > 0 ? boxPrice : price;

  /// Validade mais próxima (do produto ou de uma das caixas).
  DateTime? get nextExpiry {
    final all = [if (expiry != null) expiry!, for (final b in boxes) if (b.exp != null) b.exp!];
    if (all.isEmpty) return null;
    all.sort();
    return all.first;
  }

  int? daysToExpiry(DateTime now) {
    final e = nextExpiry;
    return e == null
        ? null
        : DateTime(e.year, e.month, e.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  /// Caixas ordenadas: primeiro as que expiram antes.
  List<MeatBox> get boxesByExpiry => [...boxes]..sort((a, b) {
      if (a.exp == null && b.exp == null) return 0;
      if (a.exp == null) return 1;
      if (b.exp == null) return -1;
      return a.exp!.compareTo(b.exp!);
    });

  factory Product.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Product(
      id: d.id,
      name: m['name'] ?? '',
      category: m['category'] ?? '',
      barcode: m['barcode'] ?? '',
      unit: m['unit'] ?? 'un',
      qty: _n(m['qty']),
      minQty: _n(m['minQty']),
      cost: _i(m['cost']),
      price: _i(m['price']),
      boxPrice: _i(m['boxPrice']),
      looseKg: _n(m['looseKg']),
      boxes: ((m['boxes'] as List?) ?? []).map((e) => MeatBox.fromMap(Map<String, dynamic>.from(e))).toList(),
      expiry: _dt(m['expiry']),
    );
  }

  /// Dados descritivos (sem o stock, que é alterado à parte com somas/subtrações).
  Map<String, dynamic> toMap() => {
        'name': name,
        'category': category,
        'barcode': barcode,
        'unit': unit,
        'minQty': minQty,
        'cost': cost,
        'price': price,
        'boxPrice': boxPrice,
        'expiry': expiry == null ? null : Timestamp.fromDate(expiry!),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

class Customer {
  Customer({
    this.id = '',
    required this.name,
    this.contact = '',
    this.phone = '',
    this.email = '',
    this.creditLimit = 0,
    this.optIn = true,
  });

  final String id, name, contact, phone, email;
  final int creditLimit;
  final bool optIn; // consentimento para receber mensagens

  String get greetName => contact.isNotEmpty ? contact : name;

  factory Customer.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Customer(
      id: d.id,
      name: m['name'] ?? '',
      contact: m['contact'] ?? '',
      phone: m['phone'] ?? '',
      email: m['email'] ?? '',
      creditLimit: _i(m['creditLimit']),
      optIn: m['optIn'] ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'contact': contact,
        'phone': phone,
        'email': email,
        'creditLimit': creditLimit,
        'optIn': optIn,
      };
}

class SaleLine {
  SaleLine({
    required this.productId,
    required this.name,
    required this.qty,
    required this.price,
    required this.cost,
    this.unit = 'un',
    this.box,
  });
  final String productId, name, unit;

  /// Unidades, ou kg para produtos ao peso.
  final double qty;
  final int price, cost;

  /// Caixa inteira vendida (só produtos ao peso).
  final MeatBox? box;

  int get total => (qty * price).round();
  int get profit => (qty * (price - cost)).round();
  bool get byWeight => unit == 'kg';

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'name': name,
        'qty': qty,
        'unit': unit,
        'price': price,
        'cost': cost,
        if (box != null) 'boxKg': box!.kg,
      };
  factory SaleLine.fromMap(Map<String, dynamic> m) => SaleLine(
        productId: m['productId'] ?? '',
        name: m['name'] ?? '',
        qty: _n(m['qty']),
        unit: m['unit'] ?? 'un',
        price: _i(m['price']),
        cost: _i(m['cost']),
        box: m['boxKg'] == null ? null : MeatBox(id: '', kg: _n(m['boxKg'])),
      );
}

class Sale {
  Sale({
    this.id = '',
    required this.number,
    required this.at,
    required this.customerId,
    required this.customerName,
    required this.lines,
    required this.method,
    this.sellerId = '',
    this.paidNow = 0,
    this.paidMethod = '',
  });

  /// method: 'cash' | 'card' | 'transfer' | 'credit' | 'partial' (parte agora, resto fiado)
  final String id, customerId, customerName, method, sellerId;
  final int number;

  /// Venda 'partial': quanto pagou na hora e como (o resto ficou a crédito).
  final int paidNow;
  final String paidMethod;

  /// Quanto entrou na hora por cada forma de pagamento.
  Map<String, int> get paidByMethod {
    if (method == 'credit') return {'credit': total};
    if (method == 'partial') return {paidMethod: paidNow, 'credit': total - paidNow};
    return {method: total};
  }
  final DateTime at;
  final List<SaleLine> lines;

  int get total => lines.fold(0, (a, l) => a + l.total);
  int get profit => lines.fold(0, (a, l) => a + l.profit);

  factory Sale.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Sale(
      id: d.id,
      number: _i(m['number']),
      at: _dt(m['at']) ?? DateTime.now(),
      customerId: m['customerId'] ?? '',
      customerName: m['customerName'] ?? '',
      method: m['method'] ?? 'cash',
      sellerId: m['sellerId'] ?? '',
      paidNow: _i(m['paidNow']),
      paidMethod: m['paidMethod'] ?? '',
      lines: ((m['lines'] as List?) ?? []).map((e) => SaleLine.fromMap(Map<String, dynamic>.from(e))).toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'number': number,
        'at': Timestamp.fromDate(at),
        'customerId': customerId,
        'customerName': customerName,
        'method': method,
        'sellerId': sellerId,
        'total': total,
        if (method == 'partial') 'paidNow': paidNow,
        if (method == 'partial') 'paidMethod': paidMethod,
        'lines': lines.map((l) => l.toMap()).toList(),
      };
}

/// Um pagamento (total ou parcial) de uma conta.
class Payment {
  Payment({required this.value, required this.at, this.method = ''});
  final int value;
  final DateTime at;
  final String method; // 'cash' | 'card' | 'transfer' | '' (antigo)

  factory Payment.fromMap(Map<String, dynamic> m) =>
      Payment(value: _i(m['value']), at: _dt(m['at']) ?? DateTime.now(), method: m['method'] ?? '');
  Map<String, dynamic> toMap() => {'value': value, 'at': Timestamp.fromDate(at), 'method': method};
}

/// Mudança da data de pagamento (fica no histórico).
class DueChange {
  DueChange({required this.from, required this.to, required this.at});
  final DateTime from, to, at;
  factory DueChange.fromMap(Map<String, dynamic> m) => DueChange(
      from: _dt(m['from']) ?? DateTime.now(), to: _dt(m['to']) ?? DateTime.now(), at: _dt(m['at']) ?? DateTime.now());
}

/// Conta a receber (cliente deve) ou a pagar (fornecedor/despesa).
class Bill {
  Bill({
    this.id = '',
    required this.kind,
    required this.party,
    this.partyId = '',
    required this.amount,
    this.paidAmount = 0,
    required this.due,
    this.note = '',
    this.status = 'open',
    this.paidAt,
    this.saleId = '',
    this.remindersSent = const [],
    this.remindCount = 0,
    this.lastRemindedAt,
    this.payments = const [],
    this.dueChanges = const [],
  });

  final List<Payment> payments;
  final List<DueChange> dueChanges;

  final String id, kind, party, partyId, note, status, saleId; // kind: 'receivable' | 'payable'
  /// Lembretes ao cliente já enviados (chave = 'before@<data>' etc.).
  final List<String> remindersSent;

  /// Quantas vezes já se enviou lembrete ao cliente por esta conta, e quando foi o último.
  final int remindCount;
  final DateTime? lastRemindedAt;
  final int amount, paidAmount;
  final DateTime due;
  final DateTime? paidAt;

  int get remaining => amount - paidAmount;
  bool get isOpen => status == 'open';
  bool get isReceivable => kind == 'receivable';

  factory Bill.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Bill(
      id: d.id,
      kind: m['kind'] ?? 'receivable',
      party: m['party'] ?? '',
      partyId: m['partyId'] ?? '',
      amount: _i(m['amount']),
      paidAmount: _i(m['paidAmount']),
      due: _dt(m['due']) ?? DateTime.now(),
      note: m['note'] ?? '',
      status: m['status'] ?? 'open',
      paidAt: _dt(m['paidAt']),
      saleId: m['saleId'] ?? '',
      remindersSent: List<String>.from(m['remindersSent'] ?? const []),
      remindCount: _i(m['remindCount']),
      lastRemindedAt: _dt(m['lastRemindedAt']),
      payments: ((m['payments'] as List?) ?? []).map((e) => Payment.fromMap(Map<String, dynamic>.from(e))).toList(),
      dueChanges: ((m['dueChanges'] as List?) ?? []).map((e) => DueChange.fromMap(Map<String, dynamic>.from(e))).toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'kind': kind,
        'party': party,
        'partyId': partyId,
        'amount': amount,
        'paidAmount': paidAmount,
        'due': Timestamp.fromDate(due),
        'note': note,
        'status': status,
        'paidAt': paidAt == null ? null : Timestamp.fromDate(paidAt!),
        'saleId': saleId,
        // 'remindersSent' é atualizado à parte (Db.markRemindersSent)
      };
}

class OutMessage {
  OutMessage({required this.at, required this.to, required this.channels, required this.text, required this.status});
  final DateTime at;
  final String to, text, status;
  final List<String> channels;

  factory OutMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return OutMessage(
      at: _dt(m['createdAt']) ?? DateTime.now(),
      to: m['toLabel'] ?? '',
      channels: List<String>.from(m['channels'] ?? const []),
      text: m['text'] ?? '',
      status: m['status'] ?? 'queued',
    );
  }
}
