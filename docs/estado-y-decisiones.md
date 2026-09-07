# Estado del proyecto y decisiones tomadas

Documento de traspaso. Si estás retomando esto sin el contexto de la
conversación donde se construyó, empezá acá.

Última actualización: 2026-08-29

---

## Qué es

Asistente financiero personal. El escaneo de tickets es la puerta de entrada,
no el producto. El objetivo es que responda preguntas sobre la plata de quien
la usa.

**En vivo:** https://mborba-proyect.web.app (Firebase Hosting, proyecto
`mborba-proyect`)

**Target:** Uruguay. `APP_LOCALE=es_UY`, `CURRENCY_CODE=UYU`, tickets DD/MM.

---

## Decisiones y por qué

Estas son las que cuestan caro revisar. El "por qué" importa más que el qué.

| Decisión | Motivo |
|---|---|
| **Plan Spark, no Blaze** | Todo lo necesario se resuelve con reglas. Blaze solo hacía falta para Storage y Cloud Functions, y ninguno es imprescindible. No se quiere tarjeta cargada. |
| **Solo web, sin tiendas** | Play cobra USD 25 una vez, Apple USD 99 por año. Se descartó pagar. La web es PWA instalable; el APK se distribuye como artifact del CI para instalación directa. |
| **Plata en centavos enteros (`int`)** | `0.1 + 0.2 != 0.3`. En un gasto suelto es invisible; en deudas compartidas se acumula. El reparto sin perder centavos usa división entera y módulo: no se puede escribir bien con `double`. Prerrequisito de grupos. |
| **Firestore ES el storage de fotos** | Firebase Storage exige Blaze en proyectos nuevos. La foto se guarda a **1000px, calidad 70, en base64** en `receipts/{id}/media/thumb`. Medido sobre tickets reales: 84-160 KB. El plan gratuito da 1 GiB, o sea ~8.000 tickets; a tres por día son siete años. No es un parche por falta de plata: **para grupos es mejor que un blob store aparte**, porque que un amigo vea la foto del ticket compartido es la misma regla de membresía que el ticket ya necesita. Con Supabase o R2 habría que duplicar el modelo de permisos en un segundo sistema, y para hacerlo seguro hace falta el Worker (Supabase valida sus propios JWT, no los de Firebase). |
| **La miniatura va en subcolección** | En el documento del ticket, `watchReceipts` se traería 20 miniaturas por snapshot: megabytes de datos móviles por cada apertura de la lista. |
| **La miniatura lleva su propio `userId`** | Alternativa era `get()` del ticket padre dentro de la regla, y cada `get()` en una regla es una lectura facturada, en cada evaluación. |
| **`rawOcrText` NO se persiste** | Era el texto completo de cada compra guardado para siempre, y no lo leía nadie. Exposición sin beneficio. Se usa durante el escaneo (vive en el `ReceiptDraft`) y se descarta. Los documentos viejos se siguen leyendo. |
| **La memoria del usuario gana sobre todo** | El orden es: lo que vos elegiste antes para ese comercio, después las reglas locales, después la IA. Nadie sabe mejor que vos en qué gastás, y los comercios chicos (que son la mayoría) nunca van a estar en una lista de cadenas. Se guarda en **un solo documento** en `users/{uid}/preferences/merchants`: se lee entero en cada escaneo, así cuesta una lectura y no una por comercio. En Firestore y no en el navegador, porque la app se usa en el celular y en la computadora. |
| **Clasificación local primero, IA después** | El clasificador de comercios corre en el dispositivo: gratis, instantáneo, offline. La IA quedó como plan B. Antes era al revés, y como la IA apunta a `localhost` no funcionaba nunca en producción. |
| **Nada de multi-moneda** | Una moneda, sale de `app.env`. Multi-moneda es un pozo: qué cotización, de qué fecha, qué pasa si cambia. |
| **Tests de reglas SIN emulador** | Se descartó el emulador (pide Java 11+, acá hay Java 8) y `@firebase/rules-unit-testing` (solo JS, metería Node en un repo Dart). En su lugar, `tool/verificar_reglas.py` usa el endpoint `TestRuleset` de la Security Rules API: **el mismo motor que corre en producción**, del lado del servidor, con Python de la biblioteca estándar y cero dependencias nuevas. 25 casos. |
| **Config en `assets/config/app.env`, versionada** | Va dentro del binario igual, así que no puede tener secretos. `.env` quedó gitignoreado y sin uso. Antes `.env` era asset obligatorio Y estaba gitignoreado: ningún clone limpio compilaba. |
| **Los gastos de grupo NO llevan copia de `memberIds`** | El diseño original la desnormalizaba para no pagar un `get()` por evaluación. Se revirtió por dos motivos. Primero: la copia queda vieja cuando alguien se suma, así que quien entra no vería ningún gasto anterior, y no puede arreglarlo (para actualizarlos necesitaría listarlos, que es lo que la regla le niega). Segundo: la condición `esDelGrupo(groupId)` no menciona `resource`, así que Firestore la evalúa **una vez por consulta** y no una por documento. El ahorro que justificaba la copia no existía. Efecto secundario: la query ya no necesita filtro, que era la causa del `permission-denied` que se chocó en producción. |
| **Los items se acotan al bloque del detalle** | Un e-Ticket de DGI tiene encabezado, detalle y pie. Sin acotar, el número de RUT entraba como un producto de $219.640.160,11 y las filas de la tabla de IVA entraban con el monto del total. Además: **ningún ítem puede costar más que el ticket entero**, que es la regla que limpia la basura sin depender de cómo el OCR cortó las columnas. |
| **Google Sign-In por `signInWithPopup` en web** | `GoogleSignIn().signIn()` está deprecado en web justamente porque no devuelve un `idToken` confiable. Además había un meta tag `google-signin-client_id` en `index.html` con un client ID sin origen autorizado, que producía `origin_mismatch`. Se removió. |

