-- Extensión de la base existente 0.12.7. Sin borrar registros ni ampliar permisos.
alter table marathon.turnos add column if not exists series_pattern jsonb;
alter table marathon.turnos add column if not exists recovered_from text references marathon.turnos(id);
alter table marathon.turnos add column if not exists booking_notes text;
create unique index if not exists turnos_recovered_from_unique on marathon.turnos(recovered_from) where recovered_from is not null;
create index if not exists turnos_series_root_idx on marathon.turnos((coalesce(original_id,id)),fecha);

create or replace function marathon.reservation_notes(value text)
returns text language sql immutable set search_path='' as $$
 select coalesce(string_agg(line,E'\n' order by ord),'') from regexp_split_to_table(coalesce(value,''),E'\n') with ordinality l(line,ord)
 where line !~* '^\s*(\[(estado|cobertura|reprogram|recuper|fijo|auditor|sistema|auto|id)[^]]*\]|(estado (actualizado|cambiado)|cobertura (actualizada|modificada)|recuperaci[oó]n (de|creada)|horario fijo|fijo hasta|original_id|request_id|turno_id)\s*[:·-])';
$$;
revoke all on function marathon.reservation_notes(text) from public,anon,authenticated;

-- Combina la agenda confirmada y las propuestas del mismo lote, en todo el intervalo.
create or replace function marathon.recovery_free(d date,site text,prof text,therapy text,h time,duration integer,planned jsonb)
returns boolean language sql stable set search_path='' as $$
 with config as (select s.*,marathon.master_norm(t.especialidad) spec from marathon.agenda_slots(d,site,prof,therapy)s join marathon.terapias t on t.id=therapy where s.hora=to_char(h,'HH24:MI')),
 active as (
 select x.sede,x.terapia_id,x.hora st,x.hora+marathon.session_minutes(x.fecha,x.sede,x.profesional_id,x.hora,x.duracion_min)*interval '1 minute' en,marathon.master_norm(t.especialidad) spec
 from marathon.turnos x join marathon.terapias t on t.id=x.terapia_id where x.fecha=d and x.profesional_id=prof and x.estado<>'CANCELADO'
 union all
 select p->>'sede',p->>'therapy',(p->>'hora')::time,(p->>'hora')::time+(p->>'duration_min')::int*interval '1 minute',marathon.master_norm(t.especialidad)
 from jsonb_array_elements(planned)p join marathon.terapias t on t.id=p->>'therapy' where p->>'prof'=prof and p->>'fecha'=d::text
 ), cuts as (select h cut_time union select st from active where st>h and st<h+duration*interval '1 minute' union select en from active where en>h and en<h+duration*interval '1 minute')
 select coalesce((select not c.blocked
 and not exists(select 1 from active a where a.st<h+duration*interval '1 minute' and h<a.en and(a.sede<>site or not(a.terapia_id=therapy or(c.spec<>'' and a.spec=c.spec))))
 and not exists(select 1 from cuts z where (select count(*) from active a where a.st<=z.cut_time and z.cut_time<a.en and a.terapia_id=therapy)>=c.capacity or(select count(*)from active a where a.st<=z.cut_time and z.cut_time<a.en)>=c.shared_capacity)
 from config c),false);
$$;
revoke all on function marathon.recovery_free(date,text,text,text,time,integer,jsonb) from public,anon,authenticated;

