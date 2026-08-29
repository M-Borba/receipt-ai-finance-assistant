# Fixtures de OCR

Salida literal de un motor de OCR sobre fotos de e-Ticket uruguayos reales.
Los otros tests del parser usan texto escrito a mano; estos no, y por eso
encontraron cosas que aquellos no podian encontrar.

## Como se generaron

Con Apple Vision (`VNRecognizeTextRequest`, `es-ES`, sin correccion de
lenguaje), ordenando los bloques por posicion vertical para aproximar el orden
de lectura de ML Kit. Las fotos originales **no estan versionadas**: ver
`.gitignore`.

Para regenerar desde una foto nueva hay que volver a armar la herramienta; el
script de Swift no se guardo porque no forma parte del build. Lo importante es
que el fixture sea salida real de un OCR, no texto tipeado a mano.

## Redaccion

Se cambiaron, respetando el largo y la forma para que los tests sigan valiendo:

- numero de CAE y codigo de seguridad (juntos permiten levantar el comprobante
  real en el sitio de DGI)
- numero de serie del e-Ticket
- RUT del comercio
- la cuenta bancaria que la panaderia imprime en el pie
- codigo de cliente y documento interno

Los productos, importes, fechas y totales estan intactos: son lo que se prueba.

## Lo que revelaron

1. **Los e-Ticket de DGI usan punto decimal y coma de miles** (`1,056.00`), al
   reves de lo que se asumia para LatAm. El parser resuelve el separador
   mirando el ultimo, asi que aguanta las dos convenciones.
2. **El numero de RUT y el de CAE entraban como productos.** El RUT de la
   carniceria se leia como un item de $219.640.160,11.
3. **Las filas de la tabla de IVA entraban como productos**, con el monto del
   total.
4. **El detalle viene en dos lineas**: el nombre en una y
   `cantidad / unitario / importe` en la siguiente, y no siempre en ese orden.
5. **Los comercios chicos no estan en ninguna lista de cadenas.** Los tres
   clasificaban `null` hasta que el vocabulario de productos crecio con lo que
   realmente dicen estos tickets (`chacinado`, `medialunas`, `malbec`,
   `zillertal`).