### El gatillo bloqueante quedó levantado

Las reglas ya tienen verificación automática: `python3 tool/verificar_reglas.py`,
25 casos contra el motor real de Firebase. Correrlo cada vez que se toque
`firestore.rules`. Detalle en [verificar-reglas.md](verificar-reglas.md).

Por qué importaba, con evidencia: **cuatro errores de reglas en dos semanas**,
uno descubierto recién al chocarlo en producción (commit `2b58a23`) y otro
recién cuando el script pudo ejecutar las reglas de verdad (el borrado de una
miniatura inexistente, que yo había "arreglado" con una condición que no
funciona).

Sigue faltando la prueba de punta a punta con dos cuentas, que el script no
puede hacer: está descrita en el mismo documento.

---

## Qué está construido

- Auth con email y Google (web usa el popup de Firebase)
- Escaneo con **revisión editable antes de guardar**: nada se escribe en
  Firestore hasta que la persona confirma
- Entrada manual de gasto
- Borrado de tickets, que borra el gasto asociado en el mismo batch
- Presupuesto por categoría con alertas in-app (verde / 80% / excedido)
- Dashboard, gastos por categoría, detalle de ticket
- Ajustes: exportar a CSV, borrar cuenta con todos sus datos
- Parser de tickets LatAm: DD/MM, vocabulario español, tildes y ñ, y **las dos
  convenciones de separador** (`1.234,56` y `1,056.00`: los e-Ticket de DGI usan
  la segunda, al revés de lo que se asumía)
- Clasificador de comercios uruguayos on-device
- **Memoria de comercios**: la app aprende con qué categoría clasificás cada
  comercio y la reusa. Va antes que las reglas fijas, porque tu carnicería del
  barrio no está ni va a estar en ninguna lista de cadenas
- Moneda y fechas por locale
- Foto del ticket legible en Firestore, ampliable con zoom desde el detalle
- CI/CD en GitHub Actions, PWA instalable
- **Tests contra tres tickets uruguayos reales** pasados por un OCR real, no
  texto inventado: ver `test/assets/ocr/README.md`
- **Grupos fase 1**: crear grupo, cargar gasto, dividir en partes iguales o por partes, balances de a pares. Sin invitaciones todavía
- **Límite conocido de las reglas**: no pueden validar que el reparto de un
  gasto de grupo sume el total, porque el lenguaje no suma valores de un mapa.
  Lo valida el cliente y la UI marca los descuadrados
