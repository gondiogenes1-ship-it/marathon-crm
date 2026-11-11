# Manual de uso vigente — 6 de noviembre de 2026

Copia de consulta en Markdown del Anexo B del Informe PPS. El documento nativo mantiene su estructura y formato en Google Docs: https://docs.google.com/document/d/1AaFatHQC4AlTSQbED4gsKWHAfAcwdSn9rEUtGULYcD8

## Marathon CRM · Manual de uso · Secretaría y Administración

Sistema versión 0.14.0 · Revisión operativa del 06/11/2026 · Acceso publicado en Vercel

Este manual tiene dos partes. La Parte A (secciones 1 a 8) es para Secretaría. La Parte B (secciones 9 a 16) es para Administración, que además hace todo lo descrito en la Parte A.

## Parte A · Secretaría

### 1. Antes de empezar

Marathon CRM es el sistema donde se cargan los pacientes, se reservan los turnos, se registran los cobros y se controla el stock de ortopedia. Funciona desde el navegador y todas las cuentas pueden operar todas las sedes.

#### 1.1 Ingresar y salir

- Abrí la dirección del sistema en el navegador.

- Escribí tu correo y tu contraseña y pulsá Ingresar.

- Cuando termines, pulsá Cerrar sesión.

Si recargás la página (F5) o cerrás y volvés a abrir la pestaña, el sistema te pide ingresar de nuevo. Es normal: por seguridad no guarda tu sesión.

#### 1.2 Tu cuenta

En Mi cuenta ves tu nombre y tu rol (Secretaría o Administración) y podés cambiar tu contraseña con Actualizar contraseña. Cada persona debe usar su propia cuenta; no compartas la contraseña.

#### 1.3 Ayuda dentro del sistema

El botón ? Ayuda abre un resumen de la pantalla en la que estás. Si algún nombre de este manual no coincide exactamente con lo que ves, la ayuda de esa pantalla es la referencia.

#### 1.4 Las tres reglas de oro

- Esperá la confirmación antes de cerrar o cambiar de pantalla. Mientras el sistema guarda, los botones se bloquean; es a propósito.

- Si aparece «Verificar guardado», pulsalo. No repitas la operación desde cero. Significa que el sistema no recibió la respuesta y no sabe si se guardó. El botón comprueba la misma operación y evita que se duplique un cobro o un turno.

- No cargues pacientes, cobros ni movimientos de prueba. Todo lo que se guarda es real.

### 2. Recorrido por la pantalla


| Menú | Para qué sirve |
| --- | --- |
| Inicio | Resumen del mes y del día: turnos, caja y accesos rápidos |
| Pacientes | Buscar, crear y editar fichas; documentos; cuenta clínica |
| Turnos | Agenda diaria o semanal; reservar, marcar asistencia, reprogramar, cancelar |
| Lista de espera | Pedidos de pacientes que esperan un turno |
| Caja | Cobros, anticipos, ingresos y egresos, contrasientos |
| Ortopedia y stock | Stock, ventas y alquileres, devoluciones, pagos pendientes |
| Informes | Consultas y descargas en Excel |
| WhatsApp | Texto de los avisos de turno |


Los menús Datos de agenda, Otros datos y Usuarios son de Administración y no los vas a ver con cuenta de Secretaría.

#### ¿Qué quiero hacer?


| Quiero… | Voy a… |
| --- | --- |
| Buscar a un paciente | Búsqueda rápida (tecla / o Ctrl + K) o Pacientes |
| Dar de alta un paciente | + Nuevo paciente |
| Reservar un turno | + Reservar turno (Inicio, Turnos o ficha del paciente) |
| Marcar que vino o faltó | Turnos o Inicio → Marcar presente / Marcar ausente |
| Cobrar una sesión | En el turno, Cuenta / cobros |
| Recibir un anticipo | Recibir anticipo (Inicio o Caja) |
| Cambiar o cancelar un turno | En el turno, Reprogramar o Cancelar turno |
| Avisar por WhatsApp | Botones de aviso en la reserva, el turno o la reprogramación |
| Anotar a alguien en espera | Agregar a lista de espera |
| Vender o alquilar un producto | Ortopedia y stock → Venta / alquiler |
| Descargar un listado | Exportar Excel o Descargar Excel completo |


### 3. Tareas del día a día

#### 3.1 Buscar un paciente

- Búsqueda rápida: desde cualquier pantalla, apretá / (fuera de un campo de texto) o Ctrl + K (en Mac, Cmd + K). Escribí al menos 2 caracteres, elegí con las flechas y Enter, y se abre la ficha.

- Pantalla Pacientes: buscá por el comienzo del DNI, el nombre o el teléfono y pulsá Buscar.

#### 3.2 Dar de alta o editar un paciente

- Pulsá + Nuevo paciente.

