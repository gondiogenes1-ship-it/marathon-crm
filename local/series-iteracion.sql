-- Las reglas cerradas conservan el horario anterior; las nuevas empiezan en el corte.
begin;

create or replace function marathon.turn_series_context(p_id text)returns jsonb language plpgsql stable set search_path=''as $$
declare t marathon.turnos%rowtype;p jsonb;members jsonb;rules jsonb;begin
 select *into t from marathon.turnos where id=p_id;
 if t.id is null then raise exception 'El turno ya no existe. Actualizá la agenda.'using errcode='PT404';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.fecha,x.hora,x.id),'[]')into members from marathon.turnos x
 where (case when t.plan_id is not null then x.plan_id=t.plan_id else x.plan_id is null and coalesce(x.original_id,x.id)=coalesce(t.original_id,t.id)end)and x.fecha>=t.fecha;
 if t.plan_id is not null then
  select to_jsonb(x)into p from marathon.agenda_planes x where x.id=t.plan_id;
  select coalesce(jsonb_agg(to_jsonb(x)order by x.id),'[]')into rules from marathon.agenda_horarios x where x.plan_id=t.plan_id;
 end if;
 return jsonb_build_object('target',to_jsonb(t),'plan',p,'schedules',coalesce(rules,'[]'),'series_days',(select jsonb_agg(num_day order by num_day)from(select distinct extract(dow from(x->>'fecha')::date)::int num_day from jsonb_array_elements(members)x where x->>'estado'='PENDIENTE')days),'series_count',(select count(*)from jsonb_array_elements(members)x where x->>'estado'='PENDIENTE'),
 'can_following',t.estado='PENDIENTE'and t.fecha>=marathon.agenda_hoy()and(t.plan_id is not null or jsonb_array_length(members)>1),
 'huella',encode(sha256(convert_to(jsonb_build_object('target',to_jsonb(t),'members',members,'plan',p,'rules',rules)::text,'UTF8')),'hex'));
end$$;
revoke all on function marathon.turn_series_context(text)from public,anon,authenticated;

create or replace function public.marathon_turn_series_context(p_id text)returns jsonb language plpgsql security definer set search_path=''as $$declare resolved text:=p_id;d date;h uuid;begin
 if not marathon.active_user()then raise exception 'Acceso no autorizado.'using errcode='42501';end if;
 if p_id~'^H-[0-9a-f-]{36}-[0-9]{4}-[0-9]{2}-[0-9]{2}$'then
  d=right(p_id,10)::date;h=substring(p_id from 3 for 36)::uuid;
  perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
  if not exists(select 1 from marathon.agenda_virtual(d)v where v.id=p_id)and not exists(select 1 from marathon.turnos where horario_id=h and fecha_habitual=d)then raise exception 'Ese turno ya no está en la agenda. Actualizá la vista.'using errcode='PT409';end if;
  perform marathon.agenda_materializar(d,d);
  select id into resolved from marathon.turnos where horario_id=h and fecha_habitual=d;
 end if;
 return marathon.turn_series_context(resolved);
end$$;

create or replace function marathon.turn_series_run(p_request_id text,p_data jsonb)returns jsonb language plpgsql set search_path=''set lock_timeout='5s'as $$
declare result jsonb;info jsonb;t marathon.turnos%rowtype;member marathon.turnos%rowtype;rule marathon.agenda_horarios%rowtype;
 p marathon.agenda_planes%rowtype;before_plan jsonb;changes jsonb;maps jsonb:='{}';ids text[];kind text;scope text;reason text;delta int;new_date date;new_hour time;site text;prof text;new_rule uuid;
 d date;candidate record;occ record;slot jsonb;duration int;count_changed int:=0;after_row jsonb;config jsonb;schedules jsonb;
