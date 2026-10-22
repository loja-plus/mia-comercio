import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../l10n/strings.dart';
import '../models/models.dart';
import '../state/app_state.dart' show ReminderItem;
import 'format.dart';

/// (Versão Android/iOS. No browser usa-se notifications_web.dart.)
/// Alertas no próprio aparelho, à data e hora certas (mesmo com a app fechada):
///  - validade de produtos (30, 7 e 1 dia antes, às 08:00)
///  - contas a pagar (1 dia antes às 09:00 e na hora exata do vencimento)
///  - contas a receber (na hora exata do vencimento)
/// Sempre que os dados mudam, todos os alertas são recalculados, por isso
/// qualquer aparelho com a app instalada recebe os mesmos avisos.
class Notifier {
  Notifier._();
  static final Notifier I = Notifier._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'mia_alerts',
    'Alertas Loja+',
    channelDescription: 'Validades e pagamentos',
    importance: Importance.high,
    priority: Priority.high,
  );
  static const _details = NotificationDetails(
    android: _channel,
    iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true, presentBadge: true),
  );

  Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Africa/Luanda'));
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    _ready = true;
  }

  Future<void> rescheduleAll({
    required List<Product> products,
    required List<Bill> bills,
    required List<ReminderItem> reminders,
    required S s,
  }) async {
    if (!_ready) return;
    await _plugin.cancelAll();
    final now = DateTime.now();
    final items = <(DateTime, String, String)>[];

    for (final p in products) {
      final exp = p.nextExpiry;
      if (exp == null || p.qty <= 0) continue;
      for (final before in const [30, 7, 1]) {
        final at = DateTime(exp.year, exp.month, exp.day - before, 8);
        items.add((at, s.t('notifExpiry'), '${p.name} · ${fmtDate(exp, s.lang)} · ${fmtQty(p.qty, p.unit)}'));
      }
    }
    for (final b in bills.where((b) => b.isOpen)) {
      if (b.isReceivable) {
        items.add((b.due, s.t('notifRecv'), '${b.party} · ${kz(b.remaining)}'));
      } else {
        final dayBefore = DateTime(b.due.year, b.due.month, b.due.day - 1, 9);
        items.add((dayBefore, s.t('notifPay'), '${b.party} · ${kz(b.remaining)} · ${fmtDateTime(b.due, s.lang)}'));
        items.add((b.due, s.t('notifPay'), '${b.party} · ${kz(b.remaining)}'));
      }
    }

    // Hora de enviar um lembrete de pagamento a um cliente (envio com um toque na app).
    for (final r in reminders) {
      items.add((r.at, s.t('notifSendReminder'), '${r.customer.name} · ${kz(r.remaining)}'));
    }

    // iOS só permite 64 alertas agendados: guardamos os mais próximos.
    final upcoming = items.where((e) => e.$1.isAfter(now)).toList()..sort((a, b) => a.$1.compareTo(b.$1));
    var id = 0;
    for (final (at, title, body) in upcoming.take(60)) {
      await _plugin.zonedSchedule(
        id++,
        title,
        body,
        tz.TZDateTime.from(at, tz.local),
        _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }
}
