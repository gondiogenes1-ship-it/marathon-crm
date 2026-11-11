# Caja y saldo a favor — Fase 1: diseño para aprobar

Fecha: 04/11/2026. Alcance: documento de diseño; no implementa funciones, migraciones ni pantallas. Base: inspección de Fase 0 y decisiones confirmadas por el usuario. La aplicación continúa funcionando como está hasta aprobar y completar las fases siguientes.

## 1. Resultado para secretaría

Un botón **Registrar movimiento** en Caja y en la ficha abre el mismo formulario. Los botones **Cobrar** de turnos, cuotas y bonos se conservan como atajos: precargan paciente y deuda total, con importe editable.

| Tipo | Subtipo | Resultado |
|---|---|---|
| Ingreso | A favor del paciente | Registra el dinero una sola vez, cancela deudas por antigüedad y conserva el sobrante como saldo. |
| Ingreso | Otro ingreso | Registra Caja sin afectar una cuenta de paciente. |
| Egreso | Pago a profesional | Registra un egreso con profesional y terapia seleccionados, sin afectar saldos de pacientes. |
| Egreso | Devolución de saldo | Devuelve dinero disponible al paciente y registra un único egreso de Caja. |
| Egreso | Reintegrar sesión a saldo | Deja la sesión sin deuda y devuelve lo efectivamente pagado al saldo; no entrega dinero ni genera un egreso de Caja. |
| Egreso | Gasto general | Registra un gasto sin paciente. |
| Egreso | Otro | Registra otro egreso de Caja con concepto obligatorio, sin afectar el saldo de pacientes. |

La opción Reintegrar sesión permanece dentro del grupo Egreso solicitado, pero lleva el aviso **“Pasa a saldo a favor; no sale dinero de Caja”**. Medio y sede de devolución solo se solicitan cuando realmente se devuelve dinero. Así se conserva el formulario solicitado sin crear un asiento ficticio por una operación interna.

Actualización solicitada por el usuario: las opciones de Egreso se presentan en el orden Pago a profesional, Devolución de saldo, Reintegrar sesión, Gasto general y Otro. Pago a profesional habilita profesional y terapia, junto con importe, medio, sede, fecha, observaciones y categoría opcional. En la muestra se exige elegir ambos y la terapia se filtra según el profesional. Esta operación registra un egreso real de Caja; no aplica ni devuelve saldo de pacientes y no calcula comisiones o liquidaciones automáticamente. Los campos de asignación van visibles en el formulario para evitar duplicarlos en Más datos opcionales.

El bono inicial sigue siendo un cargo adicional, con una única deuda identificada por su bono. Se cobra junto con las sesiones y cuotas. No se transforma en un paquete de sesiones. Lo ya cobrado del bono sigue cancelando ese bono y no se convierte además en saldo libre.

## 2. Reglas de la cuenta

- **Deuda total clínica** = deuda de sesiones PRESENTES + cuotas generadas + bonos ACTIVOS, descontando pagos y bonificaciones válidas. Ortopedia se muestra aparte y no participa de esta suma ni del saldo.
- **Saldo a favor** = dinero recibido o liberado hacia la cuenta menos aplicaciones y devoluciones, sumando los reversos. Siempre es mayor o igual a cero y pertenece al paciente, sin restricciones de sede, terapia ni profesional.
- Cobrar no modifica la asistencia. Solo los PRESENTES generan deuda de sesión. Un bono genera su cargo una vez; repetir una consulta o solicitud no lo recrea.
- Aplicar saldo nunca inserta un nuevo movimiento de Caja. La aplicación a otra sede conserva el medio, fecha y sede del ingreso original.
- No se permite ingresar saldo sin seleccionar un paciente existente. El movimiento histórico sin DNI se conserva sin asignarlo por aproximación.
- Se mantiene el orden de deuda más antigua: fecha de sesión/cuota/bono, hora, created_at, tipo e ID. Para cuotas, que no tienen hora, se usa 00:00. Tipo es solo un desempate técnico final cuando los otros datos coinciden; no da prioridad general a sesiones, bonos o cuotas.
- Importes monetarios en numeric con dos decimales. La entrada con más de dos decimales se rechaza; los cálculos derivados se redondean con round(numeric, 2), a la mitad alejándose de cero. Nunca se redondea para ocultar una diferencia de conciliación. JavaScript transmite el importe decimal validado como texto y solo calcula valores visuales, no saldos definitivos.

