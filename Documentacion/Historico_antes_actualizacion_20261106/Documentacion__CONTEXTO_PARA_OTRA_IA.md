# Contexto para continuar con otra IA

Leer README.md, Documentacion/ESTADO_ACTUAL.md y MAPA_DE_ARCHIVOS.md antes de proponer cambios.

## Preferencias del usuario

La app es un CRM para Marathon, usado por secretaría. Conservar el diseño original, la barra verde Marathon y Segoe UI. Priorizar texto legible, contraste y acciones claras. Las propuestas Marathon Claro y Stitch fueron descartadas; no retomarlas sin un pedido nuevo.

## Reglas que deben preservarse

- Mantener los permisos y la autenticación existentes. Reutilizar el editor de paciente y los comandos existentes para evitar comportamientos distintos entre pantallas.
- Anticipos: el ingreso se registra una vez en Caja; aplicarlo a una deuda no duplica el cobro. Ortopedia y bonos tienen sus propios cobros.
- Los presentes consumen sesiones; las ausencias no. Las pausas conservan el lugar habitual y se excluyen del conteo del espacio compartido.
- Mantener reintentos con identificadores de solicitud, control de versión y recuperación ante guardados inciertos.

## Cómo trabajar

El código actual está en public. No hay framework, package.json ni etapa de build. Se puede servir public con un servidor estático; el acceso real requiere la cuenta del usuario.
Para abrir con los lanzadores Windows se requiere runtime/node.exe en la instalación completa. Este ZIP no incluye ese binario para mantenerlo liviano. Para trabajar con código basta Node.js 24 o un servidor estático.
Los tests incluidos son simulaciones y no se conectan a los datos reales. No guardar pacientes, cobros o movimientos reales como parte de una prueba de interfaz.
Las credenciales privadas se configuran directamente en los servicios, nunca en el frontend ni en el chat. public/config.js contiene la configuración pública que la aplicación ya sirve al navegador.

El despliegue vigente está registrado en Documentacion/DESPLIEGUE_20261101_anticipos_ortopedia.json. Cualquier cambio posterior necesita pruebas y un nuevo despliegue cuando lo pida el usuario.
