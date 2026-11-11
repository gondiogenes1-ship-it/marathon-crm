# Marathon CRM — entrega actual del 6 de noviembre de 2026

Versión base 0.14.0 · revisión editar-secretarias-1.
Aplicación: https://marathon-crm-liart.vercel.app/?revision=editar-secretarias-1
Producción verificada: dpl_3vspdZu7ivx6LjuAzcPDQrwTGXho, READY.

## Por dónde empezar

1. Documentacion/ESTADO_ACTUAL.md: funciones, permisos y límites actuales.
2. Documentacion/CONTEXTO_PARA_OTRA_IA.md: contexto para continuar.
3. Documentacion/MAPA_DE_ARCHIVOS.md: fuentes y responsabilidades.
4. Documentacion/MANUAL_USO_ACTUAL.md: guía vigente.
5. Documentacion/PENDIENTES_DEL_INFORME.md: propuestas que todavía no están incorporadas.
6. Documentacion/INFORME_PPS_ACTUALIZADO.md: copia textual de consulta del informe principal. El documento nativo y sus anexos se conservan en Drive: https://docs.google.com/document/d/1AaFatHQC4AlTSQbED4gsKWHAfAcwdSn9rEUtGULYcD8

## Desarrollo y publicación

Frontend estático en public, sin framework ni etapa de compilación.
Con Node.js instalado: node local/servidor.cjs 8123
Luego abrir http://127.0.0.1:8123/ e ingresar con una cuenta habilitada.
Esta apertura se conecta al Supabase compartido; no es una base aislada ni funciona sin Internet.
En la instalación Windows completa se conservan los lanzadores y runtime/node.exe. El ZIP de desarrollo omite ese ejecutable; se utiliza el comando anterior.

En Vercel se publica únicamente public. El proyecto existente usa Root Directory Marathon_Vercel_0112, framework ninguno, build/install vacíos y Output Directory ".". El nombre técnico de esa carpeta no es la revisión del sistema.

## Alcance del paquete

Incluye código publicado, SQL y migraciones disponibles, funciones de servidor, pruebas y documentación seleccionada. El manifiesto de entrega y los registros de despliegue permiten verificar los archivos.
No incluye pacientes, respaldos de base, contraseñas, claves privadas, logs ni el ejecutable de Node.
No es un instalador completo de Supabase. La base compartida ya tiene las migraciones aplicadas: no volver a ejecutarlas para abrir la app en otra PC.
