# Fase 1 — resumen para aprobar

## Así funcionará

**Registrar movimiento** será el formulario común de Caja y de la ficha. Los botones **Cobrar** se conservan y abren ese mismo formulario con el paciente y su deuda total precargados, editable.

Un ingreso a favor del paciente cancela primero la deuda más antigua, sea una sesión presente, una cuota o un bono. Si sobra dinero, queda disponible para próximas deudas, sin limitarse a una sede, terapia o profesional. Antes de confirmar se muestra el detalle de lo que se pagará y del saldo que quedará.

La ficha muestra **deuda total clínica** y **saldo a favor** por separado. El bono inicial genera una deuda una sola vez y se cobra dentro de esta cuenta. Los bonos que ya están pagados siguen pagados. Ortopedia mantiene su cuenta y cobros aparte.

## Reintegrar y devolver dinero

**Reintegrar sesión a saldo:** deja la sesión sin deuda y pasa lo efectivamente pagado al saldo a favor, manteniendo la asistencia. Si la sesión estaba parcialmente pagada, solo se acredita el pago real y también se elimina la parte pendiente. La pantalla muestra ambos importes antes de confirmar. No se registra una salida de dinero de Caja.

El saldo liberado queda disponible al terminar este reintegro; se usará con el próximo ingreso o nueva deuda. Así no se vuelve a cobrar inmediatamente la misma sesión ni se oculta el saldo que se acaba de liberar.

**Devolución de saldo:** se usa cuando se entrega efectivo o se devuelve por transferencia. Esa operación sí registra un egreso y no puede superar el disponible.

## Historial y permisos

Se mantienen los permisos actuales para anular bonos, cancelar saldos y registrar los contrasientos que ya requieren ADMIN. No se eliminan registros: cada aplicación y cada reverso conserva su vínculo con el dinero recibido y con la deuda.

Para un ingreso nuevo ya aplicado, la anulación administrativa libera sus aplicaciones y hace un solo contrasiento de Caja. Si parte del dinero ya fue devuelta, se bloquea la anulación completa para no devolverlo dos veces; se ofrece revisar el saldo restante.

## Qué pasa con lo que ya existe

La migración conservará los movimientos originales. Reflejará sus pagos en la cuenta nueva sin volver a cobrarlos ni contarlos dos veces. Los anticipos conservarán exactamente su disponible; lo pagado en bonos o sesiones no se convertirá además en crédito libre.

Durante la migración no se redistribuirá automáticamente el saldo antiguo a otras deudas. Primero deberán coincidir por paciente la deuda y el saldo anteriores y posteriores. Un barrido inicial de saldos contra deudas requeriría una revisión y aprobación separadas.

Los totales de Caja por día, sede y medio deberán coincidir exactamente antes y después. Aplicar saldo nunca genera otra entrada de dinero. Se detendrá la migración si un pago histórico no puede relacionarse con certeza o si aparece una diferencia.

## Próxima fase

La aprobación de este diseño permite avanzar a **Fase 2: desarrollar y probar la base en un entorno aislado**. Antes de cambiar producción harán falta una prueba en seco, una conciliación sin diferencias y un respaldo completo cuya restauración se haya comprobado.

En esta Fase 1 solo se escribieron este resumen y FASE_1_DISENO.md, que contiene tablas propuestas, restricciones, pseudocódigo, contratos de pantalla, plan de migración y casos de prueba. Nada de ello está implementado o publicado todavía.
