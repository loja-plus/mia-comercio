import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/db.dart';
import '../services/format.dart';
import '../services/messaging.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'home_shell.dart';

/// Anunciar novidades aos clientes (plano gratuito):
///  - Email: um toque abre o email com TODOS os clientes em Bcc.
///  - WhatsApp: um toque por cliente (mensagem já escrita), ou copiar o texto
///    para uma "lista de difusão" do próprio WhatsApp.
class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key, this.initialProduct});
  final Product? initialProduct;
  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  Product? _product;
  final _text = TextEditingController();
  final _done = <String>{}; // clientes já enviados nesta sessão

  @override
  void initState() {
    super.initState();
    if (widget.initialProduct != null) {
      _product = widget.initialProduct;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _text.text = context.read<AppState>().tx('tmplArr').replaceAll('{produto}', _product!.name);
        setState(() {});
      });
    }
  }

  Future<void> _log(List<String> channels, String to) =>
      Db.I.logMessage(type: 'arrival', text: _text.text.trim(), toLabel: to, channels: channels);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final optIn = app.customers.where((c) => c.optIn).toList();
    final waList = optIn.where((c) => c.phone.isNotEmpty).toList();
    final emails = optIn.where((c) => c.email.isNotEmpty).map((c) => c.email).toList();
    final text = _text.text.trim();
    final ready = text.isNotEmpty;
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final compose = Panel(
      title: s.t('newArrival'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
          // (um produto acabado de criar pode ainda não estar na lista)
          value: app.products.any((p) => p.id == _product?.id) ? _product!.id : null,
          decoration: InputDecoration(labelText: s.t('product')),
          items: [for (final p in app.products) DropdownMenuItem(value: p.id, child: Text(p.name))],
          onChanged: (id) => setState(() {
            _product = app.products.firstWhere((p) => p.id == id);
            _text.text = app.tx('tmplArr').replaceAll('{produto}', _product!.name);
            _done.clear();
          }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: s.t('message')),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            icon: const Icon(Icons.mail_outline),
            label: Text('${s.t('emailAll')} (${emails.length})'),
            onPressed: !ready || emails.isEmpty
                ? null
                : () async {
                    await Messaging.email(bcc: emails, subject: app.tx('subjArr'), body: text);
                    await _log(['email'], '${emails.length} ${s.t('customers').toLowerCase()}');
                  },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy),
            label: Text(s.t('copyText')),
            onPressed: !ready
                ? null
                : () async {
                    await Messaging.copy(text);
                    if (context.mounted) snack(context, s.t('copied'));
                  },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.campaign_outlined),
            label: Text(s.t('waBroadcast')),
            onPressed: !ready ? null : () => Messaging.whatsappPickContact(text),
          ),
        ]),
        const SizedBox(height: 8),
        Text(s.t('waBroadcastHelp'), style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
    );

    final perCustomer = Panel(
      title: '${s.t('waOneByOne')} (${_done.length}/${waList.length})',
      child: waList.isEmpty
          ? Empty(s.t('nothing'))
          : Column(children: [
              for (final c in waList)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(c.name),
                  subtitle: Text(c.phone),
                  trailing: _done.contains(c.id)
                      ? Pill(s.t('sentOk'), Sev.ok)
                      : FilledButton.tonalIcon(
                          icon: const Icon(Icons.chat, size: 18),
                          label: const Text('WhatsApp'),
                          onPressed: !ready
                              ? null
                              : () async {
                                  await Messaging.whatsapp(c.phone, text.replaceAll('{nome}', c.greetName));
                                  setState(() => _done.add(c.id));
                                  await _log(['whatsapp'], c.name);
                                },
                        ),
                ),
            ]),
    );

    final history = Panel(
      title: s.t('history'),
      child: app.outbox.isEmpty
          ? Empty(s.t('nothing'))
          : Column(children: [
              for (final m in app.outbox.take(20))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${m.to} · ${fmtDateTime(m.at, s.lang)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(m.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Pill(m.channels.join(' + '), Sev.ok),
                ),
            ]),
    );

    return PageScaffold(
      title: s.t('broadcast'),
      children: wide
          ? [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(children: [compose, const SizedBox(height: 16), history])),
                const SizedBox(width: 16),
                Expanded(child: perCustomer),
              ])
            ]
          : [compose, const SizedBox(height: 16), perCustomer, const SizedBox(height: 16), history],
    );
  }
}

/// Abre o ecrã de anúncio já preenchido com um produto (usado depois de adicionar um produto).
Future<void> openArrival(BuildContext context, Product p) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(appBar: AppBar(), body: BroadcastScreen(initialProduct: p)),
    ));
