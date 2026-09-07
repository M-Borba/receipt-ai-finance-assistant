# Verificar las reglas

**Ya no es manual.** Los 25 casos corren solos contra el motor real de Firebase:

```bash
gcloud auth login          # una sola vez
python3 tool/verificar_reglas.py
```

Devuelve 0 si todo pasa. Corrélo **cada vez que toques `firestore.rules`**, y
antes de mandarle un link de invitación a alguien.

## Cómo funciona, y por qué no hace falta el emulador

Usa el endpoint `TestRuleset` de la Security Rules API, que es **el mismo motor
que corre en producción** y el mismo que usa el Rules Playground de la consola.
Corre del lado del servidor.

Eso evita el emulador, que pide Java 11+ (acá hay Java 8) y
`@firebase/rules-unit-testing`, que existe solo para JS y metería Node en un
repo Dart puro. El script es Python de la biblioteca estándar: cero
dependencias nuevas.

## Una trampa que ya mordió: el verde vacío

Un caso `DENY` puede pasar **por la razón equivocada**: si la ruta no matchea
ningún bloque `match`, cae en el `allow read, write: if false` del final y
deniega sin haber probado nada.

Pasó de verdad al escribir esto. Los casos de `list` usaban la ruta de la
colección (`/groups/g1/expenses`), que no matchea `match .../expenses/{id}`
porque le falta un segmento. Cuatro casos daban verde sin ejercitar una sola
línea de la regla que querían probar.

Por eso el script mira **qué expresiones visitó** cada caso y marca `VACIO` si
todas caen en la línea del deny-by-default.

## Qué cubre

- **14 casos de lo que alguien de afuera NO puede hacer**: leer un grupo ajeno,
  listar grupos, leer o listar gastos ajenos, agregarse sin token, con un token
  inventado, vencido o de otro grupo, meter a un tercero de paso, cambiarle el
  nombre al grupo al entrar, leer tickets ajenos, robar uno cambiando el
  `userId`, enumerar invitaciones, y entrar sin login.
- **11 casos de lo que sí tiene que funcionar**: leer el propio grupo, listar
  gastos **sin filtro** (el cambio de este release), crear gastos e
  invitaciones, entrar con un token válido, y borrar la propia miniatura.

## Límite conocido, verificado

**Borrar una miniatura que no existe se deniega**, y no se puede arreglar en las
reglas: tocar `resource` cuando es null aborta la evaluación, y una evaluación
abortada deniega. Se probaron `resource == null`, `!(resource != null)` y
`resource.data == null`: las tres abortan.

Por eso el borrado de la miniatura no va en el batch atómico del ticket. Si
fuera parte del batch, un ticket cuya miniatura nunca se pudo generar quedaría
imposible de borrar para siempre.

## Lo que sigue sin cubrirse

- Que un miembro escriba un reparto que no cierra. Las reglas **no pueden**
  validarlo: el lenguaje no suma los valores de un mapa. Lo valida el cliente y
  la UI marca los gastos descuadrados.
- Sacar a alguien de un grupo: no existe todavía.
- Un link robado. El token **es** la credencial: quien lo tiene, entra. Por eso
  vence a los 7 días.

## La prueba de punta a punta

El script verifica reglas, no el flujo. Una vez, antes de invitar a alguien:

1. Creá un grupo y un link.
2. Abrí el link en **incógnito** con **otra cuenta**.
3. Tiene que ver el nombre, poder entrar, y **ver los gastos que ya estaban
   cargados** (no solo los nuevos). Es lo que se rompía con el diseño anterior,
   donde el gasto llevaba una copia de `memberIds` que quedaba vieja.
4. Cargá un gasto entre los dos y confirmá que los saldos dan igual en las dos
   cuentas.
