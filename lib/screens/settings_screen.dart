import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/accounts.dart';
import '../services/db.dart';
import '../services/export.dart';
import '../services/format.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'home_shell.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    return PageScaffold(
      title: s.t('settings'),
      subtitle: '${app.userName} · ${app.roleLabel(app.role)}',
      actions: [
        OutlinedButton.icon(
            onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout), label: Text(s.t('signOut'))),
      ],
      children: [
        Panel(
          title: s.t('language'),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pt', label: Text('Português')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {app.lang},
              onSelectionChanged: (v) => app.setLang(v.first),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _CashClose(),
        if (app.isOwner) ...[
          const SizedBox(height: 16),
          const _ShopInfo(),
          const SizedBox(height: 16),
          const _Backup(),
          const SizedBox(height: 16),
          const _Staff(),
          const SizedBox(height: 16),
          const _Reorder(),
          const SizedBox(height: 16),
          const _RulesEditor(),
        ],
      ],
    );
  }
}

/// Fecho de caixa: compara o dinheiro contado com as vendas em dinheiro de hoje.
class _CashClose extends StatefulWidget {
  const _CashClose();
  @override
  State<_CashClose> createState() => _CashCloseState();
}

class _CashCloseState extends State<_CashClose> {
  final _counted = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    // Dinheiro esperado na caixa: vendas em dinheiro + parte paga em dinheiro + dívidas recebidas em dinheiro.
    final expected = (app.todayByMethod['cash'] ?? 0) + (app.todayDebtPayments['cash'] ?? 0);
    final counted = int.tryParse(_counted.text.replaceAll(RegExp(r'[^0-9]'), ''));
    final diff = counted == null ? null : counted - expected;
    return Panel(
      title: s.t('cashClose'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${s.t('expected')}: ${kz(expected)}'),
        const SizedBox(height: 10),
        Row(children: [
          SizedBox(
            width: 220,
            child: TextField(
              controller: _counted,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: s.t('counted'), isDense: true),
            ),
          ),
          const SizedBox(width: 12),
          if (diff != null) Pill('${s.t('difference')}: ${kz(diff)}', diff == 0 ? Sev.ok : (diff < 0 ? Sev.bad : Sev.warn)),
        ]),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: counted == null
              ? null
              : () async {
                  await Db.I.saveCashClose(expected: expected, counted: counted, by: app.userName);
                  if (!context.mounted) return;
                  snack(context, s.t('save'));
                  _counted.clear();
                  setState(() {});
                },
          child: Text(s.t('save')),
        ),
      ]),
    );
  }
}

/// Nome da loja (aparece nas mensagens aos clientes e no menu).
class _ShopInfo extends StatefulWidget {
  const _ShopInfo();
  @override
  State<_ShopInfo> createState() => _ShopInfoState();
}

class _ShopInfoState extends State<_ShopInfo> {
  late final _name = TextEditingController(text: context.read<AppState>().shopName);
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    return Panel(
      title: s.t('shopData'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: _name, decoration: InputDecoration(labelText: s.t('shopNameLabel'))),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: () async {
            await Db.I.saveSettings({'shopName': _name.text.trim()});
            if (context.mounted) snack(context, s.t('save'));
          },
          child: Text(s.t('save')),
        ),
      ]),
    );
  }
}

/// Cópia de segurança em Excel (gratuita). Recomenda-se uma vez por semana.
class _Backup extends StatefulWidget {
  const _Backup();
  @override
  State<_Backup> createState() => _BackupState();
}

class _BackupState extends State<_Backup> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    return Panel(
      title: s.t('backup'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.t('backupHelp')),
        const SizedBox(height: 10),
        FilledButton.icon(
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download),
          label: Text(s.t('exportExcel')),
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    final f = await ExportService.exportAll(app);
                    if (context.mounted) snack(context, '${s.t('exported')}: $f');
                  } catch (_) {
                    if (context.mounted) snack(context, s.t('errNeedInternet'));
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
        ),
      ]),
    );
  }
}

/// Encomenda sugerida: produtos abaixo do mínimo e quanto comprar (até 3× o mínimo).
class _Reorder extends StatelessWidget {
  const _Reorder();
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final low = app.products.where((p) => p.isLow).toList();
    double need(Product p) => p.minQty * 3 - p.qty;
    final total = low.fold<int>(0, (a, p) => a + (need(p) * p.cost).round());
    return Panel(
      title: s.t('reorder'),
      action: low.isEmpty ? null : Text(kz(total), style: const TextStyle(fontWeight: FontWeight.w600)),
      child: low.isEmpty
          ? Empty(s.t('nothing'))
          : Column(children: [
              for (final p in low)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.name),
                  subtitle: Text('${fmtQty(p.qty, p.unit)} / ${s.t('minQty')} ${fmtQty(p.minQty, p.unit)}'),
                  trailing: Text('+${fmtQty(need(p), p.unit)} · ${kz((need(p) * p.cost).round())}'),
                ),
            ]),
    );
  }
}

/// Quando são enviados os lembretes automáticos aos clientes.
class _RulesEditor extends StatefulWidget {
  const _RulesEditor();
  @override
  State<_RulesEditor> createState() => _RulesEditorState();
}

