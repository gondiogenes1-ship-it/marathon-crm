# Estado actual — 04/11/2026

Versión base: **0.14.0**, con revisión de interfaz y accesos del 01/11/2026.
Producción: https://marathon-crm-liart.vercel.app/
Deployment actual: `dpl_BBpwG4rCtJcPoFAUbiajDxw9htu8` (READY).
Anterior: `dpl_aDXBraFUJJ1Wi3FnRLCYS9R1r6pH`.

## Cambios vigentes

- Se restauró el diseño original. No se usa Marathon Claro ni el tema Stitch.
- Reservar turno aparece junto a los cupos libres. En fechas pasadas está deshabilitado; no se ofrece en cupos completos o bloqueados.
- Recibir anticipo se encuentra en Inicio y Caja. Primero exige seleccionar un paciente; luego reutiliza el formulario de la ficha y el comando de anticipo existente.
- En venta/alquiler de Ortopedia se puede crear o editar una ficha con el mismo editor de Reservar turno. Al guardar se selecciona el paciente y se conservan los campos de la operación.
- En Stock de Ortopedia, las filas con cantidad positiva menor o igual al mínimo se muestran amarillas. Cero o negativo se muestran rojas. Son fondos translúcidos; el texto de estado sigue visible. Los valores no informados no se marcan como cero.

## Código y pruebas

Frontend estático en public/index.html, módulos JavaScript y CSS sin compilación ni dependencias npm.
Código de backend disponible en supabase: SQL acumulativos, migraciones y funciones. No es una reconstrucción completa de la base desde cero.
Pruebas locales de los cambios en tests/: ejecutar `node tests/verificar-anticipo.mjs`, `node tests/verificar-ficha-ortopedia.mjs` y `node tests/verificar-boton-reserva.mjs`. Utilizan datos simulados; no hacen operaciones reales.

## Publicación

Vercel: equipo marathon-crm, proyecto marathon-crm.
Project ID: prj_NzIS0BFdWyclXltmOViGWydLgS0O.
Team ID: team_Hv9dp9bsgHq1Hns11NHHaRM8.
La configuración existente usa Root Directory Marathon_Vercel_0112. Para desplegar por archivos, colocar dentro de esa carpeta técnica el contenido de public. La carpeta técnica no es el número de versión actual.
Framework: ninguno. Build/install: vacíos. Output Directory: punto.
No publicar Documentacion, tests, respaldos, logs, credenciales ni prototipos.

## Base de datos

Se usa el proyecto Supabase ya configurado. Las migraciones acumulativas existentes se conservan; no volver a ejecutarlas por instalar en otra PC.
No se cambiaron tablas, permisos ni datos al organizar esta entrega. Para un proyecto nuevo es necesario revisar el esquema base y las dependencias; estos SQL no son un volcado completo.


## Actualización 02/11/2026 — turnos cancelados

Deployment: dpl_aDXBraFUJJ1Wi3FnRLCYS9R1r6pH. Secretaría excluye cancelados de Inicio, Agenda, contadores y exportación. Administración conserva la consulta completa; el historial y los registros se conservan. El filtrado en marathon_agenda_search se aplica antes de paginar para ambos formatos. Prueba local: node tests/verificar-cancelados-secretaria.mjs. Verificación de base con roles activos, sin modificar turnos.


## Revisión local 04/11/2026 — Etapa 1 de interfaz

Preparada para revisión, todavía sin publicar. Archivos CSS e index.html actualizados en public. No se cambiaron JavaScript ni Supabase. Informe: UI_Etapa1_20261104/RESUMEN_ETAPA_1.md. Respaldo: ../Respaldos/UI_Etapa1_20261104. La versión online conserva el despliegue indicado arriba.


## Publicación 04/11/2026 — Etapa 1 aprobada

Publicada en Vercel, estado READY. Los 48 archivos públicos servidos coinciden byte por byte con public/. Fuente principal: Ultima version del CRM en CRM SUPABASE. Registro: DESPLIEGUE_20261104_UI_etapa1.json. Etapas 2 a 5 pendientes. Las notas previas de revisión local describen el estado anterior a esta publicación.


## Importación de datos — 04/11/2026

Se trasladaron de Sheets las operaciones del 03/11 y sus series vinculadas: 6 pacientes, 179 turnos (143 desde hoy), 12 cobros y 3 anticipos con 3 aplicaciones. La aplicación sigue en el mismo despliegue; los datos están en Supabase. Respaldo privado en CRM SUPABASE/Respaldos/Importacion_Sheets_20261103.


