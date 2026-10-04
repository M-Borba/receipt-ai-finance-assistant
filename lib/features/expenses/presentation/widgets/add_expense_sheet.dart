import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/money.dart';
import '../../../../services/classification/merchant_classifier.dart';
import '../../../../services/classification/merchant_memory.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../domain/entities/expense_entity.dart';
import '../providers/expense_provider.dart';

/// Carga de un gasto a mano, sin ticket.
///
/// Antes el unico camino a los datos era la camara, y sacarle una foto a cada
/// compra es demasiada friccion: sin esto la app se queda vacia y ni el
/// presupuesto ni los insights tienen de donde agarrarse.
class AddExpenseSheet extends ConsumerStatefulWidget {
  const AddExpenseSheet({super.key});

  /// Abre la hoja. Devuelve true si se guardo un gasto.
  static Future<bool> show(BuildContext context) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const AddExpenseSheet(),
    );
    return guardado ?? false;
  }

  @override
  ConsumerState<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends ConsumerState<AddExpenseSheet> {
  final _amountCtrl = TextEditingController();
  final _storeCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _amountFocus = FocusNode();

  /// `other` y no Supermercado: lo que se guarda tambien se aprende, y un
  /// valor por defecto que nadie eligio no puede quedar recordado como la
  /// categoria de un comercio. `other` es "no se" y nunca se aprende.
  static const _categoriaPorDefecto = ExpenseCategory.other;

  ExpenseCategory _category = _categoriaPorDefecto;

  /// True cuando la persona toco una categoria: desde ahi la sugerencia no la
  /// cambia mas, aunque siga escribiendo el comercio.
  bool _categoriaElegida = false;

  /// True cuando la categoria actual la puso la sugerencia, para decirlo.
  bool _sugerida = false;
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _amountError;

  @override
  void initState() {
    super.initState();
    // El monto es lo unico obligatorio: que el teclado aparezca ahi solo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _amountFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _storeCtrl.dispose();
    _noteCtrl.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Nuevo gasto',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _saving ? null : () => Navigator.pop(context, false),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _amountCtrl,
                focusNode: _amountFocus,
                enabled: !_saving,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: '0,00',
                  errorText: _amountError,
                  prefixText: '${Money.symbolFor(Money.currencyCode)} ',
                ),
                onChanged: (_) {
                  if (_amountError != null) setState(() => _amountError = null);
                },
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 20),

              // El comercio va antes que la categoria porque la categoria se
              // sugiere a partir de el.
              TextField(
                controller: _storeCtrl,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Comercio (opcional)',
                  prefixIcon: Icon(Icons.storefront_outlined),
                ),
                onChanged: _sugerirCategoria,
              ),
              const SizedBox(height: 20),

              Text('Categoría',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.textSecondary,
                      )),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ExpenseCategory.values.map((c) {
                  return ChoiceChip(
                    label: Text('${c.emoji} ${c.label}'),
                    selected: c == _category,
                    onSelected: _saving
                        ? null
                        : (_) => setState(() {
                              _category = c;
                              _categoriaElegida = true;
                              _sugerida = false;
                            }),
                  );
                }).toList(),
              ),
              if (_sugerida) ...[
                const SizedBox(height: 8),
                Text(
                  'Sugerida por el comercio. Tocá otra para cambiarla.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textMuted),
                ),
              ],
              const SizedBox(height: 20),

              InkWell(
                onTap: _saving ? null : _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Fecha',
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(_esHoy(_date) ? 'Hoy' : AppDate.shortDate(_date)),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _noteCtrl,
                enabled: !_saving,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 24),

              AppButton(
                label: 'Guardar gasto',
                icon: Icons.check,
                width: double.infinity,
                isLoading: _saving,
                onPressed: _saving ? null : _save,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Primero lo que elegiste antes para ese comercio, despues las reglas por
  /// marca. Sin IA: corre con cada tecla, y en produccion la IA no esta.
  Future<void> _sugerirCategoria(String texto) async {
    if (_categoriaElegida) return;
    final comercio = texto.trim();
    final recordada = await ref
        .read(merchantMemoryProvider)
        .categoryFor(storeName: comercio);
    final sugerida =
        recordada ?? const MerchantClassifier().classify(storeName: comercio);

    // Mientras se leia la memoria la persona pudo seguir escribiendo o tocar
    // una categoria: una respuesta vieja no puede pisar a la nueva.
    if (!mounted || _categoriaElegida || _storeCtrl.text.trim() != comercio) {
      return;
    }
    setState(() {
      _category = sugerida ?? _categoriaPorDefecto;
      _sugerida = sugerida != null;
    });
  }

  bool _esHoy(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    // Money.parse acepta coma o punto decimal, asi que "1.234,56" y "1,234.56"
    // funcionan los dos.
    final amountCents = Money.parse(_amountCtrl.text);
    if (amountCents == null || amountCents <= 0) {
      setState(() => _amountError = 'Poné un monto válido');
      return;
    }

    setState(() => _saving = true);
    final error = await ref.read(expenseActionsProvider.notifier).addManual(
          amountCents: amountCents,
          category: _category,
          date: _date,
          storeName: _storeCtrl.text,
          note: _noteCtrl.text,
        );

    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _amountError = error;
      });
      return;
    }
    Navigator.pop(context, true);
  }
}