begin
 result=marathon.operation_begin(p_request_id,'turn-series',p_data);if result is not null then return result;end if;
 if p_data is null or jsonb_typeof(p_data)<>'object'or exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['id','action','scope','huella','date','time','site','prof','reason','schedules']))then raise exception 'Solicitud inválida.'using errcode='22023';end if;
 kind=p_data->>'action';scope=p_data->>'scope';
 if kind is null or kind not in('cancel','edit')or scope is null or scope not in('single','following')then raise exception 'Elegí la operación y su alcance.'using errcode='22023';end if;
 info=marathon.turn_series_context(p_data->>'id');
 if info->>'huella'is distinct from p_data->>'huella'then raise exception 'La serie cambió. Volvé a abrir el turno para revisar los cambios.'using errcode='PT409';end if;
 select *into strict t from marathon.turnos where id=p_data->>'id'for update;
 reason=btrim(coalesce(nullif(p_data->>'reason',''),'Cancelación o edición manual desde el turno'));
 if length(reason)not between 3 and 1000 then raise exception 'El motivo debe tener entre 3 y 1000 caracteres.'using errcode='22023';end if;
 if t.estado='CANCELADO'or(kind='edit'and t.estado<>'PENDIENTE')then raise exception 'Solo se editan turnos pendientes. Actualizá la agenda.'using errcode='22023';end if;
 if scope='following'and not(info->>'can_following')::boolean then raise exception 'Elegí un turno pendiente de hoy en adelante para cambiar la serie.'using errcode='22023';end if;
 select array_agg(x.id order by x.fecha,x.hora,x.id)into ids from marathon.turnos x where
 case when scope='single'then x.id=t.id else x.fecha>=t.fecha and x.estado='PENDIENTE'and(case when t.plan_id is not null then x.plan_id=t.plan_id else x.plan_id is null and coalesce(x.original_id,x.id)=coalesce(t.original_id,t.id)end)end;
 if cardinality(ids)>2000 then raise exception 'La serie supera 2000 turnos pendientes. Revisala con administración.'using errcode='22023';end if;
 if scope='following'and t.plan_id is not null then
  select *into strict p from marathon.agenda_planes where id=t.plan_id for update;before_plan=to_jsonb(p);
  if p.baja is not null and p.baja<=t.fecha then raise exception 'La asignación ya está dada de baja desde esa fecha.'using errcode='PT409';end if;
  if exists(select 1 from marathon.turnos x where x.plan_id=t.plan_id and x.fecha>=t.fecha and x.estado in('PRESENTE','AUSENTE'))then raise exception 'Hay asistencias registradas desde esa fecha. Elegí un turno posterior o modificá solo este turno.'using errcode='22023';end if;
 end if;
 if kind='cancel'then
  -- Reutilizar el circuito de estado conserva sus controles y libera saldo sin sacar dinero.
  foreach member.id in array ids loop
   select *into member from marathon.turnos where id=member.id;
   perform public.marathon_agenda_command('series-'||md5(p_request_id||member.id),'status',jsonb_build_object('id',member.id,'version',member.version,'estado','CANCELADO'));
   count_changed=count_changed+1;
  end loop;
  if scope='following'and t.plan_id is not null then
   update marathon.agenda_planes set baja=t.fecha where id=t.plan_id;
   update marathon.agenda_periodos set fin=greatest(inicio,t.fecha),anulado=anulado or inicio>=t.fecha where plan_id=t.plan_id and(fin is null or fin>t.fecha);
  end if;
 else
  new_date=marathon.agenda_date(p_data->>'date');
  schedules=p_data->'schedules';delta=new_date-t.fecha;
  if schedules is not null then
   if jsonb_typeof(schedules)<>'array'or jsonb_array_length(schedules)not between 1 and 5 or(select count(distinct x->>'day')from jsonb_array_elements(schedules)x)<>jsonb_array_length(schedules)then raise exception 'Revisá los días de atención.'using errcode='22023';end if;
   for config in select value from jsonb_array_elements(schedules)loop
    if config->>'day'not in('1','2','3','4','5')or config->>'day'is null or coalesce(config->>'time','')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$'or exists(select 1 from jsonb_object_keys(config)k where k<>all(array['day','site','prof','time']))then raise exception 'Revisá días, sede, profesional y hora.'using errcode='22023';end if;
    perform marathon.master_text(config,'site',40,true);perform marathon.master_text(config,'prof',100,true);
   end loop;
  else
   if coalesce(p_data->>'time','')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$'then raise exception 'Elegí una hora válida.'using errcode='22023';end if;
   new_hour=(p_data->>'time')::time;site=marathon.master_text(p_data,'site',40,true);prof=marathon.master_text(p_data,'prof',100,true);
  end if;
  if new_date<marathon.agenda_hoy()or abs(delta)>365 then raise exception 'Elegí una fecha de hoy en adelante, hasta 365 días de diferencia.'using errcode='22023';end if;
  if exists(select 1 from marathon.turnos x where x.id=any(ids)and(x.fecha+delta<marathon.agenda_hoy()or marathon.turn_paid(x.id)>0))then raise exception 'Hay turnos con pagos aplicados o fechas anteriores a hoy. Revisalos antes de editar.'using errcode='22023';end if;
  select coalesce(jsonb_agg(to_jsonb(x)order by x.fecha,x.hora,x.id),'[]')into changes from marathon.turnos x where x.id=any(ids);
  -- Retirar provisionalmente del cupo el conjunto. Toda la operación es atómica.
  update marathon.turnos set estado='CANCELADO'where id=any(ids);
  if scope='following'and t.plan_id is not null then
   for rule in select *from marathon.agenda_horarios x where x.plan_id=t.plan_id and(x.hasta is null or x.hasta>t.fecha)order by x.desde,x.dia,x.id for update loop
    d=greatest(rule.desde,t.fecha);d=d+((rule.dia-extract(dow from d)::int+7)%7);
    if rule.hasta is not null and d>=rule.hasta then continue;end if;
    if schedules is not null then
     select x into config from jsonb_array_elements(schedules)x where(x->>'day')::int=extract(dow from d+delta)::int;
     if config is null then raise exception 'Conservá los días de la serie; la primera fecha desplaza el conjunto.'using errcode='22023';end if;
     site=config->>'site';prof=config->>'prof';new_hour=(config->>'time')::time;
    end if;
    if d+delta<marathon.agenda_hoy()or extract(dow from d+delta)::int not between 1 and 5 then raise exception 'Todos los horarios de la serie deben quedar de lunes a viernes y desde hoy.'using errcode='22023';end if;
    duration=marathon.session_minutes(d+delta,site,prof,new_hour,rule.duracion_min);
    update marathon.agenda_horarios set hasta=greatest(desde,t.fecha)where id=rule.id;
    insert into marathon.agenda_horarios(plan_id,sede,profesional_id,dia,hora,duracion_min,desde,hasta)
    values(t.plan_id,site,prof,extract(dow from d+delta)::int,new_hour,duration,d+delta,case when rule.hasta is null then null else rule.hasta+delta end)returning id into new_rule;
    maps=maps||jsonb_build_object(rule.id::text,new_rule::text);
   end loop;
   -- Conservar las excepciones canceladas: no regenerarlas como turnos nuevos.
   for member in select *from marathon.turnos x where x.plan_id=t.plan_id and x.fecha_habitual>=t.fecha and x.estado='CANCELADO'and not(x.id=any(ids))and maps?x.horario_id::text for update loop
    update marathon.turnos set horario_id=(maps->>member.horario_id::text)::uuid,fecha_habitual=member.fecha_habitual+delta where id=member.id;
    insert into marathon.turn_audit(request_id,actor,turn_id,action,before_data,after_data)select p_request_id,auth.uid(),member.id,'series_exception',to_jsonb(member),to_jsonb(x)from marathon.turnos x where x.id=member.id;
   end loop;
  end if;
  for after_row in select value from jsonb_array_elements(changes)loop
   select *into strict member from jsonb_populate_record(null::marathon.turnos,after_row);
   if schedules is not null then
    select x into config from jsonb_array_elements(schedules)x where(x->>'day')::int=extract(dow from((case when scope='single'then member.fecha else coalesce(member.fecha_habitual,member.fecha)end)+delta))::int;
    if config is null then raise exception 'Conservá los días de las sesiones existentes.'using errcode='22023';end if;
    site=config->>'site';prof=config->>'prof';new_hour=(config->>'time')::time;
   end if;
   duration=marathon.session_minutes(member.fecha+delta,site,prof,new_hour,member.duracion_min);
   if scope='single'then
    slot=marathon.agenda_cupo(member.fecha+delta,site,prof,member.terapia_id,new_hour,null,'H-'||coalesce(member.horario_id::text,'')||'-'||coalesce(member.fecha_habitual::text,''));
   else slot=marathon.agenda_cupo(member.fecha+delta,site,prof,member.terapia_id,new_hour,null,'H-'||coalesce(maps->>member.horario_id::text,'')||'-'||coalesce((member.fecha_habitual+delta)::text,''));end if;
   if coalesce((slot->>'blocked')::boolean,true)or coalesce((slot->>'remaining')::int,0)<1 then raise exception 'Sin cupo el % a las %. No se modificó ningún turno.',member.fecha+delta,new_hour using errcode='PT409';end if;
   update marathon.turnos set fecha=member.fecha+delta,hora=new_hour,sede=site,profesional_id=prof,duracion_min=duration,estado='PENDIENTE',
    horario_id=case when maps?member.horario_id::text then(maps->>member.horario_id::text)::uuid else member.horario_id end,
    fecha_habitual=case when maps?member.horario_id::text then member.fecha_habitual+delta else member.fecha_habitual end,
    fixed_until=case when scope='following'and member.fixed_until is not null then member.fixed_until+delta else member.fixed_until end where id=member.id;
   insert into marathon.turn_audit(request_id,actor,turn_id,action,before_data,after_data)select p_request_id,auth.uid(),member.id,'series_edit',after_row,to_jsonb(x)from marathon.turnos x where x.id=member.id;
   count_changed=count_changed+1;
  end loop;
  if scope='following'and t.plan_id is not null then
   update marathon.agenda_planes set updated_at=now()where id=t.plan_id;
   -- Comprobar semanas representativas y cada cambio futuro de ocupación conocido.
   for candidate in
    with boundaries as(
     select generate_series(least(t.fecha,new_date),greatest(t.fecha,new_date)+42,interval '1 day')::date d
     union select x.fecha from marathon.turnos x where x.fecha>=least(t.fecha,new_date)and(x.dni=t.dni or x.profesional_id in(select ah.profesional_id from marathon.agenda_horarios ah where ah.id::text in(select value from jsonb_each_text(maps))))
     union select x.desde from marathon.agenda_horarios x where x.desde>=least(t.fecha,new_date)
     union select x.hasta from marathon.agenda_horarios x where x.hasta>=least(t.fecha,new_date)
     union select x.desde from marathon.agenda_pausas x where x.desde>=least(t.fecha,new_date)
     union select x.hasta from marathon.agenda_pausas x where x.hasta>=least(t.fecha,new_date)
    )select distinct h.id,h.desde,h.hasta,h.dia,(b.d+((h.dia-extract(dow from b.d)::int+7)%7))fecha
    from marathon.agenda_horarios h cross join boundaries b where h.id::text in(select value from jsonb_each_text(maps))
   loop
    if candidate.fecha<candidate.desde or(candidate.hasta is not null and candidate.fecha>=candidate.hasta)or(p.baja is not null and candidate.fecha>=p.baja)then continue;end if;
    select a.*into occ from marathon.agenda_pool(candidate.fecha)a where a.plan_id=t.plan_id and(a.id='H-'||candidate.id::text||'-'||candidate.fecha::text or a.id in(select x.id from marathon.turnos x where x.horario_id=candidate.id and x.fecha_habitual=candidate.fecha))limit 1;
    if not found then continue;end if;
    slot=marathon.agenda_cupo(occ.fecha,occ.sede,occ.profesional_id,occ.terapia_id,occ.hora,null,occ.id);
    if coalesce((slot->>'blocked')::boolean,true)or coalesce((slot->>'remaining')::int,0)<1 or exists(select 1 from marathon.agenda_pool(occ.fecha)a where a.dni=t.dni and a.id<>occ.id and a.hora<occ.hora+make_interval(mins=>occ.duracion_min)and occ.hora<a.hora+make_interval(mins=>a.duracion_min))then raise exception 'La repetición futura entra en conflicto el %. No se guardó el cambio.',occ.fecha using errcode='PT409';end if;
   end loop;
  end if;
 end if;
 if t.plan_id is not null and scope='following'then insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data)
 select p_request_id,auth.uid(),'agenda-plan',t.plan_id::text,'turn_series_'||kind,before_plan,to_jsonb(x)||jsonb_build_object('motivo',reason,'desde',t.fecha,'horarios',maps)from marathon.agenda_planes x where x.id=t.plan_id;
 else insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,after_data)values(p_request_id,auth.uid(),'turn',t.id,'turn_series_'||kind,jsonb_build_object('desde',t.fecha,'alcance',scope,'motivo',reason));end if;
 result=jsonb_build_object('ids',ids,'count',count_changed,'recurring',t.plan_id is not null and scope='following','message',case when kind='cancel'then count_changed||' turno(s) cancelados.'else count_changed||' turno(s) editados.'end||case when t.plan_id is not null and scope='following'then case when kind='cancel'then' La asignación quedó dada de baja desde la fecha elegida.'else' Se actualizó también la repetición futura.'end else''end);
 update marathon.solicitudes set resultado=result where id=p_request_id;return result;