- Completá los datos. Son obligatorios el DNI (solo números), el nombre y el apellido. También podés cargar segundo nombre, nacimiento, sexo, obra social o cobertura (puede haber más de una), afiliado, teléfono, correo, domicilio, localidad, provincia, médico y observaciones.

- Pulsá Guardar paciente y esperá el mensaje de confirmación.

- Al terminar, el sistema te ofrece Reservar turno y Agregar a lista de espera.

Tené en cuenta:

- El DNI no se puede cambiar una vez creado el paciente. Revisalo antes de guardar.

- Teléfono: cargalo completo, con característica. Si está incompleto, los avisos de WhatsApp no se pueden enviar (verás «WhatsApp: teléfono incompleto»).

- Si dos personas editan la misma ficha a la vez, el sistema avisa que cambió. Pulsá Volver a cargar ficha y repetí tu cambio.

#### 3.3 Reservar un turno

- Pulsá + Reservar turno desde Inicio, Turnos, la ficha del paciente o un horario libre de la grilla.

- Si la atención es puntual y se realiza fuera del día u horario habitual del profesional, marcá Atención excepcional en este mismo formulario. Admite fechas pasadas y permite indicar la hora. No modifica el horario habitual ni crea una serie; conserva los controles de superposición. Se guarda Pendiente y luego se registra la asistencia y el cobro por el circuito habitual.

- Elegí al paciente con Buscar paciente. Si no existe, Nuevo paciente abre el mismo formulario de la ficha.

- Elegí terapia y profesional, y pulsá Consultar horarios.

- Elegí un horario disponible. Ver indicaciones de la terapia muestra lo que hay que decirle al paciente.

- Definí cómo es el tratamiento (ver más abajo) y pulsá Revisar reserva.

- Controlá fecha, hora, sede y profesional y pulsá Confirmar reserva.

- Aparece el comprobante: podés Ver comprobante, Imprimir o Copiar para enviar, y avisar por WhatsApp (3.9).

Cómo es el tratamiento


| Modalidad de agenda | Cuándo usarla |
| --- | --- |
| Cantidad de sesiones | El paciente tiene una cantidad autorizada (por ejemplo, 10 sesiones). Cada vez que marcás Presente se descuenta una. Al completarse, los turnos que quedan se cancelan solos |
| Mensual | Tratamiento con cuota mensual. Permite indicar inicio y fin inclusive; un fin vacío mantiene la continuidad. Puede comenzar en una fecha anterior. Las cuotas mantienen el importe mensual completo, sin prorrateo automático |
| Indefinido | Horario fijo sin tope de sesiones |




| Modalidad de pago | Qué significa |
| --- | --- |
| Por clase presente | Se cobra cada clase a la que el paciente asiste |
| Bono inicial + por clase presente | Un bono al comienzo y luego cada clase. Cargá el importe del bono y, si lo cobrás en el momento, Registrar pago del bono ahora |
| Mensual | Cuota mensual; la primera se genera en la fecha de inicio |
| No abona | Sin cobro |


Para tratamientos con varios días por semana, elegí los días en Días, sede y profesional de cada atención (por ejemplo, Lun · Mié · Vie). Cuando se generan varias fechas con Generar fechas, el sistema revisa la serie completa antes de reservar.

Lo que el sistema no te deja hacer

- Reservar libremente en fechas pasadas por el circuito habitual. Se admite el inicio retroactivo en la agenda mensual y la carga de una Atención excepcional.

- Reservar sin cupo o con superposiciones incompatibles. Atención excepcional permite un día u hora fuera del horario habitual, pero conserva los controles de capacidad y superposición.

- Dar a un paciente dos turnos que se superpongan en el mismo horario.

Si aparece «El horario no tiene cupo o dejó de estar habilitado», elegí otro horario: puede haberse ocupado mientras mirabas la pantalla.

#### 3.4 Marcar asistencia

En Turnos o Inicio, en la fila del turno:

- Marcar presente: el paciente vino. Cuenta una sesión.

- Marcar ausente: el paciente faltó. No cuenta sesión.

- Marcar pendiente: deshace la marca si te equivocaste.

También existe Marcar presentes para marcar varios turnos de una vez.

Por qué a veces no te deja marcar

- Si el tratamiento está pausado en esa fecha, no se puede marcar presente ni ausente.

- Si el turno ya fue cancelado, no admite asistencia.

Ausencias automáticas. Si Administración lo activó, los turnos pendientes de días anteriores pasan solos a ausente durante la madrugada. Los reconocés porque dicen Ausencia automática. No pasan a ausente los turnos con cobros o anticipos aplicados ni los que marcaste a mano. Si el paciente sí vino, corregilo con Marcar presente.

#### 3.5 Cobrar una sesión

El cobro se registra aparte de la asistencia. El orden recomendado es:

- Marcá Presente.

- En la fila del turno pulsá Cuenta / cobros (o Cobrar ahora si se ofrece al reservar).

