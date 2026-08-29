# Grupos y división de gastos

Documento de diseño. **La fase 1 está implementada y desplegada** (2026-08-29);
las fases 2 y 3 siguen siendo diseño.

## Decisiones tomadas

| Tema | Decisión | Por qué |
|---|---|---|
| Plan de Firebase | **Spark (gratis)** | Todo lo necesario se puede hacer con reglas. Blaze solo hacía falta para Storage y Functions, y ninguno de los dos es imprescindible. |
| Imágenes de tickets | **No se guardan en la v1** | Storage pide Blaze en proyectos nuevos. El valor está en los datos extraídos, no en la foto. |
| Invitaciones | **Link con token**, validado por reglas | Sin Cloud Functions. Cuesta una lectura por persona que se une. |
| Proxy de IA | **Cloudflare Workers** | Gratis, sin tarjeta, 100k requests/día. |
| Moneda | **Una por grupo**, fija al crear | Multi-moneda es un pozo sin fondo: qué cotización, de qué fecha, qué pasa si cambia. |
| Representación de plata | **Enteros (centavos)** | `0.1 + 0.2 != 0.3`. En un libro de deudas los errores se acumulan y la gente los ve. |
| Balances | **Derivados del libro**, nunca guardados como estado mutable | Dos clientes escribiendo un balance se pisan. |

## El problema de seguridad

El modelo actual es de un dueño por documento: `request.auth.uid == resource.data.userId`.
Un gasto compartido **no tiene un dueño**. Esta es la decisión más importante del feature.

Solución elegida: **desnormalizar `memberIds` en cada documento del grupo**.

```javascript
allow read: if request.auth.uid in resource.data.memberIds;
```

Rápido y gratis. El costo es mantener el array sincronizado cuando alguien entra o sale.
La alternativa (`get()` del grupo dentro de la regla) es más limpia pero cobra una lectura
por cada evaluación de regla.

## Modelo de datos

```
groups/{groupId}
  name, currency, minorUnitFactor, createdBy, archived
  memberIds: [uid, ...]              <- para las reglas
  members: { uid: {displayName, photoUrl, joinedAt} }

groups/{groupId}/expenses/{expenseId}
  description, amountCents, date, splitMode
  paidBy: { uid: cents }             <- soporta que paguen varios
  shares:  { uid: cents }            <- ya resuelto, suma exacta a amountCents
  memberIds: [uid, ...]              <- copia para las reglas
  receiptId?                         <- enlaza al ticket escaneado
  createdBy, createdAt, editedAt

groups/{groupId}/settlements/{id}
  fromUid, toUid, amountCents, date, note

invites/{token}
  groupId, createdBy, expiresAt, maxUses, uses
```

`shares` se guarda **ya calculado**, no el modo con sus parámetros. Así el histórico no se
mueve si mañana cambia el algoritmo.

## Modos de reparto

| Modo | Cuándo | UI |
|---|---|---|
| Iguales | el 80% de los casos | un tap |
| **Partes** | alguien consumió más | `+`/`-` por persona |
| Porcentajes | control fino | resto en vivo, no deja guardar si no cierra |
| Montos exactos | ya sabés el número de cada uno | resto en vivo |

**Partes es el modo recomendado** para el caso "yo consumí más". `yo: 4, Juan: 1, Ana: 1`
equivale a 2/3 + 1/6 + 1/6 sin que nadie calcule fracciones, y no necesita sumar 100.

## Algoritmo 1: repartir sin perder centavos

Dividir 100 entre 3 da 33,33 y tres veces eso es 99,99. Si se ignora, el grupo nunca
cierra en cero. Se resuelve con el **método del resto mayor**.

```dart
/// Reparte [totalCents] en proporcion a [weights].
/// La suma del resultado es SIEMPRE exactamente totalCents.
List<int> splitLargestRemainder(int totalCents, List<int> weights) {
  final totalWeight = weights.reduce((a, b) => a + b);
  final base = <int>[];
  final remainders = <({int index, int rem})>[];

  var assigned = 0;
  for (var i = 0; i < weights.length; i++) {
    final exact = totalCents * weights[i];
    final share = exact ~/ totalWeight;
    base.add(share);
    assigned += share;
    remainders.add((index: i, rem: exact % totalWeight));
  }

  // Los centavos que faltan van a los restos mas grandes.
  // Desempate por indice: determinista en todos los dispositivos.
  remainders.sort((a, b) {
    final c = b.rem.compareTo(a.rem);
    return c != 0 ? c : a.index.compareTo(b.index);
  });

  final leftover = totalCents - assigned;
  for (var k = 0; k < leftover; k++) {
    base[remainders[k % remainders.length].index] += 1;
  }
  return base;
}
```

Invariante para los tests: `resultado.sum == totalCents`, para cualquier total y cualquier
combinación de pesos.

## Algoritmo 2: liquidar (quién le paga a quién)

Balance neto por persona: `pagó - le correspondía`. La suma de todos es cero, siempre.

Encontrar el mínimo real de transferencias es **NP-hard** (se reduce a partición de
subconjuntos). Splitwise no lo resuelve exacto: usa un **greedy** que empareja al mayor
acreedor con el mayor deudor. Garantiza a lo sumo n-1 transferencias.

