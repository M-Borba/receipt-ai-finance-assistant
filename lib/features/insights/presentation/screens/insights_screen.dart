import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/money.dart';
import '../../../../core/platform/file_saver.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../domain/entities/insight_entity.dart';
import '../../domain/insights_locales.dart';
import '../../domain/recordatorio_ics.dart';
import '../providers/insights_provider.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insightsAsync = ref.watch(monthlyInsightsProvider);
    final fijos = ref.watch(gastosFijosProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        actions: [
          IconButton(
            tooltip: 'Volver a generar',
            icon: const Icon(Icons.refresh_outlined),
            // Los calculados se recalculan solos; lo unico que se puede
            // regenerar a pedido es lo de la IA.
            onPressed: () => ref.invalidate(aiInsightsProvider),
          ),
        ],
      ),
      body: insightsAsync.when(
        data: (insights) => insights.isEmpty && fijos.isEmpty
            ? _buildEmptyState(context)
            : _buildInsights(context, insights, fijos),
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: ShimmerList(count: 4, itemHeight: 120),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('No se pudieron calcular los insights.\n$e',
                textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }

  Widget _buildInsights(BuildContext context, List<InsightEntity> insights,
      List<GastoFijo> fijos) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...insights.map((insight) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InsightCard(insight: insight),
            )),
        if (fijos.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Gastos fijos', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Lo que pagaste los últimos meses por un monto parecido. '
            '"Recordármelo" lo agrega a tu calendario y te avisa todos los '
            'meses, con la app cerrada.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final f in fijos) _FilaFijo(fijo: f),
        ],
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lightbulb_outline,
                size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text('Todavía no hay nada para contarte',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Con unos días de gastos cargados aparecen la proyección del mes '
              'y la comparación con el mes pasado.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaFijo extends StatelessWidget {
  const _FilaFijo({required this.fijo});

  final GastoFijo fijo;

  Future<void> _recordar(BuildContext context) async {
    final ics = icsRecordatorio(fijo, hoy: DateTime.now());
    try {
      await const FileSaver().save(
        fileName: 'recordatorio-${fijo.clave.replaceAll(' ', '-')}.ics',
        contents: ics,
        mimeType: 'text/calendar',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Abrí el archivo para agregarlo a tu calendario'),
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear el recordatorio. $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(fijo.nombre),
        subtitle: Text(
          'Unos ${Money.format(fijo.montoTipico)}, cerca del día '
          '${fijo.diaTipico}${fijo.pagadoEsteMes ? ' · ya pagado este mes' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: TextButton.icon(
          onPressed: () => _recordar(context),
          icon: const Icon(Icons.event_available_outlined, size: 18),
          label: const Text('Recordármelo'),
        ),
      ),
    );
  }
}

class InsightCard extends StatelessWidget {
  final InsightEntity insight;
  const InsightCard({super.key, required this.insight});

  @override
  Widget build(BuildContext context) {
    final (borderColor, bgColor) = switch (insight.type) {
      InsightType.warning => (AppColors.error, AppColors.error.withOpacity(0.05)),
      InsightType.saving => (AppColors.success, AppColors.success.withOpacity(0.05)),
      InsightType.behavior => (AppColors.warning, AppColors.warning.withOpacity(0.05)),
      InsightType.pattern => (AppColors.primary, AppColors.primary.withOpacity(0.05)),
    };

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(insight.icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        insight.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    _TypeChip(type: insight.type, color: borderColor),
                  ],
                ),
                const SizedBox(height: 8),
                Text(insight.description, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final InsightType type;
  final Color color;

  const _TypeChip({required this.type, required this.color});

  @override
  Widget build(BuildContext context) {
    final label = switch (type) {
      InsightType.pattern => 'Patrón',
      InsightType.saving => 'Ahorro',
      InsightType.behavior => 'Hábito',
      InsightType.warning => 'Atención',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