create or replace function public.marathon_turns_preview(p_action text,p_turns jsonb)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='25s' as $$
#variable_conflict use_variable
declare item jsonb;old marathon.turnos%rowtype;root text;days integer[];pattern jsonb;inferred boolean;tail date;d date;start_day date;last_day date;duration integer;chosen date;series_snapshot text;
 rows jsonb:='[]';planned jsonb:='[]';row_data jsonb;today date:=(now() at time zone 'America/Argentina/Buenos_Aires')::date;now_local timestamp:=now() at time zone 'America/Argentina/Buenos_Aires';
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_action is null or p_action not in('present','cancel','recover') or jsonb_typeof(p_turns) is distinct from 'array' then raise sqlstate '22023' using message='Operación múltiple inválida.';end if;
 if jsonb_array_length(p_turns) not between 1 and 30 or octet_length(p_turns::text)>12000 then raise sqlstate '22023' using message='Seleccioná entre 1 y 30 turnos.';end if;
 if exists(select 1 from jsonb_array_elements(p_turns)x where jsonb_typeof(x)<>'object' or coalesce(x->>'id','')='' or jsonb_typeof(x->'version') is distinct from 'number' or coalesce(x->>'version','')!~'^[0-9]{1,18}$') or (select count(distinct x->>'id')from jsonb_array_elements(p_turns)x)<>jsonb_array_length(p_turns) then raise sqlstate '22023' using message='La selección tiene turnos repetidos o inválidos.';end if;
 for item in select value from jsonb_array_elements(p_turns) order by value->>'id' loop
  select * into old from marathon.turnos t where t.id=item->>'id';
  if not found or old.version<>(item->>'version')::bigint then raise sqlstate 'PT409' using message='Uno de los turnos cambió. Actualizá la lista y revisá la selección.';end if;
  if (p_action='present' and old.estado<>'PENDIENTE') or(p_action='cancel' and old.estado='CANCELADO') or(p_action='recover' and old.estado<>'CANCELADO') then raise sqlstate '22023' using message='Hay un turno cuyo estado no permite esta acción. No se modificó ninguno.';end if;
  if p_action in('cancel','recover') and marathon.turn_cash_paid(old.id)>0 then raise sqlstate '22023' using message='Hay un turno con cobros. Registrá el reintegro antes de continuar. No se modificó ninguno.';end if;
  if p_action='recover' and exists(select 1 from marathon.turnos t where t.recovered_from=old.id) then raise sqlstate '22023' using message='Esta cancelación ya tiene una recuperación. Si esa nueva sesión se canceló, seleccioná la nueva cancelación.';end if;
  row_data=jsonb_build_object('id',old.id,'version',old.version,'estado',old.estado,'fecha',old.fecha,'hora',to_char(old.hora,'HH24:MI'),'dni',old.dni,'paciente',(select concat_ws(' ',p.apellido,p.nombre,p.segundo_nombre)from marathon.pacientes p where p.dni=old.dni),'prof',old.profesional_id,'profesional',(select concat_ws(' ',p.nombre,p.apellido)from marathon.profesionales p where p.id=old.profesional_id),'therapy',old.terapia_id,'terapia',(select t.nombre from marathon.terapias t where t.id=old.terapia_id),'sede',old.sede,'importe',old.importe,'paid',marathon.turn_paid(old.id),'coverage',old.coverage,'source_fingerprint',encode(sha256(convert_to(to_jsonb(old)::text,'UTF8')),'hex'));
  if p_action='recover' then
   root=coalesce(old.original_id,old.id);inferred=old.series_pattern is null;
   if not inferred then select array_agg(x::int order by x::int)into days from jsonb_array_elements_text(old.series_pattern->'days')x;
   else select array_agg(distinct extract(dow from t.fecha)::int order by extract(dow from t.fecha)::int)into days from marathon.turnos t where coalesce(t.original_id,t.id)=root and t.dni=old.dni and t.profesional_id=old.profesional_id and t.terapia_id=old.terapia_id and t.sede=old.sede and t.hora=old.hora and t.recovered_from is null;end if;
   if coalesce(cardinality(days),0)not between 1 and 7 or not(days<@array[0,1,2,3,4,5,6])then raise sqlstate '22023' using message='No se pudo identificar el patrón semanal de la serie. Revisá sus turnos originales.';end if;
   pattern=jsonb_build_object('days',days,'hora',to_char(old.hora,'HH24:MI'),'source',case when inferred then 'inferred' else coalesce(old.series_pattern->>'source','saved')end);
   select max(t.fecha),encode(sha256(convert_to(coalesce(jsonb_agg(jsonb_build_array(t.id,t.version,t.fecha,t.hora,t.estado)order by t.id)::text,''),'UTF8')),'hex')into tail,series_snapshot from marathon.turnos t where coalesce(t.original_id,t.id)=root;
   select greatest(tail,coalesce(max((p->>'fecha')::date),tail))into tail from jsonb_array_elements(planned)p where p->>'root'=root;
   select t.duracion_min into duration from marathon.terapias t where t.id=old.terapia_id and t.estado='ACTIVO';
   if duration is null then raise sqlstate '22023' using message='La terapia ya no está activa.';end if;
   start_day=greatest(tail+1,today);last_day=least(start_day+365,date '2100-12-31');chosen=null;
   for d in select start_day+n from generate_series(0,last_day-start_day)n where extract(dow from start_day+n)::int=any(days)order by n loop
    if d+old.hora<=now_local then continue;end if;
    if not marathon.recovery_free(d,old.sede,old.profesional_id,old.terapia_id,old.hora,marathon.session_minutes(d,old.sede,old.profesional_id,old.hora,duration),planned)then continue;end if;
    if exists(select 1 from marathon.turnos t where t.fecha=d and t.dni=old.dni and t.estado<>'CANCELADO' and t.hora<old.hora+marathon.session_minutes(d,old.sede,old.profesional_id,old.hora,duration)*interval '1 minute' and old.hora<t.hora+marathon.session_minutes(t.fecha,t.sede,t.profesional_id,t.hora,t.duracion_min)*interval '1 minute')then continue;end if;
    if exists(select 1 from jsonb_array_elements(planned)p where p->>'dni'=old.dni and p->>'fecha'=d::text and(p->>'hora')::time<old.hora+marathon.session_minutes(d,old.sede,old.profesional_id,old.hora,duration)*interval '1 minute' and old.hora<(p->>'hora')::time+(p->>'duration_min')::int*interval '1 minute')then continue;end if;
    chosen=d;exit;
   end loop;
   if chosen is null then raise sqlstate '22023' using message='No se encontró una fecha compatible en los próximos 366 días de búsqueda. No se guardó ninguna recuperación.';end if;
   duration=marathon.session_minutes(chosen,old.sede,old.profesional_id,old.hora,duration);
   row_data=row_data||jsonb_build_object('proposed_fecha',chosen,'proposed_hora',to_char(old.hora,'HH24:MI'),'duration_min',duration,'root',root,'pattern',pattern,'pattern_inferred',inferred,'series_snapshot',series_snapshot);
   planned=planned||jsonb_build_array(jsonb_build_object('root',root,'fecha',chosen,'hora',to_char(old.hora,'HH24:MI'),'dni',old.dni,'prof',old.profesional_id,'therapy',old.terapia_id,'sede',old.sede,'duration_min',duration));
  end if;
  rows=rows||jsonb_build_array(row_data);
 end loop;
 return jsonb_build_object('action',p_action,'rows',rows,'review_token',encode(sha256(convert_to(jsonb_build_object('action',p_action,'rows',rows)::text,'UTF8')),'hex'));
