import 'package:cross_file/cross_file.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/core/constants/app_constants.dart';
import 'package:receipt_ai_finance_assistant/core/errors/failures.dart';
import 'package:receipt_ai_finance_assistant/features/expenses/domain/entities/expense_entity.dart';
import 'package:receipt_ai_finance_assistant/features/receipts/data/repositories/receipt_repository_impl.dart';
import 'package:receipt_ai_finance_assistant/features/receipts/domain/entities/receipt_draft.dart';
import 'package:receipt_ai_finance_assistant/features/receipts/domain/entities/receipt_entity.dart';
import 'package:receipt_ai_finance_assistant/features/receipts/domain/repositories/receipt_repository.dart';
import 'package:receipt_ai_finance_assistant/features/receipts/presentation/providers/receipt_provider.dart';

/// Repositorio cuyo guardado siempre falla.
class _RepoQueFalla implements ReceiptRepository {
  static const mensaje = 'Sin conexion';
  int? ultimoLimite;

  @override
  Future<Either<Failure, ReceiptEntity>> saveDraft(ReceiptDraft draft) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return const Left(NetworkFailure(mensaje));
  }

  @override
  Stream<List<ReceiptEntity>> watchReceipts({int limit = 0}) {
    ultimoLimite = limit;
    return Stream.value(const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

ReceiptDraft _draftCorregido() => ReceiptDraft(
      imageFile: XFile('/tmp/ticket.jpg'),
      ocrPath: '/tmp/ticket.jpg',
      rawOcrText: 'texto',
      items: const [],
      storeName: 'Carnicería Pujadas',
      totalCents: 105600,
      category: ExpenseCategory.groceries,
    );

void main() {
  late _RepoQueFalla repo;
  late ProviderContainer c;

  setUp(() {
    repo = _RepoQueFalla();
    c = ProviderContainer(
      overrides: [receiptRepositoryProvider.overrideWithValue(repo)],
    );
  });
  tearDown(() => c.dispose());

  group('un guardado fallido no tira el borrador', () {
    test('vuelve a la revision con lo corregido y el error', () async {
      final draft = _draftCorregido();
      await c.read(scanProvider.notifier).confirm(draft);

      final estado = c.read(scanProvider);
      // Antes quedaba en ScanFailed, que no lleva el borrador: habia que
      // escanear y corregir todo de nuevo.
      expect(estado, isA<ScanReviewing>());
      estado as ScanReviewing;
      expect(estado.draft, draft);
      expect(estado.saveError, _RepoQueFalla.mensaje);
    });

    test('el borrador sobrevive aunque nadie este mirando la pantalla',
        () async {
      // keepAlive: salir de /scan en plena revision ya no lo descarta.
      final draft = _draftCorregido();
      final futuro = c.read(scanProvider.notifier).confirm(draft);
      await futuro;
      await Future<void>.delayed(Duration.zero);
      expect(c.read(scanProvider), isA<ScanReviewing>());
    });
  });

  group('la lista de tickets crece de a una pagina', () {
    test('arranca en una pagina y "ver mas" suma otra', () async {
      final sub = c.listen(receiptsStreamProvider, (_, __) {});
      addTearDown(sub.close);
      await c.read(receiptsStreamProvider.future);
      expect(repo.ultimoLimite, AppConstants.receiptsPageSize);

      c.read(receiptsLimitProvider.notifier).verMas();
      await c.read(receiptsStreamProvider.future);
      expect(repo.ultimoLimite, AppConstants.receiptsPageSize * 2);
    });
  });
}
