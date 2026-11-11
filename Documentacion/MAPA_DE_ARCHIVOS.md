# Mapa de archivos — revisión del 06/11/2026

| Ruta | Responsabilidad |
| --- | --- |
| public/index.html | Pantallas y formularios; entrada de la app publicada |
| public/app.js | Sesión, navegación y coordinación de módulos |
| public/agenda.js, agenda-recurrente.js | Reserva, edición, mensualidad, excepción y grilla |
| public/turn-series.js, turn-tools.js | Acciones y continuidad de tratamientos |
| public/agenda-patient-editor.js | Ficha compartida por reserva, Caja y Ortopedia |
| public/operations.js | Caja, espera y coordinación de operaciones |
| public/saldo.js, saldo-state.js | Saldo del paciente, vista previa e historial |
| public/cash-editor.js | Editor de ingresos para Secretaría y Administración |
| public/cash-patient-picker.js | Búsqueda y selección del paciente en Caja |
| public/cash-export.js | Excel de Caja con filtros e importes atribuidos |
| public/home.js | Inicio, asistencia y resumen de Caja |
| public/ortho.js | Venta, alquiler, devolución e inventario |
| public/patient-history.js, coverage.js | Ficha, cuenta, coberturas y teléfono |
| public/reports.js, management.js | Informes y consultas de gestión |
| public/patient-reports.js | Cinco pestañas de Gestión de pacientes |
| public/patient-report-workbook.js, xlsx.js | Excel, tablas y gráficos nativos |
| public/api.js, config.js | Conexión pública existente y solicitudes |
| public/*.css, fonts | Estilos, marca, contraste y recursos de la interfaz |
| public/vercel.json | Configuración de publicación y caché |
| supabase/migrations | Cambios acumulativos; conservar nombres y orden |
| supabase/functions | Fuentes existentes de WhatsApp |
| supabase/tests | SQL de comprobación sobre copias y datos ficticios |
| tests | Comprobaciones locales de JavaScript |
| local/servidor.cjs | Servidor estático de desarrollo |
| Documentacion/ESTADO_ACTUAL.md | Síntesis vigente y límites |
| Documentacion/INFORME_PPS_ACTUALIZADO.md | Copia textual del informe principal, revisado |
| Documentacion/MANUAL_USO_ACTUAL.md | Copia textual del Anexo B vigente |
| Documentacion/PENDIENTES_DEL_INFORME.md | Propuestas y validaciones pendientes |
| Documentacion/DICCIONARIO_SUPABASE_20261106.json | Metadatos estructurales de 51 tablas |
| Documentacion/DESPLIEGUE_20261106_editar_secretarias.json | Publicación vigente |
| Documentacion/MANIFIESTO_20261106_editar_secretarias.json | Huellas de public |
| Documentacion/VERIFICACION_ENTREGA_20261106.json | Verificación del paquete actual |

Las demás hojas de estilo y módulos de public también forman parte de la app. No eliminarlos por no figurar individualmente.

La instalación local completa conserva runtime, lanzadores, respaldos de trabajo y documentación histórica. El ZIP para otra IA omite ejecutables, logs, archivos de restauración y copias de datos.
