#!/usr/bin/env python3
"""Verifica firestore.rules contra el motor real de Firebase.

Usa el endpoint `TestRuleset` de la Security Rules API, que es **el mismo motor
que corre en produccion** y el mismo que usa el Rules Playground de la consola.
No necesita el emulador (que pide Java 11+, y aca hay Java 8), ni Node, ni
sumar una sola dependencia al repo.

    gcloud auth login          # una vez
    python3 tool/verificar_reglas.py

Devuelve 0 si todo pasa, 1 si algo falla.
"""
import json
import subprocess
import sys
import urllib.request

PROYECTO = "mborba-proyect"
DB = "/databases/(default)/documents"

# A es el dueño; B es alguien de afuera. G1 es un grupo donde A es miembro.
A, B = "uid_A", "uid_B"
G1 = "grupo1"

GRUPO = {
    "name": "Asado",
    "currency": "UYU",
    "createdBy": A,
    "memberIds": [A],
    "members": {A: {"displayName": "A"}},
    "archived": False,
}


def caso(nombre, esperado, metodo, path, auth=None, resource=None,
         data=None, mocks=None):
    req = {"path": DB + path, "method": metodo,
           "time": "2026-09-05T12:00:00Z"}
    req["auth"] = {"uid": auth} if auth else None
    if data is not None:
        req["resource"] = {"data": data}
    tc = {"expectation": esperado, "request": req}
    if resource is not None:
        tc["resource"] = {"data": resource}
    if mocks:
        tc["functionMocks"] = mocks
    return nombre, tc


def mock_grupo(datos=GRUPO):
    """Simula el get() del grupo que hacen las reglas."""
    return [{
        "function": "get",
        "args": [{"anyValue": {}}],
        "result": {"value": {"data": datos}},
    }]


def mock_invite(group_id=G1, vencido=False, existe=True, token="tok"):
    ruta = {"anyValue": {}}
    inv = {
        "groupId": group_id,
        "expiresAt": "2020-01-01T00:00:00Z" if vencido
                     else "2030-01-01T00:00:00Z",
    }
    return [
        {"function": "exists", "args": [ruta],
         "result": {"value": existe}},
        {"function": "get", "args": [ruta],
         "result": {"value": {"data": inv}}},
    ]


def con_token(base, token="tok"):
    """El grupo tal como queda tras sumarse B, con el token para la regla."""
    d = dict(base)
    d["memberIds"] = base["memberIds"] + [B]
    d["members"] = {**base["members"], B: {"displayName": "B"}}
    d["inviteToken"] = token
    return d


