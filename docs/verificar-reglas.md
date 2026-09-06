# Verificar las reglas antes de invitar a alguien

**Hacé esto antes de mandarle un link de invitación a otra persona.** Diez
minutos. Hasta ahora, equivocarse en una regla solo exponía tus propios datos;
con alguien más en un grupo, un error le muestra tus gastos o le esconde los
suyos.

No es un reemplazo de los tests automáticos contra el emulador, que siguen
pendientes. Es lo que se puede hacer sin sumar Java y Node a un repo Dart, y
cubre los casos que importan.

## Dónde

Firebase Console → Firestore Database → **Reglas** → pestaña **Playground**.

Necesitás dos `uid`: el tuyo (`A`) y uno inventado que no exista en ningún
grupo (`B`, poné cualquier string). Y el id de un grupo tuyo, que sale de la
URL cuando lo abrís: `/groups/<ese-id>`.

## Los casos

Cada fila: qué simular, y qué **tiene** que pasar. Si alguno da distinto, no
mandes el link y avisá.

### Lo que B no debe poder hacer

| # | Operación | Ruta | Auth | Esperado |
|---|---|---|---|---|
| 1 | get | `groups/{grupoId}` | B | **Denegado** |
| 2 | list | `groups` | B | **Denegado** |
| 3 | get | `groups/{grupoId}/expenses/{cualquiera}` | B | **Denegado** |
| 4 | list | `groups/{grupoId}/expenses` | B | **Denegado** |
| 5 | update | `groups/{grupoId}` agregando a B en `memberIds` **sin** `inviteToken` | B | **Denegado** |
| 6 | update | `groups/{grupoId}` con `inviteToken` inventado | B | **Denegado** |
| 7 | list | `invites` | B | **Denegado** |
| 8 | get | `receipts/{tuTicketId}` | B | **Denegado** |
| 9 | update | `receipts/{tuTicketId}` cambiando `userId` a B | B | **Denegado** |

El 5 y el 6 son los que habilita esta versión, y los más importantes.

### Lo que A sí debe poder hacer

| # | Operación | Ruta | Auth | Esperado |
|---|---|---|---|---|
| 10 | list | `groups` con filtro `memberIds arrayContains A` | A | **Permitido** |
| 11 | list | `groups/{grupoId}/expenses` **sin ningún filtro** | A | **Permitido** |
| 12 | create | `invites/{token}` con `groupId` del grupo y `expiresAt` futuro | A | **Permitido** |
| 13 | create | `invites/{token}` con `expiresAt` en el pasado | A | **Denegado** |

El 11 confirma el cambio de este release: la lectura de gastos ya no necesita
filtro porque autoriza mirando el grupo padre.

### El caso que hay que probar de verdad

El Playground no encadena operaciones, así que el flujo completo de entrar a un
grupo se prueba en la app:

1. Con tu cuenta, creá un grupo y un link.
2. Abrí el link en una **ventana de incógnito** y entrá con **otra cuenta**.
3. Tiene que ver el nombre del grupo, poder entrar, y **ver los gastos que ya
   estaban cargados** (no solo los nuevos).
4. Volvé a tu ventana: la otra persona tiene que aparecer en el grupo.
5. Cargá un gasto dividido entre los dos y confirmá que los saldos dan lo
   mismo en las dos cuentas.

El punto 3 es el que más vale: es exactamente lo que se rompía con el diseño
anterior, donde el gasto llevaba una copia de `memberIds` que quedaba vieja al
sumarse alguien.

## Lo que sigue sin estar cubierto

- Que un miembro escriba un reparto que no cierra. Las reglas **no pueden**
  validarlo: el lenguaje no suma los valores de un mapa. Lo valida el cliente y
  la UI marca los gastos descuadrados.
- Sacar a alguien de un grupo. No existe todavía.
- Un link robado. El token **es** la credencial: quien lo tiene, entra. Por eso
  vence a los 7 días.
