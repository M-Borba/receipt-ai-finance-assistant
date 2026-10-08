import 'package:cross_file/cross_file.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/constants/app_constants.dart';

import '../../data/repositories/receipt_repository_impl.dart';
import '../../domain/entities/receipt_draft.dart';
import '../../domain/entities/receipt_entity.dart';

part 'receipt_provider.g.dart';

/// Cuantos tickets trae la lista. Arranca en una pagina y crece con "Ver mas".
///
/// Antes estaba clavado en 20 y no habia paginacion: al ticket 21, el mas
/// viejo (y su foto) quedaba sin ningun camino en la app, porque el detalle
/// solo se alcanza desde esta lista.
@riverpod
class ReceiptsLimit extends _$ReceiptsLimit {
  @override
  int build() => AppConstants.receiptsPageSize;

  void verMas() => state += AppConstants.receiptsPageSize;
}

@riverpod
Stream<List<ReceiptEntity>> receiptsStream(Ref ref) {
  final repo = ref.watch(receiptRepositoryProvider);
  return repo.watchReceipts(limit: ref.watch(receiptsLimitProvider));
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
///
/// [saveError] viene cargado cuando se intento guardar y fallo: la persona
/// vuelve a la revision con todo lo que habia corregido, en vez de perderlo.
class ScanReviewing extends ScanState {
  final ReceiptDraft draft;
  final String? saveError;
  const ScanReviewing(this.draft, {this.saveError});
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

/// keepAlive: el borrador sobrevive a salir de la pantalla. Antes era
/// autoDispose y su unico oyente era la pantalla de escaneo, asi que tocar otra
/// pestana de la barra de navegacion en plena revision tiraba el OCR y todas
/// las correcciones.
@Riverpod(keepAlive: true)
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
    // Un guardado fallido vuelve a la revision con el borrador. Antes iba a
    // ScanFailed, que no lo lleva: habia que escanear y corregir todo de nuevo.
    state = result.fold(
      (failure) => ScanReviewing(draft, saveError: failure.message),
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

    // El valor que se devuelve sale SIEMPRE del resultado. Antes habia un
    // `if (!ref.mounted) return false` antes del fold, y este notifier es
    // autoDispose al que solo se accede con `read`: quedaba descartado durante
    // los tres viajes a Firestore de deleteReceipt, asi que TODOS los borrados
    // devolvian false y la pantalla mostraba "No se pudo borrar" aunque el
    // ticket se hubiera borrado bien.
    //
    // Lo unico que depende de `mounted` es tocar `state`, que revienta si el
    // provider ya murio. Es la misma trampa que ExpenseActions.
    final ok = result.isRight();
    if (ref.mounted) {
      state = result.fold(
        (f) => AsyncValue.error(f.message, StackTrace.current),
        (_) => const AsyncValue.data(null),
      );
    }
    return ok;
  }
}