- Abrí el formulario de cobro, seleccioná o verificá al paciente y completá importe, medio (Efectivo o Transferencia), sede y fecha. Pulsá Revisar movimiento: el pago se aplica a las deudas más antiguas y el sobrante queda a favor. Confirmá después de revisar el detalle.

- Esperá el mensaje de confirmación.

Para reintegrar una sesión o cuota al saldo del paciente usá la acción correspondiente. No devuelve dinero de Caja. Si entregás dinero, registrá después Devolución de saldo.

Si te equivocaste en un ingreso, abrí Caja → Editar ingreso. Está disponible para Secretaría y Administración activas. Revisá los datos precargados, escribí el motivo, pulsá Revisar edición y confirmá el resultado. Cambiar paciente o importe corrige también pagos y saldos. El historial conserva quién hizo el cambio y los valores anteriores y posteriores. La anulación con contrasiento sigue siendo una acción de Administración.

Si una sesión presente no se va a cobrar. Cuando el turno está en Presente y tiene deuda, el panel Cuenta / cobros muestra Cancelar cobro. Deja la sesión sin saldo sin mover la caja, pide un motivo (mínimo 3 caracteres) y queda registrado. Conviene consultarlo antes con Administración.

Cuenta clínica. En la ficha del paciente, Cuenta clínica muestra turnos, saldos, bonos y anticipos. Historial permite consultar movimientos anteriores.

#### 3.6 Reprogramar o cancelar un turno

- Editar turno abre el formulario de reserva con los datos precargados. Elegí si el cambio afecta solo ese turno o las sesiones siguientes de la misma serie. Podés ajustar programación, importe, cobertura y observaciones; revisá el alcance antes de confirmar. En planes mensuales, el nuevo importe modifica también la cuota actual solo si todavía no tiene pagos.

- Cancelar turno pregunta si querés cancelar solo esa atención o esa y todas las siguientes de la misma serie. En una asignación indefinida, esta última opción permite retirar el horario de la agenda desde esa fecha. Conserva los registros anteriores; conviene avisar al paciente (3.9).

- Para dar otra fecha a una sesión perdida, usá la opción de recuperación del turno si está disponible: queda vinculada al turno original.

#### 3.7 Tratamientos: pausar, dar de baja y agendar más sesiones

Desde Turnos (o la ficha del paciente) abrí la asignación del paciente. Allí encontrás:


| Acción | Cómo funciona |
| --- | --- |
| Pausar tratamiento | Indicá desde cuándo (hoy o después), el motivo (obligatorio) y, si lo sabés, Fecha de regreso (opcional). La pausa conserva el lugar del paciente en el horario |
| Reanudar tratamiento | Solo se puede el mismo día en que el paciente vuelve |
| Dar de baja | Cancela los turnos pendientes desde la fecha de baja. No se puede si el paciente ya tiene asistencias posteriores a esa fecha |
| Agendar más sesiones | Abre el formulario de reserva con los datos y el horario anterior precargados. Permite modificarlos y crea una serie nueva, independiente de la anterior; según la modalidad puede requerir un bono inicial nuevo |
| Cobrar cuota / Reintegrar cuota | Solo en tratamientos mensuales. El reintegro devuelve lo pagado al saldo a favor del paciente y deja la cuota sin deuda. Si después se entrega dinero, se registra mediante Devolución de saldo |
| Cancelar saldo de cuota | Perdona total o parcialmente una cuota. Exige motivo y no mueve la caja |


Si dos personas modifican el mismo tratamiento a la vez, el sistema avisa «El tratamiento cambió. Volvé a abrirlo». Reabrilo y repetí la acción.

#### 3.8 Lista de espera

- Desde la ficha del paciente, Agregar a lista de espera, o + Nuevo registro en la pantalla Lista de espera.

- Elegí la vista Lista o Kanban y filtrá por paciente, terapia, sede, profesional, obra social y estado. La casilla de cancelados muestra también esos pedidos.

- Cuando contactes al paciente, pulsá Marcar contactado para dejar el seguimiento.

- Cuando haya un lugar, pulsá Reservar: vincula el turno con el pedido y, al confirmar la reserva, el pedido pasa a resuelto.

- Cancelar pedido lo da de baja, y Editar pedido corrige los datos.

#### 3.9 Avisos por WhatsApp

El sistema no manda mensajes por su cuenta. Al pulsar el botón se abre WhatsApp con el mensaje ya escrito y vos lo revisás y lo enviás desde tu propio WhatsApp.

- Enviar confirmación por WhatsApp: al reservar.

- Avisar reprogramación por WhatsApp: al reprogramar.

- Avisar cancelación por WhatsApp: al cancelar.

- También hay un recordatorio para turnos pendientes.

Si el navegador bloquea la ventana, permití las ventanas emergentes para el sistema. Si el paciente no tiene teléfono completo, completá la ficha primero.