```dart
List<Transfer> settle(Map<String, int> balanceCents) {
  final creditors = <(String, int)>[];
  final debtors = <(String, int)>[];

  balanceCents.forEach((uid, cents) {
    if (cents > 0) creditors.add((uid, cents));
    if (cents < 0) debtors.add((uid, -cents));
  });

  // Desempate por uid: determinista en todos los dispositivos.
  int byAmount((String, int) a, (String, int) b) {
    final c = b.$2.compareTo(a.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  }
  creditors.sort(byAmount);
  debtors.sort(byAmount);

  final transfers = <Transfer>[];
  var i = 0, j = 0;
  var credit = creditors.isEmpty ? 0 : creditors[0].$2;
  var debt = debtors.isEmpty ? 0 : debtors[0].$2;

  while (i < creditors.length && j < debtors.length) {
    final amount = credit < debt ? credit : debt;
    transfers.add(Transfer(from: debtors[j].$1, to: creditors[i].$1, cents: amount));
    credit -= amount;
    debt -= amount;
    // Cada iteracion deja al menos a uno en cero: de ahi el limite de n-1.
    if (credit == 0 && ++i < creditors.length) credit = creditors[i].$2;
    if (debt == 0 && ++j < debtors.length) debt = debtors[j].$2;
  }
  return transfers;
}
```

**Detalle de producto más importante que el algoritmo:** Splitwise tiene la simplificación
apagada por defecto, porque a la gente le resulta rarísimo que le digan "pagale a Ana"
cuando nunca gastó nada con Ana. Hay que derivar las dos vistas del mismo libro (de a pares
y simplificada) y ofrecer un switch.

## Reglas de Firestore para el link de invitación

```javascript
function soloMeAgregoAMi() {
  return request.resource.data.memberIds.hasAll(resource.data.memberIds)
    && request.resource.data.memberIds.size() == resource.data.memberIds.size() + 1
    && request.auth.uid in request.resource.data.memberIds
    && !(request.auth.uid in resource.data.memberIds);
}

function inviteValido(token, groupId) {
  let inv = get(/databases/$(database)/documents/invites/$(token)).data;
  return inv.groupId == groupId && inv.expiresAt > request.time;
}
```

El token del link **es** la credencial: quien lo tiene, entra. Por eso conviene que expire.

## Partes difíciles, por orden de dolor

1. **Editar un gasto ya liquidado.** Cambia balances hacia atrás. Salida sana: generar un
   asiento de ajuste en vez de mutar el original.
2. **Salir de un grupo con deuda abierta.** Regla de producto: no se puede salir sin estar
   en cero, o queda como miembro inactivo.
3. **Multi-moneda.** Explícitamente fuera de alcance.

## Fases

**Fase 1. HECHA** (2026-08-29). Grupos, división en partes iguales y por partes, balances
de a pares, sin simplificación. Código en `lib/features/groups/`, 31 tests de la lógica de
plata en `test/features/groups/`.

Lo que salió distinto del diseño: **las escrituras de gastos sí hacen `get()` del grupo.**
El diseño decía usar la copia desnormalizada de `memberIds` en todos lados para no pagar
lecturas, pero con eso cualquiera podía crear un gasto en un grupo ajeno declarándose
miembro en su propia copia, y no había forma de detectarlo. Leer sigue usando la copia
(camino caliente, gratis); escribir verifica contra el grupo de verdad (raro, una lectura).

Falta de la fase 1: **invitar gente**. El grupo se crea con una sola persona y las reglas
prohíben cambiar `memberIds`. Es deliberado: el link de invitación es justo la parte que
expone datos a terceros, y necesita los tests de reglas primero.

**Fase 2.** Settle up con el greedy, switch de simplificación, registro de pagos.

**Fase 3, la que importa.** La app ya extrae **los ítems con sus precios** del ticket. Eso
habilita **asignación por ítem**: "la cerveza la tomamos Juan y yo, la ensalada fue de Ana,
la propina se divide". Splitwise no puede hacer esto porque nunca ve los ítems.

Las fases 1 y 2 nos ponen a la par de Splitwise. La 3 es lo que no pueden copiar. Si el
objetivo es diferenciación, la fase 3 no es un extra: es el producto.

## Prerrequisito bloqueante: tests de las reglas

**Antes de que grupos llegue a manos de otra persona, hay que tener tests de las
reglas de Firestore corriendo contra el emulador.**

Hoy no existen y se decidió posponerlos: mientras la app tiene un solo usuario y
las reglas filtran por `userId`, equivocarse solo expone tus propios datos. Con
grupos eso cambia: hay gente ajena leyendo documentos compartidos, y un error de
reglas expone los gastos de otro.

Qué implica montarlos:
- `firebase emulators:exec --only firestore` (el emulador es un JAR: necesita Java 11+)
- `@firebase/rules-unit-testing`, que existe solo para JS, así que suma Node al repo
- dos pasos más en el CI

Casos mínimos a cubrir: leer el documento de otro usuario, cambiar el `userId` en
un update, listar sin filtrar, escribir en una colección no declarada, y con
grupos: leer un grupo del que no sos miembro, agregarte a un grupo sin invite
válido, agregar a otro que no seas vos.

## Deuda previa: PAGADA

~~La app usa `double` para toda la plata.~~ **Hecho el 2026-08-29.** Toda la
plata es `int` de centavos: `amountCents`, `totalCents`, `unitPriceCents`,
`totalPriceCents`. Los documentos viejos con `double` se convierten al leer.

El prerrequisito de la Fase 1 ya está cumplido. Lo que sigue bloqueando el
lanzamiento a otras personas son los tests de reglas, arriba.
