# Informe de la auditoría verificada

Generado el 2026-09-04. 38 hallazgos adjudicados por un escéptico que leyó cada
archivo: **26 confirmados, 11 refutados**. La síntesis reverificó las de
severidad alta abriendo los archivos y, en un caso, ejecutando el código.

**Ya arreglados de esta lista** (ver git log):

- **D1** — borrar un ticket siempre mostraba error rojo aunque funcionara. El
  notifier es autoDispose y solo se accede con `read`, así que quedaba
  descartado durante los tres viajes a Firestore: el 100% de los borrados.
- **D2** — un ticket sin miniatura no se podía borrar nunca. El batch atómico
  incluía `media/thumb` sin condición y las reglas denegaban el borrado de un
  documento inexistente, porque `owns()` evaluaba `resource.data.userId` sobre
  null. El ticket quedaba para siempre y su gasto seguía sumando.
- **D3** — el escaneo en el celular fallaba siempre: 20 segundos de timeout que
  incluían la descarga del motor wasm y de dos idiomas desde un CDN. Ahora dos
  minutos, un solo idioma, y un mensaje que se entiende.
- **D4** — el total del mes quedaba congelado al cruzar el cambio de mes. Cada
  provider y cada pantalla llamaba a `DateTime.now()` por su cuenta, y los
  providers de totales solo se recalculan cuando Firestore emite. Ahora hay una
  única fuente de verdad, `MesActual`, con timer al primer instante del mes
  siguiente y refresco al volver del segundo plano (el timer no corre con la app
  suspendida, y el navegador congela las pestañas en segundo plano).
- **D5** — el total podía salir de la línea siguiente al keyword, porque `\s*`
  incluye el salto de línea. Probado: $22,00 en un ticket de $1.056,00.
- **D6** — guardar sin conexión dejaba la pantalla colgada para siempre.
  `batch.commit()` y `add()` resuelven recién cuando el servidor confirma, así
  que sin red el Future quedaba pendiente sin éxito ni error. Ahora las diez
  escrituras tienen `.timeout(escrituraTimeout)` (20 s) y devuelven un
  `NetworkFailure` que **no dice "no se guardó"**, porque no se sabe: Firestore
  encola la escritura y la manda cuando vuelve la red. Se cubrieron también las
  seis escrituras de grupos, que no estaban en el hallazgo.

- **D21** — `pairwiseDebts` no cerraba las columnas con más de un pagador. El
  hallazgo lo daba por "no alcanzable" porque la UI manda un solo pagador, pero
  el error es de redondeo y aparece con **dos deudores y dos acreedores**: cada
  deudor redondeaba su fila por separado, así que los dos le daban su centavo al
  mismo acreedor. Medido sobre 1,25 millones de combinaciones: **las columnas
  salían mal en el 83%** de los casos con más de un pagador. Se veía en
  pantalla, porque el saldo neto de arriba y las deudas de a pares de abajo se
  contradecían. Ahora se reparte con `allocateDebtsToCredits`, un reparto de
  transporte que cierra las dos márgenes exactamente y nunca da negativos,
  verificado en un barrido exhaustivo más 3000 casos con montos grandes.

Lo que sigue abajo es el informe tal como lo produjo la auditoría, con el resto
de los hallazgos pendientes.

---

# Auditoría consolidada, verificada de nuevo

Reverifiqué las cuatro de severidad alta abriendo los archivos y, donde se podía, ejecutando el código (escribí un test descartable en `test/zz_probe_test.dart`, lo corrí y lo borré). El repo quedó como estaba.

---

## 1. Reverificación de las altas

### Se sostienen (3)

**Borrar un ticket siempre dice "No se pudo borrar", aunque haya funcionado.**
Verificado leyendo. `lib/features/receipts/presentation/providers/receipt_provider.dart:97` tiene `if (!ref.mounted) return false;` antes del `fold`. El grep confirma que el único acceso al provider en todo el repo es `lib/features/receipts/presentation/screens/receipt_detail_screen.dart:120`, con `ref.read(...)` y sin ningún `watch` ni `listen`, o sea que el notifier (autoDispose) queda descartado durante los tres viajes a Firestore de `deleteReceipt`. El borrado sí se ejecuta, y la pantalla igual pinta el snackbar rojo de la línea 128 y no navega. Es el 100% de los borrados.

