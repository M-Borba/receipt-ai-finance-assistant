import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/format/money.dart';

import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/expenses/domain/entities/expense_entity.dart';
import '../../../../features/expenses/presentation/providers/expense_provider.dart';
import '../../../../features/expenses/presentation/providers/mes_actual_provider.dart';
import '../../../../features/expenses/presentation/widgets/add_expense_sheet.dart';
import '../../../../features/budgets/domain/entities/budget_status.dart';
import '../../../../features/budgets/presentation/providers/budget_provider.dart';
import '../../../../features/groups/presentation/providers/group_provider.dart';
import '../../../../features/insights/domain/entities/insight_entity.dart';
import '../../../../features/insights/presentation/providers/insights_provider.dart';
import '../../../../features/receipts/domain/entities/receipt_entity.dart';
import '../../../../features/receipts/presentation/providers/receipt_provider.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/loading_indicator.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final totalSpending = ref.watch(totalSpendingCurrentMonthProvider);
    final categoryTotals = ref.watch(categoryTotalsCurrentMonthProvider);
    final receiptsAsync = ref.watch(receiptsStreamProvider);
    final insightsAsync = ref.watch(monthlyInsightsProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AddExpenseSheet.show(context),
        icon: const Icon(Icons.add),
        label: const Text('Gasto'),
      ),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context, user?.displayNameOrEmail ?? 'Hola'),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _SpendingCard(totalSpending: totalSpending),
                const SizedBox(height: 16),
                const _BudgetAlerts(),
                if (categoryTotals.isNotEmpty) ...[
                  _CategoryChart(totals: categoryTotals, totalSpending: totalSpending),
                  const SizedBox(height: 16),
                ],
                _SectionHeader(
                  title: 'Insights',
                  onTap: () => context.go('/insights'),
                ),
                const SizedBox(height: 12),
                _InsightsSummary(insightsAsync: insightsAsync),
                const SizedBox(height: 16),
                _SectionHeader(
                  title: 'Grupos',
                  onTap: () => context.go('/groups'),
                ),
                const SizedBox(height: 12),
                const _ResumenGrupos(),
                const SizedBox(height: 16),
                _SectionHeader(
                  title: 'Tickets recientes',
                  onTap: () => context.go('/receipts'),
                ),
                const SizedBox(height: 12),
                _RecentReceiptsList(receiptsAsync: receiptsAsync),
                const SizedBox(height: 80),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context, String name) {
    return SliverAppBar(
      floating: true,
      backgroundColor: AppColors.backgroundDark,
      expandedHeight: 100,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hola, $name 👋',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const Text(
              'Tu resumen del mes',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: AppColors.textSecondary),
          tooltip: 'Ajustes',
          onPressed: () => context.go('/settings'),
        ),
      ],
    );
  }
}

/// Avisos de presupuesto. Es el unico bloque del dashboard que dice si estas
/// bien o mal, en vez de solo cuanto gastaste.
class _BudgetAlerts extends ConsumerWidget {
  const _BudgetAlerts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estados = ref.watch(budgetStatusesProvider);
    if (estados.isEmpty) return const SizedBox.shrink();

    // Ya vienen ordenados por urgencia: los excedidos primero.
    final alertas = estados
        .where((s) => s.state != BudgetState.ok)
        .take(3)
        .toList();