## Asistencia desde el 02/11 — actualización del 04/11/2026

Transacción confirmada: 39 presentes de la planilla (33 existentes y 6 incorporados), más un turno raíz anterior necesario para conservar una serie, y 3 cobros vinculados. Respaldo en CRM SUPABASE/Respaldos/Presentes_desde_20261102. Ver RESUMEN.md para detalle de la verificación.


## Caja con saldo a favor — Fase 1, 04/11/2026

Diseño documentado, pendiente de aprobación: Documentacion/Caja_saldo_a_favor/FASE_1_RESUMEN_PARA_APROBAR.md y FASE_1_DISENO.md. Respeta las decisiones de bonos como deuda única, reintegro a saldo con sesión sin deuda, permisos actuales y atajos Cobrar. Solo documentación; no hay migraciones nuevas, cambios de aplicación ni publicación.

## Profesional del cobro mensual — 04/11/2026

Corregida en Supabase la subconsulta que registraba cuotas mensuales sin profesional por un conflicto entre la variable h y el alias SQL. Se completó la asociación del único movimiento afectado, validando un solo profesional en sus horarios y conservando sus datos financieros. Caja ya lo muestra. No fue necesario desplegar el frontend. Detalles: PROFESIONAL_CUOTA_MENSUAL_20261104.md.

## Caja: egresos por medio y descarga Excel — revisión local 04/11/2026

Pendiente de publicar en Vercel: operations.js muestra los egresos discriminados bajo cada neto y agrega Descargar Excel en Caja. public/cash-export.js reutiliza el exportador XLSX original, recorre todas las páginas con una copia de los filtros de la última consulta aplicada, incluye columnas separadas de ingreso/egreso/neto y resúmenes por medio y general. Prueba: node tests/verificar-excel-caja.mjs (datos simulados). No modifica movimientos ni requiere migraciones.


## Publicación Caja y Excel — 04/11/2026

Cambios anteriores de egresos por medio y Descargar Excel publicados en producción. Deployment dpl_GeSpefCwrUsYk4xe1kT2NgnwGabQ, READY; 49 archivos servidos verificados. El usuario indicó publicar en Vercel las versiones de este CRM una vez terminadas y verificadas.


## Caja y saldo a favor — Fase 2 local (04/11/2026)

Motor y conversion de historicos preparados y probados exclusivamente en bases locales sinteticas. NO se aplicaron en Supabase ni se publico esta mejora. Las nuevas migraciones caja_saldo quedan pendientes; no ejecutarlas por actualizar la carpeta. Entrega y limites: Caja_saldo_a_favor/Fase_2_aislada/ENTREGA_FASE_2.md. Evidencia: RESULTADO_PRUEBAS.json. Fase 3 de pantallas pendiente del OK entre fases solicitado por el usuario; migracion real pendiente de respaldo completo restaurado y conciliacion del corte.



## Caja y saldo — Fase 3 local (04/11/2026)

Pantallas integradas y demostracion aislada en http://127.0.0.1:8776/ con pacientes ficticios. Cobrar desde Inicio sigue como atajo del formulario unico. Reintegrar cuota deja lo pagado a favor y no devuelve dinero; Devolucion de saldo registra la salida posterior. Cinco suites SQL, concurrencia, roles y regresiones JavaScript verificadas. Entrega: Caja_saldo_a_favor/Fase_3_interfaz/ENTREGA_FASE_3.md. NO publicada ni activada en Supabase/Vercel por esta tarea. Fase 4 y corte real pendientes de aprobacion, respaldo restaurado y conciliacion.

## Estado vigente — Caja y saldo ACTIVOS, 05/11/2026

Este estado reemplaza los estados pendientes de las fases anteriores, que se conservan como historial. Mejora autorizada por Gonzalo, publicada en https://marathon-crm-liart.vercel.app/ y activada en Supabase el 05/11/2026 a las 00:56:30 de Buenos Aires. Deployment dpl_Etb73WBC9wKxKu9Wk2p4A1hu9xKB READY; 52 archivos servidos coinciden con la fuente local.

Respaldo completo de base creado y restauración del CRM comprobada antes del corte. Se compararon las 41 tablas originales antes y después: ningún registro original alterado. Los 53 movimientos de Caja se conservaron y no se agregaron ingresos o egresos físicos por la conversión. Se importaron 43 fuentes y 44 aplicaciones; saldo disponible total $166.000, incluidos $40.000 de Carlos Ducasse. Los dos movimientos de prueba de Gonzalo se conservaron en Caja y no generan saldo.

