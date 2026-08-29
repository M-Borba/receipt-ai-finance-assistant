import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/config/environment.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/exceptions.dart';
import '../../features/expenses/domain/entities/expense_entity.dart';
import '../../features/insights/domain/entities/insight_entity.dart';
import '../../features/receipts/domain/entities/receipt_item_entity.dart';
import '../../core/format/money.dart';
import '../classification/merchant_classifier.dart';
import 'ai_provider.dart';
import 'ollama_provider.dart';

part 'ai_service.g.dart';

@riverpod
AIProvider aiProvider(Ref ref) {
  return OllamaProvider(
    baseUrl: Environment.ollamaBaseUrl,
    model: Environment.ollamaModel,
  );
}

@riverpod
AIService aiService(Ref ref) {
  return AIService(provider: ref.watch(aiProviderProvider));
}

class AIService {
  final AIProvider _provider;
  final MerchantClassifier _classifier;
  final _log = Logger();

  AIService({
    required AIProvider provider,
    MerchantClassifier classifier = const MerchantClassifier(),
  })  : _provider = provider,
        _classifier = classifier;

  /// El prompt se arma con las categorias reales del enum. Antes estaba escrito
  /// a mano en app_constants, asi que agregar una categoria la dejaba invisible
  /// para el modelo sin que nada avisara.
  String get _classifyPrompt {
    final lista =
        ExpenseCategory.values.map((c) => '- ${c.name} (${c.label})').join('\n');
    return '''
Sos un clasificador de gastos. Dada la lista de items de un ticket de compra,
clasificalo en UNA de estas categorias:
$lista

Responde SOLO con un objeto JSON: {"category": "<category>", "confidence": <0.0-1.0>}
Usa exactamente el identificador en ingles de la categoria, no la traduccion.
''';
  }

  Future<ExpenseCategory> classifyExpense({
    required List<ReceiptItemEntity> items,
    String? storeName,
  }) async {
    // 1. Reglas locales primero: gratis, instantaneas y funcionan offline.
    //    Cubren la mayoria de los tickets reales, asi que la IA queda para los
    //    casos raros en vez de ser el camino principal.
    final local = _classifier.classify(
      storeName: storeName,
      itemNames: items.map((i) => i.name).toList(),
    );
    if (local != null) return local;

    if (!Environment.enableAiClassification) {
      return ExpenseCategory.other;
    }

    final itemsList = items.map((i) => '- ${i.name}: \$${i.totalPriceCents}').join('\n');
    final prompt = '''
Receipt items from "${storeName ?? 'unknown store'}":
$itemsList

Classify this receipt.
''';

    try {
      final response = await _provider.complete(
        prompt: prompt,
        systemPrompt: _classifyPrompt,
        temperature: 0.1,
      );

      final json = _extractJson(response);
      final categoryStr = (json['category'] as String? ?? 'other').toLowerCase();
      return ExpenseCategory.fromString(categoryStr);
    } catch (e) {
      _log.w('AI classification failed', error: e);
      return ExpenseCategory.other;
    }
  }

  Future<List<InsightEntity>> generateMonthlyInsights({
    required String userId,
    required Map<ExpenseCategory, int> categoryTotals,
    required int totalCents,
    required List<Map<String, dynamic>> topMerchants,
    required DateTime month,
  }) async {
    if (!Environment.enableAiInsights) return [];

    final categoryBreakdown = categoryTotals.entries
        .map((e) => '${e.key.label}: ${Money.format(e.value)}')
        .join('\n');

    final merchantsList = topMerchants
        .take(5)
        .map((m) =>
            '${m['name']}: ${Money.format((m['totalCents'] as num?)?.toInt() ?? 0)} '
            '(${m['count']} visitas)')
        .join('\n');

    final prompt = '''
Resumen de gastos de ${month.month}/${month.year}:
Total: ${Money.format(totalCents)}

Por categoria:
$categoryBreakdown

Comercios con mas gasto:
$merchantsList

Genera 3 a 5 observaciones. Devuelve SOLO un array JSON:
[{"title": "...", "description": "...", "type": "pattern|saving|behavior|warning", "icon": "emoji"}]
''';

    try {
      final response = await _provider.complete(
        prompt: prompt,
        systemPrompt: AppConstants.generateInsightsSystemPrompt,
        temperature: 0.4,
        maxTokens: 1500,
      );

      final json = _extractJsonArray(response);
      return json.map((item) => InsightEntity.fromAiResponse(item, userId, month)).toList();
    } catch (e) {
      _log.e('Failed to generate AI insights', error: e);
      return _fallbackInsights(categoryTotals, totalCents, userId, month);
    }
  }

  Map<String, dynamic> _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1) throw AiException('No JSON found in response');
    return jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> _extractJsonArray(String text) {
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start == -1 || end == -1) throw AiException('No JSON array found');
    final list = jsonDecode(text.substring(start, end + 1)) as List;
    return list.cast<Map<String, dynamic>>();
  }

  List<InsightEntity> _fallbackInsights(
    Map<ExpenseCategory, int> totals,
    int totalCents,
    String userId,
    DateTime month,
  ) {
    final insights = <InsightEntity>[];
    if (totals.containsKey(ExpenseCategory.delivery)) {
      final pct = ((totals[ExpenseCategory.delivery]! / totalCents) * 100).round();
      insights.add(InsightEntity(
        id: 'fallback_delivery',
        userId: userId,
        month: month,
        title: 'Gasto en delivery',
        description: 'El delivery fue el $pct% de tus gastos del mes.',
        type: InsightType.pattern,
        icon: '🚚',
        createdAt: DateTime.now(),
      ));
    }
    return insights;
  }
}