Cambiar el texto de los mensajes. En el menú WhatsApp, pestaña de mensajes, podés editar los cuatro textos (confirmación, recordatorio, cancelación y reprogramación). Cada texto admite estas variables, que el sistema reemplaza por los datos del turno: {paciente}, {fecha}, {hora}, {sede}, {terapia} y {profesional}. Escribilas tal cual, con llaves; una variable que no esté en la lista impide guardar. Los textos son de 1 a 1000 caracteres y los cambios valen para todo el equipo.

La pestaña de vinculación con Meta la maneja Administración.

#### 3.10 Anticipos

Un anticipo es dinero que el paciente entrega antes de recibir la atención.

- Desde Inicio, Caja o la ficha, abrí Registrar movimiento y elegí A favor del paciente.

- Primero elegí al paciente; se abre el formulario con sus datos.

- Cargá importe, medio, sede y fecha. Revisá la distribución del pago y el saldo resultante antes de confirmar.

El dinero se registra una sola vez en Caja. Aplicarlo a una deuda no genera otro ingreso. Se utiliza primero para las deudas clínicas más antiguas y el sobrante permanece a favor. El reintegro de una sesión o cuota libera su pago al saldo; la devolución efectiva se registra como Devolución de saldo. Ortopedia conserva su circuito propio.

#### 3.11 Caja

- Elegí el período, la sede y, si querés, el medio, la terapia o categoría, el profesional y la persona que registró, y pulsá Actualizar caja.

- Los totales incluyen la clínica, ortopedia y los movimientos manuales. Los reintegros y egresos reducen el neto.

- Consultar cuenta busca la cuenta de un paciente por DNI para ver saldos.

- Registrar movimiento permite elegir el tipo y subtipo. Los ingresos pueden ser A favor del paciente u Otro ingreso. Los egresos incluyen Pago a profesional, Devolución de saldo, Reintegrar sesión, Reintegrar cuota a saldo, Gasto general y Otro. Categoría y Profesional o secretaría asociada se muestran directamente, sin abrir Más datos opcionales.

- Editar ingreso está disponible para Secretaría y Administración activas y conserva motivo e historial. El profesional del turno, bono o cuota se obtiene de las aplicaciones aunque el campo manual esté vacío. Al filtrar por profesional se suma solo su parte; el saldo sin aplicar se identifica por separado. Los ingresos anulados o reemplazados quedan como historial. Con devoluciones previas se pueden corregir datos descriptivos; paciente e importe requieren conciliar la devolución.

#### 3.12 Ortopedia y stock


| Pestaña o botón | Para qué sirve |
| --- | --- |
| Stock | Ver producto, marca, código, sede y disponibilidad. Fila amarilla: queda poco (en el mínimo o por debajo). Fila roja: sin stock |
| Venta / alquiler | Vender o Alquilar descuenta unidades. Buscá al paciente o creá su ficha con Nueva ficha |
| Devolución | Devolver unidades recupera el stock. Buscá por nombre, apellido o DNI |
| Pagos pendientes | Registrar cobro o Registrar reintegro de operaciones con deuda |
| Historial | Operaciones por período, sede y persona que registró |


Importante: devolver físicamente el producto no borra la deuda automáticamente. Si corresponde, registrá el reintegro o la regularización en Pagos pendientes. Las compras y los ajustes de stock las hace Administración. Cargar o editar un producto del catálogo también es de Administración.

#### 3.13 Documentos del paciente

En la ficha, pulsá Documentos.

- Subir: elegí hasta 5 archivos por vez. Solo se aceptan PDF, DOC y DOCX, de hasta 5 MB cada uno y 10 MB en total. Pulsá Guardar documentos y esperá la confirmación.

- Si se corta la subida, aparece «Subida sin confirmar»: elegí el mismo archivo otra vez y pulsá Verificar documentos.

- Descargar: desde la lista.

- Eliminar: pide confirmación y es definitivo.

#### 3.14 Informes y Excel

- En Informes, elegí el informe, el mes y los filtros, y pulsá Consultar.

- En Informes → Gestión de pacientes, consultá el período y los filtros y usá Descargar esta pestaña o Descargar informe completo. El completo incluye Resumen, Actividad, Agenda y acceso, Perfil y experiencia y Control del registro, con tablas filtrables y gráficos editables de Excel. Conserva el corte de la consulta; para actualizarlo hay que consultar y descargar otra vez. Los demás informes mantienen sus opciones de exportación y sus límites propios.

- El resumen para facturación utiliza la cobertura asociada al turno. Cuenta las sesiones presentes del mes seleccionado y las pendientes del mes siguiente; no emite comprobantes fiscales. Las métricas de Gestión de pacientes describen los datos registrados y deben interpretarse junto con los controles de calidad y sus denominadores.

- Un cero en un informe no prueba que no hubo actividad: puede significar que todavía no se cargó. Si un informe muestra «Registro en validación», tomalo como una descripción de lo cargado.

