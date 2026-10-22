import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/format.dart';
import '../state/app_state.dart';
import '../widgets/alerts.dart';
import '../widgets/common.dart';
import 'home_shell.dart';
import 'sales_screen.dart';
import 'stock_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final today = app.salesOn(DateTime.now());
    final recv = app.openReceivables, pay = app.openPayables;
    final recvOver = app.sumRemaining(recv.where((b) => daysFromToday(b.due) < 0));
    final pay7 = app.sumRemaining(pay.where((b) => daysFromToday(b.due) <= 7));
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final kpis = ResponsiveGrid(minWidth: 200, children: [
      Kpi(
        label: s.t('salesToday'),
        value: kz(app.todayTotal),
        sub: app.isOwner ? '${today.length} · ${s.t('profitToday')} ${kz(app.todayProfit)}' : '${today.length}',
        highlight: true,
      ),
      if (app.isOwner) ...[
        Kpi(label: s.t('stockValue'), value: kz(app.stockValue), sub: '${app.products.length} ${s.t('product').toLowerCase()}s'),
        Kpi(
          label: s.t('toReceive'),
          value: kz(app.sumRemaining(recv)),
          sub: '${kz(recvOver)} ${s.t('overdue')}',
          subColor: recvOver > 0 ? sevColor(context, Sev.bad) : null,
        ),
        Kpi(label: s.t('toPay'), value: kz(app.sumRemaining(pay)), sub: '${kz(pay7)} ${s.t('due7')}'),
      ],
    ]);

    final chart = Panel(title: s.t('last7'), child: SizedBox(height: 200, child: _WeekChart(app: app)));
    final todayList = Panel(
      title: s.t('salesToday'),
      child: today.isEmpty
          ? Empty(s.t('nothing'))
          : Column(children: [for (final x in today.take(6)) SaleTile(sale: x)]),
    );
    final alerts = Panel(
      title: s.t('attention'),
      child: AlertList(items: buildAlerts(app).take(10).toList(), emptyText: s.t('nothing')),
    );

    return PageScaffold(
      title: s.t('dashboard'),
      subtitle: fmtDate(DateTime.now(), s.lang),
      actions: [
        if (app.isOwner)
          OutlinedButton.icon(
              onPressed: () => openProductForm(context), icon: const Icon(Icons.add), label: Text(s.t('addProduct'))),
        FilledButton.icon(
            onPressed: () => openNewSale(context), icon: const Icon(Icons.add_shopping_cart), label: Text(s.t('newSale'))),
      ],
      children: [
        kpis,
        const SizedBox(height: 16),
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 13, child: Column(children: [chart, const SizedBox(height: 16), todayList])),
            const SizedBox(width: 16),
            Expanded(flex: 10, child: alerts),
          ])
        else ...[
          alerts,
          const SizedBox(height: 16),
          chart,
          const SizedBox(height: 16),
          todayList,
        ],
      ],
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.app});
  final AppState app;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final days = List.generate(7, (i) => startOfDay().subtract(Duration(days: 6 - i)));
    final totals = days.map((d) => app.salesOn(d).fold<int>(0, (a, x) => a + x.total)).toList();
    final max = totals.fold<int>(1, (a, b) => b > a ? b : a);
    return BarChart(BarChartData(
      maxY: max * 1.15,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (v, _) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(fmtWeekday(days[v.toInt()], app.lang), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
          ),
        ),
      ),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (g, _, rod, __) => BarTooltipItem(kz(rod.toY), TextStyle(color: cs.onInverseSurface)),
          getTooltipColor: (_) => cs.inverseSurface,
        ),
      ),
      barGroups: [
        for (var i = 0; i < 7; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: totals[i].toDouble(),
              width: 22,
              borderRadius: BorderRadius.circular(4),
              color: i == 6 ? cs.secondary : cs.primary,
            ),
          ]),
      ],
    ));
  }
}