**Borrar un ticket sin miniatura falla entero.**
Verificado leyendo las dos puntas. `lib/features/receipts/data/repositories/receipt_repository_impl.dart:206` escribe el thumb solo `if (thumbnail != null)`, pero la línea 283 hace `batch.delete(_thumbDoc(id))` sin condición. En `firestore.rules:76`, dentro de `match /media/{mediaId}`, está `allow delete: if owns();`, y `owns()` (línea 10-12) evalúa `resource.data.userId`: sobre un documento inexistente `resource` es null y la evaluación aborta, o sea deniega. Como el batch es atómico, se cae el borrado del ticket y del gasto. El disparador del lado del cliente existe: `ThumbnailService.buildBase64` devuelve null cuando `img.decodeImage` no reconoce el formato, y en web se le pasan los bytes crudos del picker.

**El OCR de la web tiene 20 s de presupuesto y carga dos idiomas.**
Verificado leyendo. `assets/config/app.env:19` tiene `OCR_PROVIDER=local`, así que `lib/services/ocr/ocr_service_factory.dart:25` devuelve `TesseractOcrService` en web. `lib/services/ocr/tesseract/tesseract_ocr_service_web.dart:44-46`: `_recognize(imagePath.toJS, 'eng+spa'.toJS).toDart.timeout(const Duration(seconds: 20))`. La firma externa declarada (líneas 9-13) admite dos parámetros, así que no hay `corePath` ni `langPath` propios: el core wasm y los dos `.traineddata` se bajan de CDN de terceros dentro de esos 20 s. El mensaje que ve el usuario es el `TimeoutException` crudo, envuelto en la línea 60.

### Se cae (1)

**"Guardar un gasto manual reporta éxito cuando la escritura falló": YA ESTÁ ARREGLADO.**
El escéptico anterior describe el código viejo. Abrí `lib/features/expenses/presentation/providers/expense_provider.dart` y las líneas 48-62 ya tienen el arreglo puesto, con el comentario que explica el motivo:

```dart
final mensaje = result.fold((f) => f.message, (_) => null);
if (ref.mounted) {
  state = mensaje == null ? const AsyncValue.data(null) : AsyncValue.error(...);
}
return mensaje;
```

Lo mismo `delete()` en las líneas 76-82. Y además ya existe `test/features/expenses/expense_actions_test.dart`, que es justo el test que el hallazgo pedía crear. Sale de la lista. Lo que queda vivo de ese ítem es solo la coletilla opcional: `add_expense_sheet.dart:230` sigue haciendo `Navigator.pop(context, true)` sin ningún snackbar de confirmación.

Ojo con el patrón: el mismo defecto que ya se arregló en `ExpenseActions` sigue intacto en `ReceiptActions`. Es la misma trampa documentada en `docs/estado-y-decisiones.md` ("Un `if (!ref.mounted) return null` puede significar salió bien"), aplicada a medias.

---

## 2. Deduplicación

De 24 hallazgos confirmados quedan **19 defectos distintos**:

| Se fusionan | Queda como |
|---|---|
| "Borrar un ticket sin miniatura" (dos veces, con distinto título) | D2 |
| "Si el usuario borra el comercio..." + "Borrar el nombre del comercio..." | D13 |
| "El prompt manda los precios en centavos" + "El prompt le manda los centavos con signo" | D19 |
| "Money.parse devuelve 0 para separadores" + "Editar un ticket acepta total 0" | D7 (comparten el fix de `receipt_detail_screen.dart:493`) |
| "addManual reporta éxito" | eliminado, ya arreglado |

---

## 3. Ordenado por impacto real para vos hoy (web, datos propios, grupos de a uno)

### Bloque A: te rompe algo hoy, en el uso normal

**D1. Borrar un ticket siempre muestra error rojo aunque haya funcionado.** ALTA.
`receipt_provider.dart:97`. Pasa en el 100% de los borrados. El riesgo real no es el cartel: es que creas que no se borró, vuelvas a Tickets, veas que sí, y no sepas en qué confiar. Peor todavía si intentás de nuevo.

**D2. Un ticket sin miniatura no se puede borrar nunca.** ALTA.
`firestore.rules:76` + `receipt_repository_impl.dart:283`. El ticket queda para siempre y su gasto sigue sumando en el dashboard y contra el presupuesto, sin ninguna salida desde la app. El estado es permanente. La única razón por la que lo pongo segundo es que hace falta que el thumbnail haya fallado (un HEIC del carrete de iPhone, por ejemplo).