### 4. Cuando algo no sale como esperabas


| Qué ves | Qué significa | Qué hacer |
| --- | --- | --- |
| «No se confirmó el guardado… Usá Verificar guardado» | No llegó la respuesta; puede haberse guardado | Pulsá Verificar guardado. No cargues todo de nuevo |
| «Hay otro guardado en curso» | Otra persona está guardando en este momento | Esperá unos segundos y reintentá |
| «La sesión venció» o «Tu sesión o tus permisos cambiaron» | Se venció el ingreso o tu cuenta cambió | Ingresá de nuevo; si sigue, avisá a Administración |
| «El tratamiento cambió. Volvé a abrirlo» | Otra persona lo modificó | Reabrilo y repetí tu cambio |
| «El horario no tiene cupo o dejó de estar habilitado» | El lugar se ocupó o el horario cambió | Elegí otro horario |
| «No se pueden reservar turnos en fechas pasadas» | La fecha ya pasó | Elegí una fecha de hoy en adelante |
| «WhatsApp: teléfono incompleto» | Falta o está mal el teléfono | Completalo en la ficha |
| «El acceso todavía no está listo» | La página aún está cargando | Esperá unos segundos o recargá |
| La pantalla no responde y los botones están grises | El sistema está guardando | Esperá; si pasa mucho tiempo, recargá y revisá si se guardó |


### 5. Buenas prácticas

- Antes de reservar, buscá al paciente. Evitás fichas duplicadas.

- Revisá el DNI al crear una ficha: no se corrige después.

- Marcá la asistencia el mismo día. Cada presente descuenta una sesión y define lo que se cobra.

- Cobros y asistencia son pasos separados. Primero Presente, después el cobro.

- Nunca borres para corregir: pedí a Administración que lo anule con contrasiento y dejá el motivo claro.

- No cierres la pestaña mientras haya un guardado sin confirmar. El navegador te va a avisar si lo intentás.

- Cerrá sesión si dejás la computadora sola.

### 6. Cuándo pedir ayuda a Administración

- Crear o desactivar sedes, terapias, profesionales o sus horarios (Datos de agenda).

- Definir qué terapias comparten el espacio físico.

- Agregar obras sociales o indicaciones por terapia (Otros datos).

- Crear usuarios, cambiar roles o desactivar cuentas (Usuarios).

- Anular un movimiento de caja con contrasiento (el botón solo lo ve Administración).

- Compras y ajustes de stock, o cargar productos nuevos en Ortopedia.

- Vincular el número de WhatsApp Business con Meta.

- Cualquier mensaje de error que se repita después de recargar e ingresar de nuevo.

### 7. Preguntas frecuentes

¿Por qué me pide ingresar de nuevo al recargar la página? Porque el sistema no guarda tu sesión en el navegador. Es una medida de seguridad.

¿Un paciente en pausa ocupa lugar? Sí. La pausa conserva su horario habitual para cuando vuelva, aunque no se pueda marcar asistencia durante la pausa.

¿Los ausentes descuentan sesión? No. Solo los presentes.

¿Se completaron las sesiones y desaparecieron los turnos futuros? Es lo esperado: al completarse la cantidad autorizada, los turnos pendientes se cancelan solos. Para seguir, usá Agendar más sesiones. Si corregís una asistencia y vuelve a haber saldo, esos turnos se restauran; los que cancelaste a mano no.

Un turno pasó a «ausente» sin que yo lo tocara. Es la ausencia automática: se aplica a los turnos pendientes de días anteriores. Si el paciente vino, marcalo como presente.

¿Puedo editar los mensajes de WhatsApp? Sí, en el menú WhatsApp. Los cambios se aplican a todo el equipo.

¿El sistema envía los WhatsApp solo? No. Abre WhatsApp con el texto armado y vos lo enviás.

Hice un cobro por error, ¿lo puedo borrar? No se borra; Administración lo anula con un contrasiento. Avisale el paciente, el importe y el motivo.

### 8. Glosario


| Término | Significado |
| --- | --- |
| Presente / Ausente / Pendiente / Cancelado | Estados de un turno |
| Cupo | Cantidad de pacientes que admite un horario |
| Tratamiento o asignación | Conjunto de turnos recurrentes de un paciente |
| Pausa | Suspensión temporal que conserva el lugar |
| Baja | Fin del tratamiento a partir de una fecha |
| Cuota | Pago mensual de un tratamiento mensual |
| Anticipo | Dinero entregado antes de la atención |
| Bono | Pago inicial de un tratamiento «bono inicial + por clase» |
| Contrasiento | Movimiento que corrige otro sin borrarlo |
| Verificar guardado | Comprobación segura cuando no se sabe si algo se guardó |


## Parte B · Administración

Esta parte es para quienes tienen cuenta de Administración. Cubre lo que Secretaría no ve: datos de agenda, catálogos, usuarios, contrasientos, ortopedia avanzada y la vinculación de WhatsApp.

