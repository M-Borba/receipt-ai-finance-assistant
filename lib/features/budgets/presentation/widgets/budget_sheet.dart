import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/money.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../expenses/domain/entities/expense_entity.dart';
import '../../domain/entities/budget_status.dart';
import '../providers/budget_provider.dart';

/// Fija o edita el tope mensual de una categoria.
class BudgetSheet extends ConsumerStatefulWidget {
  final ExpenseCategory category;
  final BudgetStatus? actual;

  const BudgetSheet({super.key, required this.category, this.actual});

  static Future<void> show(
    BuildContext context,
    ExpenseCategory category, {
    BudgetStatus? actual,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => BudgetSheet(category: category, actual: actual),
    );
  }

  @override
  ConsumerState<BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends ConsumerState<BudgetSheet> {
  late final TextEditingController _ctrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.actual != null
          ? Money.formatPlain(widget.actual!.limitCents)
          : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    final gastado = widget.actual?.spentCents ?? 0;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(c.emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Tope de ${c.label}',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _saving ? null : () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Cuánto querés gastar por mes en esta categoría. '
              'Te avisamos al llegar al 80%.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _ctrl,
              enabled: !_saving,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: '0',
                errorText: _error,
                prefixText: '${Money.symbolFor(Money.currencyCode)} ',
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _save(),
            ),

            if (gastado > 0) ...[
              const SizedBox(height: 12),
              Text(
                'Este mes ya llevás ${Money.format(gastado)} en ${c.label.toLowerCase()}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 24),

            Row(
              children: [
                if (widget.actual != null) ...[
                  Expanded(
                    child: AppButton(
                      label: 'Quitar',
                      outlined: true,
                      onPressed: _saving ? null : _remove,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: AppButton(
                    label: 'Guardar',
                    icon: Icons.check,
                    isLoading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final cents = Money.parse(_ctrl.text);
    if (cents == null || cents <= 0) {
      setState(() => _error = 'Poné un monto válido');
      return;
    }

    setState(() => _saving = true);
    final error = await ref
        .read(budgetActionsProvider.notifier)
        .setBudget(widget.category, cents);

    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _remove() async {
    setState(() => _saving = true);
    final error = await ref
        .read(budgetActionsProvider.notifier)
        .remove(widget.category);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error == null) Navigator.pop(context);
  }
}
