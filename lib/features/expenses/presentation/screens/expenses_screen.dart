import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/money.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../shared/widgets/graphify_donut_chart.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../domain/entities/expense_entity.dart';
import '../providers/expense_provider.dart';
import '../widgets/add_expense_sheet.dart';
import '../../../budgets/domain/entities/budget_status.dart';
import '../../../budgets/presentation/providers/budget_provider.dart';
import '../../../budgets/presentation/widgets/budget_sheet.dart';

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesStreamProvider);
    final categoryTotals = ref.watch(categoryTotalsCurrentMonthProvider);
    final totalSpending = ref.watch(totalSpendingCurrentMonthProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Gastos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AddExpenseSheet.show(context),
        icon: const Icon(Icons.add),
        label: const Text('Gasto'),
      ),
      body: expensesAsync.when(
        data: (_) => _buildContent(context, categoryTotals, totalSpending),
        loading: () => const LoadingIndicator(),
        error: (e, _) => ErrorDisplay(message: e.toString()),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    Map<ExpenseCategory, int> totals,
    int total,
  ) {
    final month = AppDate.monthYear(DateTime.now());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMonthHeader(context, month, total),
          const SizedBox(height: 24),
          if (totals.isNotEmpty) ...[
            _buildPieChart(context, totals, total),
            const SizedBox(height: 24),
            _buildCategoryList(context, totals, total),
          ] else
            const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Text('Todavía no hay gastos este mes'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMonthHeader(BuildContext context, String month, int total) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(month, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              Money.format(total),
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    color: AppColors.primary,
                  ),
            ),
            Text('Total spending', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart(
    BuildContext context,
    Map<ExpenseCategory, int> totals,
    int total,
  ) {
    final slices = totals.entries
        .where((e) => e.value > 0)
        .map((e) => DonutSlice(
              label: '${e.key.emoji} ${e.key.label}',
              value: Money.toMajor(e.value),
              color: e.key.color,
            ))
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Breakdown', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  GraphifyDonutChart(slices: slices),
                  IgnorePointer(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          // `total` son CENTAVOS. Sin Money.format esto mostraba
                          // 105600 en el centro del donut, mientras el
                          // encabezado de la MISMA pantalla mostraba $ 1.056,00.
                          Money.format(total),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text('total', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryList(
    BuildContext context,
    Map<ExpenseCategory, int> totals,
    int total,
  ) {
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Por categoría', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            ...sorted.map((e) => _CategoryRow(
                  category: e.key,
                  amountCents: e.value,
                  percentage: total > 0 ? e.value / total : 0,
                )),
          ],
        ),
      ),
    );
  }
}

Color _budgetColor(BudgetState state) => switch (state) {
      BudgetState.ok => AppColors.success,
      BudgetState.warning => AppColors.warning,
      BudgetState.exceeded => AppColors.error,
    };

class _CategoryRow extends ConsumerWidget {
  final ExpenseCategory category;
  final int amountCents;
  final double percentage;

  const _CategoryRow({
    required this.category,
    required this.amountCents,
    required this.percentage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budget = ref.watch(budgetStatusForProvider(category));
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          Row(
            children: [
              Text(category.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(category.label, style: Theme.of(context).textTheme.bodyLarge),
              ),
              Text(
                Money.format(amountCents),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                child: Text(
                  '${(percentage * 100).round()}%',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              // Tocar la categoria abre su tope.
              InkWell(
                onTap: () =>
                    BudgetSheet.show(context, category, actual: budget),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    budget == null
                        ? Icons.add_circle_outline
                        : Icons.tune_outlined,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              // Con tope, la barra mide cuanto queda del presupuesto, que es
              // el dato que importa. Sin tope, la proporcion sobre el mes.
              value: budget?.clampedRatio ?? percentage,
              backgroundColor: AppColors.borderDark,
              valueColor: AlwaysStoppedAnimation(
                budget == null ? category.color : _budgetColor(budget.state),
              ),
              minHeight: budget == null ? 4 : 6,
            ),
          ),
          if (budget != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  budget.state == BudgetState.exceeded
                      ? Icons.error_outline
                      : budget.state == BudgetState.warning
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline,
                  size: 13,
                  color: _budgetColor(budget.state),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    budget.isExceeded
                        ? 'Te pasaste ${Money.format(-budget.remainingCents)} del tope de ${Money.format(budget.limitCents)}'
                        : 'Quedan ${Money.format(budget.remainingCents)} de ${Money.format(budget.limitCents)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _budgetColor(budget.state),
                        ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
