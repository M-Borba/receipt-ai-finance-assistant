import 'package:cross_file/cross_file.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/receipt_repository_impl.dart';
import '../../domain/entities/receipt_draft.dart';
import '../../domain/entities/receipt_entity.dart';

part 'receipt_provider.g.dart';

@riverpod
Stream<List<ReceiptEntity>> receiptsStream(Ref ref) {
  final repo = ref.watch(receiptRepositoryProvider);
  return repo.watchReceipts();
}

/// Estados del flujo de escaneo.
///
/// El flujo viejo era: elegir foto -> escribir en Firestore. Ahora hay un paso
/// de revision en el medio, asi que nada se guarda sin confirmacion.
sealed class ScanState {
  const ScanState();
}

class ScanIdle extends ScanState {
  const ScanIdle();
}

class ScanAnalyzing extends ScanState {
  const ScanAnalyzing();
}

/// El OCR termino y espera que el usuario revise y corrija.
class ScanReviewing extends ScanState {
  final ReceiptDraft draft;
  const ScanReviewing(this.draft);
}

class ScanSaving extends ScanState {
  final ReceiptDraft draft;
  const ScanSaving(this.draft);
}

class ScanSaved extends ScanState {
  final ReceiptEntity receipt;
  const ScanSaved(this.receipt);
}

class ScanFailed extends ScanState {
  final String message;
  const ScanFailed(this.message);
}

@riverpod
class ScanNotifier extends _$ScanNotifier {
  @override
  ScanState build() => const ScanIdle();

  /// Lee el ticket. No escribe nada.
  Future<void> analyze(XFile imageFile) async {
    state = const ScanAnalyzing();
    final result = await ref.read(receiptRepositoryProvider).analyzeImage(imageFile);
    if (!ref.mounted) return;
    state = result.fold(
      (failure) => ScanFailed(failure.message),
      (draft) => ScanReviewing(draft),
    );
  }

  /// Aplica una correccion del usuario sobre el borrador.
  void updateDraft(ReceiptDraft draft) {
    if (state is ScanReviewing) state = ScanReviewing(draft);
  }

  /// Confirma y guarda.
  Future<void> confirm(ReceiptDraft draft) async {
    state = ScanSaving(draft);
    final result = await ref.read(receiptRepositoryProvider).saveDraft(draft);
    if (!ref.mounted) return;
    state = result.fold(
      (failure) => ScanFailed(failure.message),
      (receipt) => ScanSaved(receipt),
    );
  }

  void reset() => state = const ScanIdle();
}

/// Borrar un recibo tambien borra su gasto asociado, en un batch.
@riverpod
class ReceiptActions extends _$ReceiptActions {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<bool> delete(String id) async {
    state = const AsyncValue.loading();
    final result = await ref.read(receiptRepositoryProvider).deleteReceipt(id);
    if (!ref.mounted) return false;
    return result.fold(
      (failure) {
        state = AsyncValue.error(failure.message, StackTrace.current);
        return false;
      },
      (_) {
        state = const AsyncValue.data(null);
        return true;
      },
    );
  }
}
