# Caja y saldo a favor · Fase 2 preparada en aislamiento

Fecha local: 4 de noviembre de 2026. Estado: motor de base implementado y probado localmente. No publicado, no importado ni activado en Supabase. Interfaz productiva sin cambios por esta tarea.

## Decisiones del usuario sobre los ingresos manuales

| Movimiento | Interpretación confirmada | Tratamiento al futuro corte |
|---|---|---|
| MOV-b56fbddb-e1eb-4376-96c1-df1f786ec1ac · $1.000 · 26/10 | Prueba de Gonzalo Diogenes | Conservar original y contrasiento existente. No generar crédito clínico. |
| MOV-69c21c72-3972-4294-a2d2-600a50f5b883 · $1 · 01/11 | Prueba de Gonzalo Diogenes | Conservar en Caja. No generar crédito clínico ni anular sin otra instrucción. |
| MOV-fecd8747-bfa4-43e0-81f9-56d5a336fc95 · $40.000 · GIMNASIO X 3 | Saldo del paciente Carlos Ducasse | Vincular el ingreso original a su cuenta, sin insertar otro ingreso en Caja. |

La última lectura de producción encontró 53 movimientos, los mismos tres ingresos manuales con paciente y $126.000 disponibles en anticipos. El saldo disponible previsto al corte es $166.000, sujeto a repetir el control con datos actualizados. No es el total cobrado histórico: los pagos aplicados a sesiones, cuotas y bonos siguen aplicados y no se convierten además en crédito libre.

## Qué quedó implementado

- Ledger inmutable de fuentes, aplicaciones, reversos y devoluciones. Saldo derivado de eventos, con límites por fuente, paciente y deuda.
- Aplicación parcial por antigüedad entre sesiones PRESENTES, cuotas existentes y bonos ACTIVOS; fuentes y deudas con orden estable. Saldo global del paciente, sin restricciones antiguas de sede, terapia o profesional.
- Un ingreso físico de Caja al recibir dinero. Aplicaciones y reintegros internos sin nuevos ingresos ni egresos físicos.
- Vista previa calculada por el servidor, huella del reparto y versión de cuenta; rechazo de confirmaciones obsoletas. Reintentos con la misma solicitud conservan el resultado; cambiar el contenido de una clave ya usada se rechaza.
- Egresos: pago a profesional, devolución de saldo, reintegro de sesión, gasto general y otro. Pago a profesional exige profesional y terapia activos y compatibles. Otro exige concepto/motivo.
- Reintegro de sesión: libera únicamente el pago neto recuperable y bonifica el cargo restante, conserva PRESENTE y deja la sesión sin deuda. No aplica inmediatamente lo liberado a otras deudas.
- ADMIN puede revisar y anular un ingreso sin devoluciones previas. Se revierten sus aplicaciones, reabren deudas y se crea un único contrasiento que conserva las asociaciones del original. Secretaría no puede ejecutar esta anulación.
- Marcar PRESENTE, crear una cuota o un bono aplica saldo automáticamente. Salir de PRESENTE o anular un bono libera sus aplicaciones, sin mover Caja.
- Lecturas existentes adaptadas a pagos del ledger y cargos netos. Las bonificaciones no se presentan como pagos ficticios. Ortopedia conserva su circuito independiente.
- Los comandos antiguos de cobro se bloquean solamente si se activa el circuito nuevo. Se impide consumir nuevamente anticipos ya convertidos. La configuración queda apagada al instalar.
- RLS en las ocho tablas nuevas, funciones internas privadas y RPC con control de usuario activo. Importación sin RPC público: solo operación interna supervisada.

## Conversión y conciliación

`marathon.saldo_importacion_prever()` solo lee. Devuelve huella de datos, bloqueos, saldos y deudas previstos por paciente, y totales de Caja por fecha, medio, sede y origen.

`marathon.saldo_importar(request_id, huella)` rechaza cambios desde la prueba en seco y cualquier caso no cubierto. En una transacción crea representaciones del ingreso y sus aplicaciones históricas, conserva los originales y sus actores en las tablas existentes y registra el lote de importación. No aplica remanentes a otras deudas. Compara saldo, deuda y Caja antes de terminar; una diferencia revierte toda la importación. No activa el circuito.

Los pagos importados sustituyen su representación antigua para el cálculo nuevo, evitando sumarlos dos veces. Los bonos pagados continúan aplicados a su bono. El importador actual admite el patrón observado: cobros históricos positivos, anticipos con un depósito y aplicaciones, sin reintegros clínicos previos. Si aparecen reintegros, anticipos con otra estructura, cobros sobre deuda inactiva o nuevos ingresos manuales sin clasificar, se detiene y exige revisión; no los interpreta automáticamente.