Cobrar desde Inicio continúa como atajo. Reintegrar cuota o sesión acredita lo pagado al saldo y deja el cargo sin deuda; la devolución real del dinero se registra aparte desde Devolución de saldo. Pago a profesional exige profesional y terapia. Ortopedia conserva su circuito.

Actualizar la página e iniciar sesión para cargar la nueva versión. Guía: Caja_saldo_a_favor/GUIA_USO_ACTIVA.md. Evidencia completa: DESPLIEGUE_20261105_saldo_activo.json y Caja_saldo_a_favor/Corte_20261105/. No repetir la migración de activación ni aplicarla a otra base: contiene el control específico del corte de esta instalación. No restaurar el respaldo sobre producción automáticamente, porque se perderían operaciones posteriores al corte.


## Medios históricos y Caja — 05/11/2026

Revisión posterior publicada: dpl_21QAaFbXiKtBHqSJNtfZBXDw97e8, READY; 52 archivos comprobados. Los 53 movimientos coinciden con el respaldo: 41 efectivo y 12 transferencia. No se modificaron medios ni importes. Las aplicaciones internas del historial ahora identifican el medio del recibo original con la aclaración de que no hay dinero nuevo. Caja muestra ingresos y egresos para cada medio además del neto; filas, filtros y totales conciliados con los movimientos. Comparación final de las 41 tablas originales sin diferencias. Evidencia: REVISION_MEDIOS_HISTORICOS_20261105.json.

## Edición y cancelación por alcance — 05/11/2026

Publicado en Vercel (dpl_FWSiWX6jvNXBm4wr7F6yxbNwkZNA, READY; 53 archivos servidos comprobados). Cancelar permite una sesión o desde ese día en adelante, con baja real de planes indefinidos. Editar reutiliza el formulario de Reservar turno, precargado, con alcance individual o futuro; admite primera fecha y horario/sede/profesional por día. Se protegen los datos financieros y de autorización. Historial anterior y excepciones canceladas se conservan mediante reglas con vigencia temporal. Nueva migración 20261105131658_agenda_edicion_cancelacion_desde_turno.sql ya instalada.

Pruebas de series en copia restaurada y cinco suites financieras sintéticas PASS. Prueba de navegador con datos ficticios y prueba de contexto/vista previa en producción revertida. No se probaron guardados sobre turnos reales. Los 53 movimientos anteriores coinciden con el respaldo. Hubo nuevas operaciones legítimas del personal durante el despliegue, conservadas; no confundir esas altas con cambios de la migración. Guía: GUIA_EDITAR_CANCELAR_SERIES.md. Evidencia: DESPLIEGUE_20261105_edicion_cancelacion_series.json.

## Condiciones futuras y nueva serie precargada — 05/11/2026

Estado vigente: deployment dpl_6xq33rughtwVuPy2wrp9e84Y2zQv, READY; 53 archivos servidos verificados. Editar turno admite importe, cobertura y observaciones por sesión o desde el corte. Las reglas futuras guardan sus condiciones; el historial y los cobros anteriores se conservan. Por decisión del usuario, la cuota mensual actual se modifica si no tiene pagos; si tiene pagos o ajustes se conserva y la tarifa nueva rige para las próximas cuotas.

Agendar más sesiones utiliza Reservar turno con todos los datos anteriores precargados y editables. Crea una NUEVA serie, permite un nuevo bono y no copia pagos previos. Conserva el mismo horario por defecto. Se cierra únicamente la repetición virtual anterior desde el nuevo inicio, sin cancelar sus turnos ya agendados. Un fallo de la nueva reserva revierte también ese cierre; un paciente diferente no modifica el tratamiento de origen. Se retiraron Cambiar cobertura y Crear asignación habitual.

Migraciones 20261105135154 y 20261105141935 instaladas y alineadas con el historial de Supabase. Controles de instalación compararon 49 y 50 tablas dentro de las respectivas transacciones y confirmaron que no se modificaron datos anteriores. Pruebas financieras, de series y de nueva serie PASS; navegador con pacientes ficticios y RPC de precarga en producción verificados sin guardar operaciones reales de prueba. Guía: GUIA_EDITAR_CANCELAR_SERIES.md. Evidencia: DESPLIEGUE_20261105_condiciones_y_nuevas_series.json.