end$$;
revoke all on function marathon.turn_series_run(text,jsonb)from public,anon,authenticated;

create or replace function public.marathon_turn_series_preview(p_data jsonb)returns jsonb language plpgsql security definer set search_path=''as $$declare result jsonb;begin
 if not marathon.active_user()then raise exception 'Acceso no autorizado.'using errcode='42501';end if;
 begin
  result=marathon.turn_series_run('preview-'||gen_random_uuid()::text,p_data);
  raise exception using errcode='ZP001',message='Solo vista previa';
 exception when sqlstate 'ZP001'then null;end;
 return result||jsonb_build_object('preview',true);
end$$;
create or replace function public.marathon_turn_series_save(p_request_id text,p_data jsonb)returns jsonb language plpgsql security definer set search_path=''as $$begin
 if not marathon.active_user()then raise exception 'Acceso no autorizado.'using errcode='42501';end if;
 return marathon.turn_series_run(p_request_id,p_data);
end$$;
revoke all on function public.marathon_turn_series_context(text),public.marathon_turn_series_preview(jsonb),public.marathon_turn_series_save(text,jsonb)from public,anon;
grant execute on function public.marathon_turn_series_context(text),public.marathon_turn_series_preview(jsonb),public.marathon_turn_series_save(text,jsonb)to authenticated;
-- Las cuotas eligen el horario vigente en su fecha, sin reasignar cobros históricos.
CREATE OR REPLACE FUNCTION marathon.agenda_cuotas_generar(p_hoy date DEFAULT marathon.agenda_hoy())
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare n int;begin
 if p_hoy>marathon.agenda_hoy() then raise sqlstate '22023' using message='No se generan cuotas anticipadas.';end if;
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
 insert into marathon.agenda_cuotas(plan_id,periodo_id,fecha,hasta,importe,sede)
 select p.id,s.id,(s.inicio+make_interval(months=>g.n))::date,(s.inicio+make_interval(months=>g.n+1))::date,p.importe,h.sede
 from marathon.agenda_periodos s join marathon.agenda_planes p on p.id=s.plan_id
 cross join lateral generate_series(0,greatest(0,(extract(year from p_hoy)::int-extract(year from s.inicio)::int)*12+extract(month from p_hoy)::int-extract(month from s.inicio)::int))g(n)
 cross join lateral(select x.sede from marathon.agenda_horarios x where x.plan_id=p.id and(x.hasta is null or x.hasta>x.desde)order by case when x.desde<=(s.inicio+make_interval(months=>g.n))::date and(x.hasta is null or(s.inicio+make_interval(months=>g.n))::date<x.hasta)then 0 when x.desde>(s.inicio+make_interval(months=>g.n))::date then 1 else 2 end,x.desde,x.dia,x.hora limit 1)h
 where p.facturacion='monthly' and not s.anulado and s.inicio<=p_hoy
 and (s.inicio+make_interval(months=>g.n))::date<=p_hoy
 and(s.fin is null or (s.inicio+make_interval(months=>g.n))::date<s.fin)
 and(p.baja is null or (s.inicio+make_interval(months=>g.n))::date<p.baja)
 on conflict(periodo_id,fecha) do nothing;
 get diagnostics n=row_count;return n;