**D3. El escaneo en el celular falla siempre por el timeout de 20 s.** ALTA.
`tesseract_ocr_service_web.dart:44-46`. El escaneo es la puerta de entrada de la app y en el celular no llega nunca. Y ojo: `docs/estado-y-decisiones.md` ya lista "El OCR con el motor que corre en producción" bajo "Lo que NO está verificado", así que esto no está contradiciendo ninguna decisión.

### Bloque B: te muestra números equivocados

**D4. El total del mes queda congelado al cruzar el cambio de mes.** MEDIA.
`expense_provider.dart:89` y `:96` llaman `DateTime.now()` dentro del cuerpo del provider, y `expensesStream` es un `snapshots()` de Firestore que no emite si nada cambia. Además `dashboard_screen.dart:217` y `expenses_screen.dart:46` recalculan `AppDate.monthYear(DateTime.now())` en cada rebuild, así que el encabezado y el número salen de fuentes distintas y pueden discrepar. El 1 de septiembre a la mañana, con la pestaña abierta desde el 31, ves el total de agosto bajo el título "septiembre" y la alerta roja de presupuesto excedido con el presupuesto realmente en cero. En el escritorio es plenamente alcanzable.

**D5. El total del ticket puede salir de la línea siguiente al keyword.** MEDIA.
`receipt_text_parser.dart`, `_totalPattern` usa `\s*` entre el keyword y el monto, y `\s` incluye `\n`. **Lo ejecuté**: con `test/assets/ocr/carniceria.txt` sin la línea del TOTAL, `extractTotal` devuelve **2200** en un ticket de **105600**; con `panaderia.txt` sin esa línea devuelve **1000** en uno de **41114**. Lo correcto sería null. Con el fixture completo queda tapado porque gana el último match, y los tres tests de `real_receipts_test.dart` usan el fixture completo. El monto malo llega prellenado a la pantalla de revisión editable, así que hay una chance de verlo, pero $22 en un ticket de $1.056 es exactamente el tipo de número plausible que pasa desapercibido.

**D6. Guardar sin conexión deja la pantalla colgada para siempre.** MEDIA.
`receipt_repository_impl.dart:216` (`batch.commit()`) y `expense_repository_impl.dart:86` (`_col.add()`) resuelven recién cuando el servidor confirma; sin red el Future queda pendiente y no hay ningún `.timeout()`. En `scan_receipt_screen.dart:88-90` la rama `ScanSaving` renderiza el form con `isSaving: true` y `onCancel: () {}` vacío: no hay salida. Idéntico en `add_expense_sheet.dart`. No se corrompe nada, pero no tenés forma de saber si quedó guardado.

### Bloque C: toca plata, pero hace falta que tipees algo raro

**D7. Editar el total de un ticket acepta cero y le borra la plata al gasto.** BAJA.
`receipt_detail_screen.dart:493` valida solo `if (total == null)`, sin `<= 0`. Los otros tres formularios sí cortan el cero (`receipt_review_form.dart:203`, `budget_sheet.dart:155`, `add_expense_sheet.dart:208`). Y `Money.parse` devuelve 0, no null, para entradas plausibles: **ejecutado**, `Money.parse(',')` = 0, `Money.parse('.')` = 0, `Money.parse('0')` = 0. `updateReceipt` (`receipt_repository_impl.dart:294-334`) tampoco valida, así que escribe `amountCents: 0` en el gasto vinculado en el mismo batch. Recuperable a mano (la foto y los items siguen ahí), pero es el único de los cuatro formularios que quedó afuera.

**D8. `Money.parse` se come el signo menos.** BAJA.
`money.dart:66`, el `RegExp(r'[^\d.,]')` borra el `-`. **Ejecutado**: `parse('-1500')` = 150000, `parse('-1.234,56')` = 123456. Y `add_expense_sheet.dart` no tiene `inputFormatters`, así que en la web se puede tipear el `-`. Se guarda lo contrario de lo que escribiste, en silencio. Baja porque los negativos no son un caso soportado en ningún lado.

