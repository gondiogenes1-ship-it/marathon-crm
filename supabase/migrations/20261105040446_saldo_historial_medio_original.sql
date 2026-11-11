-- Solo lectura del medio original: no cambia movimientos, medios ni importes.
begin;
create or replace function public.marathon_saldo_historial(p_dni text,p_after jsonb default null,p_limit int default 25)returns jsonb language plpgsql stable security definer set search_path=''as $$declare rows jsonb;next_cursor jsonb;begin
 if not marathon.active_user()then raise exception 'Acceso no autorizado.'using errcode='42501';end if;
 if p_limit is null or p_limit not between 1 and 100 or(p_after is not null and(not(p_after?&array['at','id'])or jsonb_typeof(p_after)<>'object'))then raise exception 'Consulta inválida.'using errcode='22023';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by created_at desc,id desc),'[]')into rows from(
  select e.id,e.created_at,e.tipo,e.monto::text as importe,e.fuente_id,e.movimiento_id,e.aplicacion_id,a.turno_id,a.cuota_id,a.bono_id,
   case when e.tipo='INGRESO'then'Ingreso de Caja'when e.tipo='DEVOLUCION'then'Egreso de Caja'else'Movimiento interno'end as efecto_caja,
   u.display_name as actor,m.fecha as fecha_caja,m.medio,m.sede,m.profesional_asociado_id,origen.medio as medio_origen,origen.fecha as fecha_pago_original,origen.id as pago_original_id
  from marathon.saldo_eventos e left join marathon.saldo_aplicaciones a on a.id=e.aplicacion_id
  left join marathon.saldo_fuentes f on f.id=e.fuente_id
  left join marathon.movimientos origen on origen.id=f.movimiento_id
  left join marathon.movimientos m on m.id=e.movimiento_id left join marathon.app_users u on u.user_id=e.actor
  where e.dni=p_dni and(p_after is null or(e.created_at,e.id)<((p_after->>'at')::timestamptz,(p_after->>'id')::uuid))
  order by e.created_at desc,e.id desc limit p_limit+1)x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;next_cursor=jsonb_build_object('at',rows->(p_limit-1)->>'created_at','id',rows->(p_limit-1)->>'id');end if;
 return jsonb_build_object('rows',rows,'next',next_cursor);
end$$;

notify pgrst,'reload schema';
commit;
