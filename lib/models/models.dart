import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _dt(dynamic v) => v is Timestamp ? v.toDate() : null;
int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

class Product {
  Product({
    this.id = '',
    required this.name,
    this.category = 'Mercearia',
    this.barcode = '',
    this.qty = 0,
    this.minQty = 0,
    this.cost = 0,
    this.price = 0,
    this.expiry,
  });

  final String id;
  final String name, category, barcode;
  final int qty, minQty, cost, price; // valores em Kwanza (inteiros)
  final DateTime? expiry;

  bool get isLow => qty < minQty;
  int? daysToExpiry(DateTime now) => expiry == null
      ? null
      : DateTime(expiry!.year, expiry!.month, expiry!.day)
          .difference(DateTime(now.year, now.month, now.day))
          .inDays;

  factory Product.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Product(
      id: d.id,
      name: m['name'] ?? '',
      category: m['category'] ?? '',
      barcode: m['barcode'] ?? '',
      qty: _i(m['qty']),
      minQty: _i(m['minQty']),
      cost: _i(m['cost']),
      price: _i(m['price']),
      expiry: _dt(m['expiry']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'category': category,
        'barcode': barcode,
        'qty': qty,
        'minQty': minQty,
        'cost': cost,
        'price': price,
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
  SaleLine({required this.productId, required this.name, required this.qty, required this.price, required this.cost});
  final String productId, name;
  final int qty, price, cost;
  int get total => qty * price;
  int get profit => qty * (price - cost);

  Map<String, dynamic> toMap() => {'productId': productId, 'name': name, 'qty': qty, 'price': price, 'cost': cost};
  factory SaleLine.fromMap(Map<String, dynamic> m) => SaleLine(
      productId: m['productId'] ?? '', name: m['name'] ?? '', qty: _i(m['qty']), price: _i(m['price']), cost: _i(m['cost']));
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
  });

  final String id, customerId, customerName, method, sellerId;
  final int number;
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
        'lines': lines.map((l) => l.toMap()).toList(),
      };
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
  });

  final String id, kind, party, partyId, note, status, saleId; // kind: 'receivable' | 'payable'
  /// Lembretes ao cliente já enviados (chave = 'before@<data>' etc.).
  final List<String> remindersSent;
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
