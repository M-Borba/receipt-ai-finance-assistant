# ReceiptAI Finance Assistant

Asistente financiero personal. El escaneo de tickets es la puerta de entrada:
el objetivo es que la app responda preguntas sobre la plata de quien la usa, no
que sea un archivador de fotos de recibos.

**En vivo:** https://mborba-proyect.web.app

---

## Si venís a retomar esto, leé esto primero

| Documento | Qué contiene |
|---|---|
| **[docs/estado-y-decisiones.md](docs/estado-y-decisiones.md)** | **Empezá acá.** Las decisiones tomadas **y sus motivos**, qué está construido, qué falta, **qué NO está verificado**, y las trampas conocidas que ya mordieron. |
| [docs/grupos-y-division.md](docs/grupos-y-division.md) | Grupos estilo Splitwise: modelo de datos, algoritmos de reparto y liquidación, reglas, fases. La fase 1 está hecha. |
| [docs/hallazgos-auditoria.md](docs/hallazgos-auditoria.md) | Hallazgos de una auditoría automática, **sin verificar**. Candidatos a revisar, no bugs confirmados. |
| [SETUP.md](SETUP.md) | Puesta a punto de Firebase, Ollama y el entorno. Algunas partes están desactualizadas: manda el doc de decisiones. |

El código explica el **qué**. Esos documentos explican el **por qué**, que es lo
que se pierde y lo que cuesta caro volver a deducir.

---

## Arranque

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # los *.g.dart NO se versionan
flutter test
flutter run -d chrome --web-port=5000
```

**El `build_runner` no es opcional.** Los archivos `*.g.dart` (Riverpod, JSON)
están en `.gitignore`, así que un clone limpio no compila hasta generarlos.

## Deploy

El CI despliega solo en cada push a `main`. A mano:

```bash
flutter build web --release
firebase deploy --only hosting --project mborba-proyect
firebase deploy --only firestore:rules,firestore:indexes --project mborba-proyect
```

## Configuración

`assets/config/app.env`, **versionado a propósito**:

```
APP_LOCALE=es_UY      # formato de dinero y fechas
CURRENCY_CODE=UYU     # una sola moneda: multi-moneda está fuera de alcance
DATE_DAY_FIRST=true   # los tickets uruguayos usan DD/MM
```

Va empaquetado dentro del binario, así que **cualquiera lo lee**: no puede
tener secretos nunca. Las claves de proveedores de IA viven server-side.

---

## Lo que hay que saber antes de tocar código

Cuatro reglas que, si se rompen, rompen cosas que no se ven enseguida.

**1. Toda la plata es `int` de centavos.** Ver `lib/core/format/money.dart`.
Un `double` que toque dinero es un bug. `0.1 + 0.2 != 0.3` es invisible en un
gasto suelto y se acumula en un libro de deudas compartidas. Las cantidades
(1,5 kg) sí son `double`, eso es correcto.

**2. Plan Spark (gratis): no hay Cloud Functions ni Firebase Storage.** No
propongas soluciones que los usen. La foto del ticket se guarda en base64
dentro de Firestore, en `receipts/{id}/media/thumb`, y es deliberado: para
grupos, compartir la foto es la misma regla de membresía que el ticket ya
necesita.

**3. `firestore.rules` es la única capa de autorización, y no tiene tests.**
Cualquier cambio ahí se despliega sin red de seguridad. Ver el gatillo
bloqueante en el doc de decisiones.

**4. Solo se usa la web.** El usuario abre la PWA en celular y computadora. Los
caminos nativos (ML Kit, `dart:io`, `path_provider`) existen pero no se usan en
producción.

## Estructura

```
lib/
├── core/          router, config, formato (Money/AppDate), errores
├── features/      auth, receipts, expenses, budgets, groups, insights,
│                  dashboard, settings — cada una con domain/ data/ presentation/
├── services/      ai (AIProvider), ocr (OcrService), classification, image
└── shared/        theme y widgets reutilizables
```

`domain/` es lógica pura y testeable sin Firebase: ahí vive lo que más importa
que esté bien (`groups/domain/split.dart`, `groups/domain/balance.dart`,
`core/format/money.dart`, `services/ocr/receipt_text_parser.dart`).

## Tests

```bash
flutter test
flutter analyze lib test --no-fatal-infos
```

206 tests. El grueso cubre dos cosas:

- **El parser de tickets**, contra **tickets uruguayos reales** pasados por un
  OCR real, no texto inventado. Ver `test/assets/ocr/README.md`: ahí está qué
  reveló cada uno. Es la pieza más frágil, porque si lee mal un monto el error
  se propaga en silencio al gasto y al dashboard.
- **El reparto de plata en grupos**, con un barrido que verifica que la suma
  cierre exacta para 400 totales contra 7 combinaciones de pesos.

---

## Trampas que ya mordieron

Están todas en el [doc de decisiones](docs/estado-y-decisiones.md), pero estas
tres cuestan horas si no se saben:

- **Riverpod le saca el sufijo `Notifier`.** `ScanNotifier` genera
  `scanProvider`, no `scanNotifierProvider`.
- **`'\$'` es un escape válido en Dart.** `'\${variable}'` compila perfecto y
  muestra el texto literal en pantalla. El analyzer no lo detecta. Buscar con:
  `grep -rn '\\\${' lib --include="*.dart" | grep -v "g.dart"`
- **Los headers de cache de Hosting.** En Flutter web ningún archivo del build
  lleva hash en el nombre, así que marcar algo `immutable` deja a la gente
  clavada en una versión vieja sin salida. Todo va con `no-cache`.
