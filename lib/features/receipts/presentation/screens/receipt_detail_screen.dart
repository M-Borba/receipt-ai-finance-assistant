import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/format/money.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../services/image/thumbnail_service.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../expenses/domain/entities/expense_entity.dart';
import '../../data/repositories/receipt_repository_impl.dart';
import '../../domain/entities/receipt_entity.dart';
import '../../domain/entities/receipt_item_entity.dart';
import '../providers/receipt_provider.dart';

part 'receipt_detail_screen.g.dart';

@riverpod
Future<ReceiptEntity?> receiptDetail(Ref ref, String id) async {
  final repo = ref.watch(receiptRepositoryProvider);
  final result = await repo.getReceiptById(id);
  return result.fold((_) => null, (r) => r);
}

/// La miniatura vive en una subcoleccion: se lee solo al abrir el detalle,
/// nunca en la lista.
@riverpod
Future<String?> receiptThumbnail(Ref ref, String id) async {
  return ref.watch(receiptRepositoryProvider).getThumbnail(id);
}

class ReceiptDetailScreen extends ConsumerStatefulWidget {
  final String receiptId;
  const ReceiptDetailScreen({super.key, required this.receiptId});

  @override
  ConsumerState<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends ConsumerState<ReceiptDetailScreen> {
  bool _isSaving = false;

  void _openImageFullScreen(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenImageViewer(imageUrl: url),
      ),
    );
  }

  Future<void> _openEditSheet(BuildContext context, ReceiptEntity receipt) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EditReceiptSheet(
        receipt: receipt,
        onSave: (storeName, total, category, date) async {
          setState(() => _isSaving = true);
          final repo = ref.read(receiptRepositoryProvider);
          await repo.updateReceipt(
            id: receipt.id,
            storeName: storeName,
            totalCents: total,
            category: category,
            receiptDate: date,
          );
          ref.invalidate(receiptDetailProvider(widget.receiptId));
          if (mounted) setState(() => _isSaving = false);
        },
      ),
    );
  }

  /// Borrar un recibo tambien borra el gasto asociado (batch en el
  /// repositorio). Antes no habia forma de borrar nada desde la UI.
  Future<void> _confirmDelete(BuildContext context, String id) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar ticket'),
        content: const Text(
          'Se borra el ticket y el gasto asociado. No se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _isSaving = true);
    final ok = await ref.read(receiptActionsProvider.notifier).delete(id);
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (ok) {
      context.go('/receipts');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo borrar el ticket'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final receiptAsync = ref.watch(receiptDetailProvider(widget.receiptId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del ticket'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              ),
            )
          else
            receiptAsync.when(
              data: (receipt) => receipt == null
                  ? const SizedBox()
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Editar',
                          onPressed: () => _openEditSheet(context, receipt),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Borrar',
                          onPressed: () => _confirmDelete(context, receipt.id),
                        ),
                      ],
                    ),
              loading: () => const SizedBox(),
              error: (_, __) => const SizedBox(),
            ),
        ],
      ),
      body: receiptAsync.when(
        data: (receipt) => receipt == null
            ? const Center(child: Text('Receipt not found'))
            : _buildContent(context, receipt),
        loading: () => const LoadingIndicator(),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _sinImagen() => Container(
        height: 240,
        color: AppColors.cardDark,
        child: const Icon(Icons.image_not_supported,
            color: AppColors.textMuted, size: 48),
      );

  Widget _buildContent(BuildContext context, ReceiptEntity receipt) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: receipt.imageUrl.isEmpty
                ? null
                : () => _openImageFullScreen(context, receipt.imageUrl),
            child: Stack(
              children: [
                _buildImage(receipt.imageUrl),
                if (receipt.imageUrl.isNotEmpty) Positioned(
                  bottom: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_out_map, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text('Ver completa', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, receipt),
                const SizedBox(height: 24),
                _buildCategoryBadge(context, receipt),
                const SizedBox(height: 24),
                if (receipt.items.isNotEmpty) _buildItemsList(context, receipt.items),
                const SizedBox(height: 16),
                _buildTotalRow(context, receipt.totalCents),
                if (receipt.ocrConfidence > 0) ...[
                  const SizedBox(height: 16),
                  _buildConfidenceBar(context, receipt.ocrConfidence),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// La foto del ticket, ampliable con un toque.
  ///
  /// Se guarda a 1000px justamente para poder leer los items y los importes.
  /// Mostrarla solo en una banda de 240px recortada desperdiciaba esa
  /// resolucion: se veia el borde del papel y nada mas.
  Widget _buildImage(String url) {
    if (url.isEmpty) {
      // Sin Storage, la foto vive en Firestore.
      return Consumer(
        builder: (context, ref, _) {
          final thumb = ref.watch(receiptThumbnailProvider(widget.receiptId));
          return thumb.when(
            data: (base64) {
              final bytes = ThumbnailService.decode(base64);
              if (bytes == null) return _sinImagen();
              return _ReceiptPhoto(MemoryImage(bytes));
            },
            loading: () => const ShimmerCard(height: 240, borderRadius: 0),
            error: (_, __) => _sinImagen(),
          );
        },
      );
    }

    if (url.startsWith('http') && !url.startsWith('blob:')) {
      return _ReceiptPhoto(CachedNetworkImageProvider(url));
    }

    if (url.startsWith('blob:') || url.startsWith('data:')) {
      return _ReceiptPhoto(NetworkImage(url));
    }

    if (!kIsWeb) {
      return _ReceiptPhoto(FileImage(File(url)));
    }

    return _sinImagen();
  }

  Widget _buildHeader(BuildContext context, ReceiptEntity receipt) {
    final dateStr = AppDate.longDate(
      receipt.receiptDate ?? receipt.createdAt,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          receipt.storeName ?? 'Unknown Store',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        Text(dateStr, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }

  Widget _buildCategoryBadge(BuildContext context, ReceiptEntity receipt) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: receipt.category.color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: receipt.category.color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(receipt.category.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text(
            receipt.category.label,
            style: TextStyle(
              color: receipt.category.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList(BuildContext context, List<ReceiptItemEntity> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Items', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        const Divider(color: AppColors.borderDark),
        ...items.map((item) => _ItemRow(item: item)),
        const Divider(color: AppColors.borderDark),
      ],
    );
  }

  Widget _buildTotalRow(BuildContext context, int total) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Total', style: Theme.of(context).textTheme.titleLarge),
        Text(
          Money.format(total),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }

  Widget _buildConfidenceBar(BuildContext context, double confidence) {
    final pct = (confidence * 100).round();
    final color = pct >= 80
        ? AppColors.success
        : pct >= 60
            ? AppColors.warning
            : AppColors.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('OCR Confidence', style: Theme.of(context).textTheme.bodySmall),
            Text('$pct%', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: confidence,
            backgroundColor: AppColors.borderDark,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 4,
          ),
        ),
      ],
    );
  }
}

// ─── Full-screen image viewer ─────────────────────────────────────────────────

class _FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  const _FullScreenImageViewer({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Receipt Image', style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: _buildImageWidget(),
        ),
      ),
    );
  }

  Widget _buildImageWidget() {
    if (imageUrl.startsWith('http') && !imageUrl.startsWith('blob:')) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.contain,
        errorWidget: (_, __, ___) =>
            const Icon(Icons.image_not_supported, color: Colors.white54, size: 64),
      );
    }
    if (imageUrl.startsWith('blob:') || imageUrl.startsWith('data:')) {
      return Image.network(imageUrl, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.image_not_supported, color: Colors.white54, size: 64));
    }
    if (!kIsWeb) {
      return Image.file(File(imageUrl), fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.image_not_supported, color: Colors.white54, size: 64));
    }
    return const Icon(Icons.image_not_supported, color: Colors.white54, size: 64);
  }
}

