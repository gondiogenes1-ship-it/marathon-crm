-- Ortopedia: agrega el estado "anulada" a las ventas, para que el Historial y la
-- ficha de la operación lo muestren (en vez de solo bloquear un segundo clic en
-- Anular venta con un mensaje de error).
--
-- Una venta queda marcada "anulada" si existe un ajuste positivo de stock vinculado
-- a ella (exactamente lo que crea la acción 'void'). No depende de ninguna columna
-- nueva: se calcula al vuelo.
--
-- Correr en el SQL Editor de Supabase (una sola vez), después de ortho_anular_venta.sql.

begin;
set local lock_timeout='5s';
select pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));

-- marathon.daily_ortho alimenta el Historial, Pagos pendientes y Devoluciones.
-- Se recrea entera con el mismo contenido de siempre, agregando una sola columna al final.
CREATE OR REPLACE VIEW marathon.daily_ortho WITH (security_invoker='true') AS
 SELECT o.id,
    o.original_id,
    o.fecha,
    o.hora,
    o.tipo,
    o.producto_id,
    o.sede,
    o.cantidad,
    o.dni,
    o.semanas,
    o.devolucion_prevista,
    o.importe_total,
    o.secretaria_legacy,
    o.observaciones,
    o.created_at,
    o.updated_at,
    o.created_by,
    o.updated_by,
    o.version,
    o.precio_unitario,
    o.producto_snapshot,
    o.transfer_id,
    COALESCE((o.producto_snapshot ->> 'descripcion'::text), p.descripcion) AS producto,
    p.marca,
    p.codigo,
    concat_ws(' '::text, pac.apellido, pac.nombre, NULLIF(pac.segundo_nombre, ''::text)) AS paciente,
    COALESCE(u.display_name, o.secretaria_legacy, 'Sin registro'::text) AS actor,
    COALESCE((o.created_by)::text, ('legacy:'::text || o.secretaria_legacy), 'unknown'::text) AS actor_key,
    marathon.ortho_paid(o.id) AS paid,
        CASE
            WHEN (o.tipo = ANY (ARRAY['VENTA'::text, 'ALQUILER'::text, 'COMPRA'::text])) THEN GREATEST((0)::numeric, (o.importe_total - marathon.ortho_paid(o.id)))
            ELSE (0)::numeric
        END AS debt,
        CASE
            WHEN (o.tipo = 'ALQUILER'::text) THEN (o.cantidad - marathon.ortho_returned(o.id))
            ELSE (0)::bigint
        END AS pending,
    COALESCE(( SELECT sum(
                CASE
                    WHEN (m.tipo = ANY (ARRAY['INGRESO'::text, 'PAGO'::text])) THEN m.monto
                    WHEN (m.tipo = 'REINTEGRO'::text) THEN (- m.monto)
                    ELSE (0)::numeric
                END) AS sum
           FROM marathon.movimientos m
          WHERE (m.operacion_id = o.id)), (0)::numeric) AS income,
    o.subtotal,
    o.discount_rate,
    o.discount_amount,
    ((o.tipo = 'VENTA'::text) AND (EXISTS ( SELECT 1 FROM marathon.ortopedia_operaciones v WHERE ((v.original_id = o.id) AND (v.tipo = 'AJUSTE_POSITIVO'::text))))) AS anulada
   FROM (((marathon.ortopedia_operaciones o
     JOIN marathon.productos p ON ((p.id = o.producto_id)))
     LEFT JOIN marathon.pacientes pac ON ((pac.dni = o.dni)))
     LEFT JOIN marathon.app_users u ON ((u.user_id = o.created_by)));

-- marathon_ortho_get alimenta la ficha individual que abren "Registrar cobro",
-- "Registrar reintegro" y el nuevo "Anular venta".
do $$
declare src text; newsrc text;
begin
 src := pg_get_functiondef('public.marathon_ortho_get(text)'::regprocedure);
 newsrc := replace(src,
  $frag$'pending',case when o.tipo='ALQUILER'then o.cantidad-marathon.ortho_returned(o.id)else 0 end)into r$frag$,
  $frag$'pending',case when o.tipo='ALQUILER'then o.cantidad-marathon.ortho_returned(o.id)else 0 end,'anulada',o.tipo='VENTA' and exists(select 1 from marathon.ortopedia_operaciones v where v.original_id=o.id and v.tipo='AJUSTE_POSITIVO'))into r$frag$);
 if newsrc = src then raise exception 'marathon_ortho_get: no se encontró el patrón de pending/anulada.'; end if;
 execute newsrc;
end $$;

notify pgrst,'reload schema';
commit;
