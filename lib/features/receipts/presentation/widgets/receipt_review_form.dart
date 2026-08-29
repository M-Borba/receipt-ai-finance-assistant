import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/config/environment.dart';
import '../../../../core/format/money.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../expenses/domain/entities/expense_entity.dart';
import '../../domain/entities/receipt_draft.dart';

/// Revision editable de lo que leyo el OCR, antes de escribir nada.
///
/// Es la pieza que faltaba: el OCR se equivoca, sobre todo en web donde corre
/// Tesseract, y antes el dato malo se guardaba igual y recien despues se podia
/// corregir. Ahora la persona confirma o arregla.
class ReceiptReviewForm extends StatefulWidget {
  final ReceiptDraft draft;
  final Uint8List? imageBytes;
  final bool isSaving;
  final VoidCallback onCancel;
  final ValueChanged<ReceiptDraft> onConfirm;

  const ReceiptReviewForm({
    super.key,
    required this.draft,
    required this.imageBytes,
    required this.isSaving,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  State<ReceiptReviewForm> createState() => _ReceiptReviewFormState();
}

class _ReceiptReviewFormState extends State<ReceiptReviewForm> {
  late final TextEditingController _storeCtrl;
  late final TextEditingController _totalCtrl;
  late ExpenseCategory _category;
  late DateTime _date;
  String? _totalError;

  @override
  void initState() {
    super.initState();
    _storeCtrl = TextEditingController(text: widget.draft.storeName ?? '');
    _totalCtrl = TextEditingController(
      text: widget.draft.resolvedTotalCents > 0
          ? Money.formatPlain(widget.draft.resolvedTotalCents)
          : '',
    );
    _category = widget.draft.category;
    _date = widget.draft.receiptDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _storeCtrl.dispose();
    _totalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needsAttention = widget.draft.needsAttention(
      threshold: Environment.ocrConfidenceThreshold,
    );

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (needsAttention) const _AttentionBanner(),
              if (widget.imageBytes != null) _Thumbnail(bytes: widget.imageBytes!),
              const SizedBox(height: 20),

              _Label('Comercio'),
              TextField(
                controller: _storeCtrl,
                enabled: !widget.isSaving,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Nombre del comercio',
                  prefixIcon: Icon(Icons.storefront_outlined),
                ),
              ),
              const SizedBox(height: 20),

              _Label('Total'),
              TextField(
                controller: _totalCtrl,
                enabled: !widget.isSaving,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: '0,00',
                  errorText: _totalError,
                  prefixText: '${Money.symbolFor(Money.currencyCode)} ',
                ),
                onChanged: (_) {
                  if (_totalError != null) setState(() => _totalError = null);
                },
              ),
              const SizedBox(height: 20),

              _Label('Fecha'),
              InkWell(
                onTap: widget.isSaving ? null : _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(AppDate.shortDate(_date)),
                ),
              ),
              const SizedBox(height: 20),

              _Label('Categoría'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ExpenseCategory.values.map((c) {
                  final selected = c == _category;
                  return ChoiceChip(
                    label: Text('${c.emoji} ${c.label}'),
                    selected: selected,
                    onSelected: widget.isSaving
                        ? null
                        : (_) => setState(() => _category = c),
                  );
                }).toList(),
              ),

              if (widget.draft.items.isNotEmpty) ...[
                const SizedBox(height: 24),
                _Label('${widget.draft.items.length} ítems detectados'),
                const SizedBox(height: 4),
                ...widget.draft.items.take(20).map(
                      (i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(i.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium),
                            ),
                            Text(Money.format(i.totalPriceCents),
                                style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Descartar',
                  outlined: true,
                  onPressed: widget.isSaving ? null : widget.onCancel,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: AppButton(
                  label: 'Guardar',
                  icon: Icons.check,
                  isLoading: widget.isSaving,
                  onPressed: widget.isSaving ? null : _confirm,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(DateTime.now()) ? DateTime.now() : _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _confirm() {
    final total = Money.parse(_totalCtrl.text);
    if (total == null || total <= 0) {
      setState(() => _totalError = 'Poné un monto válido');
      return;
    }

    final store = _storeCtrl.text.trim();
    widget.onConfirm(widget.draft.copyWith(
      storeName: store.isEmpty ? null : store,
      totalCents: total,
      category: _category,
      receiptDate: _date,
    ));
  }
}

class _AttentionBanner extends StatelessWidget {
  const _AttentionBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.warning, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'El ticket se leyó con baja confianza. Revisá el total antes de guardar.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final Uint8List bytes;
  const _Thumbnail({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        bytes,
        height: 160,
        width: double.infinity,
        fit: BoxFit.cover,
        cacheWidth: 1080,
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}