// ─── Edit receipt bottom sheet ────────────────────────────────────────────────

class _EditReceiptSheet extends StatefulWidget {
  final ReceiptEntity receipt;
  final Future<void> Function(String storeName, int totalCents, ExpenseCategory category, DateTime date) onSave;

  const _EditReceiptSheet({required this.receipt, required this.onSave});

  @override
  State<_EditReceiptSheet> createState() => _EditReceiptSheetState();
}

class _EditReceiptSheetState extends State<_EditReceiptSheet> {
  late final TextEditingController _storeCtrl;
  late final TextEditingController _totalCtrl;
  late ExpenseCategory _selectedCategory;
  late DateTime _selectedDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _storeCtrl = TextEditingController(text: widget.receipt.storeName ?? '');
    _totalCtrl = TextEditingController(text: Money.formatPlain(widget.receipt.totalCents));
    _selectedCategory = widget.receipt.category;
    _selectedDate = widget.receipt.receiptDate ?? widget.receipt.createdAt;
  }

  @override
  void dispose() {
    _storeCtrl.dispose();
    _totalCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _save() async {
    // `replaceAll(',', '.')` convertia "1.234,56" en "1.234.56" => null.
    final total = Money.parse(_totalCtrl.text);
    if (total == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid total amount')),
      );
      return;
    }
    setState(() => _saving = true);
    await widget.onSave(_storeCtrl.text.trim(), total, _selectedCategory, _selectedDate);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = AppDate.shortDate(_selectedDate);

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Edit Receipt', style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Store name
            Text('Store name', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              controller: _storeCtrl,
              decoration: const InputDecoration(
                hintText: 'e.g. Walmart',
                prefixIcon: Icon(Icons.store_outlined),
              ),
            ),
            const SizedBox(height: 20),

            // Total amount
            Text('Total amount', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              controller: _totalCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: '0.00',
                prefixIcon: Icon(Icons.attach_money),
              ),
            ),
            const SizedBox(height: 20),

            // Date
            Text('Receipt date', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(dateStr, style: Theme.of(context).textTheme.bodyLarge),
              ),
            ),
            const SizedBox(height: 20),

            // Category
            Text('Category', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ExpenseCategory.values.map((cat) {
                final selected = cat == _selectedCategory;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = cat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? cat.color.withOpacity(0.2) : AppColors.surfaceDark,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? cat.color : AppColors.borderDark,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(cat.emoji),
                        const SizedBox(width: 6),
                        Text(
                          cat.label,
                          style: TextStyle(
                            color: selected ? cat.color : AppColors.textSecondary,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 28),

            // Save button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save changes', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Item row ─────────────────────────────────────────────────────────────────

class _ItemRow extends StatelessWidget {
  final ReceiptItemEntity item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: Theme.of(context).textTheme.bodyLarge),
                if (item.quantity > 1)
                  Text(
                    '${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 1)} x ${Money.format(item.unitPriceCents)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          Text(
            Money.format(item.totalPriceCents),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Vista previa de la foto del ticket. Un toque la abre a pantalla completa.
class _ReceiptPhoto extends StatelessWidget {
  const _ReceiptPhoto(this.image);

  final ImageProvider image;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Ampliar la foto del ticket',
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => _FotoAmpliada(image),
          ),
        ),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            Image(
              image: image,
              height: 240,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 240,
                color: AppColors.cardDark,
                child: const Icon(Icons.image_not_supported,
                    color: AppColors.textMuted, size: 48),
              ),
            ),
            // Sin esta pista no hay forma de saber que la foto se puede
            // ampliar: el recorte no da ninguna señal.
            Padding(
              padding: const EdgeInsets.all(12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.zoom_in, size: 18, color: Colors.white),
                      SizedBox(width: 6),
                      Text('Ver ticket',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La foto a pantalla completa, con zoom.
class _FotoAmpliada extends StatelessWidget {
  const _FotoAmpliada(this.image);

  final ImageProvider image;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Ticket'),
      ),
      body: Center(
        // minScale 1 y no menos: achicar por debajo del encuadre solo deja
        // la foto flotando en el medio de una pantalla negra.
        child: InteractiveViewer(
          maxScale: 6,
          child: Image(image: image, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
