# Caja con saldo a favor — Fase 0

Fecha: 04/11/2026. Estado: lectura terminada; pendiente resolver preguntas y aprobar la Fase 1. No se implementó código, no se creó una migración y no se modificaron datos, dinero, permisos ni la publicación de Vercel.

## Fuente revisada

Se trabajó sobre la instalación vigente en CRM SUPABASE/Ultima version del CRM y el proyecto Supabase zcjlgaociqmzjqlyacoi, en lugar del ZIP anterior al 04/11. Se leyeron el contexto, mapa de archivos, estado actual, api.js, operaciones de Caja, historial y agenda recurrente.

Se consultaron directamente las 41 tablas del esquema marathon con columnas, tipos, restricciones y RLS; las políticas; las funciones solicitadas en el prompt y sus dependencias financieras; las vistas daily_cash, daily_turns, daily_bonus y daily_advance; y todos los triggers de movimientos y turnos. No es necesario pedirle al usuario que ejecute pg_dump para obtener estas definiciones. Las referencias completas se guardan en esta misma carpeta.

Importante: las referencias de esquema y funciones NO son un respaldo restaurable de los datos. Antes de una migración real seguirá haciendo falta un respaldo completo y verificable, además de aprobar el plan.

## Situación confirmada

- Las 41 tablas tienen RLS habilitado. Las cuatro funciones públicas de escritura revisadas se conceden a authenticated; no se observaron concesiones de ejecución a anon/PUBLIC para ellas.
- operation_begin verifica usuario activo, request_id y hash de los datos, exige READ COMMITTED y toma el candado marathon:master-write:v1. touch_row aumenta versión y registra usuario/fecha. Deben conservarse.
- turn_paid suma cobros netos de la sesión y aplicaciones netas de anticipos. advance_apply aplica parcialmente solo a sesiones presentes compatibles por sede, terapia y profesional. Su aplicación no genera otro ingreso de Caja.
- Un cambio de asistencia a PRESENTE aplica anticipos; al salir de PRESENTE libera las aplicaciones. Los cobros directos todavía deben reintegrarse antes de cambiar el estado. Esta diferencia necesita contemplarse en el diseño.
- api.js redirige marathon_patient_account a marathon_agenda_patient_account. Esta última añade deuda mensual y llama a agenda_cuotas_generar: una consulta aparentemente de lectura puede generar cuotas. No se la ejecutó durante esta inspección.
- La cuenta original suma sesiones presentes; la envoltura suma cuotas. El bono se presenta por separado en el historial. La nueva deuda total debe incluir los tres conceptos sin duplicarlos. Ortopedia debe seguir mostrándose por separado, aunque el historial actual también tiene un saldo global que la incluye.
- Las cuotas descuentan tanto pagos como agenda_ajustes. Omitir esos ajustes haría reaparecer deuda bonificada. La generación vigente no crea cuotas por adelantado: fecha debe ser menor o igual a hoy.
- Los CHECK de movimientos distinguen turno, anticipo, bono, cuota y ortopedia. No corresponde retirarlos sin sustituir garantías equivalentes. El nuevo formulario no obliga por sí mismo a eliminar los CHECK actuales: la estrategia se evaluará en el diseño.
- Un bono es actualmente un cargo inicial adicional, con deuda propia y pagos propios. El campo sesiones es informativo; ninguna función revisada descuenta un consumo monetario del bono por cada presente.

## Fotografía financiera de lectura

Los valores corresponden a la inspección del 04/11; deben recalcularse al hacer la futura prueba en seco y al ejecutar la migración, porque la app continúa en uso.

| Concepto | Valor |
|---|---:|
| Pacientes | 316 |
| Turnos | 926 |
| Movimientos de Caja | 29 |
| Anticipos / eventos | 3 / 6 |
| Saldo disponible de anticipos | $143.000,00 |
| Bonos / bonos activos con pagos | 9 / 5 |
| Cobrado neto en bonos activos | $190.000,00 |
| Deuda de bonos | $139.999,97 |
| Deuda de sesiones presentes | $21.000,00 |
| Cuotas existentes / deuda mensual | 0 / $0,00 |
| Movimientos sin DNI | 1 |

No hay anticipos con saldo negativo, movimientos con fracciones menores a un centavo ni sesiones no presentes con pagos netos positivos en esta fotografía. Ningún paciente tiene DNI nulo/vacío. No se ha certificado todavía una conciliación de migración ni se modificaron importes para redondearlos.

## Conflictos y preguntas concretas

### 1. Qué se entiende por bono no consumido

El sistema no tiene un ledger de consumo del bono. Sus $190.000 cobrados corresponden a cargos de bonos ya pagados; no equivalen automáticamente a crédito libre. Convertir ese mismo importe a saldo y conservar el bono como pagado liberaría poder de compra adicional sin justificación. Usar una proporción de asistencias tampoco tiene respaldo en las reglas actuales.