end $$;
revoke all on function public.marathon_turns_preview(text,jsonb) from public,anon;
grant execute on function public.marathon_turns_preview(text,jsonb) to authenticated;

create or replace function public.marathon_turns_commit(p_request_id text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='3s' set statement_timeout='30s' as $$
#variable_conflict use_variable
declare reply jsonb;review jsonb;r jsonb;old marathon.turnos%rowtype;id text;ids jsonb:='[]';after_row jsonb;
begin
 reply=marathon.operation_begin(p_request_id,'agenda:bulk',p_data);if reply is not null then return reply;end if;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['action','turns','review_token']))then raise sqlstate '22023'using message='Solicitud inválida.';end if;
 perform 1 from marathon.turnos t join jsonb_array_elements(p_data->'turns')x on t.id=x->>'id' order by t.id for update of t;
 review=public.marathon_turns_preview(p_data->>'action',p_data->'turns');
 if coalesce(p_data->>'review_token','')<>review->>'review_token' then raise sqlstate 'PT409'using message='Los turnos, pagos o fechas disponibles cambiaron después de la revisión. Volvé a revisar antes de confirmar. No se guardó ningún cambio.';end if;
 for r in select value from jsonb_array_elements(review->'rows')loop
  if p_data->>'action'='recover' then
   select * into old from marathon.turnos t where t.id=r->>'id';id='TUR-'||gen_random_uuid()::text;
   insert into marathon.turnos(id,original_id,recovered_from,fecha,hora,sede,profesional_id,terapia_id,duracion_min,dni,importe,coverage,estado,observaciones,booking_notes,series_pattern,created_by,updated_by)
   values(id,r->>'root',old.id,(r->>'proposed_fecha')::date,(r->>'proposed_hora')::time,old.sede,old.profesional_id,old.terapia_id,(r->>'duration_min')::int,old.dni,old.importe,old.coverage,'PENDIENTE',coalesce(old.booking_notes,marathon.reservation_notes(old.observaciones)),coalesce(old.booking_notes,marathon.reservation_notes(old.observaciones)),r->'pattern',auth.uid(),auth.uid());
   select to_jsonb(t)into after_row from marathon.turnos t where t.id=id;
   insert into marathon.turn_audit(request_id,actor,turn_id,action,before_data,after_data)values(p_request_id,auth.uid(),id,'recover',to_jsonb(old),after_row);
  else
   id=r->>'id';perform public.marathon_agenda_command('BULK-'||md5(p_request_id||':'||id),'status',jsonb_build_object('id',id,'version',(r->>'version')::bigint,'estado',case when p_data->>'action'='present'then 'PRESENTE'else 'CANCELADO'end));
  end if;
  ids=ids||jsonb_build_array(id);
 end loop;
 reply=jsonb_build_object('ids',ids,'message',jsonb_array_length(ids)||case when p_data->>'action'='recover'then ' sesiones recuperadas al final de sus series. Se conservaron los cancelados; no se crearon cobros ni bonos.'else ' turnos actualizados. No se generaron cobros automáticos.'end);
 update marathon.solicitudes s set resultado=reply where s.id=p_request_id;return reply;
end $$;
revoke all on function public.marathon_turns_commit(text,jsonb) from public,anon;
grant execute on function public.marathon_turns_commit(text,jsonb) to authenticated;