**D9. La fecha del gasto que nace de un ticket se guarda a medianoche, no a mediodía.** BAJA.
`receipt_repository_impl.dart:203`, `:315` y `:323` escriben la fecha cruda. El camino manual sí normaliza a las 12, con el motivo escrito: `expense_repository_impl.dart:81-82`. Hoy los dos caminos guardan distinto la misma cosa. Para que se rompa hace falta cambiar de zona horaria (Uruguay no tiene horario de verano desde 2015), pero el arreglo son tres líneas.

### Bloque D: te hace perder trabajo, no datos

**D10. Si falla el guardado se pierde el borrador entero.** BAJA. `receipt_provider.dart:80` hace `ScanFailed(failure.message)` y tira el `draft`; `scan_receipt_screen.dart:93` cae en `_ => _buildPicker(state)`. Hay que correr Tesseract de nuevo y volver a corregir todo.

**D11. Navegar fuera de /scan durante la revisión descarta el borrador.** BAJA. `scanProvider` es autoDispose y su único oyente es `scan_receipt_screen.dart:28`. La `NavigationBar` del `MainShell` está visible en /scan y `context.go` reemplaza el child, así que la pantalla se desmonta. Nota: el `PopScope` que se suele proponer NO atrapa esto, porque `go` no dispara un pop.

**D12. Navegar mientras se guarda pierde la confirmación.** BAJA. Mismo mecanismo que D11, pero con la escritura ya en vuelo: el ticket queda guardado y no ves ni el snackbar ni el `go('/receipts')`. Sin detección de duplicados en `saveDraft`, volver a escanear el mismo ticket lo cuenta dos veces. Ventana chica (un solo commit), pero comparte arreglo con D10 y D11.

**D13. Borrar el nombre del comercio en la revisión no borra nada.** BAJA. `receipt_draft.dart:64`, `storeName ?? this.storeName` descarta el null que manda `receipt_review_form.dart:210`. Se persiste el nombre que leyó el OCR (típicamente un RUT) en `receipts/{id}` y en el gasto, y encima entra al ranking de comercios de los insights, que justamente saltea los nombres vacíos (`monthly_spending_summary.dart:55-56`).

### Bloque E: ensucia el detalle del ticket, no la plata

Ninguno de estos toca `totalCents`, o sea que ni el gasto ni el presupuesto se mueven. Los tres los **ejecuté** contra el parser real:

**D14. Una fila de IVA impresa debajo del total gana.** BAJA. `extractTotal` se queda con el último match. Con `TOTAL 1.234,00` seguido de `IVA TASA BASICA TOTAL 222,00` devuelve **22200**. Ninguno de los tres tickets reales del repo tiene ese layout, pero el filtro sale casi gratis junto con D5.

**D15. Una medida `40x60` se lee como cantidad, y esa rama no aplica el techo del total.** BAJA. `Bolsa 40x60  35,00` en un ticket de $110 da un item de **240000 centavos** con quantity 40.0 (el precio real, 3500, se pierde). La rama de cantidad hace `continue` antes del guard `cents > totalCents`, así que el invariante documentado en `docs/estado-y-decisiones.md` ("ningún ítem puede costar más que el ticket entero") no se aplica ahí.

**D16. Sin marcador de inicio de detalle, la dirección entra como producto.** BAJA. Con un ticket sin `MONEDA:` ni `Cant`, `Av. Italia 12` sale como item de $12. Los tres tickets reales traen el marcador, así que no pasa con ellos.

### Bloque F: molesto, sin daño

**D17. La lista de tickets está clavada en 20 y no hay paginación.** BAJA. `receipt_repository_impl.dart:342` pide siempre `.limit(AppConstants.receiptsPageSize)`. `getReceipts({limit})` existe (línea 234) pero no lo llama nadie en `lib/`. Al ticket 21, el número 1 y su foto quedan sin camino en la UI: el detalle solo se alcanza desde esa lista y el id es un uuid. No se pierde nada, falta el acceso.

**D18. El detalle redecodifica la foto en cada build.** BAJA. `receipt_detail_screen.dart:263-266` hace `ThumbnailService.decode` + `MemoryImage(...)` dentro del `builder` del `Consumer`. `MemoryImage` compara por identidad del `Uint8List`, así que cada rebuild es un miss del ImageCache. Editar el total tres veces deja del orden de 12 bitmaps de la misma foto vivos. El ImageCache evicta por LRU, así que es desperdicio, no fuga.

