# ReceiptAI Finance Assistant

Asistente financiero personal. El escaneo de tickets es la puerta de entrada:
el objetivo es que la app responda preguntas sobre la plata de quien la usa, no
que sea un archivador de fotos de recibos.

Flutter + Firebase (Auth, Firestore, Storage), OCR on-device con ML Kit y una
capa de IA detrás de la interfaz `AIProvider`.

## Arranque rápido

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter run
```

La configuración de Firebase y de Ollama está en [SETUP.md](SETUP.md).

## Configuración regional

`.env` define cómo se leen y se muestran los montos y las fechas:

```
APP_LOCALE=es_AR      # formato de dinero y fechas
CURRENCY_CODE=ARS     # ARS, MXN, CLP, COP, UYU, USD, EUR, BRL, PEN...
DATE_DAY_FIRST=true   # los tickets usan DD/MM (LatAm, Europa)
```

`.env` se empaqueta como asset del binario, así que **no puede contener
secretos**: cualquiera los extrae del APK o del IPA. Las claves de proveedores
de IA van server-side.

## Estructura

```
lib/
├── core/          router, config, formato (Money/AppDate), errores
├── features/      auth, receipts, expenses, insights, dashboard
│                  cada una con domain/ data/ presentation/
├── services/      ai (AIProvider), ocr (OcrService), storage, image
└── shared/        theme y widgets reutilizables
```

Las decisiones de arquitectura están documentadas en
[SETUP.md](SETUP.md#architecture-overview).

## Tests

```bash
flutter test
```

El grueso de la cobertura está sobre `ReceiptTextParser`, que es la pieza más
frágil: si lee mal un monto, el error se propaga en silencio al gasto, al
dashboard y a los insights de IA.

## Estado

MVP. Antes de publicar hacen falta, como mínimo: proxy server-side para la IA
(hoy `AIProvider` apunta a Ollama en `localhost`, que en un teléfono es el
propio teléfono), borrado de cuenta, exportación de datos y política de
privacidad.
