import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../client_config.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/db.dart';
import '../services/format.dart';
import '../services/notifications.dart';

/// Estado global: idioma, utilizador e os dados da loja em tempo real.
class AppState extends ChangeNotifier {
  String lang = 'pt';
  User? user;
  String role = 'cashier'; // 'admin', 'owner' ou 'cashier'
  String userName = '';

  List<Product> products = [];
  List<Customer> customers = [];
  List<Sale> sales = []; // últimos 31 dias
  List<Bill> bills = [];
  List<OutMessage> outbox = [];
  Map<String, dynamic> settings = {};
  bool online = true;

  /// Admin e proprietário veem todos os dados da loja.
  bool get isOwner => role == 'owner' || role == 'admin';
  bool get isAdmin => role == 'admin';
  String roleLabel(String r) => s.t(r == 'admin' ? 'admin' : (r == 'owner' ? 'owner' : 'cashier'));
  S get s => S(lang);

  /// Nome da loja deste cliente (Definições → Dados da loja), usado nas mensagens.
  String get shopName {
    final n = (settings['shopName'] as String?)?.trim() ?? '';
    return n.isEmpty ? ClientConfig.shopName : n;
  }

  /// Texto traduzido com o nome da loja no lugar de {loja}.
  String tx(String key) => s.t(key).replaceAll('{loja}', shopName);