**D19. El prompt de IA manda centavos con signo de pesos: 100x.** BAJA, latente. `ai_service.dart:77`: `'- ${i.name}: \$${i.totalPriceCents}'`, o sea `$12000` para un item de $120. Es la única interpolación de plata del archivo que no pasa por `Money.format`. Hoy no corre: el clasificador local va primero y `OllamaProvider` apunta a `localhost`, inalcanzable desde https. Queda armado para cuando llegue el proxy de IA (punto 2 de "Qué falta").

**D20. `signOut()` tira `UnmountedRefException` en un future sin await.** BAJA. `auth_provider.dart:99`, `state = const AsyncValue.data(null)` sin guard, mientras que los otros tres métodos del mismo notifier sí lo tienen. `settings_screen.dart:78-80` lo llama fire-and-forget. El logout funciona igual (el redirect lo hace `authStateProvider`), queda una excepción en la consola.

**D21. `pairwiseDebts` no cierra las columnas con más de un pagador.** BAJA, no alcanzable. **Ejecutado**: con `paidBy={a:1,b:3}`, `shares={c:2,d:2}`, `netBalances` da `{a:1, b:3, c:-2, d:-2}` pero `pairwiseDebts` da `[c->a:1, d->a:1, c->b:1, d->b:1]`, o sea a cobra 2 cuando su neto es 1. La UI manda un solo pagador (`add_group_expense_sheet.dart:223` usa un `ChoiceChip` de selección única) y con un solo pagador no hay descuadre. Además tus grupos tienen una sola persona. Es un bug latente para la fase 2.

**D22. Residuo: `test/tmp_review_probe_test.dart`.** Es una sonda de una revisión anterior que solo imprime con `print` y no verifica nada. Explica la diferencia entre "210 tests" y "213 tests" en el doc. Borralo antes del primer commit.

---

## 4. Arreglos agrupados por archivo, para aplicar de a tandas

### Tanda 1: las tres altas. Chica, alto retorno.

| Archivo | Líneas | Qué |
|---|---|---|
| `firestore.rules` | 76 | `allow delete: if signedIn() && (resource == null \|\| owns());` + `firebase deploy --only firestore:rules --project mborba-proyect` |
| `lib/features/receipts/data/repositories/receipt_repository_impl.dart` | 283 | `hayThumb` con `try/catch` alrededor del `get()` (el get de un doc inexistente **también** se deniega), y `if (hayThumb) batch.delete(...)` |
| `lib/features/receipts/presentation/providers/receipt_provider.dart` | 94-108 | mover el guard adentro del `fold`, igual que ya está hecho en `expense_provider.dart:56-62` |
| `lib/services/ocr/tesseract/tesseract_ocr_service_web.dart` | 44-46 | timeout a 3 min con mensaje en castellano, y `'eng+spa'` → `'spa'` |

El deploy de reglas es lo único que necesita un paso fuera del repo.

### Tanda 2: los números del dashboard.

| Archivo | Líneas | Qué |
|---|---|---|
| `lib/features/expenses/presentation/providers/expense_provider.dart` | 87-97 | sacar `DateTime.now()` del cuerpo, meterlo en un `currentMonthProvider` con Timer que se reinvalida |
| `lib/features/dashboard/presentation/screens/dashboard_screen.dart` | 217 | el mes sale de `summary.month`, no de `DateTime.now()` |
| `lib/features/expenses/presentation/screens/expenses_screen.dart` | 46 | ídem |
| `lib/main.dart` (raíz) | nuevo | `WidgetsBindingObserver` que invalide el mes en `AppLifecycleState.resumed` |

Requiere `dart run build_runner build --delete-conflicting-outputs`.

### Tanda 3: el parser. Un solo archivo, cuatro cambios que se pisan entre sí.

`lib/services/ocr/receipt_text_parser.dart`, líneas 38-46 (`_totalPattern`), 188-195 (`extractTotal`), 255-275 (`parseItems`), más `_itemQtyPattern`:
- D5: `[^\S\n]` en lugar de `\s` y `extractTotal` por líneas, con fallback de línea siguiente solo si trae un monto solo
- D14: `_taxRowPattern` con lookahead que deja pasar `NETO A PAGAR`
- D15: guard del techo en la rama de cantidad y exigir separación alrededor de la `x`
- D16: `_addressPattern`

