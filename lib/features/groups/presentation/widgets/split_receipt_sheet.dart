import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/money.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../receipts/domain/entities/receipt_entity.dart';
import '../../data/repositories/group_repository.dart';
import '../../domain/entities/group_entity.dart';
import '../../domain/split.dart';
import '../providers/group_provider.dart';

/// Divide un ticket escaneado en un grupo, **por item**.
///
/// Es la fase 3 de grupos: "la cerveza la tomamos Juan y yo, la ensalada fue
/// de Ana". La cuenta esta en [splitByItems]; aca solo se elige quien consumio
/// que, y se ve el resultado en vivo antes de guardar.
class SplitReceiptSheet extends ConsumerStatefulWidget {
  const SplitReceiptSheet({super.key, required this.receipt});

  final ReceiptEntity receipt;

  static Future<void> show(BuildContext context, ReceiptEntity receipt) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => SplitReceiptSheet(receipt: receipt),
      );

  @override
  ConsumerState<SplitReceiptSheet> createState() => _SplitReceiptSheetState();
}

class _SplitReceiptSheetState extends ConsumerState<SplitReceiptSheet> {
  GroupEntity? _grupo;
  String? _pagador;

  /// Quien consumio cada item, por indice. Vacio = todos.
  final _asignado = <int, Set<String>>{};
  bool _guardando = false;
  String? _error;

  void _elegirGrupo(GroupEntity g) {
    final uid = ref.read(authStateProvider).value?.uid;
    setState(() {
      _grupo = g;
      _pagador = g.memberIds.contains(uid) ? uid : g.memberIds.first;
      _asignado.clear();
      _error = null;
    });
  }

  Map<String, int> _reparto(GroupEntity g) => splitByItems(
        totalCents: widget.receipt.totalCents,
        participants: g.memberIds,
        items: [
          for (var i = 0; i < widget.receipt.items.length; i++)
            (
              cents: widget.receipt.items[i].totalPriceCents,
              quienes: (_asignado[i] ?? const <String>{}).toList(),
            ),
        ],
      );

  Future<void> _guardar(GroupEntity g) async {
    final reparto = _reparto(g);
    setState(() {
      _guardando = true;
      _error = null;
    });
    final res = await ref.read(groupRepositoryProvider).addExpense(
          group: g,
          description: widget.receipt.storeName ?? 'Ticket',
          amountCents: widget.receipt.totalCents,
          date: widget.receipt.receiptDate ?? widget.receipt.createdAt,
          // Se guarda ya resuelto, como todo reparto: el modo exacto con los
          // montos de cada uno.
          mode: SplitMode.exact,
          participants: reparto.keys.toList(),
          paidBy: {_pagador!: widget.receipt.totalCents},
          splitInputs: reparto,
          receiptId: widget.receipt.id,
        );
    if (!mounted) return;
    res.fold(
      (f) => setState(() {
        _guardando = false;
        _error = f.message;
      }),
      (_) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gasto agregado a ${g.name}')),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final grupos = ref.watch(groupsProvider);
    final g = _grupo;
    final items = widget.receipt.items;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dividir en un grupo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              '${widget.receipt.storeName ?? 'Ticket'} · '
              '${Money.format(widget.receipt.totalCents)}',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            grupos.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('No se pudieron cargar tus grupos. $e'),
              data: (lista) => lista.isEmpty
                  ? const Text(
                      'Todavía no tenés grupos. Creá uno en la pestaña Grupos.')
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final gr in lista)
                          ChoiceChip(
                            label: Text(gr.name),
                            selected: gr.id == g?.id,
                            onSelected: _guardando ? null : (_) => _elegirGrupo(gr),
                          ),
                      ],
                    ),
            ),
            if (g != null) ...[
              const SizedBox(height: 20),
              const _Etiqueta('¿Quién pagó?'),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in g.memberIds)
                    ChoiceChip(
                      label: Text(g.nameOf(m)),
                      selected: m == _pagador,
                      onSelected: _guardando
                          ? null
                          : (_) => setState(() => _pagador = m),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const _Etiqueta('¿Quién consumió cada cosa?'),
              const Text(
                'Sin elegir a nadie, el ítem se divide entre todos.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(items[i].name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          Text(Money.format(items[i].totalPriceCents),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final m in g.memberIds)
                            FilterChip(
                              visualDensity: VisualDensity.compact,
                              label: Text(g.nameOf(m)),
                              selected: _asignado[i]?.contains(m) ?? false,
                              onSelected: _guardando
                                  ? null
                                  : (on) => setState(() {
                                        final s =
                                            _asignado.putIfAbsent(i, () => {});
                                        on ? s.add(m) : s.remove(m);
                                      }),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              const Divider(),
              const _Etiqueta('Queda así'),
              for (final e in _reparto(g).entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(g.nameOf(e.key))),
                      Text(Money.format(e.value, code: g.currency),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              const Text(
                'Lo que no está en los ítems (IVA, propina, redondeo) se '
                'reparte según lo que consumió cada uno, así la suma da el '
                'total del ticket.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _guardando || _pagador == null
                      ? null
                      : () => _guardar(g),
                  icon: _guardando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.call_split),
                  label: Text('Agregar a ${g.name}'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(texto,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
      );
}
