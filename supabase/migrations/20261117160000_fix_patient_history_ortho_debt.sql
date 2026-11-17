begin;

create or replace function public.marathon_patient_history(p_dni text, p_kind text DEFAULT 'clinic'::text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 25, p_filters jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare rows jsonb;nxt jsonb;summary jsonb;cnt integer;after_date date;after_time time;first_day date:=(now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_dni is null or p_dni!~'^[0-9]{1,12}$' or p_kind is null or p_kind not in ('clinic','ortho','bonus','advance') or p_limit is null or p_limit not between 1 and 50 then raise sqlstate '22023' using message='Consulta de historial inválida.';end if;
 if p_filters is not null then
  if jsonb_typeof(p_filters)<>'object' then raise sqlstate '22023' using message='Filtro de historial inválido.';end if;
  if exists(select 1 from jsonb_object_keys(p_filters)k where k<>all(case p_kind when 'clinic' then array['estado','therapy'] when 'bonus' then array['estado','therapy'] when 'advance' then array['therapy'] else array['tipo'] end)) then raise sqlstate '22023' using message='Filtro no admitido para esta pestaña.';end if;
  if p_filters?'estado' and p_kind='clinic' and p_filters->>'estado' not in('PENDIENTE','PRESENTE','AUSENTE','CANCELADO') then raise sqlstate '22023' using message='Estado de turno inválido.';end if;
  if p_filters?'estado' and p_kind='bonus' and p_filters->>'estado' not in('ACTIVO','ANULADO') then raise sqlstate '22023' using message='Estado de bono inválido.';end if;
  if p_filters?'tipo' and p_filters->>'tipo' not in('VENTA','ALQUILER','COMPRA','AJUSTE_POSITIVO','AJUSTE_NEGATIVO','DEVOLUCION') then raise sqlstate '22023' using message='Tipo de operación inválido.';end if;
  if p_filters?'therapy' and not exists(select 1 from marathon.terapias where id=p_filters->>'therapy') then raise sqlstate '22023' using message='Terapia inválida.';end if;
 end if;
 if not exists(select 1 from marathon.pacientes where dni=p_dni) then raise sqlstate 'P0002' using message='Paciente no encontrado.';end if;
 if p_after is not null then
  if jsonb_typeof(p_after)<>'object' then raise sqlstate '22023' using message='Cursor inválido.';end if;
  if not(p_after?&array['fecha','hora','id']) or exists(select 1 from jsonb_each(p_after)e where jsonb_typeof(e.value)<>'string') or exists(select 1 from jsonb_object_keys(p_after)k where k<>all(array['fecha','hora','id'])) or length(p_after->>'id')>100 or p_after->>'fecha'!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or length(p_after->>'hora')>16 then raise sqlstate '22023' using message='Cursor inválido.';end if;
  begin after_date=(p_after->>'fecha')::date;after_time=(p_after->>'hora')::time;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then raise sqlstate '22023' using message='Cursor inválido.';end;
 end if;
 select jsonb_build_object('clinical_debt',c.debt,'ortho_debt',o.debt,'bonus_debt',b.debt,'debt',c.debt+o.debt+b.debt,'present',c.present,'upcoming',c.upcoming,'clinic_total',c.total,'ortho_total',o.total,'rental_units',o.units,'advance_available',(select coalesce(sum(available),0)from marathon.daily_advance where dni=p_dni)) into summary from(
  select coalesce(sum(case when t.estado='PRESENTE' then greatest(0,marathon.saldo_cargo_sesion(t.id)-pay.paid) else 0 end),0) debt,count(*) filter(where t.estado='PRESENTE') present,count(*) filter(where t.estado='PENDIENTE' and t.fecha>=first_day) upcoming,count(*) total
  from marathon.turnos t cross join lateral(select marathon.turn_paid(t.id) paid)pay where t.dni=p_dni
 )c cross join(
  select coalesce(sum(case when o.tipo in ('VENTA','ALQUILER') and not(o.tipo='VENTA' and exists(select 1 from marathon.ortopedia_operaciones v where v.original_id=o.id and v.tipo='AJUSTE_POSITIVO')) then greatest(0,o.importe_total-pay.paid) else 0 end),0) debt,coalesce(sum(case when o.tipo='ALQUILER' then greatest(0,o.cantidad-ret.qty) else 0 end),0) units,count(*) total
  from marathon.ortopedia_operaciones o cross join lateral(select coalesce(sum(case when m.tipo='REINTEGRO' then -m.monto else m.monto end),0) paid from marathon.movimientos m where m.operacion_id=o.id and m.origen='ORTOPEDIA')pay
  cross join lateral(select coalesce(sum(d.cantidad),0) qty from marathon.ortopedia_operaciones d where d.original_id=o.id and d.tipo='DEVOLUCION')ret where o.dni=p_dni
 )o cross join(select coalesce(sum(debt),0) debt from marathon.daily_bonus where dni=p_dni)b;
 if exists(select 1 from marathon.saldo_config where activo)then
   summary=summary||jsonb_build_object('saldo_disponible',marathon.saldo_disponible(p_dni),'advance_available',marathon.saldo_disponible(p_dni),
   'clinical_debt',coalesce((select sum(deuda)from marathon.saldo_deudas(p_dni)where tipo<>'bono'),0),
   'debt',coalesce((select sum(deuda)from marathon.saldo_deudas(p_dni)),0)+(summary->>'ortho_debt')::numeric);
  end if;
 if p_kind='clinic' then
  select count(*) into cnt from marathon.turnos t where t.dni=p_dni and(p_filters is null or p_filters->>'estado' is null or t.estado=p_filters->>'estado')and(p_filters is null or p_filters->>'therapy' is null or t.terapia_id=p_filters->>'therapy');
  select coalesce(jsonb_agg(to_jsonb(x) order by fecha desc,hora desc,id desc),'[]'::jsonb) into rows from(
   select t.id,t.fecha,t.hora,t.sede,t.estado,t.importe,t.coverage,t.observaciones,t.version,t.attendance_auto,t.attendance_auto_at,th.nombre terapia,concat_ws(' ',p.nombre,nullif(p.segundo_nombre,''),p.apellido) profesional,pay.paid,case when t.estado='PRESENTE' then greatest(0,marathon.saldo_cargo_sesion(t.id)-pay.paid) else 0 end debt
   from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id join marathon.profesionales p on p.id=t.profesional_id
   cross join lateral(select marathon.turn_paid(t.id) paid)pay
   where t.dni=p_dni and(p_after is null or(t.fecha,t.hora,t.id)<(after_date,after_time,p_after->>'id'))and(p_filters is null or p_filters->>'estado' is null or t.estado=p_filters->>'estado')and(p_filters is null or p_filters->>'therapy' is null or t.terapia_id=p_filters->>'therapy') order by t.fecha desc,t.hora desc,t.id desc limit p_limit+1
  )x;
 elsif p_kind='ortho' then
  select count(*) into cnt from marathon.ortopedia_operaciones o where o.dni=p_dni and(p_filters is null or p_filters->>'tipo' is null or o.tipo=p_filters->>'tipo');
  select coalesce(jsonb_agg(to_jsonb(x) order by fecha desc,hora desc,id desc),'[]'::jsonb) into rows from(
   select o.id,o.fecha,o.hora,o.sede,o.tipo,o.cantidad,o.devolucion_prevista,o.importe_total,o.subtotal,o.discount_rate,o.discount_amount,o.observaciones,coalesce(nullif(o.producto_snapshot->>'descripcion',''),nullif(o.producto_snapshot->>'description',''),p.descripcion,o.producto_id) producto,pay.paid,case when o.tipo in ('VENTA','ALQUILER') and not(o.tipo='VENTA' and exists(select 1 from marathon.ortopedia_operaciones v where v.original_id=o.id and v.tipo='AJUSTE_POSITIVO')) then greatest(0,o.importe_total-pay.paid) else 0 end debt,case when o.tipo='ALQUILER' then greatest(0,o.cantidad-ret.qty) else 0 end pending,exists(select 1 from marathon.ortopedia_operaciones v where v.original_id=o.id and v.tipo='AJUSTE_POSITIVO') anulada
   from marathon.ortopedia_operaciones o left join marathon.productos p on p.id=o.producto_id
   cross join lateral(select coalesce(sum(case when m.tipo='REINTEGRO' then -m.monto else m.monto end),0) paid from marathon.movimientos m where m.operacion_id=o.id and m.origen='ORTOPEDIA')pay
   cross join lateral(select coalesce(sum(d.cantidad),0) qty from marathon.ortopedia_operaciones d where d.original_id=o.id and d.tipo='DEVOLUCION')ret
   where o.dni=p_dni and(p_after is null or(o.fecha,o.hora,o.id)<(after_date,after_time,p_after->>'id'))and(p_filters is null or p_filters->>'tipo' is null or o.tipo=p_filters->>'tipo') order by o.fecha desc,o.hora desc,o.id desc limit p_limit+1
  )x;
 elsif p_kind='advance'then
  select count(*) into cnt from marathon.daily_advance a where a.dni=p_dni and(p_filters is null or p_filters->>'therapy' is null or a.terapia_id=p_filters->>'therapy');
 select coalesce(jsonb_agg(to_jsonb(x)order by fecha desc,hora desc,id desc),'[]'::jsonb)into rows from(
 select a.* from marathon.daily_advance a where dni=p_dni and(p_after is null or(a.fecha,a.hora,a.id)<(after_date,after_time,p_after->>'id'))and(p_filters is null or p_filters->>'therapy' is null or a.terapia_id=p_filters->>'therapy')order by fecha desc,hora desc,id desc limit p_limit+1)x;
 else
  select count(*) into cnt from marathon.daily_bonus b where b.dni=p_dni and(p_filters is null or p_filters->>'estado' is null or b.estado=p_filters->>'estado')and(p_filters is null or p_filters->>'therapy' is null or b.terapia_id=p_filters->>'therapy');
  select coalesce(jsonb_agg(to_jsonb(x) order by fecha desc,hora desc,id desc),'[]'::jsonb) into rows from(
   select b.* from marathon.daily_bonus b where b.dni=p_dni and(p_after is null or(b.fecha,b.hora,b.id)<(after_date,after_time,p_after->>'id'))and(p_filters is null or p_filters->>'estado' is null or b.estado=p_filters->>'estado')and(p_filters is null or p_filters->>'therapy' is null or b.terapia_id=p_filters->>'therapy') order by b.fecha desc,b.hora desc,b.id desc limit p_limit+1
  )x;
 end if;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('fecha',rows->(p_limit-1)->>'fecha','hora',rows->(p_limit-1)->>'hora','id',rows->(p_limit-1)->>'id');end if;
 return jsonb_build_object('rows',rows,'next',nxt,'summary',summary,'total',cnt);
end $function$;

commit;