### 9. Qué cambia con una cuenta de Administración

Arriba a la derecha ves tu nombre y «Administración». Además de todo lo de la Parte A, tenés lo siguiente:


| Dónde | Qué podés hacer |
| --- | --- |
| Datos de agenda | Crear y editar sedes, terapias y profesionales con sus horarios; configurar el espacio compartido |
| Otros datos | Obras sociales, registro de secretarias e indicaciones por terapia |
| Usuarios | Crear cuentas, vincular cuentas existentes, cambiar permiso y estado |
| Caja | Anular con contrasiento un movimiento |
| Ortopedia y stock | Catálogo y productos nuevos, compras, ajustes de stock, configuración por sede y pago de compras |
| Turnos | Cambiar la cobertura de cualquier turno. Secretaría solo puede hacerlo en turnos pendientes o que no tenían cobertura cargada |
| WhatsApp | La pestaña de vinculación con Meta |


Tres cosas para tener presentes:

- Los permisos se controlan en el servidor, no solo en la pantalla. Si una cuenta de Secretaría intentara una acción de Administración, el sistema la rechaza.

- Tus cambios llegan a todo el equipo en el momento: horarios, terapias, mensajes de WhatsApp, usuarios. Revisá antes de guardar.

- Las reglas generales de la Parte A siguen valiendo: esperá la confirmación y, si aparece Verificar guardado, pulsalo en lugar de repetir.

### 10. Datos de agenda: sedes, terapias y profesionales

De acá salen los cupos, duraciones y horarios que ve Secretaría al reservar.

- Abrí Datos de agenda y elegí la lista: Sedes, Terapias o Profesionales.

- Buscá un registro o pulsá Crear; para modificar uno existente, Editar.

- Completá los campos y pulsá Guardar.

- Esperá «Guardado confirmado. Volvé a cargar el listado para ver los cambios» y pulsá Volver a cargar.


| Registro | Campos | A tener en cuenta |
| --- | --- | --- |
| Sede | Nombre de la sede (obligatorio, hasta 40 caracteres), Dirección, Teléfono, Observaciones, Estado | El nombre no se puede cambiar una vez creada la sede |
| Terapia | Nombre de terapia (obligatorio), Especialidad, Duración (minutos, de 5 a 480; por defecto 60), Pacientes simultáneos (de 1 a 200; por defecto 1), Estado | La duración y los pacientes simultáneos intervienen al reservar |
| Profesional | Nombre, Segundo nombre, Apellido, Matrícula, Especialidad (obligatoria), Estado, Terapias que realiza y Horarios de atención | Creá primero las terapias; se admiten hasta 40 horarios por profesional |


Horarios de atención. Cada horario lleva sede, día de la semana, Desde y Hasta. Necesitás al menos una sede activa antes de agregar horarios, y Quitar horario elimina uno. Un horario solo se ofrece para reservar si cae dentro de una franja del profesional y la terapia figura entre las que realiza.

Orden recomendado para algo nuevo: sede → terapia → profesional (con sus terapias y horarios). Después, en Turnos, consultá los horarios para confirmar que aparecen como esperás.

Inactivar en lugar de borrar. Cambiá el Estado a Inactivo: se conserva la historia. Si el registro tiene turnos futuros o pedidos de espera, el sistema avisa: «Este registro tiene N turnos futuros pendientes y N pedidos de espera abiertos. Se conservarán. ¿Querés inactivarlo?». Los turnos no se cancelan solos; si hace falta, reprogramalos o cancelalos desde Turnos. Antes de acortar una duración o quitar una franja, revisá qué reservas existen.

### 11. Espacio compartido

Sirve para saber cuántas personas coinciden en un mismo lugar físico cuando varias terapias lo usan. Se configura al final de Datos de agenda.

- En Terapias del espacio compartido, elegí las terapias que usan el mismo lugar.

- Pulsá Guardar configuración. Los próximos horarios que se consulten usarán la nueva selección.

Qué hace y qué no:

- Es solo informativo. Muestra «Espacio compartido: N» al consultar horarios; no agrega un límite físico ni cambia los cupos del profesional.

- Cuenta personas distintas con turnos pendientes o presentes que coinciden con esa sesión, en la misma sede y entre las terapias configuradas. No incluye la reserva nueva y no cuenta a los pacientes pausados.

- Sin terapias seleccionadas, el indicador deja de mostrarse.

- Si aparece «La configuración enviada no está aplicada», revisá la selección y guardá de nuevo; si cambió mientras la editabas, usá Volver a cargar.

### 12. Otros datos: obras sociales, secretarias e indicaciones

Abrí Otros datos. Hay tres listas, todas con búsqueda, Crear, Editar, estado Activo o Inactivo y la misma lógica de guardado (Guardar, confirmación y Verificar guardado si hace falta).


