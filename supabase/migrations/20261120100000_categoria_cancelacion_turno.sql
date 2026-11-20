-- Distingue, al cancelar un turno, un error de carga de la secretaria de una cancelacion
-- real (paciente, profesional, reprogramado, otro). El motivo elegido queda en
-- turnos.categoria_cancelacion y turn_audit (trazabilidad intacta), y el informe de
-- pacientes separa "Cancelados" de "Error de carga" para que el indicador de
-- cancelaciones no se infle con errores de tipeo.

alter table marathon.turnos add column if not exists categoria_cancelacion text;
alter table marathon.turnos drop constraint if exists turnos_categoria_cancelacion_check;
alter table marathon.turnos add constraint turnos_categoria_cancelacion_check
 check (categoria_cancelacion is null or categoria_cancelacion in ('ERROR_CARGA','PACIENTE','PROFESIONAL','OTRO'));

create or replace function public.marathon_agenda_command(p_request_id text, p_action text, p_data jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
 set lock_timeout to '5s'
as $function$
declare uid uuid:=auth.uid();req marathon.solicitudes%rowtype;hashed text;reply jsonb;old marathon.turnos%rowtype;after_row jsonb;
 dates date[];d date;site text;prof text;therapy text;dni text;hour_text text;obs text;cost numeric;duration integer;base_duration integer;
 ids text[]:=array[]::text[];id text;root_id text;state text;slot record;paid numeric;ver bigint;coverage jsonb;reason text;cancel_category text;bonus jsonb;fixed_dates date[];fixed_until date;fixed_days integer[];member marathon.turnos%rowtype;series_days integer[];series_pattern jsonb;
begin
 perform 1 from marathon.app_users where user_id=uid and active and role in('ADMIN','SECRETARIA') for share;
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
 if exists(select 1 from jsonb_object_keys(p_data) k where k<>all(case p_action when 'book' then array['dates','sede','prof','therapy','dni','hora','importe','observaciones','coverage','fixed_from','fixed_until','fixed_days','series_days','bonus_amount','bonus_paid','bonus_medium'] when 'coverage' then array['id','version','coverage','motivo'] when 'bonus_pay' then array['id','version','monto','medio','observaciones'] when 'bonus_refund' then array['id','version','monto','medio','observaciones'] when 'bonus_cancel' then array['id','version','motivo'] when 'advance_deposit' then array['dni','sede','therapy','prof','monto','medio','observaciones','apply_existing'] when 'advance_apply' then array['dni'] when 'advance_refund' then array['id','version','monto','medio','observaciones'] when 'fixed_end' then array['id','version'] else array['id','version','estado','categoria_cancelacion'] end)) then raise sqlstate '22023' using message='La solicitud contiene campos no admitidos.';end if;
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
  if state='CANCELADO' then
   cancel_category=marathon.master_text(p_data,'categoria_cancelacion',20,true);
   if cancel_category not in('ERROR_CARGA','PACIENTE','PROFESIONAL','OTRO') then raise sqlstate '22023' using message='Elegí el motivo de la cancelación.';end if;
  end if;
  ver=(p_data->>'version')::bigint;
  select * into old from marathon.turnos t where t.id=id for update;
  if not found then raise sqlstate 'PT404' using message='El turno ya no existe.';end if;
  if old.version<>ver then raise sqlstate 'PT409' using message='El turno cambió. Actualizá la agenda antes de modificarlo.';end if;
  select coalesce(sum(case when m.tipo='REINTEGRO' then -m.monto else m.monto end),0) into paid from marathon.movimientos m where m.turno_id=id;
  if state<>'PRESENTE' and paid>0 and not exists(select 1 from marathon.saldo_config where activo) then raise sqlstate '22023' using message='El turno tiene cobros. Registrá el reintegro antes de cambiar su estado.';end if;
     if old.estado='CANCELADO' and state<>'CANCELADO' and exists(select 1 from marathon.turnos r where r.recovered_from=old.id) then raise sqlstate 'PT409' using message='Esta cancelación ya fue recuperada. Consultá la nueva sesión.';end if;
if old.estado='CANCELADO' and state<>'CANCELADO' then
   if old.excepcional then
    select to_char(old.hora,'HH24:MI')hora,(q->>'remaining')::int remaining,(q->>'blocked')::boolean blocked into slot from(select marathon.excepcion_cupo(old.fecha,old.sede,old.profesional_id,old.terapia_id,old.hora,old.duracion_min,old.id)q)x;
   else
   select * into slot from marathon.agenda_slots(old.fecha,old.sede,old.profesional_id,old.terapia_id) s where s.hora=to_char(old.hora,'HH24:MI');
   -- No restaurar con una duración distinta de la que se comprobó.
   if marathon.session_minutes(old.fecha,old.sede,old.profesional_id,old.hora,old.duracion_min)<>(select marathon.session_minutes(old.fecha,old.sede,old.profesional_id,old.hora,t.duracion_min) from marathon.terapias t where t.id=old.terapia_id) then raise sqlstate 'PT409' using message='Cambió la duración de la terapia. Creá una nueva reserva para este turno cancelado.';end if;
   end if;
   if slot.hora is null or slot.remaining<1 or slot.blocked then raise sqlstate 'PT409' using message='El horario ya no tiene cupo. El turno sigue cancelado.';end if;
   if exists(select 1 from marathon.turnos t where t.dni=old.dni and t.fecha=old.fecha and t.estado<>'CANCELADO' and t.hora<old.hora+marathon.session_minutes(old.fecha,old.sede,old.profesional_id,old.hora,old.duracion_min)*interval '1 minute' and old.hora<t.hora+marathon.session_minutes(t.fecha,t.sede,t.profesional_id,t.hora,t.duracion_min)*interval '1 minute') then raise sqlstate 'PT409' using message='El paciente tiene otro turno que se superpone.';end if;
  end if;
  if state<>'PRESENTE' then perform marathon.advance_apply(p_request_id,id,true);end if;
 update marathon.turnos t set estado=state,categoria_cancelacion=case when state='CANCELADO' then cancel_category else null end,attendance_manual_date=t.fecha,attendance_auto=false,attendance_auto_at=null where t.id=id;
 if state='PRESENTE'then perform marathon.advance_apply(p_request_id,id);end if;
  select to_jsonb(t) into after_row from marathon.turnos t where t.id=id;
  insert into marathon.turn_audit(request_id,actor,turn_id,action,before_data,after_data) values(p_request_id,uid,id,p_action,to_jsonb(old),after_row);
  reply=jsonb_build_object('ids',jsonb_build_array(id),'message','Estado del turno actualizado.');
 end if;
 update marathon.solicitudes s set resultado=reply where s.id=p_request_id;return reply;
end $function$;

create or replace function marathon.turn_series_run(p_request_id text, p_data jsonb)
 returns jsonb
 language plpgsql
 set search_path to ''
 set lock_timeout to '5s'
as $function$
declare result jsonb;info jsonb;t marathon.turnos%rowtype;member marathon.turnos%rowtype;rule marathon.agenda_horarios%rowtype;
 p marathon.agenda_planes%rowtype;before_plan jsonb;changes jsonb;maps jsonb:='{}';ids text[];kind text;scope text;reason text;cancel_category text;delta int;new_date date;new_hour time;site text;prof text;new_rule uuid;
 d date;candidate record;occ record;slot jsonb;duration int;count_changed int:=0;after_row jsonb;config jsonb;schedules jsonb;fee numeric;cov jsonb;memo text;qrow marathon.agenda_cuotas%rowtype;quotes_changed int:=0;quotes_kept int:=0;new_therapy text;therapy_minutes int;
begin
 result=marathon.operation_begin(p_request_id,'turn-series',p_data);if result is not null then return result;end if;
 if p_data is null or jsonb_typeof(p_data)<>'object'or exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['id','action','scope','huella','date','time','site','prof','reason','categoria_cancelacion','schedules','amount','coverage','notes','therapy']))then raise exception 'Solicitud inválida.'using errcode='22023';end if;
 kind=p_data->>'action';scope=p_data->>'scope';
 if kind is null or kind not in('cancel','edit')or scope is null or scope not in('single','following')then raise exception 'Elegí la operación y su alcance.'using errcode='22023';end if;
 if kind='cancel' then
  cancel_category=marathon.master_text(p_data,'categoria_cancelacion',20,true);
  if cancel_category not in('ERROR_CARGA','PACIENTE','PROFESIONAL','OTRO') then raise exception 'Elegí el motivo de la cancelación.'using errcode='22023';end if;
 end if;
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
   perform public.marathon_agenda_command('series-'||md5(p_request_id||member.id),'status',jsonb_build_object('id',member.id,'version',member.version,'estado','CANCELADO','categoria_cancelacion',cancel_category));
   count_changed=count_changed+1;
  end loop;
  if scope='following'and t.plan_id is not null then
   update marathon.agenda_planes set baja=t.fecha where id=t.plan_id;
   update marathon.agenda_periodos set fin=greatest(inicio,t.fecha),anulado=anulado or inicio>=t.fecha where plan_id=t.plan_id and(fin is null or fin>t.fecha);
  end if;
 else
  new_date=marathon.agenda_date(p_data->>'date');
  if p_data?'therapy'then
   new_therapy=marathon.master_text(p_data,'therapy',100,true);
   select duracion_min into therapy_minutes from marathon.terapias where id=new_therapy and estado='ACTIVO';
   if therapy_minutes is null then raise exception 'Seleccioná una terapia activa.'using errcode='22023';end if;
  end if;
  if t.plan_id is not null then select *into strict p from marathon.agenda_planes where id=t.plan_id;end if;
  if p_data?'amount'then
   if coalesce(p_data->>'amount','')!~'^[0-9]{1,10}(\.[0-9]{1,2})?$'then raise exception 'Indicá un importe válido, con hasta dos decimales.'using errcode='22023';end if;
   fee=(p_data->>'amount')::numeric;
   if(p.facturacion='none'and fee<>0)or(p.facturacion='monthly'and fee<=0)then raise exception 'El importe debe respetar la modalidad de pago.'using errcode='22023';end if;
   if p.facturacion='monthly'and scope='single'and fee<>marathon.agenda_tarifa(p.id,t.fecha)then raise exception 'El importe mensual se modifica para la serie. Elegí este turno y los siguientes.'using errcode='22023';end if;
  end if;
  if p_data?'coverage'then cov=marathon.normalize_turn_coverage(t.dni,p_data->'coverage');end if;
  if p_data?'notes'then
   if jsonb_typeof(p_data->'notes')<>'string'or length(p_data->>'notes')>1000 then raise exception 'Las observaciones admiten hasta 1000 caracteres.'using errcode='22023';end if;
   memo=p_data->>'notes';
  end if;
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
    duration=marathon.session_minutes(d+delta,site,prof,new_hour,case when new_therapy is not null and new_therapy<>coalesce(rule.terapia_override,p.terapia_id)then therapy_minutes else rule.duracion_min end);
    update marathon.agenda_horarios set hasta=greatest(desde,t.fecha)where id=rule.id;
    insert into marathon.agenda_horarios(plan_id,sede,profesional_id,dia,hora,duracion_min,desde,hasta,importe_override,coverage_override,observaciones_override,terapia_override)
    values(t.plan_id,site,prof,extract(dow from d+delta)::int,new_hour,duration,d+delta,case when rule.hasta is null then null else rule.hasta+delta end,case when p.facturacion in('class','bonus_class')then coalesce(fee,rule.importe_override)else rule.importe_override end,coalesce(cov,rule.coverage_override),coalesce(memo,rule.observaciones_override),coalesce(new_therapy,rule.terapia_override))returning id into new_rule;
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
   duration=marathon.session_minutes(member.fecha+delta,site,prof,new_hour,case when new_therapy is not null and new_therapy<>member.terapia_id then therapy_minutes else member.duracion_min end);
   if scope='single'then
    slot=marathon.agenda_cupo(member.fecha+delta,site,prof,coalesce(new_therapy,member.terapia_id),new_hour,null,'H-'||coalesce(member.horario_id::text,'')||'-'||coalesce(member.fecha_habitual::text,''));
   else slot=marathon.agenda_cupo(member.fecha+delta,site,prof,coalesce(new_therapy,member.terapia_id),new_hour,null,'H-'||coalesce(maps->>member.horario_id::text,'')||'-'||coalesce((member.fecha_habitual+delta)::text,''));end if;
   if coalesce((slot->>'blocked')::boolean,true)or(coalesce((slot->>'capacity')::int,1)<=1 and coalesce((slot->>'remaining')::int,0)<1) then raise exception 'Sin cupo el % a las %. No se modificó ningún turno.',member.fecha+delta,new_hour using errcode='PT409';end if;
   update marathon.turnos set fecha=member.fecha+delta,hora=new_hour,sede=site,profesional_id=prof,terapia_id=coalesce(new_therapy,member.terapia_id),terapia_override=coalesce(new_therapy,member.terapia_override),duracion_min=duration,estado='PENDIENTE',importe=case when p.facturacion in('monthly','none')then member.importe else coalesce(fee,member.importe)end,coverage=coalesce(cov,member.coverage),booking_notes=coalesce(memo,member.booking_notes),
    horario_id=case when maps?member.horario_id::text then(maps->>member.horario_id::text)::uuid else member.horario_id end,
    fecha_habitual=case when maps?member.horario_id::text then member.fecha_habitual+delta else member.fecha_habitual end,
    fixed_until=case when scope='following'and member.fixed_until is not null then member.fixed_until+delta else member.fixed_until end where id=member.id;
   insert into marathon.turn_audit(request_id,actor,turn_id,action,before_data,after_data)select p_request_id,auth.uid(),member.id,'series_edit',after_row,to_jsonb(x)from marathon.turnos x where x.id=member.id;
   count_changed=count_changed+1;
  end loop;
  if scope='following'and t.plan_id is not null then
   if p.facturacion='monthly'and fee is not null then
    update marathon.agenda_tarifas set vigente=false where plan_id=t.plan_id and vigente and desde>=t.fecha;
    insert into marathon.agenda_tarifas(plan_id,desde,importe,request_id,created_by)values(t.plan_id,t.fecha,fee,p_request_id,auth.uid());
    for qrow in select *from marathon.agenda_cuotas q where q.plan_id=t.plan_id and q.hasta>t.fecha order by q.fecha for update loop
     if marathon.agenda_cuota_pagado(qrow.id)>0 or exists(select 1 from marathon.agenda_ajustes a where a.cuota_id=qrow.id)then
      quotes_kept=quotes_kept+1;
     elsif qrow.importe<>fee then
      update marathon.agenda_cuotas set importe=fee where id=qrow.id;
      insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data)
      select p_request_id,auth.uid(),'agenda-cuota',qrow.id::text,'importe_desde_turno',to_jsonb(qrow),to_jsonb(x)from marathon.agenda_cuotas x where x.id=qrow.id;
      quotes_changed=quotes_changed+1;
     end if;
    end loop;
   end if;
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
    if coalesce((slot->>'blocked')::boolean,true)or(coalesce((slot->>'capacity')::int,1)<=1 and coalesce((slot->>'remaining')::int,0)<1) or exists(select 1 from marathon.agenda_pool(occ.fecha)a where a.dni=t.dni and a.id<>occ.id and a.hora<occ.hora+make_interval(mins=>occ.duracion_min)and occ.hora<a.hora+make_interval(mins=>a.duracion_min))then raise exception 'La repetición futura entra en conflicto el %. No se guardó el cambio.',occ.fecha using errcode='PT409';end if;
   end loop;
  end if;
 end if;
 if t.plan_id is not null and scope='following'then insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data)
 select p_request_id,auth.uid(),'agenda-plan',t.plan_id::text,'turn_series_'||kind,before_plan,to_jsonb(x)||jsonb_build_object('motivo',reason,'categoria_cancelacion',cancel_category,'desde',t.fecha,'horarios',maps)from marathon.agenda_planes x where x.id=t.plan_id;
 else insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,after_data)values(p_request_id,auth.uid(),'turn',t.id,'turn_series_'||kind,jsonb_build_object('desde',t.fecha,'alcance',scope,'motivo',reason,'categoria_cancelacion',cancel_category));end if;
 result=jsonb_build_object('ids',ids,'count',count_changed,'recurring',t.plan_id is not null and scope='following','cuotas_actualizadas',quotes_changed,'cuotas_conservadas',quotes_kept,'message',case when kind='cancel'then count_changed||' turno(s) cancelados.'else count_changed||' turno(s) editados.'end||case when t.plan_id is not null and scope='following'then case when kind='cancel'then' La asignación quedó dada de baja desde la fecha elegida.'else' Se actualizó también la repetición futura.'end else''end||case when quotes_changed>0 then' Se actualizó la cuota sin pagos.'else''end||case when quotes_kept>0 then' Las cuotas con pagos o ajustes conservaron su importe; el nuevo valor se aplica a las próximas.'else''end);
 update marathon.solicitudes set resultado=result where id=p_request_id;return result;
