import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/db.dart';
import '../services/format.dart';
import '../services/messaging.dart';
import '../state/app_state.dart';
import '../widgets/alerts.dart';
import '../widgets/common.dart';
import 'home_shell.dart';

/// Lembretes de pagamento (plano gratuito):
/// a app diz QUANDO enviar e prepara a mensagem; um toque abre o WhatsApp
/// ou o email com o texto já escrito, e a pessoa só carrega em "Enviar".
class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final due = app.dueReminders;
    final upcoming = app.upcomingReminders;
    final rules = app.rules;
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final toSend = Panel(
      title: '${s.t('toSendNow')} (${due.length})',
      child: due.isEmpty
          ? Empty(s.t('nothing'))
          : Column(children: [for (final r in due) _DueTile(item: r)]),
    );
    final next = Panel(
      title: s.t('scheduled'),
      child: upcoming.isEmpty
          ? Empty(s.t('nothing'))
          : Column(children: [
              for (final r in upcoming.take(12))
                StripeTile(
                  sev: Sev.info,
                  title: '${r.customer.name} · ${fmtDateTime(r.at, s.lang)}',
                  subtitle: '${kz(r.bill.remaining)} · ${s.t('due')} ${fmtDate(r.bill.due, s.lang)}',
                ),
            ]),
    );
    final rulesPanel = Panel(
      title: s.t('rules'),
      child: Column(children: [
        StripeTile(
            sev: Sev.info,
            title: s.t('rule1').replaceAll('{d}', '${rules['beforeDays']}').replaceAll('{h}', rules['beforeHour'])),
        StripeTile(sev: Sev.warn, title: s.t('rule2').replaceAll('{h}', rules['onDueHour'])),
        StripeTile(
            sev: Sev.bad,
            title: s.t('rule3').replaceAll('{d}', '${rules['afterDays']}').replaceAll('{h}', rules['afterHour'])),
      ]),
    );
    final mine = Panel(title: s.t('myAlerts'), child: AlertList(items: buildAlerts(app), emptyText: s.t('nothing')));

    return PageScaffold(
      title: s.t('reminders'),
      subtitle: s.t('remindersHelp'),
      children: wide
          ? [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(children: [toSend, const SizedBox(height: 16), next])),
                const SizedBox(width: 16),
                Expanded(child: Column(children: [rulesPanel, const SizedBox(height: 16), mine])),
              ])
            ]
          : [toSend, const SizedBox(height: 16), next, const SizedBox(height: 16), rulesPanel, const SizedBox(height: 16), mine],
    );
  }
}

class _DueTile extends StatelessWidget {
  const _DueTile({required this.item});
  final ReminderItem item;

  Future<void> _sent(AppState app, List<String> channels) async {
    await Db.I.markRemindersSent(item.bill.id, item.keys);
    await Db.I.logMessage(
      type: 'payment_reminder',
      text: app.paymentText(item.bill),
      toLabel: item.customer.name,
      channels: channels,
      billId: item.bill.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final s = app.s;
    final c = item.customer;
    final text = app.paymentText(item.bill);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${c.name} · ${kz(item.bill.remaining)}', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('${s.t('due')} ${dueText(item.bill.due, s)}', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
                bottomRight: Radius.circular(12),
                bottomLeft: Radius.circular(3)),
          ),
          child: Text(text),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (c.phone.isNotEmpty)
            FilledButton.icon(
              icon: const Icon(Icons.chat),
              label: const Text('WhatsApp'),
              onPressed: () async {
                await Messaging.whatsapp(c.phone, text);
                await _sent(app, ['whatsapp']);
              },
            ),
          if (c.email.isNotEmpty)
            OutlinedButton.icon(
              icon: const Icon(Icons.mail_outline),
              label: const Text('Email'),
              onPressed: () async {
                await Messaging.email(to: [c.email], subject: app.tx('subjPay'), body: text);
                await _sent(app, ['email']);
              },
            ),
          TextButton(onPressed: () => Db.I.markRemindersSent(item.bill.id, item.keys), child: Text(s.t('skip'))),
        ]),
      ]),
    );
  }
}
