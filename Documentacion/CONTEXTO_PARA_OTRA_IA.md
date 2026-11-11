# Contexto para continuar Marathon CRM

Corte: 06/11/2026. Leer primero README.md, ESTADO_ACTUAL.md, MAPA_DE_ARCHIVOS.md y PENDIENTES_DEL_INFORME.md.

## Fuente actual

public coincide con la revisión editar-secretarias-1 publicada en Vercel. Deployment: dpl_3vspdZu7ivx6LjuAzcPDQrwTGXho.
Última migración: 20261106225955_caja_edicion_secretarias.sql.
Código estático HTML/CSS/JavaScript, sin framework, build ni package.json. Supabase compartido existente; no ejecutar migraciones otra vez por instalar en otra PC.

## Decisiones del usuario que deben conservarse

Conservar el diseño y la barra verde Marathon. Usar el formulario existente de reserva para editar, continuar series y cargar atenciones excepcionales; no sustituirlo por otra pantalla.

Editar ingreso está habilitado para ADMIN y SECRETARIA activos. Esta autorización posterior reemplaza la decisión anterior de reservarlo solo a Administración. Se mantienen vista previa, motivo, auditoría, control de versión, huella e idempotencia.

Un pago se registra una vez en Caja. Las aplicaciones al paciente son otro registro. Al cambiar paciente o importe en una edición, corregir pagos y saldos; al cambiar solo medio o descripción, conservar aplicaciones. No inventar un profesional para crédito sin aplicar ni atribuirle todo un pago si solo una parte pagó su atención.

Reintegrar sesión o cuota devuelve el pago al saldo del paciente. La devolución física se registra aparte. Conservar los controles de conciliación y los límites específicos de Ortopedia.

Agendar más sesiones crea otra serie con datos precargados y modificables, con posibilidad de bono nuevo. Modificar una serie desde una fecha conserva el pasado; una cuota actual solo cambia si no tiene pagos.

La atención excepcional permite profesional fuera de su día/hora habitual y fecha pasada, con controles de superposición, sin modificar su horario recurrente.

## Cuidado de datos y pruebas

El sistema está en funcionamiento. No crear pacientes, turnos o movimientos reales para probar interfaz. Usar datos ficticios y copias locales; los tests SQL se revierten. No borrar ni reconstruir historia financiera para resolver una visualización.

Revisar las funciones actuales antes de modificar SQL. Mantener permisos de usuarios activos, funciones privadas, auditoría, solicitudes idempotentes y manejo de cambios concurrentes. Las tablas auxiliares no se abren al cliente por modificar una pantalla.

El esquema estructural documentado tiene 51 tablas y 520 campos. No incluye filas de usuarios ni pacientes y no sustituye un respaldo. Los respaldos completos privados no forman parte del ZIP.

## Informe PPS y propuestas

Documento nativo: https://docs.google.com/document/d/1AaFatHQC4AlTSQbED4gsKWHAfAcwdSn9rEUtGULYcD8
Las notas del autor fueron desarrolladas y ubicadas en 4.4.1 (Deming/PDSA) y 4.5 (información e indicadores para decidir). Se preservaron los anexos, la encuesta y los antecedentes históricos.
La distribución por obra social específica y el indicador de stock propuesto para el tablero son desarrollos pendientes. El acceso exclusivo a Informes también debe definirse: las consultas actuales verifican usuario activo. No implementar estas ideas por encontrarlas escritas en el informe; hace falta un pedido de trabajo específico.

Los tableros describen registros disponibles. No presentar pacientes por grupo como suma institucional, primeras observadas como pacientes nuevos confirmados, minutos profesionales como capacidad física o ingresos como rentabilidad. No inventar satisfacción ni diagnósticos.