  final _subs = <StreamSubscription>[];
  Timer? _reschedule, _tick;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    lang = prefs.getString('lang') ?? 'pt';
    FirebaseAuth.instance.authStateChanges().listen(_onUser);
  }

  Future<void> setLang(String l) async {
    lang = l;
    (await SharedPreferences.getInstance()).setString('lang', l);
    _scheduleAlerts();
    notifyListeners();
  }

  Future<void> _onUser(User? u) async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    user = u;
    if (u != null) {
      // Sem internet usamos a última função/nome guardados neste aparelho.
      final prefs = await SharedPreferences.getInstance();
      role = prefs.getString('role_${u.uid}') ?? 'cashier';
      userName = prefs.getString('name_${u.uid}') ?? (u.email ?? '');
      try {
        final profile = await FirebaseFirestore.instance
            .collection('users')
            .doc(u.uid)
            .get()
            .timeout(const Duration(seconds: 5));
        if (profile.exists && profile.data()?['active'] == false) {
          await FirebaseAuth.instance.signOut();
          return;
        }
        if (!profile.exists) {
          // conta sem perfil (ex.: criada fora da app) → sem acesso
          await FirebaseAuth.instance.signOut();
          return;
        }
        if (profile.exists) {
          role = profile.data()?['role'] ?? role;
          userName = profile.data()?['name'] ?? userName;
          await prefs.setString('role_${u.uid}', role);
          await prefs.setString('name_${u.uid}', userName);
        }
      } catch (_) {
        // offline: continua com os dados guardados
      }
      final db = Db.I;
      _subs.addAll([
        db.products().listen((v) => _set(() => products = v, alerts: true)),
        db.customers().listen((v) => _set(() => customers = v)),
        db.salesSince(startOfDay().subtract(const Duration(days: 31))).listen((v) => _set(() => sales = v)),
        db.bills(receivablesOnly: !isOwner).listen((v) => _set(() => bills = v, alerts: true)),
        db.settings().listen((v) => _set(() => settings = v)),
        if (isOwner) db.outbox().listen((v) => _set(() => outbox = v)),
        db.online().listen((v) => _set(() => online = v)),
        // Se o admin desativar esta conta ou mudar a função, a app reage logo.
        FirebaseFirestore.instance.collection('users').doc(u.uid).snapshots().listen((d) async {
          final m = d.data();
          if (m == null) return;
          if (m['active'] == false) {
            await FirebaseAuth.instance.signOut();
            return;
          }
          final newRole = m['role'] as String? ?? role;
          if (newRole != role) {
            role = newRole;
            (await SharedPreferences.getInstance()).setString('role_${u.uid}', role);
            await _onUser(u); // volta a ligar com as permissões novas
          }
        }),
      ]);
      // Atualiza a lista de lembretes a enviar a cada minuto.
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(minutes: 1), (_) => notifyListeners());
    } else {
      // Saiu: limpa os dados da memória (o próximo a entrar só vê os seus).
      _tick?.cancel();
      products = [];
      customers = [];
      sales = [];
      bills = [];
      outbox = [];
      role = 'cashier';
    }
    notifyListeners();
  }

  void _set(VoidCallback f, {bool alerts = false}) {
    f();
    if (alerts) _scheduleAlerts();
    notifyListeners();
  }

  void _scheduleAlerts() {
    _reschedule?.cancel();
    _reschedule = Timer(const Duration(seconds: 2), () {
      Notifier.I.rescheduleAll(products: products, bills: bills, reminders: upcomingReminders, s: s);
    });
  }

  // ---------- Números calculados para o painel ----------
  List<Sale> salesOn(DateTime day) {
    final a = startOfDay(day), b = a.add(const Duration(days: 1));
    return sales.where((x) => !x.at.isBefore(a) && x.at.isBefore(b)).toList();
  }

  int get lastSaleNumber => sales.fold(1000, (a, x) => x.number > a ? x.number : a);

  int get todayTotal => salesOn(DateTime.now()).fold(0, (a, x) => a + x.total);
  int get todayProfit => salesOn(DateTime.now()).fold(0, (a, x) => a + x.profit);
  int get stockValue => products.fold(0, (a, p) => a + p.cost * p.qty);
  List<Bill> get openReceivables => bills.where((b) => b.isOpen && b.isReceivable).toList();
  List<Bill> get openPayables => bills.where((b) => b.isOpen && !b.isReceivable).toList();
  int sumRemaining(Iterable<Bill> l) => l.fold(0, (a, b) => a + b.remaining);

  int owedBy(String customerId) => sumRemaining(openReceivables.where((b) => b.partyId == customerId));

  Customer? customerById(String id) {
    for (final c in customers) {
      if (c.id == id) return c;
    }
    return null;
  }

  Product? productByBarcode(String code) {
    for (final p in products) {
      if (p.barcode.isNotEmpty && p.barcode == code) return p;
    }
    return null;
  }

  // ---------- Lembretes de pagamento aos clientes ----------
  /// Horários dos lembretes de uma conta (por defeito: 3 dias antes às 09:00,
  /// no dia às 08:00, 2 dias depois às 10:00 — editável nas Definições).
  List<(String, DateTime)> reminderTimes(Bill b) {
    final r = rules;
    DateTime at(int offsetDays, String hhmm) {
      final p = hhmm.split(':');
      return DateTime(b.due.year, b.due.month, b.due.day + offsetDays, int.parse(p[0]), int.parse(p[1]));
    }

    return [
      ('before', at(-(r['beforeDays'] as num).toInt(), r['beforeHour'] as String)),
      ('due', at(0, r['onDueHour'] as String)),
      ('after', at((r['afterDays'] as num).toInt(), r['afterHour'] as String)),
    ];
  }

  static String reminderKey(String kind, DateTime at) => '$kind@${at.toIso8601String()}';

  bool _canMessage(Customer? c) => c != null && c.optIn && (c.phone.isNotEmpty || c.email.isNotEmpty);

  /// Lembretes cuja hora já chegou e que ainda não foram enviados.
  /// Por cliente/conta mostra só o mais recente, para não repetir mensagens.
  List<ReminderItem> get dueReminders {
    final now = DateTime.now();
    final out = <ReminderItem>[];
    for (final b in openReceivables) {
      final c = customerById(b.partyId);
      if (!_canMessage(c)) continue;
      final passed = reminderTimes(b).where((t) => !t.$2.isAfter(now)).toList();
      if (passed.isEmpty) continue;
      final keys = passed.map((t) => reminderKey(t.$1, t.$2)).toList();
      if (b.remindersSent.contains(keys.last)) continue;
      out.add(ReminderItem(bill: b, customer: c!, kind: passed.last.$1, at: passed.last.$2, keys: keys));
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  /// Próximos lembretes (ainda no futuro).
  List<ReminderItem> get upcomingReminders {
    final now = DateTime.now();
    final out = <ReminderItem>[];
    for (final b in openReceivables) {
      final c = customerById(b.partyId);
      if (!_canMessage(c)) continue;
      for (final t in reminderTimes(b)) {
        if (t.$2.isAfter(now)) {
          out.add(ReminderItem(bill: b, customer: c!, kind: t.$1, at: t.$2, keys: [reminderKey(t.$1, t.$2)]));
        }
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  /// Texto do lembrete de pagamento (modelo editável nas Definições).
  String paymentText(Bill b) {
    final c = customerById(b.partyId);
    final custom = (settings['templatePayment_$lang'] as String?) ?? s.t('tmplPay');
    return custom
        .replaceAll('{loja}', shopName)
        .replaceAll('{nome}', c?.greetName ?? b.party)
        .replaceAll('{valor}', kz(b.remaining))
        .replaceAll('{data}', fmtDate(b.due, lang));
  }

  /// Regras de lembrete aos clientes (editáveis nas Definições).
  Map<String, dynamic> get rules => {
        'beforeDays': 3,
        'beforeHour': '09:00',
        'onDueHour': '08:00',
        'afterDays': 2,
        'afterHour': '10:00',
        ...Map<String, dynamic>.from(settings['reminderRules'] ?? {}),
      };
}

class ReminderItem {
  ReminderItem({required this.bill, required this.customer, required this.kind, required this.at, required this.keys});
  final Bill bill;
  final Customer customer;
  final String kind; // 'before' | 'due' | 'after'
  final DateTime at;
  final List<String> keys; // chaves a marcar como enviadas
}