`supabase/tests/saldo_conciliar.sql` permite volver a comparar el lote. Antes de activar debe informar lote encontrado, Caja igual, diferencias vacías, fuentes sin saldo negativo y circuito apagado. Se ejecuta antes de nuevas operaciones del circuito.

## Pruebas y evidencia

Se usó PostgreSQL 18 en localhost:55439. Bases exclusivas de esta tarea: marathon_saldo_impl_20261104 y marathon_saldo_restauracion_20261104. La segunda se creó desde un esquema vacío de datos y recibió todas las migraciones de saldo en orden. Los fixtures son sintéticos y se revierten con ROLLBACK. La prueba concurrente crea y elimina únicamente una base temporal propia.

Ejecutar `python supabase/tests/verificar_saldo_local.py`. Evidencia completa: RESULTADO_PRUEBAS.json.

Pruebas: ingreso parcial/exacto/con sobrante/sin deuda; orden mixto de cuota, bono y sesiones; fracción de centavo rechazada; vista previa vencida; idempotencia; pago a profesional; reintegro total/parcial; anulación y bloqueo luego de devolución; PRESENTE repetido y salida a AUSENTE; cuota y bono automáticos; inmutabilidad; permisos de Secretaría y acceso anónimo/inactivo; importación sin duplicar Caja ni crédito de bonos; huella y conciliación; dos conexiones con reintento de ingreso y devoluciones simultáneas.

Las funciones de referencia se cotejaron de nuevo contra producción mediante sus huellas: ninguna de las 138 funciones leídas cambió durante la preparación. La auditoría remota fue de lectura; los controles de las nuevas tablas y permisos se verificaron en la instalación local, porque aún no existen en producción.

## Decisiones de implementación para revisar

1. Se rechaza dinero con más de dos decimales. Se usa numeric, sin redondear diferencias de conciliación.
2. No se barren saldos históricos durante la conversión: el saldo disponible y las deudas deben coincidir exactamente antes y después. La siguiente operación válida aplica el saldo según las reglas nuevas.
3. La generación de cuotas se separa de consultas de ficha y grilla mientras el circuito nuevo esté activo. Se agregó `marathon_saldo_preparar()` como operación explícita para usuarios autenticados. La Fase 3 debe darle un acceso visible antes de revisar cobros. El proceso programado conserva materialización de turnos y ausencias; sin usuario no genera cuotas con efectos financieros. Así no se atribuyen aplicaciones automáticas a una secretaria que no las ejecutó.
4. La atribución original permanece en los movimientos históricos. Los eventos importados identifican al administrador que realiza la importación y enlazan a esos originales. No se cambia la fecha original de Caja.
5. Los nuevos movimientos usan subtipo explícito; no se deduce la clasificación de históricos a partir de textos como “anticipo”.

## Antes de producción

Falta Fase 3: formulario único, selección de paciente, accesos desde ficha/turnos/cuotas/bonos, vista previa, historial y verificación del flujo completo desde el navegador. La interfaz productiva continúa usando el circuito anterior.

Falta Fase 4: manual de secretarías y documentación final de publicación. Además se debe obtener y verificar mediante restauración un respaldo completo de la base real, ejecutar una prueba en seco sobre el corte real, revisar casos nuevos y aprobar el plan de conversión. La restauración del esquema local con datos sintéticos NO equivale a ese respaldo completo.

No ejecutar en producción por copiar la carpeta o publicar public/. Las migraciones se prepararon para revisión. No activar saldo_config ni importar hasta completar los puntos anteriores. Una vez activo y con operaciones nuevas no corresponde “volver atrás” borrando el ledger ni restaurando un respaldo antiguo sobre datos posteriores; cualquier reversión operativa necesita conciliación y conservar todo el historial.

## Archivos de esta entrega

- supabase/migrations/*caja_saldo*.sql: estructura, motor, eventos, integración, controles, importación, consultas, cierre, permisos y trazabilidad. Se agregaron migraciones nuevas; se conservó el borrador de estructura previo.
- supabase/tests/saldo_*: fixtures, suites SQL, concurrencia y conciliación. `saldo_reconstruir_local.sql` se limita por nombre y ausencia de pacientes a la base vacía de QA; no es una migración productiva.
- supabase/tests/verificar_saldo_local.py: ejecutor de pruebas y auditoría local.
- supabase/tests/preparar_integracion_saldo.py y preparar_consultas_saldo.py: preparación local de adaptaciones desde las funciones vigentes leídas. No se ejecutan al publicar.
- Esta carpeta: referencia de funciones y restricciones, esquema local sin datos, informe de pruebas y entrega. Los archivos de referencia no son una reconstrucción completa de Supabase.

La Fase 3 requiere el OK entre fases pedido en PROMPT_modulo_caja_saldo_a_favor.md. La autorización para desarrollar no se tomó como autorización para migrar dinero real.