CASOS = [
    # --- Lo que B NO debe poder hacer ---
    caso("1  B no lee un grupo ajeno", "DENY", "get",
         f"/groups/{G1}", auth=B, resource=GRUPO),
    caso("2  B no lista grupos", "DENY", "list", "/groups/g9", auth=B),
    caso("3  B no lee un gasto de un grupo ajeno", "DENY", "get",
         f"/groups/{G1}/expenses/e1", auth=B, mocks=mock_grupo()),
    caso("4  B no lista gastos de un grupo ajeno", "DENY", "list",
         f"/groups/{G1}/expenses/e9", auth=B, mocks=mock_grupo()),
    caso("5  B no se agrega SIN token", "DENY", "update",
         f"/groups/{G1}", auth=B, resource=GRUPO,
         data={**GRUPO, "memberIds": [A, B],
               "members": {**GRUPO["members"], B: {"displayName": "B"}}}),
    caso("6  B no se agrega con un token inventado", "DENY", "update",
         f"/groups/{G1}", auth=B, resource=GRUPO, data=con_token(GRUPO),
         mocks=mock_invite(existe=False)),
    caso("7  B no se agrega con un token VENCIDO", "DENY", "update",
         f"/groups/{G1}", auth=B, resource=GRUPO, data=con_token(GRUPO),
         mocks=mock_invite(vencido=True)),
    caso("8  B no se agrega con un token de OTRO grupo", "DENY", "update",
         f"/groups/{G1}", auth=B, resource=GRUPO, data=con_token(GRUPO),
         mocks=mock_invite(group_id="otro")),
    caso("9  B no mete a un tercero de paso", "DENY", "update",
         f"/groups/{G1}", auth=B, resource=GRUPO,
         data={**GRUPO, "memberIds": [A, B, "uid_C"],
               "members": {**GRUPO["members"], B: {"displayName": "B"},
                           "uid_C": {"displayName": "C"}},
               "inviteToken": "tok"},
         mocks=mock_invite()),
    caso("10 B no le cambia el nombre al grupo al entrar", "DENY", "update",
         f"/groups/{G1}", auth=B, resource=GRUPO,
         data={**con_token(GRUPO), "name": "Robado"},
         mocks=mock_invite()),
    caso("11 B no lee tickets ajenos", "DENY", "get",
         "/receipts/r1", auth=B, resource={"userId": A, "totalCents": 100}),
    caso("12 B no roba un ticket cambiando el userId", "DENY", "update",
         "/receipts/r1", auth=B, resource={"userId": A, "totalCents": 100},
         data={"userId": B, "totalCents": 100}),
    caso("13 nadie enumera invitaciones", "DENY", "list",
         "/invites/t9", auth=B),
    caso("14 sin login no se lee nada", "DENY", "get",
         f"/groups/{G1}", resource=GRUPO),

    # --- Lo que SI tiene que funcionar ---
    caso("15 A lee su grupo", "ALLOW", "get",
         f"/groups/{G1}", auth=A, resource=GRUPO),
    caso("16 A lista gastos SIN filtro", "ALLOW", "list",
         f"/groups/{G1}/expenses/e9", auth=A, mocks=mock_grupo()),
    caso("17 A crea un gasto en su grupo", "ALLOW", "create",
         f"/groups/{G1}/expenses/e2", auth=A, mocks=mock_grupo(),
         data={"createdBy": A, "amountCents": 10000,
               "date": "2026-08-30T00:00:00Z"}),
    caso("18 B NO crea un gasto en un grupo ajeno", "DENY", "create",
         f"/groups/{G1}/expenses/e3", auth=B, mocks=mock_grupo(),
         data={"createdBy": B, "amountCents": 10000,
               "date": "2026-08-30T00:00:00Z"}),
    caso("19 B SI se agrega con un token valido", "ALLOW", "update",
         f"/groups/{G1}", auth=B, resource=GRUPO, data=con_token(GRUPO),
         mocks=mock_invite()),
    caso("20 A crea una invitacion a su grupo", "ALLOW", "create",
         "/invites/tok2", auth=A, mocks=mock_grupo(),
         data={"groupId": G1, "createdBy": A,
               "expiresAt": "2030-01-01T00:00:00Z"}),
    caso("21 A no crea una invitacion ya vencida", "DENY", "create",
         "/invites/tok3", auth=A, mocks=mock_grupo(),
         data={"groupId": G1, "createdBy": A,
               "expiresAt": "2020-01-01T00:00:00Z"}),
    caso("22 B no crea invitaciones a un grupo ajeno", "DENY", "create",
         "/invites/tok4", auth=B, mocks=mock_grupo(),
         data={"groupId": G1, "createdBy": B,
               "expiresAt": "2030-01-01T00:00:00Z"}),
    caso("23 A borra SU miniatura", "ALLOW", "delete",
         "/receipts/r1/media/thumb", auth=A, resource={"userId": A}),
    caso("24 B no borra la miniatura de A", "DENY", "delete",
         "/receipts/r1/media/thumb", auth=B, resource={"userId": A}),
    # Borrar un documento que NO existe se deniega, y no se puede arreglar en
    # las reglas: tocar `resource` cuando es null aborta la evaluacion, y una
    # evaluacion abortada deniega. Se probaron `resource == null`,
    # `!(resource != null)` y `resource.data == null`: las tres abortan.
    # Por eso el cliente NO mete ese borrado en el batch atomico.
    caso("25 borrar una miniatura inexistente se deniega (limite conocido)",
         "DENY", "delete", "/receipts/r9/media/thumb", auth=A),
]


def main():
    token = subprocess.run(["gcloud", "auth", "print-access-token"],
                           capture_output=True, text=True).stdout.strip()
    if not token:
        print("No hay token. Corré: gcloud auth login")
        return 2

    with open("firestore.rules", encoding="utf-8") as f:
        reglas = f.read()

    # La linea del deny-by-default: un DENY que solo la visita no prueba nada.
    linea_catchall = next(
        (i for i, l in enumerate(reglas.split("\n"), 1)
         if "allow read, write: if false" in l), -1)

    body = {
        "source": {"files": [{"name": "firestore.rules", "content": reglas}]},
        "testSuite": {"testCases": [
            {**tc, "expressionReportLevel": "VISITED"} for _, tc in CASOS]},
    }

    req = urllib.request.Request(
        f"https://firebaserules.googleapis.com/v1/projects/{PROYECTO}:test",
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {token}",
            "x-goog-user-project": PROYECTO,
            "Content-Type": "application/json",
        },
    )
    try:
        resp = json.load(urllib.request.urlopen(req))
    except urllib.error.HTTPError as e:
        print("La API rechazó la consulta:")
        print(e.read().decode()[:800])
        return 2

    if "testResults" not in resp:
        print(json.dumps(resp, indent=2)[:800])
        return 2

    fallos = 0
    for (nombre, tc), res in zip(CASOS, resp["testResults"]):
        ok = res.get("state") == "SUCCESS"
        # Un DENY que no visito ninguna expresion de la regla que se quiere
        # probar no prueba nada: cayo en el deny-by-default del final.
        # Se detecta mirando si TODAS las expresiones visitadas estan en la
        # linea del catch-all.
        lineas = {e.get("sourcePosition", {}).get("line")
                  for e in res.get("visitedExpressions", [])}
        vacio = (ok and tc["expectation"] == "DENY"
                 and lineas and lineas <= {linea_catchall})
        marca = "VACIO" if vacio else ("ok  " if ok else "FALLA")
        print(f"{marca} {nombre}")
        if vacio:
            fallos += 1
            print("        no matcheo ninguna regla: el DENY no prueba nada")
        if not ok:
            fallos += 1
            for e in res.get("errorPosition", {}), :
                if e:
                    print(f"        linea {e.get('line')}")
            if res.get("debugMessages"):
                print("        " + "; ".join(res["debugMessages"])[:200])

    print()
    print(f"{len(CASOS) - fallos}/{len(CASOS)} casos correctos")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