## 3. Modelo propuesto

Los nombres siguientes son propuestos; se concretarán en una migración nueva de Fase 2.

| Elemento | Campos y responsabilidad |
|---|---|
| movimientos.subtipo | Subtipo explícito para registros nuevos. El historial sin subtipo conserva su clasificación histórica. |
| saldo_cuentas | dni como PK/FK y version para control optimista. No guarda un saldo monetario mutable. |
| saldo_fuentes | id, dni, movimiento de ingreso original, procedencia histórica y created_at. Identifica el origen de cada peso; el ingreso original solo puede vincularse una vez. |
| saldo_aplicaciones | id, dni, fuente_id, una FK destino entre turno_id/cuota_id/bono_id, importe, request_id, actor y created_at. Cada aplicación tiene un único origen y una única deuda. |
| saldo_eventos | id, dni, fuente_id, tipo, monto, aplicacion_id opcional, movimiento_id opcional, reverso_de opcional, request_id, actor, created_at y clave de idempotencia por efecto. Es append-only. |
| saldo_ajustes_sesion | id, turno_id, monto, motivo, tipo, reverso_de, request_id y actor. Registra bonificación para que un reintegro a saldo no vuelva a crear deuda. Se distingue de pagos y de asistencia. |
| saldo_importacion_map | Identificador único de origen, destino y lote de migración. Impide importar dos veces un movimiento o aplicación antiguos. |

Tipos de evento: INGRESO, APLICACION, REVERSO_APLICACION y DEVOLUCION. Los registros importados añaden una marca de procedencia, no un ingreso nuevo de Caja. saldo_aplicaciones describe el vínculo y saldo_eventos registra su efecto monetario: **no se suman ambas tablas como si fueran dos pagos**.

### Integridad y convivencia

1. Se conservan los CHECK actuales de movimientos. Los ingresos nuevos de saldo usan origen CAJA, tipo INGRESO, DNI obligatorio y las FKs de deuda/anticipo/ortopedia nulas; las devoluciones usan CAJA/EGRESO bajo las mismas condiciones. Otro ingreso/gasto general no lleva DNI. Un CHECK adicional valida el subtipo y estas combinaciones solo en movimientos nuevos que lo utilicen. Las aplicaciones enlazan las deudas desde sus propias tablas.
2. Se mantienen los movimientos históricos de origen CLINICA, ANTICIPO, BONO, CAJA y ORTOPEDIA con sus FKs. daily_cash sigue sumando los mismos movimientos; solo necesita exponer el subtipo si lo requiere la pantalla. Los filtros actuales ya admiten CAJA.
3. Toda aplicación tiene exactamente una FK destino válida. La fuente, la deuda, los eventos y la cuenta deben pertenecer al mismo DNI; las funciones y triggers de integridad verifican esa correspondencia bajo el candado existente. El tipo de deuda y el paciente no pueden cambiar después de una aplicación.
4. Un reverso identifica la aplicación original y no supera su importe todavía aplicado. Una devolución no supera el disponible de las fuentes seleccionadas. La suma de aplicaciones vigentes de una deuda no supera su cargo neto. Las restricciones agregadas se validan dentro de la misma transacción serializada; no se intentan expresar como CHECK que consulte otras filas.
5. Ledger y aplicaciones no se editan ni borran desde la app. Los errores se corrigen con nuevos eventos enlazados. RLS permanece habilitado en todas las tablas nuevas, sin acceso directo más amplio ni funciones privilegiadas públicas innecesarias. Se conserva el patrón de funciones internas con search_path vacío y RPC autorizados.
6. El histórico reflejado en el nuevo modelo se identifica expresamente. Las funciones de cuenta usarán **el ledger nuevo para lo migrado o el cálculo histórico para lo no migrado, nunca ambos para el mismo pago**. Los consumidores existentes de turn_paid, advance_paid, vistas e informes deberán adaptarse juntos y verificarse.

## 4. Aplicación automática y concurrencia

Pseudocódigo del comportamiento, no implementación:

```text
registrar ingreso(request_id, datos, version_cuenta, huella_vista_previa):
  verificar usuario activo e idempotencia con solicitudes
  tomar candado marathon:master-write:v1 y bloquear cuenta/fuentes/deudas
  comprobar versión, importes y huella de la vista previa
  si cambió el reparto o la cuenta: no guardar; devolver nueva vista previa
  insertar un ingreso de Caja y su fuente/evento de saldo
  aplicar_disponible(paciente)
  incrementar versión y guardar resultado de la solicitud
  confirmar toda la transacción

aplicar_disponible(paciente):
  calcular deudas exigibles netas, ordenadas determinísticamente
  tomar fuentes con disponible, por fecha/hora/created_at/id
  para cada deuda y cada fuente:
    aplicar el mínimo entre deuda pendiente y disponible de la fuente
    registrar aplicación y su único evento monetario
    continuar hasta agotar deuda o saldo
  comprobar saldo no negativo y límites de cada aplicación
```

Las cuotas se generan de forma idempotente antes de construir una vista previa que deba incluirlas. Se separará la lectura de la escritura: una consulta de ficha o una vista previa no debe crear silenciosamente cuotas ni aplicar saldo. La generación explícita/programada y la confirmación toman el mismo candado; si aparece una cuota entre vista previa y confirmación, se pide revisar el nuevo reparto.

Cada comando mantiene p_request_id y hash del payload. Un reintento obtiene el resultado guardado; la misma clave con otros datos se rechaza. El contador de versión cambia también al aplicar o liberar saldo. Los efectos internos llevan claves únicas por solicitud y operación. La UI conserva el bloqueo global y el botón Verificar guardado; no genera otra solicitud por un resultado incierto.

### Cuándo se dispara

| Hecho | Efecto |
|---|---|
| Ingreso a favor | Genera un único asiento de Caja y aplica el disponible a la cuenta completa. |
| Nuevo PRESENTE | Aparece su deuda y se aplica disponible, empezando por la deuda más antigua de toda la cuenta. Repetir PRESENTE no duplica cargo ni aplicación. |
| Nueva cuota / nuevo bono | Crea un cargo identificado una sola vez y ejecuta la misma aplicación, sin otro asiento de Caja. |
| Salir de PRESENTE | Libera las aplicaciones de esa sesión y elimina su exigibilidad por estado; no simula una devolución de efectivo. Se integra con las validaciones existentes y se registra el cambio de asistencia. |
| Reintegro de sesión a saldo | Libera el pago y bonifica el cargo de la sesión en la misma transacción; no ejecuta un barrido de cobro en ese comando. |
| Anulación o cancelación de deuda | Conserva su operación y permisos actuales; su adaptador contable libera solo aplicaciones que dejen de corresponder al cargo, sin duplicar movimientos. |

El saldo liberado por un reintegro permanece disponible al terminar ese comando para que el resultado mostrado sea el confirmado por el usuario. Se utilizará en el próximo ingreso o nueva deuda. No se introduce un proceso que vuelva a aplicar ese saldo inmediatamente en segundo plano. La vista previa explica si existen otras deudas pendientes.

## 5. Reintegros, devoluciones y anulaciones

### Sesión reintegrada a saldo

La operación completa deja sin deuda el cargo vigente de esa sesión y devuelve a saldo su pago neto recuperable. En una sesión parcialmente pagada, se libera solo lo pagado y se bonifica también la parte pendiente; jamás se crea crédito por dinero no recibido. La revisión muestra por separado importe de la sesión, pago a liberar y deuda que se bonificará. La asistencia se conserva. Repetir la solicitud no produce otra devolución ni otra bonificación.

Los pagos antiguos reflejados tienen la misma trazabilidad: se revierte su aplicación contable, conservando el asiento original de Caja. Las funciones de lectura dejan de considerarlos aplicados a esa sesión. No se añade un REINTEGRO monetario porque el dinero sigue dentro de Caja.

### Devolución de saldo

Se elige paciente, importe, medio, sede, fecha y motivo. Se consumen fuentes disponibles en orden estable; el egreso de Caja es uno, aunque requiera varias fuentes y eventos. Se conserva el detalle de procedencia. Si otra secretaria consumió saldo, el servidor rechaza la versión vieja y no devuelve dinero por encima del disponible.

### Anular un ingreso aplicado

El contrasiento monetario administrativo conserva su restricción actual a ADMIN. Para un ingreso del flujo nuevo sin devoluciones previas, la vista previa muestra las aplicaciones que se liberarán y las deudas que reabrirán. Bajo el candado se revierten sus aplicaciones activas, se registra el único egreso compensatorio con compensacion_de y motivo y se agota esa fuente. No se usan ingresos de otro paciente ni se deja negativo el saldo.

