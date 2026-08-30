import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/format/money.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../domain/entities/receipt_entity.dart';
import '../providers/receipt_provider.dart';

class ReceiptListScreen extends ConsumerWidget {
  const ReceiptListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptsAsync = ref.watch(receiptsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tickets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            onPressed: () => context.go('/scan'),
          ),
        ],
      ),
      body: receiptsAsync.when(
        data: (receipts) => receipts.isEmpty
            ? _buildEmptyState(context)
            : _buildList(context, receipts),
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: ShimmerList(count: 6),
        ),
        error: (e, _) => ErrorDisplay(message: e.toString()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/scan'),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Agregar ticket', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<ReceiptEntity> receipts) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: receipts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => ReceiptCard(
        receipt: receipts[index],
        onTap: () => context.go('/receipts/${receipts[index].id}'),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.receipt_long_outlined, size: 64, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text('No receipts yet', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Scan your first receipt to get started',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class ReceiptCard extends StatelessWidget {
  final ReceiptEntity receipt;
  final VoidCallback onTap;

  const ReceiptCard({super.key, required this.receipt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dateStr = AppDate.shortDate(
      receipt.receiptDate ?? receipt.createdAt,
    );

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: receipt.category.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(receipt.category.emoji, style: const TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      receipt.storeName ?? receipt.category.label,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(dateStr, style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(width: 8),
                        _StatusBadge(status: receipt.status),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                Money.format(receipt.totalCents),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final ReceiptStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      ReceiptStatus.completed => (AppColors.success, 'Done'),
      ReceiptStatus.processing => (AppColors.warning, 'Processing'),
      ReceiptStatus.failed => (AppColors.error, 'Failed'),
      ReceiptStatus.pending => (AppColors.textMuted, 'Pending'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