| Lista | Para qué sirve |
| --- | --- |
| Obras sociales | Nombre, CUIT (opcional), domicilio, localidad, correo y observaciones. Alimenta las coberturas de las fichas y los informes |
| Secretarias (registro) | Registro de las personas del equipo. No crea, habilita ni deshabilita cuentas de ingreso: eso se hace en Usuarios |
| Indicaciones por terapia | Texto que Secretaría ve con Ver indicaciones de la terapia al reservar. Se define por terapia y, según el caso, por cobertura |


Si una obra social deja de operar, pasala a Inactivo en lugar de borrarla, para no perder el dato de pacientes y turnos anteriores.

### 13. Usuarios

Abrí Usuarios. Verás una lista paginada con búsqueda por nombre o correo y el Último ingreso de cada persona.

Principios del sistema: las cuentas son individuales, todas operan todas las sedes, Secretaría no administra usuarios ni catálogos y no se envían correos automáticos.

#### 13.1 Crear un usuario

- Pulsá + Nuevo usuario.

- Completá Nombre que verá el equipo, Correo de ingreso, Permiso (Secretaría o Administración) y Contraseña inicial, de 12 a 128 caracteres.

- Pulsá Crear usuario y esperá la confirmación.

- Entregale la contraseña inicial a la persona por un canal seguro, porque el sistema no le manda ningún correo, y pedile que la cambie desde Mi cuenta en su primer ingreso.

#### 13.2 Vincular una cuenta que ya existe

Usalo cuando la persona ya tiene cuenta de acceso. Pulsá Vincular cuenta existente: la cuenta debe existir y tener el correo confirmado; pulsá Vincular y habilitar para darle acceso a Marathon con el permiso elegido.

#### 13.3 Altas pendientes

Si una creación se interrumpe (se cortó la conexión, por ejemplo), la cuenta queda en Altas pendientes. Usá Retomar alta y luego Completar alta. Retomar un alta no cambia la contraseña de una cuenta ya creada. Si ves «Operación pausada», es ese caso.

#### 13.4 Cambiar permiso, nombre o estado

- Elegí a la persona y pulsá Editar acceso.

- Cambiá el nombre, el Permiso o el Estado del acceso (Activo o Inactivo) y pulsá Guardar acceso.

Desactivar pide confirmación («Sus nuevas operaciones quedarán bloqueadas») y conserva toda la historia. La persona verá «Tu sesión o tus permisos cambiaron» al intentar operar. Desactivá el acceso el mismo día que alguien se va del equipo.

Límites de seguridad: no podés desactivar tu propia cuenta ni cambiar tu propio rol. Conviene que haya siempre al menos dos cuentas de Administración.

### 14. Caja y ortopedia: tareas de Administración

#### 14.1 Anular un movimiento con contrasiento

- En Caja, buscá el movimiento con los filtros de período, sede, medio y persona.

- Pulsá Anular con contrasiento. El botón aparece solo si el movimiento no tiene ya un contrasiento ni es uno, y si es un pago de la clínica o de ortopedia, o un ingreso o egreso manual de caja.

- En Aprobar contrasiento el sistema muestra el importe y el medio del movimiento contrario y aclara que el original se conserva. Escribí el Motivo (mínimo 3 caracteres) y confirmá. Para operaciones de ortopedia se abre el formulario propio de ortopedia.

- En la lista queda «Con contrasiento registrado» en el original y «Compensa: …» en el nuevo.

Pedí siempre el dato de quién lo solicitó y por qué: el motivo es lo que explica el movimiento en una auditoría.

#### 14.2 Ortopedia


| Acción | Cómo se hace |
| --- | --- |
| Nuevo producto / Editar producto | Desde el catálogo. Cargá Precio de venta, Precio semanal de alquiler y Costo de compra (opcional). Si falta precio o costo, el sistema avisa «Falta precio o costo en el catálogo» |
| Configurar por sede | Habilitá la sede para ese producto, definí el Stock mínimo y cargá las unidades iniciales una sola vez. Después se usan compra o ajuste. Un producto no habilitado en una sede no se puede operar ahí |
| Comprar | Registra la compra de unidades. Si queda deuda, aparece en Pagos pendientes |
| Pagar compra | Registra el pago de una compra con deuda |
| Ajuste positivo / Ajuste negativo | Corrige el stock por diferencias de inventario |
| Traslado entre sedes | Elegí Sede de origen y Sede de destino y pulsá Transferir; queda un «Traslado vinculado». Este botón también está disponible para Secretaría |


El Estado del stock del filtro distingue Bajo mínimo, En mínimo y Sin stock informado. Recordá que una devolución recupera stock pero conserva la deuda: el reintegro se registra aparte en Pagos pendientes.

### 15. WhatsApp: vinculación con Meta

El menú WhatsApp tiene dos pestañas. Mensajes automáticos es la misma que ve Secretaría. La pestaña de conexión es solo para Administración.