Pregunta: ¿el bono debe seguir siendo un cargo inicial adicional, o representa dinero adelantado para pagar sesiones? Si es lo segundo, hace falta definir cómo se atribuye el consumo de los bonos existentes. Esa definición debe aprobarse antes de calcular qué se convierte; no se asumió una fórmula.

### 2. Reintegro de sesión que sigue presente

La regla actual crea deuda siempre que la sesión esté PRESENTE y su importe supere lo pagado. Si se libera un pago hacia el saldo pero la sesión sigue debiéndose, la aplicación automática por deuda más antigua podría volver a cobrar esa misma sesión. Liberar un pago no equivale a bonificar el cargo.

Pregunta: después de ese reintegro, ¿la sesión debe quedar bonificada y sin deuda, o debe continuar pendiente de pago? El diseño necesita distinguir esa decisión de corregir la asistencia a ausente/cancelado, que sí elimina la deuda por dejar de estar PRESENTE.

### 3. Permisos efectivos frente al prompt

El contrasiento monetario de marathon_cash_command sí exige ADMIN. Sin embargo, bonus_change permite bonus_cancel para un bono sin pagos sin verificar ADMIN; marathon_agenda_plan_command permite quota_waive sin verificar ADMIN; y marathon_turn_cancel_charge permite cancelar deuda de una sesión sin verificar ADMIN. Sus funciones públicas son ejecutables por usuarios autenticados activos, incluidos SECRETARIA. Por tanto, la afirmación de que todas estas anulaciones ya son exclusivas de ADMIN no coincide con la base vigente.

Pregunta: ¿se exige ADMIN también para anular bonos y bonificar/cancelar saldos de sesiones o cuotas, siguiendo la regla del nuevo prompt? Las devoluciones ordinarias y reintegros no se confundirán con contrasientos administrativos.

### 4. Atajos del formulario único

La propuesta de mantener Cobrar sesión/cuota/bono es compatible como acceso al mismo formulario, con paciente e importe de deuda total, sin una segunda lógica de cobro.

Pregunta: ¿se conservan esos atajos con ese comportamiento?

## Riesgos identificados para la Fase 1

- Una devolución de saldo mueve dinero; liberar una aplicación es solo una redistribución contable. La pantalla debe diferenciarlas aunque estén dentro del mismo flujo.
- Anular un ingreso ya aplicado exige rastrear sus aplicaciones y devoluciones. El diseño deberá explicar qué pasa si parte ya fue devuelta y cómo impedir un saldo negativo, conservando una única salida de Caja por el importe que realmente se devuelve.
- Cambiar el orden de las deudas después de una operación no debe reasignar silenciosamente pagos históricos ya consolidados. La aplicación y su reversión deben dejar trazabilidad por deuda e ingreso.
- La vista previa necesita comprobar versiones y saldos de nuevo al confirmar. Dos secretarias no pueden aplicar el mismo saldo o pagar una deuda dos veces.
- Existe una acción para cancelar deuda de sesión y ajustes de cuota. El diseño debe incluirlos; los pagos y bonificaciones no pueden desaparecer al unificar la cuenta.
- No hay cuotas reales en esta fotografía. Su comportamiento futuro requiere pruebas con datos de prueba en un entorno aislado, no crear cuotas artificiales en producción.
- El movimiento sin DNI debe conservarse sin atribuirlo por aproximación a un paciente. No puede convertirse automáticamente a saldo personal.
- La sede sigue siendo obligatoria para el asiento de Caja, aunque el crédito sea único por paciente. El cobro deberá conservar sede/medio/fecha originales al aplicarse a deudas de otra sede.
- La hora no existe en agenda_cuotas; el diseño debe definir un desempate convencional y estable para ese tipo de deuda, además de created_at, tipo e ID cuando corresponda.

## Decisiones tomadas en esta fase

1. Consultar la base conectada y guardar sus definiciones actuales, sin pedir exportaciones que ya podemos obtener.
2. Usar la versión vigente y conservar las mejoras publicadas y las importaciones de datos del 04/11.
3. Limitar la auditoría a SELECT y definiciones. Evitar RPC de lectura con efectos secundarios, como la generación de cuotas.
4. Guardar documentación y referencias fuera de public. No modificar la app, pruebas, migraciones ni Vercel.
5. Dejar sin decidir el consumo de bonos, la semántica del reintegro y el ajuste de permisos hasta recibir respuesta. Ortopedia sigue fuera del saldo propuesto, tal como pide el prompt.

## Archivos de esta fase y límites

- FASE_0_REVISION_Y_PREGUNTAS.md: este informe.
- esquema_y_funciones.json: esquema, restricciones, políticas, funciones, vistas y fotografía agregada de lectura.
- funciones_vigentes_referencia.sql: copias de funciones existentes para consulta; no es una migración nueva.

No se ejecutaron migraciones ni pruebas que escriban datos reales. Tampoco se ha construido un prototipo o documento de diseño de Fase 1, porque el prompt exige aprobación entre fases. Quedan pendientes las respuestas anteriores y el OK para elaborar ese diseño, todavía sin implementar.
