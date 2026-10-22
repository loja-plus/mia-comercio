import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../client_config.dart';
import '../services/db.dart';
import '../state/app_state.dart';
import 'accounts_screen.dart';
import 'broadcast_screen.dart';
import 'customers_screen.dart';
import 'dashboard_screen.dart';
import 'reminders_screen.dart';
import 'sales_screen.dart';
import 'settings_screen.dart';
import 'stock_screen.dart';

class _Dest {
  const _Dest(this.key, this.icon, this.page, {this.ownerOnly = false});
  final String key;
  final IconData icon;
  final Widget page;
  final bool ownerOnly;
}

const _all = <_Dest>[
  _Dest('dashboard', Icons.space_dashboard_outlined, DashboardScreen()),
  _Dest('sales', Icons.point_of_sale_outlined, SalesScreen()),
  _Dest('stock', Icons.inventory_2_outlined, StockScreen()),
  _Dest('accounts', Icons.account_balance_wallet_outlined, AccountsScreen(), ownerOnly: true),
  _Dest('customers', Icons.people_outline, CustomersScreen()),
  _Dest('reminders', Icons.notifications_outlined, RemindersScreen(), ownerOnly: true),
  _Dest('broadcast', Icons.campaign_outlined, BroadcastScreen(), ownerOnly: true),
  _Dest('settings', Icons.settings_outlined, SettingsScreen()),
];

/// iPad / tablet: menu lateral. Telemóvel: barra em baixo com "Mais".
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final dests = _all.where((d) => !d.ownerOnly || app.isOwner).toList();
    if (_i >= dests.length) _i = 0;
    final width = MediaQuery.sizeOf(context).width;
    final due = app.isOwner ? app.dueReminders.length : 0; // lembretes por enviar

    if (width >= 700) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            extended: width >= 1100,
            selectedIndex: _i,
            onDestinationSelected: (i) => setState(() => _i = i),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: width >= 1100
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(ClientConfig.appName,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      Text(app.shopName, style: Theme.of(context).textTheme.bodySmall),
                    ])
                  : Text('L+', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
            destinations: [
              for (final d in dests)
                NavigationRailDestination(
                  icon: d.key == 'reminders' && due > 0 ? Badge(label: Text('$due'), child: Icon(d.icon)) : Icon(d.icon),
                  label: Text(s.t(d.key)),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: SafeArea(left: false, child: _WithSync(child: dests[_i].page))),
        ]),
      );
    }

    const mainCount = 4;
    final more = _i >= mainCount;
    return Scaffold(
      body: SafeArea(child: _WithSync(child: dests[_i].page)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: more ? mainCount : _i,
        onDestinationSelected: (i) {
          if (i < mainCount) return setState(() => _i = i);
          showModalBottomSheet(
            context: context,
            builder: (_) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (var j = mainCount; j < dests.length; j++)
                  ListTile(
                    leading: Icon(dests[j].icon),
                    title: Text(s.t(dests[j].key)),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _i = j);
                    },
                  ),
              ]),
            ),
          );
        },
        destinations: [
          for (var j = 0; j < mainCount; j++) NavigationDestination(icon: Icon(dests[j].icon), label: s.t(dests[j].key)),
          NavigationDestination(
            icon: due > 0 ? Badge(label: Text('$due'), child: const Icon(Icons.more_horiz)) : const Icon(Icons.more_horiz),
            label: s.lang == 'pt' ? 'Mais' : 'More',
          ),
        ],
      ),
    );
  }
}

/// Faixa no topo que mostra o estado da sincronização.
class _WithSync extends StatelessWidget {
  const _WithSync({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      ValueListenableBuilder<int>(
        valueListenable: Db.I.pending,
        builder: (context, n, _) {
          if (app.online && n == 0) return const SizedBox.shrink();
          final text = !app.online
              ? '${s.t('offline')}${n > 0 ? ' · ${s.t('pendingSync').replaceAll('{n}', '$n')}' : ''}'
              : s.t('syncing').replaceAll('{n}', '$n');
          return Material(
            color: app.online ? cs.secondaryContainer : cs.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Icon(app.online ? Icons.sync : Icons.cloud_off, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
              ]),
            ),
          );
        },
      ),
      Expanded(child: child),
    ]);
  }
}

/// Cabeçalho comum de cada ecrã.
class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, required this.title, required this.children, this.actions = const [], this.subtitle});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.sizeOf(context).width >= 700 ? 24.0 : 16.0;
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, pad, pad, 40),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 12,
          runSpacing: 12,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
              if (subtitle != null)
                Text(subtitle!, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }
}