-- FUNCIONES EXISTENTES ACTUALIZADAS (definiciones originales preservadas salvo campos de serie, notas y recuperación)
CREATE OR REPLACE FUNCTION public.marathon_agenda_command(p_request_id text, p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '3s'
AS $function$
#variable_conflict use_variable
declare uid uuid:=auth.uid();req marathon.solicitudes%rowtype;hashed text;reply jsonb;old marathon.turnos%rowtype;after_row jsonb;
 dates date[];d date;site text;prof text;therapy text;dni text;hour_text text;obs text;cost numeric;duration integer;base_duration integer;
 ids text[]:=array[]::text[];id text;root_id text;state text;slot record;paid numeric;ver bigint;coverage jsonb;reason text;bonus jsonb;fixed_dates date[];fixed_until date;fixed_days integer[];member marathon.turnos%rowtype;series_days integer[];series_pattern jsonb;
begin
 perform 1 from marathon.app_users where user_id=uid and active for share;
 if not found then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_request_id is null or p_request_id !~ '^[a-zA-Z0-9_-]{12,100}$' or p_action is null or p_action not in ('book','status','coverage','fixed_end','bonus_pay','bonus_refund','bonus_cancel','advance_deposit','advance_apply','advance_refund') or p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>20000 then raise sqlstate '22023' using message='Solicitud inválida.';end if;
 if current_setting('transaction_isolation')<>'read committed' then raise sqlstate '22023' using message='La agenda requiere transacciones READ COMMITTED.';end if;
 hashed=encode(sha256(convert_to(jsonb_build_object('action',p_action,'data',p_data)::text,'UTF8')),'hex');
 insert into marathon.solicitudes(id,usuario_id,tipo,payload_hash) values(p_request_id,uid,'agenda:'||p_action,hashed) on conflict on constraint solicitudes_pkey do nothing;
 select * into req from marathon.solicitudes s where s.id=p_request_id for update;
 if req.id is null or req.usuario_id<>uid or req.tipo<>'agenda:'||p_action or req.payload_hash<>hashed then raise sqlstate '22023' using message='Identificador de solicitud utilizado con otros datos.';end if;
 if req.resultado is not null then return req.resultado;end if;
 -- Mismo orden y mismo candado que el mantenimiento de maestros. Tres usuarios: prima la integridad.
 -- VOLATILE (valor predeterminado) permite leer el estado confirmado después de esperar el candado.
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
 if exists(select 1 from jsonb_object_keys(p_data) k where k<>all(case p_action when 'book' then array['dates','sede','prof','therapy','dni','hora','importe','observaciones','coverage','fixed_from','fixed_until','fixed_days','series_days','bonus_amount','bonus_paid','bonus_medium'] when 'coverage' then array['id','version','coverage','motivo'] when 'bonus_pay' then array['id','version','monto','medio','observaciones'] when 'bonus_refund' then array['id','version','monto','medio','observaciones'] when 'bonus_cancel' then array['id','version','motivo'] when 'advance_deposit' then array['dni','sede','therapy','prof','monto','medio','observaciones','apply_existing'] when 'advance_apply' then array['dni'] when 'advance_refund' then array['id','version','monto','medio','observaciones'] when 'fixed_end' then array['id','version'] else array['id','version','estado'] end)) then raise sqlstate '22023' using message='La solicitud contiene campos no admitidos.';end if;
 if p_action='book' then
  site=marathon.master_text(p_data,'sede',40,true);prof=marathon.master_text(p_data,'prof',100,true);therapy=marathon.master_text(p_data,'therapy',100,true);
  dni=marathon.master_text(p_data,'dni',12,true);hour_text=marathon.master_text(p_data,'hora',5,true);obs=marathon.master_text(p_data,'observaciones',1000);
  if dni !~ '^[0-9]{1,12}$' or not exists(select 1 from marathon.pacientes p where p.dni=dni) then raise sqlstate '22023' using message='Buscá y seleccioná un paciente registrado.';end if;
  if hour_text !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or jsonb_typeof(p_data->'importe') is distinct from 'number' or coalesce(p_data->>'importe','') !~ '^[0-9]{1,10}(\.[0-9]{1,2})?$' then raise sqlstate '22023' using message='Hora o importe inválidos (hasta dos decimales).';end if;
  cost=(p_data->>'importe')::numeric;
  if p_data?'coverage' then coverage=marathon.normalize_turn_coverage(dni,p_data->'coverage');end if;
  if jsonb_typeof(p_data->'dates') is distinct from 'array' or jsonb_array_length(p_data->'dates') not between 1 and 60 then raise sqlstate '22023' using message='Seleccioná entre 1 y 60 fechas.';end if;
  if exists(select 1 from jsonb_array_elements(p_data->'dates') x where jsonb_typeof(x)<>'string') then raise sqlstate '22023' using message='Fecha inválida.';end if;
  select array_agg(marathon.agenda_date(value) order by value) into dates from jsonb_array_elements_text(p_data->'dates');
  if cardinality(dates)<>(select count(distinct x) from unnest(dates) x) then raise sqlstate '22023' using message='Hay fechas repetidas en la reserva.';end if;
  if p_data ?| array['fixed_until','fixed_from','fixed_days'] then
   fixed_dates=marathon.fixed_dates(p_data->>'fixed_from',p_data->>'fixed_until',p_data->'fixed_days');
   if dates<>fixed_dates then raise sqlstate '22023' using message='El horario fijo debe incluir todas las fechas hasta la revisión.';end if;
   fixed_until=marathon.agenda_date(p_data->>'fixed_until');
   select array_agg(x::int order by x::int) into fixed_days from jsonb_array_elements_text(p_data->'fixed_days')x;
  end if;
     if p_data?'series_days' then
    if jsonb_typeof(p_data->'series_days') is distinct from 'array' or jsonb_array_length(p_data->'series_days') not between 1 and 7 or exists(select 1 from jsonb_array_elements_text(p_data->'series_days') x where x !~ '^[0-6]$') then raise sqlstate '22023' using message='Días semanales inválidos.';end if;
    select array_agg(distinct x::int order by x::int) into series_days from jsonb_array_elements_text(p_data->'series_days') x;
    if cardinality(series_days)<>jsonb_array_length(p_data->'series_days') or exists(select 1 from unnest(dates) x where extract(dow from x)::int<>all(series_days)) then raise sqlstate '22023' using message='Los días de la serie no coinciden con las fechas elegidas.';end if;
    if fixed_days is not null and fixed_days<>series_days then raise sqlstate '22023' using message='Los días del horario fijo no coinciden con la serie.';end if;
   else
    select array_agg(distinct extract(dow from x)::int order by extract(dow from x)::int) into series_days from unnest(dates) x;
   end if;
   series_pattern=jsonb_build_object('days',series_days,'hora',hour_text,'source',case when p_data?'series_days' then 'selected' else 'inferred' end);
select t.duracion_min into duration from marathon.terapias t where t.id=therapy and t.estado='ACTIVO';
  if duration is null then raise sqlstate '22023' using message='La terapia ya no está activa. Actualizá los datos de agenda.';end if;
  base_duration=duration;
  foreach d in array dates loop
   duration=marathon.session_minutes(d,site,prof,hour_text::time,base_duration);
   select * into slot from marathon.agenda_slots(d,site,prof,therapy) s where s.hora=hour_text;
   if slot.hora is null or slot.remaining<1 or slot.blocked then raise sqlstate 'PT409' using message='Sin cupo el '||d||' a las '||hour_text||'. No se guardó ningún turno de la reserva.';end if;
   if exists(select 1 from marathon.turnos t where t.dni=dni and t.fecha=d and t.estado<>'CANCELADO' and t.hora<(hour_text::time+duration*interval '1 minute') and hour_text::time<(t.hora+marathon.session_minutes(t.fecha,t.sede,t.profesional_id,t.hora,t.duracion_min)*interval '1 minute')) then raise sqlstate 'PT409' using message='El paciente ya tiene un turno que se superpone el '||d||'. No se guardó la reserva.';end if;
   id='TUR-'||gen_random_uuid()::text;if root_id is null then root_id=id;end if;
   insert into marathon.turnos(id,original_id,fecha,sede,hora,duracion_min,terapia_id,profesional_id,dni,importe,estado,observaciones,booking_notes,series_pattern,coverage,fixed_until,fixed_days,created_by,updated_by)
    values(id,case when id=root_id then null else root_id end,d,site,hour_text::time,duration,therapy,prof,dni,cost,'PENDIENTE',obs,obs,series_pattern,coverage,fixed_until,fixed_days,uid,uid);
   select to_jsonb(t) into after_row from marathon.turnos t where t.id=id;
   insert into marathon.turn_audit(request_id,actor,turn_id,action,after_data) values(p_request_id,uid,id,p_action,after_row);ids=array_append(ids,id);
  end loop;
  bonus=marathon.bonus_create(p_request_id,root_id,p_data);
  reply=jsonb_build_object('ids',ids,'coverage',coverage,'bonus',bonus,'sessions',(select jsonb_agg(jsonb_build_object('fecha',t.fecha,'hora',to_char(t.hora,'HH24:MI'),'end_hour',to_char(t.hora+t.duracion_min*interval '1 minute','HH24:MI'),'duration_min',t.duracion_min) order by t.fecha,t.hora,t.id) from marathon.turnos t where t.id=any(ids)),'message',case when cardinality(ids)=1 then 'Turno reservado.' else cardinality(ids)||' turnos reservados.' end);
 elsif p_action='fixed_end' then
  id=marathon.master_text(p_data,'id',100,true);ver=marathon.operation_version(p_data);
  select * into old from marathon.turnos t where t.id=id for update;
  if not found or old.fixed_until is null then raise sqlstate '22023' using message='No se encontró un horario fijo.';end if;
  if old.version<>ver then raise sqlstate 'PT409' using message='El turno cambió. Actualizá la agenda.';end if;
  for member in select t.* from marathon.turnos t where coalesce(t.original_id,t.id)=coalesce(old.original_id,old.id)
   and t.fecha>=old.fecha and t.fecha>=(now() at time zone 'America/Argentina/Buenos_Aires')::date and t.estado='PENDIENTE' order by t.fecha,t.hora,t.id for update loop
   if marathon.turn_paid(member.id)>0 then raise sqlstate 'PT409' using message='Hay un turno con cobros. Reintegrá antes de finalizar el fijo.';end if;
   update marathon.turnos t set estado='CANCELADO' where t.id=member.id;
   select to_jsonb(t) into after_row from marathon.turnos t where t.id=member.id;
   insert into marathon.turn_audit(request_id,actor,turn_id,action,before_data,after_data)values(p_request_id,uid,member.id,'fixed_end',to_jsonb(member),after_row);
   ids=array_append(ids,member.id);
  end loop;
  if cardinality(ids)=0 then raise sqlstate '22023' using message='No quedan turnos futuros pendientes para finalizar.';end if;
  reply=jsonb_build_object('ids',ids,'message',cardinality(ids)||' turnos futuros cancelados. Se conservaron asistencia y cobros anteriores.');
 elsif p_action in('bonus_pay','bonus_refund','bonus_cancel') then
  reply=marathon.bonus_change(p_request_id,p_action,p_data);
 elsif p_action in('advance_deposit','advance_apply','advance_refund')then
 reply=marathon.advance_change(p_request_id,p_action,p_data);
 elsif p_action='coverage' then
  id=marathon.master_text(p_data,'id',100,true);reason=marathon.master_text(p_data,'motivo',500,true);
  if length(btrim(reason))<3 then raise sqlstate '22023' using message='Indicá el motivo de la corrección (mínimo 3 caracteres).';end if;
  ver=marathon.operation_version(p_data);
  select * into old from marathon.turnos t where t.id=id for update;
  if not found then raise sqlstate 'PT404' using message='El turno ya no existe.';end if;
  if old.version<>ver then raise sqlstate 'PT409' using message='El turno cambió. Actualizá la agenda.';end if;
  if coalesce(old.coverage->>'type','')<>'' and old.estado<>'PENDIENTE' and not exists(select 1 from marathon.app_users u where u.user_id=uid and u.active and u.role='ADMIN') then raise sqlstate '42501' using message='Solo administración puede corregir la cobertura de un turno que no está pendiente.';end if;
  coverage=marathon.normalize_turn_coverage(old.dni,p_data->'coverage');
  update marathon.turnos t set coverage=coverage where t.id=id;
  select to_jsonb(t) into after_row from marathon.turnos t where t.id=id;
  insert into marathon.turn_audit(request_id,actor,turn_id,action,before_data,after_data) values(p_request_id,uid,id,'coverage',to_jsonb(old),after_row||jsonb_build_object('motivo_cobertura',reason));
  reply=jsonb_build_object('ids',jsonb_build_array(id),'message','Cobertura del turno actualizada. Se conservaron importe, estado y pagos.');
 else
  id=marathon.master_text(p_data,'id',100,true);state=marathon.master_text(p_data,'estado',10,true);
  if state not in ('PENDIENTE','PRESENTE','AUSENTE','CANCELADO') or jsonb_typeof(p_data->'version') is distinct from 'number' or coalesce(p_data->>'version','') !~ '^[0-9]{1,18}$' then raise sqlstate '22023' using message='Estado o versión inválidos.';end if;
  ver=(p_data->>'version')::bigint;
  select * into old from marathon.turnos t where t.id=id for update;
  if not found then raise sqlstate 'PT404' using message='El turno ya no existe.';end if;
  if old.version<>ver then raise sqlstate 'PT409' using message='El turno cambió. Actualizá la agenda antes de modificarlo.';end if;
  select coalesce(sum(case when m.tipo='REINTEGRO' then -m.monto else m.monto end),0) into paid from marathon.movimientos m where m.turno_id=id;
  if state<>'PRESENTE' and paid>0 then raise sqlstate '22023' using message='El turno tiene cobros. Registrá el reintegro antes de cambiar su estado.';end if;
     if old.estado='CANCELADO' and state<>'CANCELADO' and exists(select 1 from marathon.turnos r where r.recovered_from=old.id) then raise sqlstate 'PT409' using message='Esta cancelación ya fue recuperada. Consultá la nueva sesión.';end if;
if old.estado='CANCELADO' and state<>'CANCELADO' then
   select * into slot from marathon.agenda_slots(old.fecha,old.sede,old.profesional_id,old.terapia_id) s where s.hora=to_char(old.hora,'HH24:MI');
   -- No restaurar con una duración distinta de la que se comprobó.
   if marathon.session_minutes(old.fecha,old.sede,old.profesional_id,old.hora,old.duracion_min)<>(select marathon.session_minutes(old.fecha,old.sede,old.profesional_id,old.hora,t.duracion_min) from marathon.terapias t where t.id=old.terapia_id) then raise sqlstate 'PT409' using message='Cambió la duración de la terapia. Creá una nueva reserva para este turno cancelado.';end if;
   if slot.hora is null or slot.remaining<1 or slot.blocked then raise sqlstate 'PT409' using message='El horario ya no tiene cupo. El turno sigue cancelado.';end if;
   if exists(select 1 from marathon.turnos t where t.dni=old.dni and t.fecha=old.fecha and t.estado<>'CANCELADO' and t.hora<old.hora+marathon.session_minutes(old.fecha,old.sede,old.profesional_id,old.hora,old.duracion_min)*interval '1 minute' and old.hora<t.hora+marathon.session_minutes(t.fecha,t.sede,t.profesional_id,t.hora,t.duracion_min)*interval '1 minute') then raise sqlstate 'PT409' using message='El paciente tiene otro turno que se superpone.';end if;
  end if;
  if state<>'PRESENTE' then perform marathon.advance_apply(p_request_id,id,true);end if;
 update marathon.turnos t set estado=state,attendance_manual_date=t.fecha,attendance_auto=false,attendance_auto_at=null where t.id=id;
 if state='PRESENTE'then perform marathon.advance_apply(p_request_id,id);end if;
  select to_jsonb(t) into after_row from marathon.turnos t where t.id=id;
  insert into marathon.turn_audit(request_id,actor,turn_id,action,before_data,after_data) values(p_request_id,uid,id,p_action,to_jsonb(old),after_row);
  reply=jsonb_build_object('ids',jsonb_build_array(id),'message','Estado del turno actualizado.');
 end if;
 update marathon.solicitudes s set resultado=reply where s.id=p_request_id;return reply;
end $function$
;
CREATE OR REPLACE FUNCTION public.marathon_agenda_search(p_filters jsonb, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d date;e date;rows jsonb;nxt jsonb;summary jsonb;state text;layout text;groups jsonb;
begin
 if not marathon.active_user()then raise sqlstate '42501'using message='Acceso no autorizado.';end if;
 perform marathon.daily_validate(p_filters,array['from','to','sede','prof','therapy','query','state','layout'],least(p_limit,100),p_after);
 d=marathon.agenda_date(p_filters->>'from');e=marathon.agenda_date(p_filters->>'to');state=coalesce(p_filters->>'state','');
 if p_limit is null or p_limit not between 1 and 10000 or e<d or e-d>31 or(p_after is not null and not(p_after?&array['fecha','hora','id']))then raise sqlstate '22023'using message='Elegí un período de hasta 32 días y una página válida.';end if;
 if state not in('','PENDIENTE','PRESENTE','AUSENTE','CANCELADO')then raise sqlstate '22023'using message='Estado de turno inválido.';end if;

 layout=coalesce(p_filters->>'layout','');
 if layout not in('','blocks')or(layout='blocks'and p_limit>50)then raise sqlstate '22023'using message='Vista o cantidad de bloques inválida.';end if;
 if layout='blocks'then
  with base as(
  select jsonb_build_array(t.sede,t.profesional_id,t.terapia_id)::text group_id,t.*,b.coverage,b.fixed_until,b.attendance_auto,p.telefono,p.observaciones patient_notes,coalesce(b.booking_notes,marathon.reservation_notes(b.observaciones)) booking_notes,exists(select 1 from marathon.turnos r where r.recovered_from=b.id) has_recovery from marathon.daily_turns t
  join marathon.turnos b on b.id=t.id join marathon.pacientes p on p.dni=t.dni
  where t.fecha between d and e and(coalesce(p_filters->>'sede','')=''or t.sede=p_filters->>'sede')
  and(coalesce(p_filters->>'prof','')=''or t.profesional_id=p_filters->>'prof')
  and(coalesce(p_filters->>'therapy','')=''or t.terapia_id=p_filters->>'therapy')
  and(coalesce(p_filters->>'query','')=''or strpos(marathon.master_norm(t.paciente||' '||t.dni),marathon.master_norm(p_filters->>'query'))>0)

 ), chosen as(select * from base where state=''or estado=state),
 keys as(
  select fecha,hora,group_id from chosen where p_after is null or(fecha,hora,group_id)>(marathon.agenda_date(p_after->>'fecha'),(p_after->>'hora')::time,p_after->>'id')
  group by fecha,hora,group_id order by fecha,hora,group_id limit p_limit+1
 ), wanted as(select * from keys order by fecha,hora,group_id limit p_limit),
 paged as(select c.* from chosen c join wanted k using(fecha,hora,group_id)),
 metadata as(
  select fecha,hora,group_id,min(sede) sede,min(profesional_id) profesional_id,min(terapia_id) terapia_id,min(profesional) profesional,min(terapia) terapia,count(*) listed
  from paged group by fecha,hora,group_id
 )
 select coalesce((select jsonb_agg(to_jsonb(x)-'group_id'order by fecha,hora,group_id,id)from paged x),'[]'::jsonb),
 (select jsonb_build_object('total',count(*),'patients',count(distinct dni),'PENDIENTE',count(*)filter(where estado='PENDIENTE'),'PRESENTE',count(*)filter(where estado='PRESENTE'),'AUSENTE',count(*)filter(where estado='AUSENTE'),'CANCELADO',count(*)filter(where estado='CANCELADO'),'debt',coalesce(sum(debt),0))from base),
 coalesce((select jsonb_agg(jsonb_build_object('fecha',m.fecha,'hora',m.hora,'key',m.group_id,'sede',m.sede,'profesional_id',m.profesional_id,'terapia_id',m.terapia_id,'profesional',m.profesional,'terapia',m.terapia,'listed',m.listed,'availability_known',s.hora is not null,'capacity',s.capacity,'remaining',s.remaining,'blocked',s.blocked)order by m.fecha,m.hora,m.group_id)
 from metadata m left join lateral(select * from marathon.agenda_slots(m.fecha,m.sede,m.profesional_id,m.terapia_id)s where s.hora=to_char(m.hora,'HH24:MI'))s on true),'[]'::jsonb),
 (select case when(select count(*)from keys)>p_limit then jsonb_build_object('fecha',fecha,'hora',hora,'id',group_id)end from wanted order by fecha desc,hora desc,group_id desc limit 1)
 into rows,summary,groups,nxt;
 return jsonb_build_object('rows',rows,'next',nxt,'summary',summary,'blocks',groups,'generated_at',statement_timestamp(),'layout','blocks');
 end if;
 with base as(
  select t.*,b.coverage,b.fixed_until,b.attendance_auto,p.telefono,p.observaciones patient_notes,coalesce(b.booking_notes,marathon.reservation_notes(b.observaciones)) booking_notes,exists(select 1 from marathon.turnos r where r.recovered_from=b.id) has_recovery from marathon.daily_turns t
  join marathon.turnos b on b.id=t.id join marathon.pacientes p on p.dni=t.dni
  where t.fecha between d and e and(coalesce(p_filters->>'sede','')=''or t.sede=p_filters->>'sede')
  and(coalesce(p_filters->>'prof','')=''or t.profesional_id=p_filters->>'prof')
  and(coalesce(p_filters->>'therapy','')=''or t.terapia_id=p_filters->>'therapy')
  and(coalesce(p_filters->>'query','')=''or strpos(marathon.master_norm(t.paciente||' '||t.dni),marathon.master_norm(p_filters->>'query'))>0)
 ), paged as(
  select * from base where(state=''or estado=state)and(p_after is null or(fecha,hora,id)>(marathon.agenda_date(p_after->>'fecha'),(p_after->>'hora')::time,p_after->>'id'))
  order by fecha,hora,id limit p_limit+1
 )
 select coalesce((select jsonb_agg(to_jsonb(x)order by fecha,hora,id)from paged x),'[]'::jsonb),
 (select jsonb_build_object('total',count(*),'patients',count(distinct dni),'PENDIENTE',count(*)filter(where estado='PENDIENTE'),'PRESENTE',count(*)filter(where estado='PRESENTE'),'AUSENTE',count(*)filter(where estado='AUSENTE'),'CANCELADO',count(*)filter(where estado='CANCELADO'),'debt',coalesce(sum(debt),0))from base)
 into rows,summary;
 if p_limit=10000 and jsonb_array_length(rows)>10000 then raise sqlstate '22023'using message='Hay más de 10.000 turnos. Reducí el período o los filtros para exportar el listado completo.';end if;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('fecha',rows->(p_limit-1)->>'fecha','hora',rows->(p_limit-1)->>'hora','id',rows->(p_limit-1)->>'id');end if;
 return jsonb_build_object('rows',rows,'next',nxt,'summary',summary,'generated_at',statement_timestamp());
end $function$
;
revoke all on function public.marathon_agenda_command(text,text,jsonb) from public,anon;
grant execute on function public.marathon_agenda_command(text,text,jsonb) to authenticated;
revoke all on function public.marathon_agenda_search(jsonb,jsonb,integer) from public,anon;
grant execute on function public.marathon_agenda_search(jsonb,jsonb,integer) to authenticated;