- **219 tests**, `flutter analyze` en 0 errores y 0 warnings

## Qué falta

1. ~~**Foto en alta en el dispositivo**~~ **Descartado.** Existía porque la
   miniatura de 480px era ilegible. A 1000px se leen los ítems y los importes,
   sincroniza a todos lados y se comparte con un grupo sin trabajo extra. Una
   copia local solo en el celular era peor en todo salvo en resolución.
2. **Proxy de IA** en Cloudflare Workers. Sin esto la clasificación por IA y los
   insights solo funcionan en la máquina de desarrollo, porque `AIProvider`
   apunta a Ollama en `localhost`. Sirve para: insights, estructurar el texto
   cuando el regex falla, y el chat futuro. Para clasificar ya casi no hace
   falta.
3. **Notificaciones.** Hoy cero. Las push necesitan un servidor que mire los
   datos: el mismo Worker del punto 2, con un cron. En iPhone solo funcionan si
   la persona instaló el PWA en la pantalla de inicio.
4. **Grupos fase 2 y 3.** Settle up, y la que importa: asignación por ítem
   ("la cerveza la tomamos Juan y yo"). Ver `docs/grupos-y-division.md`.

---

## Lo que NO está verificado

Importante para no confiar de más en el estado "todo verde":

- **El camino completo contra Firestore.** No hay sesión de usuario en el
  entorno de desarrollo de la IA. Guardar, borrar y presupuestos están
  verificados por compilación y tests de lógica pura, no de punta a punta.
- **La UI renderizada.** Nadie cliqueó las pantallas desde el lado del
  desarrollo asistido. Desbordes, contraste y teclado tapando campos son
  invisibles ahí.
- **El flujo de invitación de punta a punta.** Las reglas sí se ejecutan ahora
  (25 casos), pero nadie abrió un link con una segunda cuenta real.
- **El OCR con el motor que corre en producción.** Ya hay tres tickets
  uruguayos reales en `test/assets/ocr/`, pero el texto lo produjo Apple Vision,
  no ML Kit (móvil) ni Tesseract (web). Lo que se verificó es el **parser**
  contra salida real de un OCR; lo que falta es confirmar que ML Kit corta las
  líneas parecido. Donde más puede diferir es en el detalle, porque el nombre y
  los números vienen en líneas separadas y cada motor arma las columnas a su
  manera. El total, la fecha y el comercio no dependen del corte de líneas.
- **El precio de cada ítem es aproximado; el total es exacto.** Según el
  comercio, la columna que queda pegada al nombre es el importe o el precio
  unitario, y no hay forma de distinguirlas sin conocer el layout. En 8 de los 9
  ítems de los tickets reales queda el importe correcto. El total, que es lo que
  alimenta el gasto y el presupuesto, sale bien en los tres. La pantalla de
  revisión permite corregir antes de guardar.

Confirmado funcionando en un celular real por el usuario.

---

## Trampas conocidas

**Un `if (!ref.mounted) return X` puede significar "salió bien".** Apareció dos
veces: en `ExpenseActions` (donde `null` era éxito) y en `ReceiptActions` (donde
`false` era fallo, así que el 100% de los borrados mostraba error aunque
funcionaran). Los notifiers autoDispose a los que solo se accede con `read`
quedan descartados apenas empieza el `await`, así que esa rama **es la normal, no
la excepción**. La regla: el valor devuelto sale del resultado, siempre; lo único
que depende de `mounted` es tocar `state`.

**Detalle original:** Pasó en
`ExpenseActions`, donde el contrato del método era "null es éxito": una
escritura fallida mientras la pantalla se cerraba se reportaba como guardada y
el gasto se perdía en silencio. La regla: el valor que se devuelve sale del
resultado, siempre; lo único que depende de `mounted` es tocar `state`.

