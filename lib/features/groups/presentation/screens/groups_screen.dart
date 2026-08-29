import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/format/money.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../data/repositories/group_repository.dart';
import '../../domain/entities/group_entity.dart';
import '../providers/group_provider.dart';

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grupos = ref.watch(groupsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Grupos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _nuevoGrupo(context, ref),
        icon: const Icon(Icons.group_add),
        label: const Text('Nuevo grupo'),
      ),
      body: grupos.when(
        loading: () => const Center(child: LoadingIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('No se pudieron cargar los grupos.\n$e',
                textAlign: TextAlign.center),
          ),
        ),
        data: (lista) {
          if (lista.isEmpty) return const _SinGrupos();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: lista.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _TarjetaGrupo(lista[i]),
          );
        },
      ),
    );
  }

  Future<void> _nuevoGrupo(BuildContext context, WidgetRef ref) async {
    final nombre = await showDialog<String>(
      context: context,
      builder: (_) => const _DialogoNuevoGrupo(),
    );
    if (nombre == null || nombre.trim().isEmpty) return;

    final res = await ref.read(groupRepositoryProvider).createGroup(
          name: nombre,
          currency: Money.currencyCode,
        );
    if (!context.mounted) return;
    res.fold(
      (f) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(f.message))),
      (g) => context.push('/groups/${g.id}'),
    );
  }
}

class _TarjetaGrupo extends ConsumerWidget {
  const _TarjetaGrupo(this.grupo);

  final GroupEntity grupo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saldo = ref.watch(myBalanceProvider(grupo.id));
    return Card(
      child: ListTile(
        onTap: () => context.push('/groups/${grupo.id}'),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
          child: const Icon(Icons.groups, color: AppColors.primary),
        ),
        title: Text(grupo.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(grupo.memberIds.length == 1
            ? 'Solo vos'
            : '${grupo.memberIds.length} personas'),
        trailing: _Saldo(saldo, grupo.currency),
      ),
    );
  }
}

/// El saldo propio. Se dice en palabras y no solo con un signo: "debés" y
/// "te deben" son lo primero que la gente busca al abrir la app.
class _Saldo extends StatelessWidget {
  const _Saldo(this.cents, this.currency);

  final int cents;
  final String currency;

  @override
  Widget build(BuildContext context) {
    if (cents == 0) {
      return const Text('Al día',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13));
    }
    final debo = cents < 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(debo ? 'Debés' : 'Te deben',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        Text(
          Money.format(cents.abs(), code: currency),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: debo ? AppColors.error : AppColors.success,
          ),
        ),
      ],
    );
  }
}

class _SinGrupos extends StatelessWidget {
  const _SinGrupos();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups_outlined,
                size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            const Text('Todavía no tenés grupos',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Un grupo sirve para dividir gastos: el asado, el alquiler, '
              'un viaje. Cada uno carga lo que pagó y la app calcula quién '
              'le debe a quién.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogoNuevoGrupo extends StatefulWidget {
  const _DialogoNuevoGrupo();

  @override
  State<_DialogoNuevoGrupo> createState() => _DialogoNuevoGrupoState();
}

class _DialogoNuevoGrupoState extends State<_DialogoNuevoGrupo> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo grupo'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Nombre',
          hintText: 'Asado del sábado',
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Crear'),
        ),
      ],
    );
  }
}
