import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/money.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/repositories/group_repository.dart';
import '../../domain/balance.dart';
import '../../domain/entities/group_entity.dart';
import '../../domain/entities/group_expense_entity.dart';
import '../providers/group_provider.dart';
import '../widgets/add_group_expense_sheet.dart';

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grupo = ref.watch(groupProvider(groupId));

    return grupo.when(
      loading: () => const Scaffold(body: Center(child: LoadingIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('No se pudo abrir el grupo.\n$e')),
      ),
      data: (g) {
        if (g == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Este grupo ya no existe.')),
          );
        }
        return _Contenido(grupo: g);
      },
    );
  }
}

class _Contenido extends ConsumerWidget {
  const _Contenido({required this.grupo});

  final GroupEntity grupo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gastos = ref.watch(groupExpensesProvider(grupo.id));
    final uid = ref.watch(authStateProvider).value?.uid ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(grupo.name)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => AddGroupExpenseSheet(grupo: grupo),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Agregar gasto'),
      ),
      body: gastos.when(
        loading: () => const Center(child: LoadingIndicator()),
        error: (e, _) => Center(child: Text('No se pudieron cargar los gastos.\n$e')),
        data: (lista) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            _Resumen(grupo: grupo, gastos: lista, uid: uid),
            const SizedBox(height: 24),
            if (grupo.memberIds.length == 1) const _AvisoSolo(),
            if (lista.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text('Todavía no hay gastos en este grupo.',
                      style: TextStyle(color: AppColors.textMuted)),
                ),
              )
            else ...[
              const Text('Gastos',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final g in lista)
                _FilaGasto(grupo: grupo, gasto: g, uid: uid),
            ],
          ],
        ),
      ),
    );
  }
}

/// Saldo propio arriba de todo y las deudas de a pares debajo.
///
/// La vista de a pares es la de por defecto a proposito: decirle a alguien
/// "pagale a Ana" cuando nunca gasto nada con Ana resulta rarisimo. La vista
/// simplificada llega en la fase 2, con un switch.
class _Resumen extends StatelessWidget {
  const _Resumen({required this.grupo, required this.gastos, required this.uid});

  final GroupEntity grupo;
  final List<GroupExpenseEntity> gastos;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final saldo = balanceOf(gastos, uid);
    final mias = debtsInvolving(gastos, uid);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              saldo == 0
                  ? 'Estás al día'
                  : saldo > 0
                      ? 'Te deben ${Money.format(saldo, code: grupo.currency)}'
                      : 'Debés ${Money.format(-saldo, code: grupo.currency)}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: saldo == 0
                    ? AppColors.textMuted
                    : saldo > 0
                        ? AppColors.success
                        : AppColors.error,
              ),
            ),
            if (mias.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              for (final d in mias)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          d.from == uid
                              ? 'Le debés a ${grupo.nameOf(d.to)}'
                              : '${grupo.nameOf(d.from)} te debe',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      Text(
                        Money.format(d.cents, code: grupo.currency),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: d.from == uid
                              ? AppColors.error
                              : AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilaGasto extends ConsumerWidget {
  const _FilaGasto(
      {required this.grupo, required this.gasto, required this.uid});

  final GroupEntity grupo;
  final GroupExpenseEntity gasto;
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final neto = gasto.netFor(uid);
    final pagadores = gasto.paidBy.keys.map(grupo.nameOf).join(' y ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(gasto.description.isEmpty ? 'Gasto' : gasto.description),
        subtitle: Text(
          '$pagadores pagó ${Money.format(gasto.amountCents, code: grupo.currency)}'
          ' · ${AppDate.shortDate(gasto.date)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              neto == 0
                  ? '—'
                  : neto > 0
                      ? '+${Money.format(neto, code: grupo.currency)}'
                      : '-${Money.format(-neto, code: grupo.currency)}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: neto == 0
                    ? AppColors.textMuted
                    : neto > 0
                        ? AppColors.success
                        : AppColors.error,
              ),
            ),
          ],
        ),
        onLongPress: () => _borrar(context, ref),
      ),
    );
  }

  Future<void> _borrar(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Borrar el gasto?'),
        content: Text('Se recalculan los saldos de todo el grupo. '
            '"${gasto.description}" se borra para todos.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref
        .read(groupRepositoryProvider)
        .deleteExpense(gasto.groupId, gasto.id);
  }
}

/// Un grupo de una sola persona no divide nada. Decirlo evita que alguien
/// cargue gastos esperando que aparezca un saldo que nunca va a aparecer.
class _AvisoSolo extends StatelessWidget {
  const _AvisoSolo();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.warning, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sos la única persona del grupo. Invitar gente con un link '
              'llega en la próxima versión.',
              style: TextStyle(fontSize: 13, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
