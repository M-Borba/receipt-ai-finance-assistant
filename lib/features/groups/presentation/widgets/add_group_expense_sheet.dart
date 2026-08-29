import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/money.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/repositories/group_repository.dart';
import '../../domain/entities/group_entity.dart';
import '../../domain/split.dart';

/// Alta de un gasto compartido.
///
/// El reparto se previsualiza en vivo: la gente tiene que ver cuanto le queda
/// a cada uno ANTES de guardar, porque despues discutir un numero es peor que
/// corregirlo.
class AddGroupExpenseSheet extends ConsumerStatefulWidget {
  const AddGroupExpenseSheet({super.key, required this.grupo});

  final GroupEntity grupo;

  @override
  ConsumerState<AddGroupExpenseSheet> createState() =>
      _AddGroupExpenseSheetState();
}

class _AddGroupExpenseSheetState extends ConsumerState<AddGroupExpenseSheet> {
  final _descripcion = TextEditingController();
  final _monto = TextEditingController();

  late String _pagador;
  late Set<String> _participan;
  final _partes = <String, int>{};
  SplitMode _modo = SplitMode.equal;
  DateTime _fecha = DateTime.now();
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final uid = ref.read(authStateProvider).value?.uid;
    _pagador = uid ?? widget.grupo.memberIds.first;
    _participan = widget.grupo.memberIds.toSet();
    for (final m in widget.grupo.memberIds) {
      _partes[m] = 1;
    }
  }

  @override
  void dispose() {
    _descripcion.dispose();
    _monto.dispose();
    super.dispose();
  }

  int get _montoCents => Money.parse(_monto.text) ?? 0;

  List<String> get _participantes =>
      widget.grupo.memberIds.where(_participan.contains).toList();

  /// El reparto tal como quedaria. Null si todavia no se puede calcular.
  Map<String, int>? get _preview {
    if (_montoCents <= 0 || _participantes.isEmpty) return null;
    try {
      return computeShares(
        totalCents: _montoCents,
        participants: _participantes,
        mode: _modo,
        inputs: _partes,
      );
    } on ArgumentError {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final grupo = widget.grupo;
    final preview = _preview;

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
            Text('Nuevo gasto en ${grupo.name}',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),

            TextField(
              controller: _descripcion,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                hintText: 'Asado, nafta, entradas',
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _monto,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Monto',
                prefixText: '${Money.symbolFor(grupo.currency)} ',
              ),
            ),
            const SizedBox(height: 16),

            _Etiqueta('¿Quién pagó?'),
            Wrap(
              spacing: 8,
              children: [
                for (final uid in grupo.memberIds)
                  ChoiceChip(
                    label: Text(grupo.nameOf(uid)),
                    selected: _pagador == uid,
                    onSelected: (_) => setState(() => _pagador = uid),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            _Etiqueta('¿Entre quiénes se divide?'),
            Wrap(
              spacing: 8,
              children: [
                for (final uid in grupo.memberIds)
                  FilterChip(
                    label: Text(grupo.nameOf(uid)),
                    selected: _participan.contains(uid),
                    onSelected: (v) => setState(() {
                      v ? _participan.add(uid) : _participan.remove(uid);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            _Etiqueta('¿Cómo se divide?'),
            SegmentedButton<SplitMode>(
              segments: const [
                ButtonSegment(
                    value: SplitMode.equal, label: Text('Iguales')),
                ButtonSegment(
                    value: SplitMode.shares, label: Text('Por partes')),
              ],
              selected: {_modo},
              onSelectionChanged: (s) => setState(() => _modo = s.first),
            ),

            if (_modo == SplitMode.shares) ...[
              const SizedBox(height: 8),
              const Text(
                'Poné cuántas partes le tocan a cada uno. Con 4, 1 y 1, el '
                'primero paga dos tercios y los otros un sexto cada uno. No '
                'tiene que sumar nada en particular.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              for (final uid in _participantes)
                _FilaPartes(
                  nombre: grupo.nameOf(uid),
                  partes: _partes[uid] ?? 0,
                  onCambio: (v) => setState(() => _partes[uid] = v),
                ),
            ],

            const SizedBox(height: 16),
            if (preview != null) _Preview(preview, grupo),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13)),
            ],

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    _guardando || preview == null ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Guardar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });

    final res = await ref.read(groupRepositoryProvider).addExpense(
          group: widget.grupo,
          description: _descripcion.text,
          amountCents: _montoCents,
          date: _fecha,
          mode: _modo,
          participants: _participantes,
          // Un solo pagador desde la UI. El modelo soporta varios: la pantalla
          // para cargarlos llega cuando haga falta.
          paidBy: {_pagador: _montoCents},
          splitInputs: _partes,
        );

    if (!mounted) return;
    res.fold(
      (f) => setState(() {
        _guardando = false;
        _error = f.message;
      }),
      (_) => Navigator.pop(context),
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
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      );
}

class _FilaPartes extends StatelessWidget {
  const _FilaPartes({
    required this.nombre,
    required this.partes,
    required this.onCambio,
  });

  final String nombre;
  final int partes;
  final ValueChanged<int> onCambio;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(nombre)),
        IconButton(
          onPressed: partes > 0 ? () => onCambio(partes - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 28,
          child: Text('$partes',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        IconButton(
          onPressed: () => onCambio(partes + 1),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

/// Cuanto le queda a cada uno, en vivo. Los centavos sobrantes ya estan
/// repartidos: la suma de esta lista es exactamente el monto del gasto.
class _Preview extends StatelessWidget {
  const _Preview(this.shares, this.grupo);

  final Map<String, int> shares;
  final GroupEntity grupo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Le toca a cada uno',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          for (final e in shares.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(child: Text(grupo.nameOf(e.key))),
                  Text(Money.format(e.value, code: grupo.currency),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