class _RulesEditorState extends State<_RulesEditor> {
  Map<String, dynamic>? _r;
  late final TextEditingController _tmpl;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _tmpl = TextEditingController(
        text: (app.settings['templatePayment_${app.lang}'] as String?) ?? app.s.t('tmplPay'));
  }

  Future<void> _time(String key) async {
    final p = (_r![key] as String).split(':');
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])));
    if (t == null) return;
    setState(() => _r![key] = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    _r ??= Map<String, dynamic>.from(app.rules);
    Widget days(String key) => DropdownButton<int>(
          value: (_r![key] as num).toInt(),
          items: [for (var i = 1; i <= 14; i++) DropdownMenuItem(value: i, child: Text('$i ${s.t('days')}'))],
          onChanged: (v) => setState(() => _r![key] = v),
        );
    Widget hour(String key) => OutlinedButton(onPressed: () => _time(key), child: Text(_r![key]));

    return Panel(
      title: s.t('rules'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Icon(Icons.looks_one_outlined), days('beforeDays'), hour('beforeHour'),
        ]),
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Icon(Icons.looks_two_outlined), Text(s.t('today')), hour('onDueHour'),
        ]),
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Icon(Icons.looks_3_outlined), days('afterDays'), hour('afterHour'),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _tmpl,
          maxLines: 3,
          decoration: InputDecoration(labelText: '${s.t('message')} ({nome} {valor} {data} {loja})'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () async {
            await Db.I.saveSettings({
              'reminderRules': _r,
              'lang': app.lang,
              'templatePayment_${app.lang}': _tmpl.text.trim(),
            });
            if (context.mounted) snack(context, s.t('save'));
          },
          child: Text(s.t('save')),
        ),
      ]),
    );
  }
}

/// Funcionários: admin gere todas as contas; proprietário só caixas.
class _Staff extends StatelessWidget {
  const _Staff();

  Future<void> _run(BuildContext context, Future<void> Function() f, {String? okKey}) async {
    final s = context.read<AppState>().s;
    try {
      await f();
      if (context.mounted && okKey != null) snack(context, s.t(okKey));
    } catch (e) {
      if (context.mounted) snack(context, s.t(accountErrorKey(e)));
    }
  }

  Future<void> _add(BuildContext context) async {
    final app = context.read<AppState>();
    final s = app.s;
    final name = TextEditingController(), email = TextEditingController(), pass = TextEditingController();
    var role = 'cashier';
    // Admin escolhe qualquer função; proprietário só cria caixas.
    final roles = app.isAdmin ? const ['cashier', 'owner', 'admin'] : const ['cashier'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(s.t('addStaff')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: InputDecoration(labelText: s.t('name'))),
              const SizedBox(height: 10),
              TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: s.t('email'))),
              const SizedBox(height: 10),
              TextField(
                  controller: pass, decoration: InputDecoration(labelText: s.t('password'), helperText: s.t('pwHint'))),
              if (roles.length > 1) ...[
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: [for (final r in roles) ButtonSegment(value: r, label: Text(app.roleLabel(r)))],
                  selected: {role},
                  onSelectionChanged: (v) => set(() => role = v.first),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('save'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(
      context,
      () => Accounts.I.createStaff(name: name.text.trim(), email: email.text.trim(), password: pass.text, role: role),
      okKey: 'staffSaved',
    );
  }

  Future<void> _reset(BuildContext context, StaffMember m) async {
    final s = context.read<AppState>().s;
    final ok = await confirmDialog(context, s.t('resetConfirm').replaceAll('{email}', m.email),
        ok: s.t('send'), cancel: s.t('cancel'));
    if (!ok || !context.mounted) return;
    await _run(context, () => Accounts.I.sendPasswordReset(m.email), okKey: 'resetSent');
  }

  Widget _member(BuildContext context, AppState app, StaffMember m) {
    final s = app.s;
    final me = m.uid == app.user?.uid;
    final canTouch = !me && StaffMember.canManage(app.role, m.role);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(me ? '${m.name} (${s.t('you')})' : m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${m.email} · ${app.roleLabel(m.role)}${m.active ? '' : ' · ${s.t('inactive')}'}'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (app.isAdmin && !me)
          PopupMenuButton<String>(
            tooltip: s.t('changeRole'),
            icon: const Icon(Icons.badge_outlined),
            onSelected: (r) => _run(context, () => Accounts.I.setRole(m.uid, r), okKey: 'save'),
            itemBuilder: (_) => [
              for (final r in const ['admin', 'owner', 'cashier'])
                CheckedPopupMenuItem(value: r, checked: m.role == r, child: Text(app.roleLabel(r))),
            ],
          ),
        if (canTouch || (me && app.isAdmin))
          IconButton(
            tooltip: s.t('resetPassword'),
            icon: const Icon(Icons.key_outlined),
            onPressed: () => _reset(context, m),
          ),
        if (canTouch) Switch(value: m.active, onChanged: (v) => _run(context, () => Accounts.I.setActive(m.uid, v))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    return Panel(
      title: s.t('staff'),
      action: FilledButton.tonalIcon(
          onPressed: () => _add(context), icon: const Icon(Icons.person_add), label: Text(s.t('addStaff'))),
      child: StreamBuilder<List<StaffMember>>(
        stream: Accounts.I.staff(),
        builder: (context, snap) {
          final list = [...?snap.data];
          if (list.isEmpty) return Empty(s.t('nothing'));
          const order = {'admin': 0, 'owner': 1, 'cashier': 2};
          list.sort((a, b) => (order[a.role] ?? 3).compareTo(order[b.role] ?? 3));
          return Column(children: [
            for (final m in list) _member(context, app, m),
          ]);
        },
      ),
    );
  }
}