end$function$;

create or replace function public.marathon_patient_dashboard(p_filters jsonb)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
 cut timestamp:=statement_timestamp() at time zone 'America/Argentina/Buenos_Aires';
 d date; e date; n_days int; prev date; finish timestamp; prev_finish timestamp;
 v_site text; v_therapy text; v_professional text; v_specialty text;
 summary jsonb; previous jsonb; groups jsonb; trend jsonb; coverage_json jsonb; coverage_entities jsonb;
 firsts jsonb; waiting jsonb; capacity jsonb; quality jsonb; flow jsonb; catalog jsonb;
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_filters is null or jsonb_typeof(p_filters)<>'object' or length(p_filters::text)>3000
 or exists(select 1 from jsonb_object_keys(p_filters)k where k<>all(array['from','to','sede','therapy','professional','specialty'])) then
 raise sqlstate '22023' using message='Filtros de pacientes invalidos.';end if;
 if coalesce(p_filters->>'from','')!~'^\d{4}-\d{2}-\d{2}$'or coalesce(p_filters->>'to','')!~'^\d{4}-\d{2}-\d{2}$'then
 raise sqlstate '22023'using message='Elegi fechas validas para el informe.';end if;
 begin d:=(p_filters->>'from')::date;e:=(p_filters->>'to')::date+1;
 exception when invalid_datetime_format or datetime_field_overflow then raise sqlstate '22023'using message='Elegi fechas validas para el informe.';end;
 n_days:=e-d;prev:=d-n_days;
 if n_days<1 or n_days>93 or e-1>cut::date or e-1>date '2100-12-31'or prev<date '2000-01-01' then
 raise sqlstate '22023' using message='Elegi hasta 93 dias, sin fechas futuras y con periodo anterior desde 2000.';end if;
 v_site:=coalesce(p_filters->>'sede','');v_therapy:=coalesce(p_filters->>'therapy','');
 v_professional:=coalesce(p_filters->>'professional','');v_specialty:=coalesce(p_filters->>'specialty','');
 finish:=least(e::timestamp,cut);prev_finish:=finish-make_interval(days=>n_days);
 -- Todas las filas de pacientes quedan dentro del servidor. Solo se devuelven agregados.
 with scoped as materialized (
 select t.*,coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad') specialty
 from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id
 where t.fecha>=prev and t.fecha<e and(v_site=''or t.sede=v_site)
 and(v_therapy=''or t.terapia_id=v_therapy)and(v_professional=''or t.profesional_id=v_professional)
 and(v_specialty=''or coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')=v_specialty)
 ), marked as (
 select *,fecha+hora+make_interval(mins=>duracion_min) ended,
 case when fecha>=d then 'current' else 'previous' end period from scoped
 ), stats as (
 select period,count(*) total,count(*)filter(where estado='PRESENTE') present,
 count(distinct dni)filter(where estado='PRESENTE') patients,
 count(*)filter(where estado='AUSENTE') absent,count(*)filter(where estado='AUSENTE'and attendance_auto) auto_absent,
 count(*)filter(where estado='PENDIENTE') pending,count(*)filter(where estado='CANCELADO'and coalesce(categoria_cancelacion,'')<>'ERROR_CARGA') cancelled,count(*)filter(where estado='CANCELADO'and categoria_cancelacion='ERROR_CARGA') load_error
 from marked where (period='current'and ended<=finish)or(period='previous'and ended<=prev_finish)group by period
 ), comparisons as (
 select k.period,coalesce(s.total,0) total,coalesce(s.present,0) present,coalesce(s.patients,0) patients,
 coalesce(s.absent,0) absent,coalesce(s.pending,0) pending,coalesce(s.cancelled,0) cancelled,coalesce(s.load_error,0) load_error,coalesce(s.auto_absent,0) auto_absent,
 round(100.0*s.present/nullif(s.present+s.absent,0),2) attendance,
 round(100.0*(s.present+s.absent)/nullif(s.present+s.absent+s.pending,0),2) completeness,
 round(s.present::numeric/nullif(s.patients,0),2) frequency
 from(values('current'),('previous'))k(period)left join stats s using(period)
 )select(select to_jsonb(b)-'period'from comparisons b where period='current'),
 (select to_jsonb(b)-'period'from comparisons b where period='previous')into summary,previous;
 with finished as materialized (
 select t.*,th.nombre therapy,coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad') specialty,
 concat_ws(' ',pr.nombre,nullif(pr.segundo_nombre,''),pr.apellido)professional
 from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id join marathon.profesionales pr on pr.id=t.profesional_id
 where t.fecha>=d and t.fecha<e and t.fecha+t.hora+make_interval(mins=>t.duracion_min)<=finish
 and(v_site=''or t.sede=v_site)and(v_therapy=''or t.terapia_id=v_therapy)and(v_professional=''or t.profesional_id=v_professional)
 and(v_specialty=''or coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')=v_specialty)
 ), grouped as (
 select g.kind,g.id,g.label,count(*)total,count(*)filter(where estado='PRESENTE')present,
 count(distinct dni)filter(where estado='PRESENTE')patients,count(*)filter(where estado='AUSENTE')absent,
 count(*)filter(where estado='PENDIENTE')pending,count(*)filter(where estado='CANCELADO'and coalesce(categoria_cancelacion,'')<>'ERROR_CARGA')cancelled,count(*)filter(where estado='CANCELADO'and categoria_cancelacion='ERROR_CARGA')load_error,
 round(100.0*count(*)filter(where estado='PRESENTE')/nullif(count(*)filter(where estado in('PRESENTE','AUSENTE')),0),2)attendance
 from finished f cross join lateral(values('specialty',f.specialty,f.specialty),('therapy',f.terapia_id,f.therapy),
 ('site',f.sede,f.sede),('professional',f.profesional_id,f.professional))g(kind,id,label)group by g.kind,g.id,g.label
 ), series as (
 select fecha date,count(*)filter(where estado='PRESENTE')present,count(*)filter(where estado='AUSENTE')absent,
 count(distinct dni)filter(where estado='PRESENTE')patients from finished group by fecha
 ), types as (
 select case when coverage->>'type'in('PARTICULAR','OBRA_SOCIAL','ART','CLUB')then coverage->>'type'else 'SIN_REGISTRO'end type,
 count(*)attentions,count(distinct dni)patients from finished where estado='PRESENTE'group by 1
 ), entities as (
 select nullif(btrim(coverage->>'obra_social_id'),'') os_id,count(*)attentions,count(distinct dni)patients
 from finished where estado='PRESENTE'and coverage->>'type'='OBRA_SOCIAL'group by 1
 ), entity_total as(select sum(attentions) t from entities)
 select(select coalesce(jsonb_agg(to_jsonb(g)order by kind,patients desc,label),'[]'::jsonb)from grouped g),
 (select coalesce(jsonb_agg(jsonb_build_object('date',g::date,'present',coalesce(s.present,0),'absent',coalesce(s.absent,0),'patients',coalesce(s.patients,0))order by g),'[]'::jsonb)
 from generate_series(d::timestamp,(e-1)::timestamp,interval '1 day')g left join series s on s.date=g::date),
 (select jsonb_agg(jsonb_build_object('type',k.type,'label',k.label,'attentions',coalesce(t.attentions,0),'patients',coalesce(t.patients,0),
 'percent',round(100.0*coalesce(t.attentions,0)/nullif((summary->>'present')::numeric,0),2))order by k.ord)
 from(values('PARTICULAR','Particular',1),('OBRA_SOCIAL','Obra social',2),('ART','ART',3),('CLUB','Club',4),('SIN_REGISTRO','Sin registrar',5))k(type,label,ord)left join types t using(type)),
 (select coalesce(jsonb_agg(jsonb_build_object('id',en.os_id,
 'label',case when en.os_id is null then 'Sin entidad identificada'when o.id is null then 'Entidad fuera de catalogo'else o.nombre end,
 'state',o.estado,'identified',(en.os_id is not null and o.id is not null),
 'attentions',en.attentions,'patients',en.patients,
 'percent',round(100.0*en.attentions/nullif(et.t,0),2))order by(en.os_id is null),en.attentions desc),'[]'::jsonb)
 from entities en left join marathon.obras_sociales o on o.id=en.os_id cross join entity_total et)
 into groups,trend,coverage_json,coverage_entities;
 -- Primera observada: minima atencion real registrada; no usa alta de ficha ni bonos.
 with attended as materialized (
 select t.dni,t.sede,t.terapia_id,coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')specialty,
 t.fecha+t.hora started,t.fecha+t.hora+make_interval(mins=>t.duracion_min)ended,t.profesional_id
 from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id
 where t.estado='PRESENTE'and t.fecha+t.hora+make_interval(mins=>t.duracion_min)<=cut
 ), first_global as(select dni,min(started)first_at from attended group by dni),
 first_site as(select dni,sede,min(started)first_at from attended group by dni,sede),
 first_specialty as(select dni,specialty,min(started)first_at from attended group by dni,specialty),
 current_people as(select distinct dni from attended where started>=d and started<finish and ended<=finish and(v_site=''or sede=v_site)
 and(v_therapy=''or terapia_id=v_therapy)and(v_professional=''or profesional_id=v_professional)and(v_specialty=''or attended.specialty=v_specialty))
 select jsonb_build_object('observed',count(*)filter(where g.first_at>=d and g.first_at<finish),'returning',count(*)filter(where g.first_at<d),
 'first_site',case when v_site=''then null else(select count(*)from current_people c join first_site fs on fs.dni=c.dni and fs.sede=v_site where fs.first_at>=d and fs.first_at<finish)end,
 'first_specialty',case when v_specialty=''then null else(select count(*)from current_people c join first_specialty fs on fs.dni=c.dni and fs.specialty=v_specialty where fs.first_at>=d and fs.first_at<finish)end,
 'confirmed',null,'history_complete',false)into firsts from current_people c join first_global g using(dni);
 with filtered as materialized (
 select w.*,th.nombre therapy,coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')specialty,
 cut::date-w.fecha age from marathon.espera w join marathon.terapias th on th.id=w.terapia_id
 where(v_site=''or w.sede=v_site)and(v_therapy=''or w.terapia_id=v_therapy)and(v_professional=''or w.profesional_id=v_professional)
 and(v_specialty=''or coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')=v_specialty)
 ), active as(select * from filtered where estado in('PENDIENTE','CONTACTADO')),
 wg as(select specialty label,count(*)requests,count(distinct dni)patients,min(fecha)oldest,
 percentile_cont(0.5)within group(order by age)filter(where age>=0)median_days from active group by specialty),
 assigned as(
 select w.id,t.fecha-w.fecha days from filtered w join marathon.turnos t on t.id=w.reserved_turn_id
 where w.fecha>=d and w.fecha<e and w.fecha<=cut::date and w.estado='RESUELTO'and t.estado<>'CANCELADO'and t.fecha>=w.fecha
 )select jsonb_build_object('requests',(select count(*)from active),'patients',(select count(distinct dni)from active),
 'median_days',(select percentile_cont(0.5)within group(order by age)filter(where age>=0)from active),
 'invalid_dates',(select count(*)from active where age<0),'rows',(select coalesce(jsonb_agg(to_jsonb(wg)order by requests desc,label),'[]'::jsonb)from wg),
 'linked_count',(select count(*)from assigned),'linked_median_days',(select percentile_cont(0.5)within group(order by days)from assigned),
 'complete_demand',false,'first_offer_days',null)into waiting;
 -- Tiempo profesional, no cupos fisicos. Dia de horarios: 0 domingo ... 6 sabado.
 with dates as(select g::date date from generate_series(d::timestamp,(e-1)::timestamp,interval '1 day')g),
 offered as(
 select h.profesional_id,h.sede,dt.date,range_agg(tsrange(dt.date+h.inicio,least(dt.date+h.fin,finish),'[)'))ranges
 from dates dt join marathon.horarios h on h.dia=extract(dow from dt.date)
 join marathon.profesionales pr on pr.id=h.profesional_id and pr.estado='ACTIVO'
 join marathon.sedes sd on sd.nombre=h.sede and sd.estado='ACTIVO'
 where dt.date+h.inicio<finish and h.fin>h.inicio and(v_site=''or h.sede=v_site)and(v_professional=''or h.profesional_id=v_professional)
 and(v_therapy=''or exists(select 1 from marathon.profesional_terapias pt where pt.profesional_id=h.profesional_id and pt.terapia_id=v_therapy))
 and(v_specialty=''or exists(select 1 from marathon.profesional_terapias pt join marathon.terapias th on th.id=pt.terapia_id where pt.profesional_id=h.profesional_id and coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')=v_specialty))
 group by h.profesional_id,h.sede,dt.date
 ), booked as(
 select t.profesional_id,t.sede,t.fecha,
 range_agg(tsrange(t.fecha+t.hora,least(t.fecha+t.hora+make_interval(mins=>t.duracion_min),finish),'[)'))reserved,
 range_agg(tsrange(t.fecha+t.hora,t.fecha+t.hora+make_interval(mins=>t.duracion_min),'[)'))filter(where t.estado='PRESENTE'and t.fecha+t.hora+make_interval(mins=>t.duracion_min)<=finish)effective
 from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id
 where t.fecha>=d and t.fecha<e and t.fecha+t.hora<finish and t.estado in('PENDIENTE','PRESENTE')
 and(v_site=''or t.sede=v_site)and(v_therapy=''or t.terapia_id=v_therapy)and(v_professional=''or t.profesional_id=v_professional)
 and(v_specialty=''or coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')=v_specialty)
 group by t.profesional_id,t.sede,t.fecha
 ), inter as(
 select o.*,o.ranges*coalesce(b.reserved,'{}'::tsmultirange)reserved,o.ranges*coalesce(b.effective,'{}'::tsmultirange)effective
 from offered o left join booked b on b.profesional_id=o.profesional_id and b.sede=o.sede and b.fecha=o.date
 ), op as(select profesional_id,range_agg(r)ranges from offered cross join lateral unnest(ranges)r group by profesional_id),
 rp as(select profesional_id,range_agg(r)ranges from inter cross join lateral unnest(reserved)r group by profesional_id),
 ep as(select profesional_id,range_agg(r)ranges from inter cross join lateral unnest(effective)r group by profesional_id),
 mins as(
 select op.profesional_id,concat_ws(' ',pr.nombre,nullif(pr.segundo_nombre,''),pr.apellido)label,
 (select coalesce(sum(extract(epoch from upper(r)-lower(r))/60),0)from unnest(op.ranges)r)available,
 (select coalesce(sum(extract(epoch from upper(r)-lower(r))/60),0)from unnest(rp.ranges)r)reserved,
 (select coalesce(sum(extract(epoch from upper(r)-lower(r))/60),0)from unnest(ep.ranges)r)effective
 from op left join rp using(profesional_id)left join ep using(profesional_id)join marathon.profesionales pr on pr.id=op.profesional_id
 ), rows as(select *,round(100*reserved/nullif(available,0),2)reserved_pct,round(100*effective/nullif(available,0),2)effective_pct from mins)
 select jsonb_build_object('available',coalesce(sum(available),0),'reserved',coalesce(sum(reserved),0),'effective',coalesce(sum(effective),0),
 'reserved_pct',round(100*sum(reserved)/nullif(sum(available),0),2),'effective_pct',round(100*sum(effective)/nullif(sum(available),0),2),
 'rows',coalesce(jsonb_agg(to_jsonb(rows)order by reserved desc,label),'[]'::jsonb),'physical_capacity',null,'current_schedules',true)
 into capacity from rows;
 with current_turns as(
 select t.*from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id where t.fecha>=d and t.fecha<e
 and(v_site=''or t.sede=v_site)and(v_therapy=''or t.terapia_id=v_therapy)and(v_professional=''or t.profesional_id=v_professional)
 and(v_specialty=''or coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')=v_specialty)
 ), heat as(
 select extract(isodow from fecha)::int as weekday,extract(hour from hora)::int as hour_bucket,count(*) as count
 from current_turns where estado in('PENDIENTE','PRESENTE')and fecha+hora<finish group by 1,2
 )select jsonb_build_object('future',(select count(*)from current_turns where fecha+hora>=finish),
 'missing_coverage',(select count(*)from current_turns where estado='PRESENTE'and fecha+hora+make_interval(mins=>duracion_min)<=finish and coalesce(coverage->>'type','')not in('PARTICULAR','OBRA_SOCIAL','ART','CLUB')),
 'scope_turns',(select count(*)from current_turns),'clinical_diagnoses',false,'experience',false),
 (select coalesce(jsonb_agg((to_jsonb(h)-'hour_bucket')||jsonb_build_object('hour',h.hour_bucket)order by h.hour_bucket,h.weekday),'[]'::jsonb)from heat h)into quality,flow;
 select jsonb_build_object(
 'specialties',(select coalesce(jsonb_agg(x.specialty order by x.specialty),'[]'::jsonb)from(select distinct coalesce(nullif(btrim(especialidad),''),'Sin especialidad')specialty from marathon.terapias)x),
 'therapies',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',nombre,'specialty',coalesce(nullif(btrim(especialidad),''),'Sin especialidad'))order by nombre),'[]'::jsonb)from marathon.terapias),
 'professionals',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',concat_ws(' ',nombre,nullif(segundo_nombre,''),apellido)||case when estado='INACTIVO'then ' (inactivo)'else ''end)order by apellido,nombre),'[]'::jsonb)from marathon.profesionales))into catalog;
 return jsonb_build_object('generated_at',statement_timestamp(),'today',cut::date,'filters',p_filters,
 'period',jsonb_build_object('from',d,'to',e-1,'days',n_days,'previous_from',prev,'previous_to',d-1,'cut',finish,'previous_cut',prev_finish,'partial_day',e::timestamp>cut),
 'summary',summary,'previous',previous,'groups',groups,'trend',trend,'coverage',coverage_json,'coverage_entities',coverage_entities,'firsts',firsts,'waiting',waiting,'capacity',capacity,'quality',quality,'flow',flow,'catalog',catalog);
end;
$function$;
