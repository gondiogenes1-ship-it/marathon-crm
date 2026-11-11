# Caja con saldo a favor — decisiones confirmadas

Confirmadas por el usuario el 04/11/2026, después de la revisión de Fase 0. Este archivo complementa las preguntas del informe inicial y deja constancia de sus respuestas.

## Bono inicial

Es un cargo inicial que genera una única deuda. Se incluye en la cuenta normal del paciente junto con sesiones y cuotas y se cobra desde el formulario único. No se transforma en un paquete de sesiones ni se calcula un consumo proporcional por asistencias. Los bonos ya pagados siguen pagados: su cobro histórico no se convierte además en crédito libre. El diseño debe evitar tanto recrear la deuda como duplicar el dinero.

## Reintegrar sesión

La sesión queda sin deuda y el importe neto efectivamente pagado que se reintegre pasa al saldo a favor del paciente. No se agrega saldo por la parte que nunca se pagó. El reintegro hacia saldo no produce por sí mismo una salida de Caja ni modifica la asistencia. Se debe registrar la liberación de pagos y la bonificación correspondiente para que la sesión no se cobre automáticamente otra vez.

Si se necesita entregar efectivo o devolver por transferencia, se registra después una devolución de saldo: esa devolución sí genera el egreso de Caja y no puede superar el saldo disponible.

## Anulaciones y cancelaciones de deuda existentes

Se conservan los permisos y el funcionamiento actuales, por instrucción expresa del usuario. No se impondrá ADMIN a las acciones que hoy secretaría puede realizar. Se conserva la restricción actual de ADMIN para los contrasientos monetarios administrativos que ya la exigen. La Fase 1 debe distinguir estas acciones de la nueva liberación de pago a saldo.

## Atajos Cobrar

Se conservan en sesiones, cuotas y bonos. Abren el mismo formulario único, con el paciente y el importe de deuda total precargados y editables, sin lógica de cobro independiente.

## Estado de las fases

Las cuatro preguntas de Fase 0 quedan resueltas. No se ha autorizado ni ejecutado ninguna migración o implementación financiera. El siguiente paso previsto por el prompt es la Fase 1: documento de diseño sin código, sujeto al OK entre fases que exige el usuario.