Si una parte de ese ingreso ya se devolvió, no se permite anular nuevamente el importe completo. Se conserva el criterio de bloqueo por reintegros previos del flujo vigente; se informa lo ya devuelto y se ofrece la devolución del saldo restante o la revisión administrativa, sin crear una anulación parcial implícita. La futura implementación no ofrecerá esta acción sobre un origen histórico que no pueda rastrearse con exactitud.

Las cancelaciones de deuda de sesión, anulaciones de bonos y ajustes de cuotas mantienen los permisos vigentes de secretaría y administración, según la corrección expresa del usuario. El ajuste de sesión nuevo para reintegrar a saldo no convierte esas acciones en contrasientos de Caja. Los bonos históricos anulados con pagos requieren revisión individual: no se cambia su estado ni se crea crédito por inferencia.

## 6. Migración y conciliación

### Representación histórica, sin volver a cobrar

La migración conserva los registros originales y refleja en el ledger su significado:

- Cobro directo de una sesión: fuente por el cobro real y aplicación histórica por su pago neto vigente. Su saldo libre inicial es cero cuando está aplicado por completo. Un reintegro monetario histórico se refleja como salida de esa fuente y liberación de su aplicación, sin otra salida de Caja.
- Anticipo: fuentes por depósitos reales; aplicaciones, reversos y devoluciones por sus eventos existentes. El disponible resultante debe ser exactamente el actual. Las restricciones antiguas se conservan en el historial y dejan de limitar aplicaciones posteriores al corte.
- Bono o cuota: fuente por su ingreso real y aplicación histórica a su propio cargo. Los bonos ya pagados siguen cancelados por sus pagos. No se convierten los $190.000 observados en bonos pagados en otros $190.000 libres. Ese importe fue una fotografía de Fase 0, no una instrucción fija para migrar.
- Ajustes de cuotas y cancelaciones de cargos de sesión: se respetan sin recrear el importe perdonado. Los importes de sesiones ya reducidos por una cancelación no se vuelven a reducir al reflejar el historial.
- Ortopedia: no se refleja en este saldo y conserva su circuito completo. Los movimientos manuales previos no se reclasifican como crédito solo por tener DNI: requieren procedencia inequívoca y, si no la hay, permanecen como movimientos históricos fuera del saldo.

No se aplica automáticamente el saldo histórico a otras deudas durante la migración. Primero se exige igualdad de deuda y disponible antes/después por paciente. Las reglas automáticas nuevas operan desde el corte en los eventos descritos arriba; cualquier barrido inicial de saldos contra deudas sería una operación separada, con vista previa y aprobación explícita.

### Pasos

1. Releer esquema y funciones, obtener un respaldo restaurable de toda la base y comprobar su restauración en entorno aislado. Las referencias de Fase 0 no sustituyen ese respaldo.
2. Preparar una prueba en seco sin escrituras: clasificación por movimiento/evento, asignación exacta a fuentes y deudas y diferencias o casos sin resolver. No inferir correspondencias por nombre ni por importes parecidos.
3. Validar en una copia la migración versionada y su repetibilidad. Las claves únicas de importación hacen que un segundo intento no agregue dinero ni aplicaciones.
4. Conciliar por paciente deuda de sesiones, cuotas y bonos, pagos netos por deuda y saldo disponible; por ingreso, dinero recibido/devuelto/aplicado/disponible; y Caja por fecha, medio y sede. Se incluyen los movimientos sin DNI en la conciliación de Caja, aunque no formen parte de una cuenta personal.
5. Ventana de mantenimiento: pausar escrituras de la app y tareas que generen deudas, tomar el candado, recalcular la línea de base y efectuar migración/cambio de funciones en una transacción. Revalidar la conciliación con la base ya bloqueada; no confiar en una fotografía tomada horas antes.
6. El corte solo se confirma con diferencias monetarias de $0,00 y sin casos de procedencia sin resolver. Si falla, rollback de toda la transacción. Reabrir escrituras únicamente con backend y frontend compatibles y verificados.
7. Tras escrituras nuevas en el modelo, una vuelta atrás requiere reconciliación o migración inversa; no basta con recuperar el JavaScript anterior. Se conservará una versión compatible y el procedimiento de contingencia.

## 7. Pantallas y contratos previstos

