# Estado actual — 6 de noviembre de 2026

Versión base: 0.14.0. Revisión publicada: editar-secretarias-1.
URL: https://marathon-crm-liart.vercel.app/?revision=editar-secretarias-1
Deployment: dpl_3vspdZu7ivx6LjuAzcPDQrwTGXho, READY.
Última migración aplicada: 20261106225955_caja_edicion_secretarias.sql.
Registro: DESPLIEGUE_20261106_editar_secretarias.json. El manifiesto identifica 55 archivos servidos; public contiene además vercel.json.

## Agenda y pacientes

- Se conserva el diseño Marathon, la barra verde, el contraste y los controles legibles.
- Reservar turno junto a los cupos y editor de ficha compartido.
- Editar turno utiliza la reserva precargada y permite una atención o las siguientes de la misma serie.
- Importes, coberturas y observaciones se modifican desde la fecha elegida. Una cuota mensual actual cambia solo si no tiene pagos.
- Cancelación de una atención o de esa y las siguientes; permite retirar una asignación indefinida desde una fecha.
- Agendar más sesiones crea una serie nueva con datos y horario precargados, todos modificables; puede corresponder un bono nuevo.
- Modalidad mensual con inicio y fin opcional inclusive, carga retroactiva y cuota mensual completa sin prorrateo automático.
- Atención excepcional en el mismo formulario: atención puntual fuera de día/hora habitual, incluso pasada. No cambia horarios ni crea serie; conserva controles de superposición. Se guarda Pendiente y se registra luego asistencia y cobro.

## Caja y saldo a favor

- Un ingreso se registra una vez; las aplicaciones a sesiones, bonos y cuotas no duplican Caja.
- Se aplican primero las deudas más antiguas y el sobrante queda a favor.
- Reintegrar sesión o cuota acredita saldo; para entregar dinero se usa Devolución de saldo.
- Los medios de pago se conservan y se muestran en Caja e historial.
- Profesional y terapia se obtienen de la atención pagada. Al filtrar se suma solo su parte; el saldo sin aplicar queda identificado.
- Registrar movimiento muestra directamente categoría y profesional o secretaría, sin desplegar Más datos opcionales.
- Editar ingreso está habilitado para ADMIN y SECRETARIA activos. Permite revisar paciente, subtipo, importe, medio, fecha/hora, sede, concepto, observaciones y asociaciones manuales. Exige motivo, vista previa y confirmación.
- Cambiar paciente o importe corrige aplicaciones, deudas y saldos. Cambiar solo medio o datos descriptivos conserva aplicaciones.
- Antes/después, motivo, responsable y fecha quedan en historial. Las versiones reemplazadas y su contrasiento técnico se conservan y Caja muestra la versión efectiva.

## Límites vigentes

Los ingresos anulados o reemplazados quedan como historial. Con devolución física previa, paciente e importe requieren conciliación; los datos descriptivos pueden corregirse. Las ventas mantienen su circuito de Ortopedia para cambiar paciente o importe. Una asociación manual no reemplaza al profesional del turno, bono o cuota.

## Informes y Ortopedia

Gestión de pacientes ofrece Resumen, Actividad, Agenda y acceso, Perfil y experiencia y Control del registro. Descargar esta pestaña o Descargar informe completo genera Excel con tablas y gráficos editables, filtros y corte. Las descargas no se actualizan solas.

La consulta de facturación apoya trámites y no emite comprobantes fiscales. La experiencia del paciente y los diagnósticos requieren registros propios. Los indicadores describen datos cargados y no prueban por sí mismos mejoras de desempeño.

Ortopedia conserva venta/alquiler, devolución, cobros y stock. Bajo o mínimo: amarillo; sin stock: rojo translúcido. El editor compartido permite crear o editar la ficha.

## Verificación y continuidad

Las funciones de edición y cinco variantes históricas se probaron en copias locales con ADMIN y SECRETARIA. Inactivos y anónimos siguen excluidos. Las instalaciones compararon movimientos, fuentes, aplicaciones y eventos; no modificaron registros existentes.

La revisión del informe desarrolla el ciclo de mejora continua y la utilidad de los tableros. Las nuevas propuestas se documentan en PENDIENTES_DEL_INFORME.md; esta entrega documental no las implementa.

El esquema consultado tiene 51 tablas y 520 campos en marathon. DICCIONARIO_SUPABASE_20261106.json contiene solo estructura y restricciones. Los SQL son acumulativos y no un respaldo completo. Los respaldos privados permanecen en la carpeta Respaldos, fuera del ZIP.

La documentación anterior se conserva en Historico_antes_actualizacion_20261106. Sus fechas y decisiones fueron reemplazadas por esta síntesis.
