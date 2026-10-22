import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/db.dart';
import '../services/format.dart';
import '../state/app_state.dart';
import 'common.dart';

const payMethods = ['cash', 'card', 'transfer'];

/// Pergunta quanto foi pago e como (dinheiro, Multicaixa, transferência).
/// Não deixa passar de [max]. Devolve (valor, forma) ou null.
Future<(int, String)?> askPayment(BuildContext context, {required String title, required int max}) {
  final s = context.read<AppState>().s;
  final ctrl = TextEditingController(text: '$max');
  var method = 'cash';
  return showDialog<(int, String)>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final v = int.tryParse(ctrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final tooMuch = v > max;
      return AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            onChanged: (_) => set(() {}),
            decoration: InputDecoration(
              labelText: s.t('amount'),
              helperText: '${s.t('totalOwed')}: ${kz(max)}',
              errorText: tooMuch ? s.t('moreThanOwed') : null,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in payMethods)
              ChoiceChip(label: Text(s.t(m)), selected: method == m, onSelected: (_) => set(() => method = m)),
          ]),
          if (v > 0 && v < max) ...[
            const SizedBox(height: 10),
            Text('${s.t('stillOwes')}: ${kz(max - v)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(s.t('cancel'))),
          FilledButton(
            onPressed: v <= 0 || tooMuch ? null : () => Navigator.pop(c, (v, method)),
            child: Text(s.t('save')),
          ),
        ],
      );
    }),
  );
}

/// Escolher nova data e hora de pagamento (ex.: o cliente pediu para pagar dia 28 em vez de 24).
Future<void> changeDueDialog(BuildContext context, Bill b) async {
  final s = context.read<AppState>().s;
  final d = await showDatePicker(
    context: context,
    initialDate: b.due.isBefore(DateTime.now()) ? DateTime.now() : b.due,
    firstDate: DateTime.now().subtract(const Duration(days: 1)),
    lastDate: DateTime.now().add(const Duration(days: 730)),
    helpText: '${s.t('newDueDate')} · ${b.party}',
  );
  if (d == null || !context.mounted) return;
  final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(b.due));
  if (!context.mounted) return;
  final newDue = DateTime(d.year, d.month, d.day, t?.hour ?? b.due.hour, t?.minute ?? b.due.minute);
  await Db.I.changeDue(b, newDue);
  if (context.mounted) {
    snack(context, '${s.t('dueChanged')}: ${fmtDate(b.due, s.lang)} → ${fmtDateTime(newDue, s.lang)}');
  }
}

/// Texto pequeno "data mudada (era 24 out)".
String dueMovedText(Bill b, String lang, String label) =>
    b.dueChanges.isEmpty ? '' : ' · $label ${fmtDate(b.dueChanges.first.from, lang)}';