| Pantalla | Cambio |
|---|---|
| Caja | Registrar movimiento como entrada principal; tabla conserva fecha, sede, medio y totales e incorpora subtipo. Contrasientos siguen disponibles según permisos. |
| Formulario | Tipo, subtipo y campos pertinentes. Paciente, importe, medio, sede, fecha, observaciones, categoría y profesional/secretaría asociada donde corresponda. Los campos internos sin efecto monetario no piden medio de pago. |
| Vista previa | Deuda actual, saldo previo, ingreso nuevo, importe a cancelar y saldo resultante; detalle ordenado y aplicaciones parciales. Sin guardar hasta Confirmar ingreso. Un cambio concurrente obliga a revisar la nueva propuesta. |
| Ficha | Deuda total clínica y saldo a favor positivos y separados. Desglose de sesiones/cuotas/bonos. Deuda de Ortopedia separada y sin posibilidad de usar este saldo. |
| Historial | Entradas/salidas reales de Caja y movimientos internos identificados como tales; vínculo ingreso → deuda → reverso. Los registros históricos mantienen sus referencias. |
| Turnos / cuotas / bonos | Cobrar abre el formulario común con deuda total editable. Desaparecen formularios independientes de cobro; permanecen las acciones de cancelación vigentes y el nuevo reintegro a saldo. |

Se proponen una lectura unificada de cuenta, una vista previa sin efectos secundarios y un comando único de movimiento. Los nombres y firmas definitivos se fijan en Fase 2; no se añadirán llamadas adivinadas al frontend. Los comandos de asistencia, generación de cuotas, bonos y ajustes invocan las mismas funciones contables internas. Las rutas antiguas se adaptan o rechazan con un mensaje claro para evitar que un navegador con caché continúe usando la lógica anterior después del corte.

Ejemplo ilustrativo, sin datos reales: si debe $20.000 y entrega $30.000, la vista previa informa “Se cancelará $20.000 · Quedará a favor $10.000” y lista las deudas que se saldarán. Aplicaciones posteriores de esos $10.000 no aumentan el ingreso del día.

## 8. Verificación exigida para aprobar la implementación

- Ingreso menor, igual y mayor a deuda; sin deuda; varias sedes; deudas mezcladas y empates; saldo parcial; bono creado una sola vez.
- Nuevo PRESENTE con y sin saldo; repetición del mismo estado; salida de PRESENTE y reingreso posterior; reintegro total a saldo con pago completo o parcial; sesión bonificada que no se vuelve a cobrar.
- Devolución exacta y superior al saldo; anulación de ingreso aplicado; bloqueo con devoluciones previas; contrasientos, ajustes y permisos existentes; ninguna operación modifica Ortopedia.
- Dos sesiones PostgreSQL compitiendo por el mismo saldo y pruebas de reintento con mismo request_id, datos distintos y vista previa desactualizada. La concurrencia real no se demuestra con llamadas secuenciales.
- Migración en seco y ejecutada, segunda ejecución, pagos/reintegros históricos, bonos anulados, DNI faltante, datos ambiguos y conciliación exacta antes/después.
- Pruebas existentes de anticipo, reserva y ficha de Ortopedia adaptadas al formulario común; recorrido completo de ficha/Caja/Turnos, teclado, errores y respuesta incierta. Las pruebas financieras se realizan en entorno aislado, sin datos ficticios en producción.

## 9. Decisiones de diseño propuestas y límites

Para revisar: conservar los CHECK actuales de movimientos; usar CAJA para nuevos ingresos/devoluciones de saldo; reflejar los pagos históricos sin duplicarlos; desempatar cuotas con hora 00:00; no redistribuir saldo durante la migración ni inmediatamente después de un reintegro a saldo; rechazar anulación completa si hay devoluciones previas; y conservar un contador de versión sin saldo mutable.

Estas decisiones concretan las reglas confirmadas. La preservación de permisos prevalece sobre la afirmación inicial del prompt de que toda cancelación sería exclusiva de ADMIN. Las diferencias de importes, procedencia o modelo que aparezcan al implementar se informarán antes de resolverlas.

Archivo entregado: FASE_1_DISENO.md. Solo se creó documentación. No se probaron aún las tablas, algoritmos, conciliación, migración, concurrencia o pantallas propuestas: esas verificaciones corresponden a Fase 2 y Fase 3. No se modificó la base, la app ni Vercel.

**Siguiente paso, sujeto a aprobación:** Fase 2, desarrollar y probar la base en entorno aislado. La ejecución de una migración sobre producción seguirá requiriendo aprobación del plan de datos y respaldo verificado.