Qué logra y qué no. Vincular un número prepara la conexión del WhatsApp Business de Marathon con el sistema. Hoy los avisos de turno siguen saliendo desde el WhatsApp de cada secretaria con el texto armado (Parte A, 3.9). El propio asistente aclara que la bandeja de chat y el envío dentro del CRM requieren su propia habilitación.

Requisitos. Una aplicación de Meta con registro insertado v4, permisos aprobados y la modalidad de coexistencia de WhatsApp Business habilitada por Meta o por un proveedor autorizado. La persona que configura debe administrar la cuenta de Marathon en Meta.

- Preparación inicial. En la pestaña de conexión cargá el ID de aplicación de Meta, el ID de configuración del registro insertado y la Clave secreta de la aplicación de Meta, y tildá la modalidad de coexistencia. Pulsá Guardar preparación. La clave se guarda cifrada en el servidor; para conservarla en una edición posterior, dejá el campo vacío.

- Configurar Meta. En Direcciones para configurar en Meta copiá (seleccionando cada campo) el dominio autorizado y la URI OAuth, la URL de devolución de eventos y el Token de verificación, y pegalos en la consola de Meta.

- Revisar estado. Pulsá Revisar estado hasta ver «Recepción de eventos verificada por Meta».

- Vincular el número. Con «Preparado», pulsá Vincular número y después Vincular WhatsApp. Se abre una ventana oficial de Meta: ingresá con la cuenta que administra Marathon, elegí el número existente, revisá los permisos y confirmá en el celular. Si hay varios números, el sistema pide «Elegí el número que querés vincular».

- Resultado. Ves «Número autorizado y conexión verificada» con el número vinculado. Verificar vinculación y Renovar autorización quedan disponibles para más adelante.

Importante: para autorizar el número hay que abrir el sistema publicado con dirección https. La versión local solo permite preparar la configuración. Cada intento de vinculación vence a los 10 minutos.

Si falla, los mensajes más comunes son: «No se pudo cargar Meta. Revisá la conexión o el bloqueador de contenido» (desactivá el bloqueador para el sitio), «La autorización no se completó. Pulsá Revisar estado antes de volver a iniciar» y «Meta no devolvió la información del número a tiempo. Revisá los dominios y volvé a iniciar».

### 16. Rutina, seguridad y resolución de problemas

#### 16.1 Rutina sugerida


| Cuándo | Qué revisar |
| --- | --- |
| Al sumar una terapia o profesional | Crear terapia, luego profesional con terapias y horarios, y probar con Consultar horarios en Turnos |
| Cada semana | Informes (Gestión y Pacientes), Altas pendientes, movimientos con contrasiento y stock bajo mínimo |
| Cuando alguien se va | Desactivar el acceso en Usuarios el mismo día |
| Cuando cambian los textos de aviso | Editarlos en WhatsApp → Mensajes automáticos y avisar al equipo |


#### 16.2 Seguridad y respaldo

- Usá cuentas individuales y contraseñas de 12 a 128 caracteres. Nunca compartas una cuenta de Administración.

- Las claves de Meta se guardan cifradas en el servidor. No las pegues en chats, planillas ni correos.

- La sesión no se guarda en el navegador; en computadoras compartidas, Cerrar sesión al terminar.

- Todo lo que se carga es real, también en una copia local del sistema, que usa los mismos datos de producción. No pruebes con pacientes inventados.

- Las ausencias automáticas de turnos pendientes no tienen pantalla de configuración: se activan o desactivan en la base de datos. Pedilo a quien mantiene el sistema.

- La información vive en Supabase; el paquete de archivos del sistema no es una copia de seguridad. Confirmá con quien administra Supabase que existan respaldos programados y quién puede restaurarlos.

#### 16.3 Mensajes frecuentes de Administración


| Mensaje | Qué significa | Qué hacer |
| --- | --- | --- |
| «Solo administración.» | La cuenta no tiene permiso de Administración | Verificá el permiso en Usuarios |
| «La cuenta debe existir y tener el correo confirmado…» | Al vincular, la cuenta no existe o no confirmó el correo | Confirmar el correo de la cuenta y repetir |
| «Operación pausada…» | Un alta quedó a medias | Retomar alta y Completar alta |
| «Creá una sede activa antes de agregar horarios» | El profesional no tiene sedes donde asignar horarios | Crear o activar una sede |
| «Creá primero las terapias que atiende este profesional» | Aún no hay terapias para asignar | Crear las terapias primero |
| «Se admiten hasta 40 horarios» | Se superó el máximo de un profesional | Quitar horarios que sobren o unificar franjas |
| «Sede todavía no habilitada para este producto» | El producto no está configurado en esa sede | Configurar por sede |
| «Falta precio o costo en el catálogo» | El producto no tiene precio o costo cargado | Editar producto |
| «La configuración enviada no está aplicada» | El espacio compartido cambió mientras se editaba | Volver a cargar y guardar de nuevo |




