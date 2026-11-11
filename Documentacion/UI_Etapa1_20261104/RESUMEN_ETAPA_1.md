# Etapa 1 — revisión local del 04/11/2026

Estado: aprobada por el usuario y publicada en Vercel el 04/11/2026. Deployment dpl_BBpwG4rCtJcPoFAUbiajDxw9htu8, READY. Etapas 2–5 pendientes.

## Cambios

- 322 declaraciones tipográficas de hasta 14 px pasan a la escala --fs-md de 14 px. La escala define 13, 14, 18 y 24 px; no se reduce ningún título.
- Controles principales con altura mínima de 44 px, separación de 8 px en grupos de acciones y navegación, casillas de 24 px con etiqueta de al menos 44 px.
- Foco visible de 3 px, halo blanco y variante sobre la barra verde; soporte de colores forzados.
- Inputs de 16 px en móvil para evitar zoom automático. Se conserva la fuente vigente (Segoe UI), los verdes, estructura y funciones.
- Capa final accessibility.css y versiones ?v=20261104-etapa1 de cada CSS modificado en index.html.

## Contraste

Fórmula WCAG: luminancia sRGB lineal y (Lclaro+0,05)/(Loscuro+0,05). Umbral 4,5:1.

| Texto | Color anterior → nuevo | Fondo | Antes | Después |
|---|---|---|---:|---:|
| Kicker de acceso | #809085 → #596b5e | #ffffff | 3.36:1 | 5.69:1 |
| Texto de acceso | #728c79 → #4e6956 | #eaf4e9 | 3.24:1 | 5.35:1 |
| Detalle de métricas | #738277 → #53675a | #ffffff | 4.05:1 | 6.08:1 |
| Cancelado | #7a7d79 → #585e57 | #eff1ee | 3.67:1 | 5.86:1 |
| Texto secundario | #62766c → #53675c | #f5f6f3 | 4.47:1 | 5.59:1 |

Los contrastes son los pares específicos del pedido. El muestreo de las once pantallas estáticas visibles también pasó; se corrigió el símbolo decorativo de ficha vacía. No constituye una certificación de todas las combinaciones de estados dinámicos.

## Archivos de aplicación completos

- [agenda-recurrente.css](../../public/agenda-recurrente.css)
- [button-variants.css](../../public/button-variants.css)
- [impeccable.css](../../public/impeccable.css)
- [index.html](../../public/index.html)
- [marathon-brand.css](../../public/marathon-brand.css)
- [marathon-salud.css](../../public/marathon-salud.css)
- [marathon-ui.css](../../public/marathon-ui.css)
- [patient-reports.css](../../public/patient-reports.css)
- [shared-space.css](../../public/shared-space.css)
- [style.css](../../public/style.css)
- [accessibility.css](../../public/accessibility.css)

La carpeta public contiene los archivos completos actualizados. El ZIP de esta etapa incluye únicamente estos archivos y este informe.

## Verificaciones

- Cuatro pruebas locales con código 0: reservar junto a cupos, ficha de Ortopedia, anticipos y ocultación de cancelados.
- 11 pantallas × 3 anchos solicitados (1440, 820, 390), revisadas en marcos locales. Sin desborde horizontal de página, textos visibles menores a 13 px ni controles principales menores a 44 px en las plantillas estáticas. Ver auditoria-pantallas.json. La herramienta presenta pequeñas diferencias de redondeo por escala.
- Recorrido Tab de correo a contraseña: foco verde de 3 px visible. Esc no altera el formulario. No se crearon nuevos diálogos en esta etapa.
- Auditoría de fuentes CSS: cero declaraciones numéricas inferiores a 13 px. Ver auditoria-fuentes-contraste.json.
- Verificación por hash: ningún módulo JavaScript de public cambió. No se modificó supabase/.

## Límites y decisiones

- Previsualización sin conexión a Supabase y sin datos inventados. No se validaron filas con pacientes reales, cobros ni diálogos generados al operar.
- La herramienta de inspección registró dos errores MutationObserver durante la inspección de marcos. La vista previa no contiene ese código, pero con este método no se certifica una consola limpia de la aplicación real.
- No se cambiaron confirmaciones, guardados, navegación, lógica, RPC, fuentes ni modo oscuro: pertenecen a otras etapas o exceden esta revisión.
- El documento menciona Outfit; la versión vigente aplica Segoe UI. Se conserva el estilo actual y se difiere la unificación de fuente a la Etapa 5.
- La copia publicada es dpl_BBpwG4rCtJcPoFAUbiajDxw9htu8. Verificados 48 archivos públicos, idénticos a public/.

## Respaldo previo

C:/Users/Gonzalo/OneDrive/Desktop/CRM SUPABASE/Respaldos/UI_Etapa1_20261104
