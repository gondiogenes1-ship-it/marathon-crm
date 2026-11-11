# Profesional de la mensualidad — 04/11/2026

Aplicado en Supabase, proyecto actual de Marathon. No requiere nuevo despliegue de Vercel.

## Causa y corrección

La función `public.marathon_agenda_plan_command(text,text,jsonb)` declara un registro `h` y utiliza `#variable_conflict use_variable`. La subconsulta del profesional de la cuota también usaba el alias `h`; sus referencias se resolvían como el registro local no inicializado y devolvían NULL.

Se cambió únicamente el alias de esa subconsulta a `quota_schedule`. Se conservan el comando, sus permisos, el control de versión, el identificador de reintento y las reglas de cobro y reintegro. Se conserva la selección ordenada por día y horario que ya tenía la función.

Migración: `supabase/migrations/20261104223000_profesional_cobro_mensual.sql`.
Respaldo de la función anterior: `CRM SUPABASE/Respaldos/profesional_mensual_20261104/funcion_anterior.sql`.

## Movimiento existente

Se completó la asociación faltante del único movimiento mensual existente. Los horarios del plan, en la misma sede y dentro del período de la cuota, identificaban un único profesional. El relleno no asigna profesionales cuando hay más de uno o faltan horarios.

El trigger normal de actualización conserva el control de versión. La migración administrativa queda registrada por Supabase; el cobro y su auditoría original se conservan.

## Verificación

- Prueba de lectura reprodujo el resultado NULL con el alias anterior y obtuvo el profesional correcto con el nuevo alias.
- Función de producción contiene la subconsulta corregida.
- Cuotas con movimientos: 1; movimientos mensuales sin profesional: 0.
- La vista usada por Caja devuelve `professional_key` y `associated` correctamente para ese movimiento.
- La asociación coincide con el profesional de los turnos del tratamiento.
- La migración verificó antes y después una huella de identificadores, fechas, horas, origen, tipo, importes, medios, sedes y vínculos de cuotas/compensaciones. Coinciden.
- No se registraron nuevos cobros o reintegros para realizar las pruebas.
