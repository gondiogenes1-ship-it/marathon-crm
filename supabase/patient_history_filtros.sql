-- Agrega filtros a la ficha del paciente: por estado y terapia en el historial
-- clinico, por estado y terapia en bonos, por terapia en anticipos, y por tipo
-- de operacion en ortopedia. Agrega el parametro p_filters (jsonb, opcional)
-- a marathon_patient_history. Como se agrega un parametro, hay que borrar la
-- firma vieja antes de crear la nueva (si no, Postgres crea una funcion
-- duplicada y queda ambigua).
-- Correr en el SQL Editor de Supabase (una sola vez).

begin;
set local lock_timeout='5s';
select pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));

do $$
declare src text; cur text; prev text;
begin
 src := pg_get_functiondef('public.marathon_patient_history(text,text,jsonb,integer)'::regprocedure);
 cur := src;

 prev := cur;
 cur := replace(cur,
  $frag$p_limit integer DEFAULT 25)$frag$,
  $frag$p_limit integer DEFAULT 25, p_filters jsonb DEFAULT NULL::jsonb)$frag$);
 if cur = prev then raise exception 'marathon_patient_history: no se encontró la firma de parámetros.'; end if;

 prev := cur;
 cur := replace(cur,
  $frag$ if p_dni is null or p_dni!~'^[0-9]{1,12}$' or p_kind is null or p_kind not in ('clinic','ortho','bonus','advance') or p_limit is null or p_limit not between 1 and 50 then raise sqlstate '22023' using message='Consulta de historial inválida.';end if;$frag$,
  $frag$ if p_dni is null or p_dni!~'^[0-9]{1,12}$' or p_kind is null or p_kind not in ('clinic','ortho','bonus','advance') or p_limit is null or p_limit not between 1 and 50 then raise sqlstate '22023' using message='Consulta de historial inválida.';end if;
 if p_filters is not null then
  if jsonb_typeof(p_filters)<>'object' then raise sqlstate '22023' using message='Filtro de historial inválido.';end if;
  if exists(select 1 from jsonb_object_keys(p_filters)k where k<>all(case p_kind when 'clinic' then array['estado','therapy'] when 'bonus' then array['estado','therapy'] when 'advance' then array['therapy'] else array['tipo'] end)) then raise sqlstate '22023' using message='Filtro no admitido para esta pestaña.';end if;
  if p_filters?'estado' and p_kind='clinic' and p_filters->>'estado' not in('PENDIENTE','PRESENTE','AUSENTE','CANCELADO') then raise sqlstate '22023' using message='Estado de turno inválido.';end if;
  if p_filters?'estado' and p_kind='bonus' and p_filters->>'estado' not in('ACTIVO','ANULADO') then raise sqlstate '22023' using message='Estado de bono inválido.';end if;
  if p_filters?'tipo' and p_filters->>'tipo' not in('VENTA','ALQUILER','COMPRA','AJUSTE_POSITIVO','AJUSTE_NEGATIVO','DEVOLUCION') then raise sqlstate '22023' using message='Tipo de operación inválido.';end if;
  if p_filters?'therapy' and not exists(select 1 from marathon.terapias where id=p_filters->>'therapy') then raise sqlstate '22023' using message='Terapia inválida.';end if;
 end if;$frag$);
 if cur = prev then raise exception 'marathon_patient_history: no se encontró la validación principal.'; end if;

 prev := cur;
 cur := replace(cur,
  $frag$where t.dni=p_dni and(p_after is null or(t.fecha,t.hora,t.id)<(after_date,after_time,p_after->>'id')) order by t.fecha desc,t.hora desc,t.id desc limit p_limit+1$frag$,
  $frag$where t.dni=p_dni and(p_after is null or(t.fecha,t.hora,t.id)<(after_date,after_time,p_after->>'id'))and(p_filters is null or p_filters->>'estado' is null or t.estado=p_filters->>'estado')and(p_filters is null or p_filters->>'therapy' is null or t.terapia_id=p_filters->>'therapy') order by t.fecha desc,t.hora desc,t.id desc limit p_limit+1$frag$);
 if cur = prev then raise exception 'marathon_patient_history: no se encontró el where de clinic.'; end if;

 prev := cur;
 cur := replace(cur,
  $frag$where o.dni=p_dni and(p_after is null or(o.fecha,o.hora,o.id)<(after_date,after_time,p_after->>'id')) order by o.fecha desc,o.hora desc,o.id desc limit p_limit+1$frag$,
  $frag$where o.dni=p_dni and(p_after is null or(o.fecha,o.hora,o.id)<(after_date,after_time,p_after->>'id'))and(p_filters is null or p_filters->>'tipo' is null or o.tipo=p_filters->>'tipo') order by o.fecha desc,o.hora desc,o.id desc limit p_limit+1$frag$);
 if cur = prev then raise exception 'marathon_patient_history: no se encontró el where de ortho.'; end if;

 prev := cur;
 cur := replace(cur,
  $frag$select a.* from marathon.daily_advance a where dni=p_dni and(p_after is null or(a.fecha,a.hora,a.id)<(after_date,after_time,p_after->>'id'))order by fecha desc,hora desc,id desc limit p_limit+1)x;$frag$,
  $frag$select a.* from marathon.daily_advance a where dni=p_dni and(p_after is null or(a.fecha,a.hora,a.id)<(after_date,after_time,p_after->>'id'))and(p_filters is null or p_filters->>'therapy' is null or a.terapia_id=p_filters->>'therapy')order by fecha desc,hora desc,id desc limit p_limit+1)x;$frag$);
 if cur = prev then raise exception 'marathon_patient_history: no se encontró el where de advance.'; end if;

 prev := cur;
 cur := replace(cur,
  $frag$select b.* from marathon.daily_bonus b where b.dni=p_dni and(p_after is null or(b.fecha,b.hora,b.id)<(after_date,after_time,p_after->>'id')) order by b.fecha desc,b.hora desc,b.id desc limit p_limit+1$frag$,
  $frag$select b.* from marathon.daily_bonus b where b.dni=p_dni and(p_after is null or(b.fecha,b.hora,b.id)<(after_date,after_time,p_after->>'id'))and(p_filters is null or p_filters->>'estado' is null or b.estado=p_filters->>'estado')and(p_filters is null or p_filters->>'therapy' is null or b.terapia_id=p_filters->>'therapy') order by b.fecha desc,b.hora desc,b.id desc limit p_limit+1$frag$);
 if cur = prev then raise exception 'marathon_patient_history: no se encontró el where de bonus.'; end if;

 drop function public.marathon_patient_history(text,text,jsonb,integer);
 execute cur;
end $$;

revoke all on function public.marathon_patient_history(text,text,jsonb,integer,jsonb) from public,anon;
grant execute on function public.marathon_patient_history(text,text,jsonb,integer,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