**Una query sin el filtro que la regla espera se rechaza ENTERA.** Confirmado
en producción el 2026-08-31 (commit `2b58a23`, "Fix permission denied error on
group expenses"), no es teoría. Firestore evalúa la consulta contra su resultado
**posible**, no contra los documentos que existen: si la regla dice
`uid in resource.data.memberIds`, la query necesita
`.where('memberIds', arrayContains: uid)` aunque todos los documentos cumplan.

Corolario que ya mordió dos veces más: **`get` y `list` son permisos distintos**.
La regla de `receipts/{id}/media` permite `get` pero no `list`, así que
`.collection('media').get()` (que es un listado) se rechaza. Cuando el id es
conocido, ir directo al documento evita el problema y ahorra una lectura.

Antes de escribir cualquier query nueva, mirar qué pide la regla de esa
colección.

**El service worker de Flutter cachea la app entera.** Después de un deploy, la
pestaña vieja puede seguir sirviendo la versión anterior hasta que se recargue.
Para probar en el momento: ventana de incógnito, o DevTools → Application →
Service Workers → Unregister.

**Los headers de cache de Hosting estaban mal y ya se arreglaron** (2026-08-30).
`main.dart.js` salía con `immutable, max-age=31536000`, o sea un año, y `/` no
tomaba la regla de `no-cache` porque estaba escrita como `/index.html` literal.
En Flutter web **ningún** archivo del build lleva hash en el nombre: el
versionado lo hace el service worker, no la URL, así que marcar algo como
`immutable` es mentirle al navegador. Ahora todo va con `no-cache`, que no
significa "no cachear" sino "revalidar antes de usar": se siguen recibiendo 304
y el service worker sirve igual desde Cache Storage.

**Los `*.g.dart` están gitignoreados.** Cualquier clone o CI necesita correr
`dart run build_runner build --delete-conflicting-outputs` antes de analizar o
testear.

**Riverpod le saca el sufijo `Notifier` al provider generado.** `ScanNotifier`
genera `scanProvider`, no `scanNotifierProvider`.

**Cuidado con `\$` al editar con heredocs.** En Dart `'\$'` es un escape válido,
así que `'\${variable}'` y `'\$variable'` compilan perfecto y muestran el texto
literal en pantalla. El analyzer no lo detecta.

Ya pasó **tres** veces: en el prompt de la IA, en los avisos del dashboard, y en
`MerchantTotal.signature`, donde devolvía la misma constante para todos los
comercios y por eso los insights nunca se regeneraban.

El grep que teníamos anotado **no detectaba la tercera forma**, porque solo
buscaba `\${`. El bueno es:

```bash
grep -rnE '\\\$[a-zA-Z_{]' lib --include="*.dart" | grep -v "g.dart"
```

Un `\$` seguido de un espacio o de otro `$` es correcto (imprimir un signo de
peso). Seguido de una letra o de `{`, casi siempre es el bug.

**`flutter analyze` sin excluir `build/`** devuelve miles de errores ajenos.
Ya está excluido en `analysis_options.yaml`.

---

## Comandos

```bash
# desarrollo
dart run build_runner build --delete-conflicting-outputs
flutter analyze lib test --no-fatal-infos
flutter test
flutter run -d chrome --web-port=5000

# deploy (el CI lo hace solo en push a main, si está el secret)
flutter build web --release
firebase deploy --only hosting --project mborba-proyect
firebase deploy --only firestore:rules,firestore:indexes --project mborba-proyect
```

## Infraestructura: qué hay y qué no

**Firebase Hosting es el único hosting, y alcanza.** Sirve la app con CDN,
HTTPS y dominio, gratis. Vercel, Netlify o similares serían un segundo lugar
donde desplegar lo mismo: otra cuenta que mantener y dos versiones que pueden
quedar desincronizadas. No suman nada acá.

**El deploy automático anda.** El secret `FIREBASE_SERVICE_ACCOUNT` está
puesto y el job "Web a Firebase Hosting" pasa en cada push a `main`. No hace
falta desplegar a mano.

**El job del APK se sacó** (2026-09-05). Fallaba siempre y solo se usa la web.
Un job permanentemente en rojo entrena a ignorar el CI: cuando todo está en
rojo, un rojo nuevo no dice nada. La config de Android quedó arreglada, así que
volver a agregarlo es recuperar el job del historial.

## Pendientes de infraestructura

- **Rotar el client secret de OAuth** que estuvo suelto en el directorio del
  repo (`client_secret_*.json`, ya gitignoreado).
- **Firebase Storage está sin activar.** No hace falta mientras se use la
  miniatura.