## 05/11/2026 · Corrección de Editar turno
- Fecha y sede se cargan antes de reconstruir las opciones: terapia y profesional quedan precargados correctamente al abrir desde una semana o día diferente.
- Sede, terapia y profesional habilitados. La cabecera actualiza los horarios por día sin reiniciar importe, cobertura ni observaciones. Cambiar el alcance conserva los datos ya editados.
- Se admite cambiar terapia para una sesión o desde la seleccionada en adelante; reglas temporales y excepciones individuales conservan el historial. Se mantiene paciente, modalidad de cobro y cantidad autorizada.
- Migración 20261105150833_agenda_edicion_campos_completos.sql: columnas privadas nullable terapia_override, controles de tratamiento compatibles y validación de cupos. El guardado de instalación compara todas las tablas de datos y revierte si se cambia algún registro.
- Pruebas: agenda_series_scope, agenda_condiciones_scope, agenda_nueva_serie y agenda_edicion_terapia PASS. Asistencia y cobro tras cambiar terapia comprobados en copia local. Navegador: guardado completo con paciente ficticio; ningún guardado de prueba en producción.
- Producción Vercel dpl_DLx9i5q6KNiRqUCgABT54yhnBqa7 READY; revisión editar-campos-5. Los 53 archivos servidos coinciden con los archivos locales por SHA1.


## 05/11/2026 · Agenda mensual con inicio y fin
- Al reservar con modalidad de agenda Mensual, se muestra Fecha de fin opcional. Fecha de inicio admite días anteriores a hoy solo para Mensual. Fin es inclusivo; vacío mantiene continuidad.
- Los límites se guardan en plan, horarios y período de cuotas. No hay sesiones ni renovaciones posteriores al fin. Las cuotas mantienen importe mensual completo, sin prorrateo automático, explicado antes de confirmar.
- Las sesiones pasadas de una reserva mensual retroactiva se cargan pendientes de revisión y quedan protegidas del cierre automático de asistencia. No se crea ningún ingreso de Caja al reservar.
- Pruebas agenda_mensual_fechas PASS en dos copias locales; condiciones, nueva serie y edición de terapia PASS. Reserva real de prueba solo en demostración local para Marina Mensual de prueba, 02/11 a 30/11, 1 cuota de ejemplo.
- Migración 20261105180938_agenda_mensual_inicio_fin.sql instalada en Supabase con comparación de todas las tablas: ningún registro previo cambiado. Publicación en Vercel en verificación.

