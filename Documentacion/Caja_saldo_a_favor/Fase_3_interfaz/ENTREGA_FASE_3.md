# Caja y saldo · Pantallas para revisión local

4 de noviembre de 2026. Estado: implementado y probado en una demostración local. Producción y sus movimientos permanecen sin cambios por esta tarea.

Demostración: http://127.0.0.1:8776/ . Usa la misma interfaz de public/ y una base PostgreSQL exclusiva, marathon_saldo_demo_20261104, con pacientes ficticios. El cartel amarillo identifica la demostración. La configuración de prueba intercepta las llamadas de la aplicación y las dirige a esa base local; no inicia sesión ni envía operaciones a Supabase. Los archivos de demostración están en local/, fuera de public/ y del despliegue.

## Recorrido implementado

- Inicio y Caja: un botón Registrar movimiento reemplaza los accesos manual/anticipo cuando el circuito está activo.
- Cobrar desde Inicio o Turnos sigue funcionando. Abre ese mismo formulario, con paciente, sede del turno y deuda clínica total precargados. El importe es editable; el reparto respeta las deudas más antiguas. No se garantiza pagar específicamente el turno seleccionado si hay otras deudas anteriores: la vista previa lo detalla.
- Ficha: Registrar movimiento e Historial de saldo, con deuda clínica total y saldo a favor juntos. Ortopedia se identifica como cuenta aparte.
- Cuenta desde Caja: muestra sesiones, cuotas y bonos pendientes y un acceso al formulario común. El saldo a favor se diferencia de deuda.
- Cobrar cuota y Cobrar bono son atajos del formulario común. Los bonos no se cobran al reservar con otro formulario. Su anulación conserva el historial y libera su pago al saldo.
- Egresos: Pago a profesional, Devolución de saldo, Reintegrar sesión, Reintegrar cuota a saldo, Gasto general y Otro. Pago a profesional exige profesional y terapia compatibles, sin paciente. Concepto/motivo obligatorio para los egresos y para Otro ingreso.
- Paciente: búsqueda por nombre/apellido/DNI, selección explícita y creación/edición de ficha con el editor existente.
- Revisar movimiento consulta el reparto en el servidor. Confirmar se habilita con esa revisión; cambiar datos la invalida. Se conserva la solicitud al verificar un guardado incierto, sin generar otra operación. Un conflicto de versión exige revisar nuevamente.
- Actualizar cuotas es una acción visible y separada de consultar una ficha; genera las cuotas pendientes y aplica saldo disponible sin duplicar Caja.

## Decisión confirmada: reintegrar cuota

El usuario volvió a confirmar expresamente que lo pagado debe quedar como saldo a favor. La cuota queda sin deuda y no se devuelve dinero de Caja. La parte impaga de una cuota parcialmente pagada se bonifica, sin inventar crédito. La pantalla informa:

“Lo pagado se acredita como saldo a favor del paciente y la cuota queda sin deuda. Este reintegro NO devuelve dinero de Caja. Para devolver dinero, registrá después una Devolución de saldo.”

La revisión y el mensaje de éxito repiten esta diferencia. Desde una cuota pagada, Reintegrar cuota al saldo abre el mismo formulario con paciente y cuota seleccionados. Si se devuelve dinero después, se registra Devolución de saldo con importe, medio, sede, fecha y motivo. Nunca puede superar lo disponible.

## Evidencia

Pruebas SQL, roles e idempotencia: ../Fase_2_aislada/RESULTADO_PRUEBAS.json. Cinco suites SQL y concurrencia con dos conexiones: PASS. Se agregó saldo_cuota_smoke.sql para cubrir la decisión anterior, incluidos reintegro parcial, ausencia de egreso, reintento y devolución posterior.

Regresiones JavaScript: verificar-anticipo.mjs, verificar-boton-reserva.mjs y verificar-ficha-ortopedia.mjs: PASS. verificar-saldo-estado.mjs comprueba activación por sesión, compatibilidad con servidores anteriores y que los errores de red/permisos no se oculten.

Recorrido real desde navegador hacia los RPC y PostgreSQL de demostración:

1. Cobrar desde Inicio abrió al paciente ficticio con $28.000 de deuda total; la revisión mostró bono y sesiones en orden. Confirmar agregó exactamente un ingreso físico de $28.000.
2. Reintegrar la cuota pagada de $5.000 dejó $5.000 a favor y la cuota sin deuda. La cantidad de movimientos físicos siguió en tres y los egresos en cero.
3. Intentar devolver $6.000 sobre ese saldo fue rechazado y Confirmar quedó deshabilitado.
4. Devolver $1.500 desde Devolución de saldo dejó $3.500 a favor y agregó un único egreso. Caja de prueba: ingresos $45.000, egresos $1.500, neto $43.500. La cuenta del paciente mostró el saldo resultante.
5. Pago a profesional mostró profesional/terapia y ocultó paciente; la revisión fue válida sin modificar el saldo clínico. No se confirmó ese egreso de prueba.

Capturas: reintegro-cuota-preview.png (revisión del reintegro) y ficha-saldo-demo.png (ficha final). Se verificó una columna y ausencia de desbordamiento horizontal a 537 px CSS; los controles conservan texto de 14 px y altura mínima de 44 px. Los importes y nombres de esa captura son ficticios.

## Protección del sistema en funcionamiento

La interfaz consulta marathon_saldo_estado al entrar. Si el circuito está apagado o la función todavía no existe en el servidor, mantiene los formularios anteriores. Una falla de red o permisos se informa; no se interpreta como autorización para usar otro circuito. La activación no se hace desde el navegador.

No se desplegó en Vercel ni se aplicaron migraciones en Supabase. Los dos ingresos de prueba de Gonzalo y los $40.000 de Carlos conservan el tratamiento acordado en el plan de conversión; aún no se convirtió ningún movimiento real.

Se agregaron dos migraciones a la entrega anterior: reintegro de cuota a saldo y encapsulación autenticada de las lecturas de historial/bonos. Estas lecturas ya verificaban usuario activo; ahora pueden consultar los helpers privados del ledger sin abrir las tablas o funciones internas a los clientes. Se verificaron consultas de Secretaría y rechazo a usuarios inactivos.

## Archivos y decisiones

Public/: saldo.js, saldo.css y saldo-state.js son nuevos. Se adaptaron app.js, operations.js, api.js, patient-history.js, agenda.js, agenda-recurrente.js e index.html. No hay compilación ni dependencias nuevas. El diseño y la barra Marathon se conservan. Los archivos anteriores a esta fase están en respaldo_public/.

Se agregó Reintegrar cuota a saldo a los subtipos de Egreso para conservar el comportamiento confirmado y permitir usar el mismo formulario tanto desde una cuota como desde Caja. Los campos profesional y terapia se muestran solo donde corresponden; el profesional asociado opcional no se duplica en Pago a profesional.

El flujo completo usa el backend local real; no se probó contra escrituras en producción. La prueba del esquema local no reemplaza el respaldo completo y restaurado que se requiere para el corte real.

Queda pendiente aprobar esta fase visual y completar la Fase 4 de documentación. Antes de activar en producción faltan respaldo completo verificado mediante restauración, nueva prueba en seco de los datos reales, conciliación sin diferencias y aprobación del corte. No ejecutar automáticamente todas las migraciones por copiar esta carpeta.