Hacelos juntos: D14 y D5 comparten la reescritura de `extractTotal`.

### Tanda 4: plata y validación.

| Archivo | Líneas | Qué |
|---|---|---|
| `lib/core/format/money.dart` | 65-67 | rechazar `-` (D8) y rechazar entradas sin dígitos (D7) |
| `lib/features/receipts/presentation/screens/receipt_detail_screen.dart` | 493 | `if (total == null \|\| total <= 0)` |
| `lib/features/receipts/data/repositories/receipt_repository_impl.dart` | 301 | `if (totalCents <= 0) return const Left(ValidationFailure(...))` en `updateReceipt` |
| `lib/features/receipts/data/repositories/receipt_repository_impl.dart` | 203, 315, 323 | normalizar la fecha a mediodía, idealmente con un `AppDate.aMediodia()` en `core/format/money.dart` que usen los tres llamadores |
| `lib/features/receipts/domain/entities/receipt_draft.dart` | 52-70 | centinela en `copyWith` para `storeName` (solo ese campo) |

### Tanda 5: el flujo de escaneo. Un solo refactor, tres bugs.

`lib/features/receipts/presentation/providers/receipt_provider.dart` (líneas 32-41, 53-86) y `lib/features/receipts/presentation/screens/scan_receipt_screen.dart` (líneas 21-25, 72-95):
- D10: estado `ScanSaveFailed(draft, message)` que preserva el borrador
- D11 y D12: `@Riverpod(keepAlive: true)` + los bytes de la foto en el estado + `initState` que resetea si volvés a un estado terminal

Con `keepAlive` hay que **sacar** los `if (!ref.mounted) return;` de las líneas 62 y 78: ahora tocar `state` después del await es seguro, y esos returns eran justo los que se tragaban el resultado.

### Tanda 6: timeouts de red.

`lib/features/receipts/data/repositories/receipt_repository_impl.dart:216` y `lib/features/expenses/data/repositories/expense_repository_impl.dart:86`, más `scan_receipt_screen.dart:90` (`onCancel: () {}` → reset real).

### Tanda 7: el resto, suelto.

`lib/services/ai/ai_service.dart:77`, `lib/features/auth/presentation/providers/auth_provider.dart:99` + `lib/features/settings/presentation/screens/settings_screen.dart:76-81`, `lib/features/groups/domain/balance.dart:95-101`, `lib/features/receipts/presentation/screens/receipt_detail_screen.dart:32-35 y 263-266`, `lib/features/receipts/presentation/screens/receipt_list_screen.dart:49-58` + `receipt_repository_impl.dart:228`, y `rm test/tmp_review_probe_test.dart`.

---

## 5. Qué es seguro y qué necesita que decidas

### Seguros, aplicalos sin pensar más (mecánicos, con test que los fija)

- **D1** `receipt_provider.dart:97`. Es exactamente el mismo arreglo que ya está aplicado y testeado en `expense_provider.dart`. Copiá el patrón y copiá el test.
- **D2** `firestore.rules:76`. El escéptico lo verificó contra el emulador: el caso del thumb ausente pasa a 200 y "borrar un ticket ajeno" sigue dando 403. El chequeo en el cliente va **con** `try/catch`, porque el `get()` del doc inexistente también se deniega.
- **D7, D8** `money.dart` + `receipt_detail_screen.dart:493` + `updateReceipt`. Cuatro líneas. Alinea el cuarto formulario con los otros tres, que ya validan igual.
- **D9** fecha a mediodía. Alinea el camino del ticket con el manual, que ya tiene el motivo escrito.
- **D13** centinela en `copyWith`, solo para `storeName`. No lo extiendas a `receiptDate` ni a `totalCents`: ahí `_confirm` nunca manda null y el centinela solo perdería chequeo de tipos.
- **D14, D15, D16** filtros del parser. Verificados contra la suite: los 210 tests siguen pasando. Ojo con el lookahead de `_taxRowPattern`, sin él se rompe el test existente de `NETO A PAGAR $ 999,90`.
- **D19** `ai_service.dart:77`. Sacá el `\$` literal, `Money.format` ya trae el símbolo.
- **D20** guard en `signOut` + `try/catch` en el call site.
- **D22** borrar `test/tmp_review_probe_test.dart`.
- **D21** `pairwiseDebts`. Marcado seguro **con reserva**: el reemplazo por matriz que propone el escéptico está verificado (31 tests de `test/features/groups/` pasan, más un fuzz de 200.000). Pero es un algoritmo nuevo de 40 líneas en el código que reparte plata entre personas, y hoy no es alcanzable desde la app. Yo lo dejaría para cuando toques la fase 2, con el fuzz test puesto **primero**. La solución alternativa que propuso el reporte original (correr el greedy de `settle` dentro de cada gasto) está **mal**: rompe el test `balance_test.dart:123` y contradice el comentario de la función.