- Vercel aceptó la publicación dpl_8QsJ9nAFTzHWLU9kakT1RD8sUTXL, que permanece QUEUED por la incidencia oficial “Build delays and degraded Vercel Dashboard performance” (05/11 18:25 UTC, https://www.vercel-status.com/). La versión pública anterior continúa activa. No dar por completada la activación hasta READY y verificar archivos con MANIFIESTO_20261105_mensual_fechas.json. No generar otra publicación mientras esta permanezca en cola.

- Actualización final: dpl_8QsJ9nAFTzHWLU9kakT1RD8sUTXL READY y dominio de producción activo. Verificados los 53 archivos públicos por SHA1 contra el manifiesto, sin diferencias. URL: https://marathon-crm-liart.vercel.app/?revision=mensual-fechas-1 .


## 05/11/2026 · Excel de las pestañas de Informes
- Gestión de pacientes: Descargar esta pestaña y Descargar informe completo. El completo contiene Resumen, Actividad, Agenda y acceso, Perfil y experiencia y Control del registro.
- Exportación nativa XLSX en el navegador, con tablas filtrables y gráficos de barras/líneas editables vinculados a las celdas. Se conserva el corte, los filtros consultados y la dimensión seleccionada. No se vuelve a consultar ni se modifica la base al descargar.
- Se conservan pacientes únicos institucionales sin sumar grupos o días, tasas sin base como Sin base, cobertura de la atención, espera actual y límites de las métricas. Incluye mapa de horarios con formato condicional.
- Diseño contrastado con las guías de Microsoft de organización de hojas, accesibilidad y selección de gráficos, y la skill Spreadsheets. Gráficos sin 3D, ejes de barras desde cero, unidades y fechas explícitas, series de líneas distinguibles con trazo además de color.
- Validación: cinco descargas individuales, completo, vacío y texto literal; ZIP/XML, relaciones, referencias y gráficos nativos verificados. Importación y render con Artifact Tool correctos. Descargas completas e individuales comprobadas por navegador con datos ficticios. Al cambiar filtros se deshabilitan ambas hasta consultar nuevamente.

- Publicación final: dpl_4zxCoBDNYG7L4U3qce3FfkCpaeKM READY. Verificados 54 archivos públicos por SHA1, sin diferencias. Revisión informes-excel-3. No se hicieron cambios de esquema ni escrituras de datos en producción.


## 06/11/2026 · Atención excepcional en la reserva existente
- Se conserva la pestaña y el formulario de Reservar turno. Se agrega únicamente la casilla Atención excepcional con descripción breve. Desmarcada mantiene el flujo habitual. Marcada permite una atención puntual en fechas pasadas o fuera del día/hora habitual, con hora libre y duración de la terapia.
- No crea horarios, series, autorizaciones ni cuotas. Valida paciente, profesional y terapia activos, cupo y superposiciones incompatibles. Se guarda Pendiente; Presente y cobro siguen por el circuito existente. Las cargas pasadas quedan protegidas de la ausencia automática por ser una carga posterior.
- Identificación en observaciones y auditoría, con actor e idempotencia. Edición de excepciones pendientes y restauración tras cancelación compatibles con horarios excepcionales. Al guardar desde Turnos se muestra la agenda de la fecha para encontrar la atención fuera de la grilla habitual.
- Migración 20261106204407_atencion_excepcional_puntual.sql: columna nullable excepcional y RPC de previsualización/guardado con permiso de usuario activo. Guardián transaccional comparó todas las tablas y confirmó que la instalación no cambió datos existentes.
- Pruebas: atención excepcional PASS en dos copias; en la copia con saldo activo se comprobó Presente y cobro por transferencia. Domingo sin horarios, profesional en otra sede simultánea, superposición del paciente, preview reversible, reintentos y controles de permisos verificados. Agenda normal, condiciones y mensualidades PASS. La prueba de series se hizo con reloj local de día hábil dentro de una transacción revertida, dado que mañana es sábado.
- Navegador local con datos ficticios: misma reserva, casilla activada/desactivada conserva importe y restituye la modalidad normal; fecha pasada y hora 19:35 guardadas correctamente. No se hicieron reservas de prueba en producción.
- Producción Vercel dpl_5AuBrJXb2maGr2tXWkXSsTAx2JVb READY; 54 archivos públicos verificados por SHA1, sin diferencias. Revisión excepcional-1. Se conservaron los módulos de Informes Excel y agenda mensual.


## 06/11/2026 · Profesional en Caja y filtro del saldo aplicado
- Causa: SALDO_INGRESO conserva el ingreso una sola vez y las atenciones pagadas se vinculan mediante saldo_aplicaciones. Caja leía únicamente los enlaces directos antiguos y mostraba esos ingresos sin profesional.
- Se incorpora lectura privada de la distribución vigente por sesión, bono y cuota. Usa el profesional y terapia de la atención; cuotas de un único profesional toman el horario válido del período. Una cuota con varios profesionales no recibe una asignación arbitraria.
- Cada ingreso sigue siendo un solo movimiento. Se muestran las partes por profesional y terapia, saldo disponible sin aplicar y saldo efectivamente devuelto. Al filtrar profesional/terapia se suma solo la intersección de sus aplicaciones y se conserva visible el monto original. La anulación continúa sobre el movimiento completo.
- Excel de Caja comparte filtros, importes atribuidos y referencia al monto original. Se agregan filtros Sin profesional / saldo sin aplicar y categorías de saldo sin aplicar/devuelto. Los informes de gestión y el resto de la agenda se conservan.
- Migración 20261106215440_caja_profesional_aplicaciones.sql: solo funciones de consulta. Guardia transaccional con comparación completa de movimientos, fuentes, aplicaciones y eventos PASS; no se modificaron datos ni medios existentes.
- Pruebas locales PASS: sesiones, bono y cuota; pago compartido entre dos profesionales; remanente; filtros cruzados; efectivo y transferencia; paginación sin duplicados; reintegro a saldo y devolución física; autorización. Excepcional/PRESENTE/cobro PASS. Navegador y descarga Excel PASS.
- Producción: 19 movimientos del 06/11 conservados; 12 ingresos con aplicación muestran profesional por $72.000 aplicados. Totales efectivos verificados sin diferencias contra movimientos: ingresos efectivo $230.000, transferencia $18.000, egresos efectivo $21.800. Todos los históricos concilian por movimiento. Lectura según aplicaciones vigentes; no es una liquidación histórica congelada.
- Publicación Vercel dpl_3SeFY2ZQorG5qrhGajfTHbVgxNht en verificación. Revisión caja-profesional-1.

- Publicación final: READY y dominio principal activo. Los 54 archivos públicos coinciden por SHA1, sin diferencias. URL: https://marathon-crm-liart.vercel.app/?revision=caja-profesional-1 .


## 06/11/2026 · Campos opcionales visibles en Registrar movimiento
- Se elimina el desplegable Más datos opcionales: Categoría (opcional) y Profesional o secretaría asociada se muestran directamente en el formulario. Se conservan los controles específicos por subtipo y el profesional/terapia obligatorio de Pago a profesional.
- Cambio exclusivamente visual, sin migraciones ni escrituras en Supabase. Comprobado en navegador con datos ficticios; ningún movimiento de prueba registrado.
- Vercel dpl_AraCKuudz8k3wY3qBKjcAGo6xKSn READY; 54 archivos públicos verificados sin diferencias. Revisión campos-visibles-1.


## 06/11/2026 · Editar ingresos de Caja · Solo Administración
- Botón Editar ingreso en ingresos originales vigentes, exclusivo ADMIN tanto en interfaz como en tres RPC de base (consulta, preview y guardado). Formulario precargado: subtipo, paciente con buscador/ficha, importe, fecha/hora, medio, sede, concepto, observaciones, categoría, profesional/secretaría y terapia manual. Motivo obligatorio. Autor de registro y auditoría no se pueden falsificar.
- Cambios descriptivos y de medio conservan íntegramente las aplicaciones. Cambios de paciente, importe o clasificación revierten las aplicaciones previas y registran un ingreso corregido por el circuito de saldo, con deuda pendiente y crédito correspondientes. La confirmación exige huella y versiones vigentes; el preview revierte todas sus escrituras.
- Original y contrasiento técnico permanecen en movimientos y ledger, enlazados por cash_edits y operation_audit; no se muestran como dinero nuevo en Caja. Caja, Inicio y exportación comparten la lectura efectiva. Historial accesible al abrir la edición de la versión vigente, con antes/después, motivo, usuario y fecha.
- La asociación manual no modifica al profesional del turno/bono/cuota. Ingresos anulados o reemplazados no se vuelven a editar. Con devolución física previa se permite corregir datos descriptivos; paciente/importe requieren conciliar la devolución. Cambios de paciente/importe de ventas permanecen en el circuito de Ortopedia para conservar artículos y stock.
- Migración 20261106224224_caja_editar_ingresos_admin.sql instalada con guardia de integridad completa de movimientos, fuentes, aplicaciones y eventos: PASS, ningún dato previo cambiado. No se realizó ninguna edición de prueba en producción.
- SQL PASS en dos copias, cinco variantes históricas PASS, autorización/huella/reintentos/preview, reducción y cambio de paciente, medio, clasificación e ingresos con devoluciones. Pruebas de aplicaciones/profesional y atención excepcional PASS. Navegador local: corrección guardada de $12000 efectivo a $9000 transferencia; ingreso efectivo y totales correctos.
- Producción dpl_GuZZCDMi4C5YAf6sr3XpNS2Ceku1 READY. Los 55 archivos servidos coinciden por SHA1, sin diferencias. URL: https://marathon-crm-liart.vercel.app/?revision=editar-ingreso-1 .


## 06/11/2026 · Edición de ingresos también para Secretaría
- Nueva autorización expresa del usuario: Editar ingreso disponible para ADMIN y SECRETARIA activos. Cambian el botón y los controles de consulta/preview/guardado/helper/guardia de corrección; se mantienen funciones internas privadas, auditoría, motivo, huella, idempotencia y reglas de conciliación. Título del formulario Editar ingreso.
- Pruebas completas de edición y cinco variantes históricas PASS con rol SECRETARIA. Inactivos y anónimos continúan rechazados. Consulta de producción verificada con Secretaría activa no administradora; no se guardaron cambios reales durante las pruebas.
- Migración 20261106225955_caja_edicion_secretarias.sql aplicada con guardia completa de integridad financiera PASS. Seguridad conserva los conteos 19/71/1.
- Vercel dpl_3vspdZu7ivx6LjuAzcPDQrwTGXho READY; 55 archivos servidos verificados por SHA1 sin diferencias. URL: https://marathon-crm-liart.vercel.app/?revision=editar-secretarias-1 .