    if (alertas.isEmpty) {
      final resumen = ref.watch(budgetSummaryProvider);
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    color: AppColors.success, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tus ${resumen.total} presupuestos están en verde',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: alertas.map((s) {
          final excedido = s.state == BudgetState.exceeded;
          final color = excedido ? AppColors.error : AppColors.warning;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Text(s.category.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          excedido
                              ? 'Te pasaste en ${s.category.label}'
                              : 'Vas por el ${s.percent}% en ${s.category.label}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: color, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          excedido
                              ? '${Money.format(s.spentCents)} de ${Money.format(s.limitCents)}'
                              : 'Quedan ${Money.format(s.remainingCents)} este mes',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SpendingCard extends ConsumerWidget {
  final int totalSpending;
  const _SpendingCard({required this.totalSpending});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // El mes sale del mismo provider que el total, asi que el titulo y el
    // numero no pueden discrepar. Ver MesActual.
    final month = AppDate.monthYear(ref.watch(mesActualProvider));

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(month, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          Text(
            Money.format(totalSpending),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text('Gastado este mes',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}

class _CategoryChart extends StatelessWidget {
  final Map<ExpenseCategory, int> totals;
  final int totalSpending;

  const _CategoryChart({required this.totals, required this.totalSpending});

  @override
  Widget build(BuildContext context) {
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(4).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Top Categories', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: top.first.value * 1.2,
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx >= top.length) return const SizedBox.shrink();
                          return Text(
                            top[idx].key.emoji,
                            style: const TextStyle(fontSize: 16),
                          );
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(top.length, (i) {
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: top[i].value.toDouble(),
                          color: top[i].key.color,
                          width: 32,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: top.map((e) {
                final pct = totalSpending > 0 ? (e.value / totalSpending * 100).round() : 0;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: e.key.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${e.key.label} $pct%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _SectionHeader({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        TextButton(
          onPressed: onTap,
          child: const Text('Ver todo', style: TextStyle(color: AppColors.primary)),
        ),
      ],
    );
  }
}

class _InsightsSummary extends StatelessWidget {
  final AsyncValue<List<InsightEntity>> insightsAsync;
  const _InsightsSummary({required this.insightsAsync});

  @override
  Widget build(BuildContext context) {
    return insightsAsync.when(
      data: (insights) {
        if (insights.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline, color: AppColors.textMuted),
                  const SizedBox(width: 12),
                  Text(
                    'Add more receipts to get insights',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          );
        }
        final first = insights.first;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(first.icon, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(first.title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(first.description, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const ShimmerCard(height: 80),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _RecentReceiptsList extends StatelessWidget {
  final AsyncValue<List<ReceiptEntity>> receiptsAsync;
  const _RecentReceiptsList({required this.receiptsAsync});

  @override
  Widget build(BuildContext context) {
    return receiptsAsync.when(
      data: (receipts) {
        if (receipts.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.receipt_outlined, color: AppColors.textMuted),
                  const SizedBox(width: 12),
                  Text('No receipts yet', style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          );
        }

        final recent = receipts.take(3).toList();
        return Column(
          children: recent
              .map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _DashboardReceiptTile(receipt: r),
                  ))
              .toList(),
        );
      },
      loading: () => const ShimmerList(count: 3, itemHeight: 72),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _DashboardReceiptTile extends StatelessWidget {
  final ReceiptEntity receipt;
  const _DashboardReceiptTile({required this.receipt});

  @override
  Widget build(BuildContext context) {
    final date = AppDate.dayMonth(receipt.receiptDate ?? receipt.createdAt);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(receipt.category.emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    receipt.storeName ?? receipt.category.label,
                    style: Theme.of(context).textTheme.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(date, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Text(
              Money.format(receipt.totalCents),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// Los grupos con el saldo propio, en el inicio.
///
/// Antes grupos solo existia en la barra de abajo. Quien entra al inicio a ver
/// como viene el mes tambien quiere saber si le deben algo, y no habia ninguna
/// señal de que la seccion existiera.
class _ResumenGrupos extends ConsumerWidget {
  const _ResumenGrupos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grupos = ref.watch(groupsProvider);

    return grupos.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: LoadingIndicator()),
        ),
      ),
      // Un error acá no puede romper el inicio entero: se calla y sigue.
      error: (_, __) => const SizedBox.shrink(),
      data: (lista) {
        if (lista.isEmpty) {
          return Card(
            child: ListTile(
              onTap: () => context.go('/groups'),
              leading: const CircleAvatar(
                backgroundColor: AppColors.cardDark,
                child: Icon(Icons.group_add, color: AppColors.primary),
              ),
              title: const Text('Dividir gastos con alguien'),
              subtitle: const Text(
                'El asado, el alquiler, un viaje',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ),
          );
        }

        return Column(
          children: [
            for (final g in lista.take(3))
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => context.go('/groups/${g.id}'),
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.cardDark,
                    child: Icon(Icons.groups, color: AppColors.primary),
                  ),
                  title: Text(g.name),
                  trailing: Consumer(
                    builder: (context, ref, _) {
                      final saldo = ref.watch(myBalanceProvider(g.id));
                      if (saldo == 0) {
                        return const Text(
                          'Al día',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 13),
                        );
                      }
                      final debo = saldo < 0;
                      return Text(
                        '${debo ? '-' : '+'}'
                        '${Money.format(saldo.abs(), code: g.currency)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: debo ? AppColors.error : AppColors.success,
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