### Necesitan una decisión tuya antes de tocar

- **D3, el OCR.** Subir el timeout de 20 s a 3 min es seguro (hoy no es margen, es menos que el piso). Pasar de `'eng+spa'` a `'spa'` es **decisión de producto**: baja a la mitad la descarga de traineddata y acelera el reconocimiento, pero un ticket en inglés deja de leerse. Dado que el target es Uruguay y la pantalla de revisión ya existe para corregir, yo lo haría, pero decidilo vos. Aparte, lo que saca el problema de raíz (servir `corePath` y `langPath` desde `web/` para que el service worker los cachee) es un cambio de otro tamaño: hay que pasar la firma externa a tres argumentos. Y hay algo que ningún test cubre: **medí una vez a mano en tu celular, con caché e IndexedDB borrados, cuánto tarda en frío**, y anotá el número en el doc.
- **D4, el mes en curso.** El arreglo cambia cuándo se regeneran los insights. `MonthlySpendingSummary` existe justamente para que `monthlyInsightsProvider` no se regenere en cada snapshot, y eso está escrito en el doc de la clase. Con el arreglo el resumen cambia una vez al cruzar el mes, que es cuando los insights sí tienen que regenerarse: es correcto, pero es un llamado a la IA más por mes que hoy no ocurre. Además, el Timer necesita el tope de 6 horas porque en web un `setTimeout` de más de 24,8 días desborda.
- **D6, timeouts de red.** El mensaje importa. El `.timeout()` **no cancela** la escritura encolada, así que si el texto invita a reintentar se duplica el gasto. Para que reintentar sea inocuo hay que además derivar el id del gasto del `receiptId` (`_expensesCol.doc(receiptId)` en vez de `_expensesCol.doc()`, línea 197) y hacer que el `receiptId` nazca en el `ReceiptDraft`. Eso es un cambio de modelo, no un timeout.
- **D10, D11, D12, el keepAlive del escaneo.** Decidí qué se preserva. El `keepAlive` salva la corrida de Tesseract y la foto, que es lo caro, pero **no** salva lo que tipeaste: el comercio, el total, la fecha y la categoría viven en el `State` de `ReceiptReviewForm` y recién salen en `onConfirm`. Para salvar eso también hay que empujar cada cambio con `updateDraft`, que es más invasivo. Y con `keepAlive` aparece un riesgo nuevo: un borrador que queda pegado entre sesiones si el `reset()` no cubre todos los caminos.
- **D17, paginación.** Es una feature chica, no un arreglo. Definí si querés "Ver tickets anteriores", scroll infinito, o un filtro por mes (que probablemente sea lo más útil para una app de finanzas).
- **D18, el `MemoryImage`.** Mover la decodificación al provider es seguro y cambia la firma del generado. Lo que **no** haría es el `cacheWidth` que propone el reporte: la misma imagen se reusa en `_FotoAmpliada` con zoom hasta 5x, y bajarle la resolución al bitmap arruinaría justo aquello para lo que la miniatura se guarda a 1000px.

### Un pendiente que no es un bug pero condiciona todo

`docs/estado-y-decisiones.md` dice que los tests de reglas necesitan Node y `@firebase/rules-unit-testing`. **Eso no es cierto**: alcanza con el JAR del emulador (`firebase setup:emulators:firestore`) corrido con el JDK 21 que ya trae Android Studio, y un script sin dependencias que autentique con un JWT de alg `none`. El escéptico ya lo hizo para verificar D2. Actualizá esa fila del doc: el "gatillo bloqueante" es mucho más barato de lo que quedó escrito, y `firestore.rules` sigue siendo tu única capa de autorización sin un solo test.