end$function$
;
CREATE OR REPLACE FUNCTION marathon.saldo_deudas(p_dni text)
 RETURNS TABLE(tipo text, id text, fecha date, hora time without time zone, created_at timestamp with time zone, cargo numeric, pagado numeric, deuda numeric, sede text, profesional text, terapia text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 with all_debts as(
 select 'sesion'::text tipo,t.id,t.fecha,t.hora,t.created_at,
 greatest(0,t.importe-coalesce((select sum(a.monto)from marathon.saldo_ajustes_sesion a where a.turno_id=t.id),0))cargo,
 marathon.saldo_pagado('sesion',t.id)pagado,t.sede,t.profesional_id profesional,t.terapia_id terapia
 from marathon.turnos t where t.dni=p_dni and t.estado='PRESENTE'
 union all
 select 'cuota',q.id::text,q.fecha,'00:00'::time,q.created_at,greatest(0,q.importe-coalesce((select sum(a.importe)from marathon.agenda_ajustes a where a.cuota_id=q.id),0)),marathon.saldo_pagado('cuota',q.id::text),q.sede,
 (select hs.profesional_id from marathon.agenda_horarios hs where hs.plan_id=q.plan_id and(hs.hasta is null or hs.hasta>hs.desde)order by case when hs.desde<=q.fecha and(hs.hasta is null or q.fecha<hs.hasta)then 0 when hs.desde>q.fecha then 1 else 2 end,hs.desde,hs.dia,hs.hora,hs.id limit 1),p.terapia_id
 from marathon.agenda_cuotas q join marathon.agenda_planes p on p.id=q.plan_id where p.dni=p_dni
 union all
 select 'bono',b.id,b.fecha,b.hora,b.created_at,b.importe,marathon.saldo_pagado('bono',b.id),b.sede,b.profesional_id,b.terapia_id
 from marathon.bonos_serie b where b.dni=p_dni and b.estado='ACTIVO')
 select d.tipo,d.id,d.fecha,d.hora,d.created_at,d.cargo,d.pagado,greatest(0,d.cargo-d.pagado),d.sede,d.profesional,d.terapia from all_debts d
 order by d.fecha,d.hora,d.created_at,d.tipo,d.id
$function$
;

notify pgrst,'reload schema';
commit;
