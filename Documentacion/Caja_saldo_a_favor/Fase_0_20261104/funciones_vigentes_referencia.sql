-- Referencia leída de la base vigente: marathon.touch_row()
CREATE OR REPLACE FUNCTION marathon.touch_row()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$ begin
 new.updated_at=now(); new.updated_by=auth.uid(); new.version=old.version+1; return new;
end $function$
;

-- Referencia leída de la base vigente: marathon_agenda_command(text,text,jsonb)
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

-- Referencia leída de la base vigente: marathon.operation_begin(text,text,jsonb)
CREATE OR REPLACE FUNCTION marathon.operation_begin(p_id text, p_kind text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare uid uuid:=auth.uid();h text;r marathon.solicitudes%rowtype;begin
 perform 1 from marathon.app_users where user_id=uid and active for share;
 if not found then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_id is null or p_id !~ '^[a-zA-Z0-9_-]{12,100}$' or p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>60000 then raise sqlstate '22023' using message='Solicitud inválida.';end if;
 if current_setting('transaction_isolation')<>'read committed' then raise sqlstate '22023' using message='La operación requiere transacciones READ COMMITTED.';end if;
 h=encode(sha256(convert_to(p_data::text,'UTF8')),'hex');
 insert into marathon.solicitudes(id,usuario_id,tipo,payload_hash) values(p_id,uid,p_kind,h) on conflict on constraint solicitudes_pkey do nothing;
 select * into r from marathon.solicitudes s where s.id=p_id for update;
 if r.id is null or r.usuario_id<>uid or r.tipo<>p_kind or r.payload_hash<>h then raise sqlstate '22023' using message='Identificador de solicitud utilizado con otros datos.';end if;
 if r.resultado is not null then return r.resultado;end if;
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));return null;
end $function$
;

-- Referencia leída de la base vigente: marathon.turn_paid(text)
CREATE OR REPLACE FUNCTION marathon.turn_paid(p_id text)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select marathon.turn_cash_paid(p_id)+marathon.advance_paid(p_id)
$function$
;

-- Referencia leída de la base vigente: marathon_patient_account(text,jsonb,integer)
CREATE OR REPLACE FUNCTION public.marathon_patient_account(p_dni text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare rows jsonb;nxt jsonb;total numeric;name text;begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_limit is null or p_limit not between 1 and 100 or(p_after is not null and(jsonb_typeof(p_after)<>'object' or not(p_after ?& array['fecha','id']))) then raise sqlstate '22023' using message='Consulta inválida.';end if;
 select concat_ws(' ',apellido,nombre,nullif(segundo_nombre,'')) into name from marathon.pacientes where dni=p_dni;if name is null then raise sqlstate 'PT404' using message='Paciente no encontrado.';end if;
 select coalesce(sum(greatest(0,t.importe-marathon.turn_paid(t.id))),0) into total from marathon.turnos t where t.dni=p_dni and t.estado='PRESENTE';
 select coalesce(jsonb_agg(to_jsonb(x) order by x.fecha,x.id),'[]'::jsonb) into rows from(
 select t.id,t.fecha,to_char(t.hora,'HH24:MI') hora,t.sede,t.estado,t.version,t.importe,th.nombre terapia,marathon.turn_paid(t.id) paid,greatest(0,t.importe-marathon.turn_paid(t.id)) debt from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id
 where t.dni=p_dni and t.estado='PRESENTE' and t.importe>marathon.turn_paid(t.id) and(p_after is null or(t.fecha,t.id)>(marathon.agenda_date(p_after->>'fecha'),p_after->>'id')) order by t.fecha,t.id limit p_limit+1)x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('fecha',rows->(p_limit-1)->>'fecha','id',rows->(p_limit-1)->>'id');end if;
 return jsonb_build_object('rows',rows,'next',nxt,'debt',total,'name',name);
end $function$
;

-- Referencia leída de la base vigente: marathon_cash_command(text,text,jsonb)
CREATE OR REPLACE FUNCTION public.marathon_cash_command(p_request_id text, p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '3s'
AS $function$
#variable_conflict use_variable
declare reply jsonb;t marathon.turnos%rowtype;old marathon.movimientos%rowtype;m numeric;paid numeric;medium text;site text;dni text;concept text;obs text;reason text;kind text;origin text;id text;tid text;comp text;d date;after_data jsonb;category text;associated_prof text;associated_sec text;
begin
 reply=marathon.operation_begin(p_request_id,'cash:'||coalesce(p_action,''),p_data);if reply is not null then return reply;end if;
 if p_action is null or p_action not in ('pay','refund','cash','reverse') or exists(select 1 from jsonb_object_keys(p_data)k where k<>all(case p_action when 'cash' then array['tipo','sede','dni','monto','medio','concepto','observaciones','fecha','categoria','profesional_asociado_id','secretaria_asociada'] when 'reverse' then array['id','version','motivo','fecha'] else array['id','version','monto','medio','observaciones','fecha'] end)) then raise sqlstate '22023' using message='Operación de caja inválida.';end if;
 d=case when coalesce(p_data->>'fecha','')='' then(now() at time zone 'America/Argentina/Buenos_Aires')::date else marathon.agenda_date(marathon.master_text(p_data,'fecha',10,true)) end;
 if p_action='reverse' then
  if not marathon.is_admin() then raise sqlstate '42501' using message='Solo ADMIN puede aprobar un contrasiento.';end if;
  reason=marathon.master_text(p_data,'motivo',1000,true);if length(reason)<3 then raise sqlstate '22023' using message='Indicá el motivo (3 a 1000 caracteres).';end if;
  select * into old from marathon.movimientos x where x.id=marathon.master_text(p_data,'id',100,true) for update;
  if old.id is null or old.compensacion_de is not null or not((old.tipo='PAGO' and old.origen='CLINICA' and old.turno_id is not null)or(old.origen='CAJA' and old.tipo in('INGRESO','EGRESO')))then raise sqlstate '22023' using message='Solo se corrigen cobros clínicos o movimientos manuales originales mediante contrasiento.';end if;
  if old.version<>marathon.operation_version(p_data) or exists(select 1 from marathon.movimientos where compensacion_de=old.id) then raise sqlstate 'PT409' using message='El cobro cambió o ya tiene contrasiento.';end if;
  if old.origen='CAJA'then
   m=old.monto;medium=old.medio;site=old.sede;dni=old.dni;comp=old.id;kind=case when old.tipo='EGRESO'then'INGRESO'else'EGRESO'end;origin='CAJA';concept='Contrasiento de '||old.id;obs=reason;category=old.categoria;associated_prof=old.profesional_asociado_id;associated_sec=old.secretaria_asociada;
  else
  select * into t from marathon.turnos where turnos.id=old.turno_id for update;paid=marathon.turn_cash_paid(t.id);
  if paid<old.monto then raise sqlstate '22023' using message='Hay reintegros previos. El cobro completo no puede anularse; registrá el reintegro del saldo correspondiente.';end if;
  m=old.monto;medium=old.medio;site=old.sede;dni=old.dni;tid=old.turno_id;comp=old.id;kind='REINTEGRO';origin='CLINICA';concept='Contrasiento de '||old.id;obs=reason;
 end if;
 elsif p_action in ('pay','refund') then
  select * into t from marathon.turnos where turnos.id=marathon.master_text(p_data,'id',100,true) for update;
  if t.id is null then raise sqlstate 'PT404' using message='Turno no encontrado.';end if;
  if t.version<>marathon.operation_version(p_data) then raise sqlstate 'PT409' using message='El turno cambió. Volvé a abrir su cuenta.';end if;
  m=marathon.operation_amount(p_data);medium=marathon.master_text(p_data,'medio',13,true);obs=marathon.master_text(p_data,'observaciones',1000);paid=marathon.turn_paid(t.id);
  if p_action='pay' and(t.estado<>'PRESENTE' or m>t.importe-paid) then raise sqlstate '22023' using message='Solo se cobran turnos presentes y hasta su saldo pendiente.';end if;
  if p_action='refund' and m>marathon.turn_cash_paid(t.id) then raise sqlstate '22023' using message='El reintegro supera lo cobrado.';end if;
  site=t.sede;dni=t.dni;tid=t.id;kind=case when p_action='pay' then 'PAGO' else 'REINTEGRO' end;origin='CLINICA';concept=case when p_action='pay' then 'Cobro de turno' else 'Reintegro de turno' end;
 else
  m=marathon.operation_amount(p_data);medium=marathon.master_text(p_data,'medio',13,true);obs=marathon.master_text(p_data,'observaciones',1000);site=marathon.master_text(p_data,'sede',40,true);dni=nullif(marathon.master_text(p_data,'dni',12),'');concept=marathon.master_text(p_data,'concepto',200,true);kind=marathon.master_text(p_data,'tipo',7,true);origin='CAJA';
  if kind not in ('INGRESO','EGRESO') or not exists(select 1 from marathon.sedes where nombre=site and estado='ACTIVO') or(dni is not null and not exists(select 1 from marathon.pacientes p where p.dni=dni)) then raise sqlstate '22023' using message='Tipo, sede o paciente inválidos.';end if;
 end if;
 if p_action='cash'then
 category=nullif(marathon.master_text(p_data,'categoria',100),'');associated_prof=nullif(marathon.master_text(p_data,'profesional_asociado_id',100),'');associated_sec=nullif(marathon.master_text(p_data,'secretaria_asociada',100),'');
 if(associated_prof is not null and associated_sec is not null)or(associated_prof is not null and not exists(select 1 from marathon.profesionales pr where pr.id=associated_prof and pr.estado='ACTIVO'))or(associated_sec is not null and not exists(select 1 from marathon.secretarias where nombre=associated_sec and estado='ACTIVO'))then raise sqlstate '22023'using message='Elegí un profesional o una secretaria activos para asociar.';end if;
 end if;
 if medium not in ('EFECTIVO','TRANSFERENCIA') then raise sqlstate '22023' using message='Elegí el medio de pago.';end if;
 id='MOV-'||gen_random_uuid()::text;
 insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,turno_id,concepto,observaciones_legacy,compensacion_de,motivo,created_by,updated_by,categoria,profesional_asociado_id,secretaria_asociada)
 values(id,d,(now() at time zone 'America/Argentina/Buenos_Aires')::time,origin,kind,dni,m,medium,site,tid,concept,obs,comp,reason,auth.uid(),auth.uid(),category,associated_prof,associated_sec);
 select to_jsonb(x) into after_data from marathon.movimientos x where x.id=id;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data) values(p_request_id,auth.uid(),'movement',id,p_action,case when old.id is not null then to_jsonb(old) end,after_data);
 reply=jsonb_build_object('id',id,'message',case p_action when 'pay' then 'Cobro registrado.' when 'refund' then 'Reintegro registrado.' when 'reverse' then 'Contrasiento registrado. El cobro original se conserva.' else 'Movimiento de caja registrado.' end);
 update marathon.solicitudes s set resultado=reply where s.id=p_request_id;return reply;
end $function$
;

-- Referencia leída de la base vigente: marathon_cash_search(jsonb,jsonb,integer)
CREATE OR REPLACE FUNCTION public.marathon_cash_search(p_filters jsonb, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d date;e date;rows jsonb;nxt jsonb;totals jsonb;begin
 if not marathon.active_user()then raise sqlstate '42501'using message='Acceso no autorizado.';end if;
 perform marathon.daily_validate(p_filters,array['from','to','sede','medium','category','prof','actor'],p_limit,p_after);d=marathon.agenda_date(p_filters->>'from');e=marathon.agenda_date(p_filters->>'to');
 if e<d or e-d>3660 or coalesce(p_filters->>'medium','')not in('','EFECTIVO','TRANSFERENCIA')or(p_after is not null and not(p_after?&array['fecha','hora','id']))then raise sqlstate '22023'using message='Período o filtros de caja inválidos.';end if;
 with filtered as(select * from marathon.daily_cash where fecha between d and e and origen in('CLINICA','CAJA','ORTOPEDIA','BONO','ANTICIPO')and(coalesce(p_filters->>'sede','')=''or sede=p_filters->>'sede')and(coalesce(p_filters->>'medium','')=''or medio=p_filters->>'medium')and(coalesce(p_filters->>'category','')=''or category_key=p_filters->>'category')and(coalesce(p_filters->>'prof','')=''or professional_key=p_filters->>'prof')and(coalesce(p_filters->>'actor','')=''or actor_key=p_filters->>'actor')),
 page as(select * from filtered where p_after is null or(fecha,hora,id)>(marathon.agenda_date(p_after->>'fecha'),(p_after->>'hora')::time,p_after->>'id')order by fecha,hora,id limit p_limit+1),
 sums as(select medio,coalesce(sum(monto)filter(where tipo in('PAGO','INGRESO')),0)income,coalesce(sum(monto)filter(where tipo in('EGRESO','REINTEGRO')),0)expense from filtered group by medio)
 select coalesce((select jsonb_agg(to_jsonb(x)order by fecha,hora,id)from page x),'[]'::jsonb),coalesce((select jsonb_object_agg(medio,jsonb_build_object('income',income,'expense',expense,'net',income-expense))from sums),'{}'::jsonb)into rows,totals;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('fecha',rows->(p_limit-1)->>'fecha','hora',rows->(p_limit-1)->>'hora','id',rows->(p_limit-1)->>'id');end if;return jsonb_build_object('rows',rows,'next',nxt,'totals',totals);
end $function$
;

-- Referencia leída de la base vigente: marathon.bonus_create(text,text,jsonb)
CREATE OR REPLACE FUNCTION marathon.bonus_create(request_id text, root_id text, data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
#variable_conflict use_variable
declare amount numeric:=0;paid boolean:=false;medium text;root marathon.turnos%rowtype;id text;mov text;reply jsonb;
begin
 if data?'bonus_amount' then
  if jsonb_typeof(data->'bonus_amount') is distinct from 'number' or coalesce(data->>'bonus_amount','') !~ '^[0-9]{1,10}(\.[0-9]{1,2})?$' then raise sqlstate '22023' using message='Importe de bono inválido (hasta dos decimales).';end if;
  amount=(data->>'bonus_amount')::numeric;
 end if;
 if data?'bonus_paid' then if jsonb_typeof(data->'bonus_paid') is distinct from 'boolean' then raise sqlstate '22023' using message='Indicá si el bono se cobra al reservar.';end if;paid=(data->>'bonus_paid')::boolean;end if;
 if paid and amount<=0 then raise sqlstate '22023' using message='Ingresá el importe del bono antes de registrar su pago.';end if;
 if amount=0 then return null;end if;
 if paid then medium=marathon.master_text(data,'bonus_medium',13,true);if medium not in('EFECTIVO','TRANSFERENCIA') then raise sqlstate '22023' using message='Elegí el medio de pago del bono.';end if;end if;
 select * into root from marathon.turnos t where t.id=root_id;
 if root.id is null then raise sqlstate '22023' using message='No se encontró la serie del bono.';end if;
 id='BON-'||gen_random_uuid()::text;
 insert into marathon.bonos_serie(id,serie_id,dni,sede,terapia_id,profesional_id,importe,fecha,hora,primera_fecha,sesiones,observaciones,created_by,updated_by)
 values(id,root_id,root.dni,root.sede,root.terapia_id,root.profesional_id,amount,(now() at time zone 'America/Argentina/Buenos_Aires')::date,(now() at time zone 'America/Argentina/Buenos_Aires')::time,root.fecha,
 (select count(*) from marathon.turnos t where coalesce(t.original_id,t.id)=root_id),'Bono inicial único de la reserva',auth.uid(),auth.uid());
 if paid then
  mov='MOV-'||gen_random_uuid()::text;
  insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,bono_id,concepto,categoria,profesional_asociado_id,created_by,updated_by)
  values(mov,(now() at time zone 'America/Argentina/Buenos_Aires')::date,(now() at time zone 'America/Argentina/Buenos_Aires')::time,'BONO','INGRESO',root.dni,amount,medium,root.sede,id,'Cobro de bono inicial','Bono inicial',root.profesional_id,auth.uid(),auth.uid());
  insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,after_data)select request_id,auth.uid(),'movement',mov,'bonus_pay',to_jsonb(m) from marathon.movimientos m where m.id=mov;
 end if;
 select to_jsonb(b) into reply from marathon.daily_bonus b where b.id=id;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,after_data)values(request_id,auth.uid(),'bonus',id,'create',reply);
 return reply;
end $function$
;

-- Referencia leída de la base vigente: marathon_bonus_get(text,jsonb,integer)
CREATE OR REPLACE FUNCTION public.marathon_bonus_get(p_id text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare bonus jsonb;rows jsonb;nxt jsonb;after_date date;after_time time;
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_id is null or length(p_id)>100 or p_limit is null or p_limit not between 1 and 50 then raise sqlstate '22023' using message='Consulta de bono inválida.';end if;
 select to_jsonb(b) into bonus from marathon.daily_bonus b where b.id=p_id;
 if bonus is null then raise sqlstate 'PT404' using message='Bono no encontrado.';end if;
 if p_after is not null then
  if jsonb_typeof(p_after)<>'object' or not(p_after?&array['fecha','hora','id']) or exists(select 1 from jsonb_object_keys(p_after)k where k<>all(array['fecha','hora','id'])) or exists(select 1 from jsonb_each(p_after)e where jsonb_typeof(e.value)<>'string') or coalesce(p_after->>'fecha','')!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or length(p_after->>'hora')>16 or length(p_after->>'id')>100 then raise sqlstate '22023' using message='Cursor inválido.';end if;
  begin after_date=(p_after->>'fecha')::date;after_time=(p_after->>'hora')::time;exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then raise sqlstate '22023' using message='Cursor inválido.';end;
 end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by fecha desc,hora desc,id desc),'[]'::jsonb) into rows from(
 select m.id,m.fecha,m.hora,m.tipo,m.monto,m.medio,m.concepto,m.observaciones_legacy,coalesce(u.display_name,m.secretaria_legacy,'Sin registro') actor from marathon.movimientos m left join marathon.app_users u on u.user_id=m.created_by
 where m.bono_id=p_id and m.origen='BONO' and(p_after is null or(m.fecha,m.hora,m.id)<(after_date,after_time,p_after->>'id')) order by m.fecha desc,m.hora desc,m.id desc limit p_limit+1)x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('fecha',rows->(p_limit-1)->>'fecha','hora',rows->(p_limit-1)->>'hora','id',rows->(p_limit-1)->>'id');end if;
 return jsonb_build_object('bonus',bonus,'rows',rows,'next',nxt);
end $function$
;

-- Referencia leída de la base vigente: marathon.advance_paid(text)
CREATE OR REPLACE FUNCTION marathon.advance_paid(p_id text)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select coalesce(sum(case when tipo='APLICACION'then monto when tipo='REVERSO'then -monto else 0 end),0) from marathon.anticipo_eventos where turno_id=p_id
$function$
;

-- Referencia leída de la base vigente: marathon.turn_cash_paid(text)
CREATE OR REPLACE FUNCTION marathon.turn_cash_paid(p_id text)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select coalesce(sum(case when tipo in ('REINTEGRO','EGRESO') then -monto else monto end),0) from marathon.movimientos where turno_id=p_id
$function$
;

-- Referencia leída de la base vigente: marathon_cash_list(text,text,jsonb,integer)
CREATE OR REPLACE FUNCTION public.marathon_cash_list(p_fecha text, p_sede text DEFAULT ''::text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d date;rows jsonb;nxt jsonb;totals jsonb;begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;d=marathon.agenda_date(p_fecha);
 if p_limit is null or p_limit not between 1 and 100 or(p_after is not null and(jsonb_typeof(p_after)<>'object' or not(p_after ?& array['hora','id']))) then raise sqlstate '22023' using message='Consulta inválida.';end if;
 if p_after is not null and coalesce(p_after->>'hora','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9](\:[0-5][0-9](\.[0-9]{1,6})?)?$' then raise sqlstate '22023' using message='Cursor inválido.';end if;
 select coalesce(jsonb_object_agg(medio,jsonb_build_object('income',income,'expense',expense,'net',income-expense)),'{}'::jsonb) into totals from(
 select medio,sum(case when tipo in ('PAGO','INGRESO') then monto else 0 end) income,sum(case when tipo in ('REINTEGRO','EGRESO') then monto else 0 end) expense from marathon.movimientos where fecha=d and origen in ('CLINICA','CAJA','ORTOPEDIA','BONO','ANTICIPO') and(coalesce(p_sede,'')='' or sede=p_sede) group by medio)x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.hora,x.id),'[]'::jsonb) into rows from(
 select m.*,concat_ws(' ',p.apellido,p.nombre) paciente,u.display_name actor,exists(select 1 from marathon.movimientos r where r.compensacion_de=m.id) reversed from marathon.movimientos m left join marathon.pacientes p on p.dni=m.dni left join marathon.app_users u on u.user_id=m.created_by
 where m.fecha=d and m.origen in ('CLINICA','CAJA','ORTOPEDIA','BONO','ANTICIPO') and(coalesce(p_sede,'')='' or m.sede=p_sede) and(p_after is null or(m.hora,m.id)>((p_after->>'hora')::time,p_after->>'id')) order by m.hora,m.id limit p_limit+1)x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('hora',rows->(p_limit-1)->>'hora','id',rows->(p_limit-1)->>'id');end if;
 return jsonb_build_object('rows',rows,'next',nxt,'totals',totals);
end $function$
;

-- Referencia leída de la base vigente: marathon_advance_get(text,jsonb,integer)
CREATE OR REPLACE FUNCTION public.marathon_advance_get(p_id text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare a jsonb;rows jsonb;nxt jsonb;
begin
 if not marathon.active_user()then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_limit is null or p_limit not between 1 and 50 or length(coalesce(p_id,''))>100 then raise sqlstate '22023' using message='Consulta inválida.';end if;
 if p_after is not null and(jsonb_typeof(p_after)<>'object'or not(p_after?&array['at','id'])or length(p_after::text)>200)then raise sqlstate '22023' using message='Cursor inválido.';end if;
 select to_jsonb(x)into a from marathon.daily_advance x where id=p_id;
 if a is null then raise sqlstate 'PT404' using message='Anticipo no encontrado.';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by created_at desc,id desc),'[]')into rows from(
 select e.*,m.medio,t.fecha turn_date,t.hora turn_hour,coalesce(u.display_name,'Sin registro') actor_name
 from marathon.anticipo_eventos e left join marathon.movimientos m on m.id=e.movimiento_id left join marathon.turnos t on t.id=e.turno_id left join marathon.app_users u on u.user_id=e.actor
 where e.anticipo_id=p_id and(p_after is null or(e.created_at,e.id)<((p_after->>'at')::timestamptz,(p_after->>'id')::uuid))order by e.created_at desc,e.id desc limit p_limit+1)x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('at',rows->(p_limit-1)->>'created_at','id',rows->(p_limit-1)->>'id');end if;
 return jsonb_build_object('advance',a,'rows',rows,'next',nxt);
end $function$
;

-- Referencia leída de la base vigente: marathon_turn_account(text)
CREATE OR REPLACE FUNCTION public.marathon_turn_account(p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t marathon.turnos%rowtype;paid numeric;history jsonb;
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 select * into t from marathon.turnos where id=p_id;
 if t.id is null then raise sqlstate 'PT404' using message='Turno no encontrado.';end if;
 paid=marathon.turn_paid(t.id);
 select coalesce(jsonb_agg(jsonb_build_object('created_at',a.created_at,'before_amount',a.before_data->'importe',
  'amount',a.after_data->'importe_cancelado','after_amount',a.after_data->'importe',
  'reason',a.after_data->>'motivo_cancelacion','actor',coalesce(to_jsonb(u)->>'name',to_jsonb(u)->>'nombre','Usuario autorizado')) order by a.created_at desc,a.id desc),'[]'::jsonb)
 into history from marathon.turn_audit a left join marathon.app_users u on u.user_id=a.actor
 where a.turn_id=t.id and a.action='cancel_charge';
 return to_jsonb(t)||jsonb_build_object('paid',paid,'cash_paid',marathon.turn_cash_paid(t.id),
  'advance_paid',marathon.advance_paid(t.id),'debt',case when t.estado='PRESENTE' then greatest(0,t.importe-paid) else 0 end,'charge_cancellations',history);
end $function$
;

-- Referencia leída de la base vigente: marathon.agenda_completar()
CREATE OR REPLACE FUNCTION marathon.agenda_completar()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if new.plan_id is not null and pg_trigger_depth()=1 then
  update marathon.agenda_planes set updated_at=now() where id=new.plan_id;
  if exists(select 1 from marathon.agenda_planes p where p.id=new.plan_id and p.modalidad='sessions' and marathon.agenda_presentes(p.id)>=marathon.agenda_total(p.id))then
   update marathon.turnos set estado='CANCELADO',agenda_motivo='SESIONES_COMPLETAS' where plan_id=new.plan_id and id<>new.id and estado='PENDIENTE' and fecha>=new.fecha;
  end if;
 end if;return new;
end$function$
;

-- Referencia leída de la base vigente: marathon.agenda_movimiento_guard()
CREATE OR REPLACE FUNCTION marathon.agenda_movimiento_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare q marathon.agenda_cuotas%rowtype;begin
 if new.cuota_id is null and new.compensacion_de is not null then select cuota_id into new.cuota_id from marathon.movimientos where id=new.compensacion_de;end if;
 if new.cuota_id is null then return new;end if;
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
 select * into strict q from marathon.agenda_cuotas where id=new.cuota_id for update;
 if new.tipo='INGRESO'and new.monto>marathon.agenda_cuota_saldo(q.id)or new.tipo='EGRESO'and new.monto>marathon.agenda_cuota_pagado(q.id)then raise sqlstate '22023'using message='El movimiento supera el saldo de la cuota. Revisá los pagos y reintegros previos.';end if;
 update marathon.agenda_planes set updated_at=now()where id=q.plan_id;return new;
end$function$
;

-- Referencia leída de la base vigente: marathon.agenda_turno_guard()
CREATE OR REPLACE FUNCTION marathon.agenda_turno_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare p marathon.agenda_planes%rowtype;q jsonb;a uuid;begin
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
 if tg_op='INSERT' and new.recovered_from is not null and new.plan_id is null then
  select t.plan_id into new.plan_id from marathon.turnos t where t.id=new.recovered_from;
  if new.plan_id is not null then new.fecha_habitual=new.fecha;end if;
 end if;
 if new.plan_id is not null then
  select * into strict p from marathon.agenda_planes where id=new.plan_id for update;
  if new.dni<>p.dni or new.terapia_id<>p.terapia_id then raise sqlstate '22023' using message='El turno no corresponde al tratamiento.';end if;
  if new.estado in('PRESENTE','AUSENTE') and marathon.agenda_pausado(p.id,new.fecha) then raise sqlstate '22023' using message='El tratamiento está pausado; conserva su lugar y no registra faltas.';end if;
  if new.estado='PRESENTE' and p.baja is not null and new.fecha>=p.baja then raise sqlstate '22023' using message='El tratamiento está dado de baja.';end if;
  if new.estado='PENDIENTE'and p.modalidad='sessions'and marathon.agenda_presentes(p.id)-(case when tg_op='UPDATE'and old.estado='PRESENTE'then 1 else 0 end)>=marathon.agenda_total(p.id)then raise sqlstate '22023'using message='Las sesiones están completas. Registrá una nueva cantidad.';end if;
  if new.estado='PRESENTE' and p.modalidad='sessions' then
   select x.id into a from marathon.agenda_autorizaciones x where x.plan_id=p.id and (select count(*) from marathon.turnos t where t.autorizacion_id=x.id and t.estado='PRESENTE' and t.id<>new.id)<x.cantidad order by x.fecha,x.created_at,x.id limit 1;
   if a is null then raise sqlstate '22023' using message='Se completaron las sesiones autorizadas. Registrá una nueva cantidad.';end if;new.autorizacion_id=a;
  elsif new.estado<>'PRESENTE' then new.autorizacion_id=null;end if;
 end if;
 if new.estado<>'CANCELADO' and (tg_op='INSERT' or old.estado='CANCELADO' or (old.fecha,old.hora,old.sede,old.profesional_id,old.terapia_id) is distinct from(new.fecha,new.hora,new.sede,new.profesional_id,new.terapia_id)) then
  if exists(select 1 from marathon.agenda_pool(new.fecha)x where x.dni=new.dni and x.id<>new.id and not(x.plan_id is not distinct from new.plan_id and new.horario_id is not null and x.id='H-'||new.horario_id::text||'-'||new.fecha_habitual::text) and x.hora<new.hora+make_interval(mins=>new.duracion_min) and new.hora<x.hora+make_interval(mins=>x.duracion_min)) then raise sqlstate '22023' using message='El paciente ya tiene atención o un lugar reservado en ese horario.';end if;
  q=marathon.agenda_cupo(new.fecha,new.sede,new.profesional_id,new.terapia_id,new.hora,new.plan_id,new.id);
  if coalesce((q->>'remaining')::int,0)<1 or coalesce((q->>'blocked')::boolean,true) then raise sqlstate '22023' using message='El horario no tiene cupo o dejó de estar habilitado.';end if;
 end if;return new;
end$function$
;

-- Referencia leída de la base vigente: marathon_agenda_patient_account(text,jsonb,integer)
CREATE OR REPLACE FUNCTION public.marathon_agenda_patient_account(p_dni text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '3s'
AS $function$
declare r jsonb;plans jsonb;debt numeric;begin
 if not marathon.active_user()then raise sqlstate '42501'using message='Acceso no autorizado.';end if;
 perform marathon.agenda_cuotas_generar();r=public.marathon_patient_account(p_dni,p_after,p_limit);
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'terapia',t.nombre,'debt',coalesce((select sum(marathon.agenda_cuota_saldo(q.id))from marathon.agenda_cuotas q where q.plan_id=p.id),0))order by p.inicio),'[]'::jsonb)into plans from marathon.agenda_planes p join marathon.terapias t on t.id=p.terapia_id where p.dni=p_dni and p.facturacion='monthly';
 select coalesce(sum((x->>'debt')::numeric),0)into debt from jsonb_array_elements(plans)x;
 return r||jsonb_build_object('plans',plans,'debt',coalesce((r->>'debt')::numeric,0)+debt);
end$function$
;

-- Referencia leída de la base vigente: marathon.bonus_change(text,text,jsonb)
CREATE OR REPLACE FUNCTION marathon.bonus_change(request_id text, action text, data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
#variable_conflict use_variable
declare old marathon.bonos_serie%rowtype;paid numeric;amount numeric;medium text;obs text;mov text;after_row jsonb;
begin
 select * into old from marathon.bonos_serie b where b.id=marathon.master_text(data,'id',100,true) for update;
 if old.id is null then raise sqlstate 'PT404' using message='Bono no encontrado.';end if;
 if old.version<>marathon.operation_version(data) then raise sqlstate 'PT409' using message='El bono cambió. Volvé a abrirlo antes de guardar.';end if;
 if old.estado='ANULADO' then raise sqlstate '22023' using message='El bono está anulado.';end if;
 select coalesce(sum(case when m.tipo='EGRESO' then -m.monto else m.monto end),0) into paid from marathon.movimientos m where m.bono_id=old.id and m.origen='BONO';
 if action='bonus_cancel' then
  obs=marathon.master_text(data,'motivo',1000,true);if length(obs)<3 then raise sqlstate '22023' using message='Indicá un motivo de al menos 3 caracteres.';end if;
  if paid<>0 then raise sqlstate '22023' using message='Reintegrá lo cobrado antes de anular el bono.';end if;
  update marathon.bonos_serie b set estado='ANULADO',observaciones=concat_ws(E'\n',b.observaciones,obs) where b.id=old.id;
 elsif action in('bonus_pay','bonus_refund') then
  amount=marathon.operation_amount(data);medium=marathon.master_text(data,'medio',13,true);obs=marathon.master_text(data,'observaciones',1000);
  if medium not in('EFECTIVO','TRANSFERENCIA') then raise sqlstate '22023' using message='Elegí el medio de pago.';end if;
  if action='bonus_pay' and amount>old.importe-paid then raise sqlstate '22023' using message='El cobro supera el saldo del bono.';end if;
  if action='bonus_refund' and amount>paid then raise sqlstate '22023' using message='El reintegro supera lo cobrado del bono.';end if;
  if action='bonus_refund' and length(btrim(coalesce(obs,'')))<3 then raise sqlstate '22023' using message='Indicá el motivo del reintegro.';end if;
  mov='MOV-'||gen_random_uuid()::text;
  insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,bono_id,concepto,observaciones_legacy,categoria,profesional_asociado_id,created_by,updated_by)
  values(mov,(now() at time zone 'America/Argentina/Buenos_Aires')::date,(now() at time zone 'America/Argentina/Buenos_Aires')::time,'BONO',case when action='bonus_pay' then 'INGRESO' else 'EGRESO' end,old.dni,amount,medium,old.sede,old.id,
  case when action='bonus_pay' then 'Cobro de bono inicial' else 'Reintegro de bono inicial' end,obs,'Bono inicial',old.profesional_id,auth.uid(),auth.uid());
  update marathon.bonos_serie b set updated_at=now() where b.id=old.id;
  insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,after_data)select request_id,auth.uid(),'movement',mov,action,to_jsonb(m) from marathon.movimientos m where m.id=mov;
 else raise sqlstate '22023' using message='Operación de bono inválida.';end if;
 select to_jsonb(b) into after_row from marathon.daily_bonus b where b.id=old.id;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data)values(request_id,auth.uid(),'bonus',old.id,action,to_jsonb(old),after_row);
 return jsonb_build_object('id',old.id,'message',case action when 'bonus_pay' then 'Cobro del bono registrado. Las sesiones se mantienen separadas.' when 'bonus_refund' then 'Reintegro registrado. El saldo del bono queda pendiente.' else 'Bono anulado. Se conservaron movimientos y sesiones.' end);
end $function$
;

-- Referencia leída de la base vigente: marathon.advance_apply(text,text,boolean)
CREATE OR REPLACE FUNCTION marathon.advance_apply(p_request text, p_turn text, p_release boolean DEFAULT false)
 RETURNS numeric
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
#variable_conflict use_variable
declare t marathon.turnos%rowtype;a record;need numeric;amount numeric;total numeric:=0;
begin
 select * into t from marathon.turnos where id=p_turn for update;
 if not found then raise sqlstate 'PT404' using message='Turno no encontrado.';end if;
 if p_release then
  for a in select anticipo_id,sum(case when tipo='APLICACION'then monto else -monto end) available from marathon.anticipo_eventos where turno_id=t.id group by anticipo_id having sum(case when tipo='APLICACION'then monto else -monto end)>0 order by anticipo_id loop
   insert into marathon.anticipo_eventos(anticipo_id,turno_id,tipo,monto,request_id,actor)values(a.anticipo_id,t.id,'REVERSO',a.available,p_request,auth.uid());
   update marathon.anticipos set observaciones=observaciones where id=a.anticipo_id;total=total+a.available;
  end loop;
 else
  if t.estado<>'PRESENTE' then return 0;end if;
  need=greatest(0,t.importe-marathon.turn_paid(t.id));
  for a in select * from marathon.daily_advance where dni=t.dni and sede=t.sede and(terapia_id is null or terapia_id=t.terapia_id)and(profesional_id is null or profesional_id=t.profesional_id)and available>0 order by fecha,hora,id loop
   exit when need<=0;amount=least(need,a.available);
   insert into marathon.anticipo_eventos(anticipo_id,turno_id,tipo,monto,request_id,actor)values(a.id,t.id,'APLICACION',amount,p_request,auth.uid());
   update marathon.anticipos set observaciones=observaciones where id=a.id;total=total+amount;need=need-amount;
  end loop;
 end if;
 if total>0 then update marathon.turnos set observaciones=observaciones where id=t.id;end if;
 return total;
end $function$
;

-- Referencia leída de la base vigente: marathon.advance_change(text,text,jsonb)
CREATE OR REPLACE FUNCTION marathon.advance_change(p_request text, p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
#variable_conflict use_variable
declare a marathon.anticipos%rowtype;aid text;mid text;dni text;site text;therapy text;prof text;obs text;medium text;amount numeric;available numeric;applied numeric:=0;t record;d date:=(now() at time zone 'America/Argentina/Buenos_Aires')::date;h time:=(now() at time zone 'America/Argentina/Buenos_Aires')::time;
begin
 obs=marathon.master_text(p_data,'observaciones',1000);
 if p_action in('advance_deposit','advance_apply')then
  dni=marathon.master_text(p_data,'dni',12,true);
  if dni !~ '^[0-9]{1,12}$' or not exists(select 1 from marathon.pacientes p where p.dni=dni)then raise sqlstate '22023' using message='Seleccioná un paciente registrado.';end if;
 end if;
 if p_action='advance_deposit'then
  site=marathon.master_text(p_data,'sede',40,true);therapy=nullif(marathon.master_text(p_data,'therapy',100),'');prof=nullif(marathon.master_text(p_data,'prof',100),'');
  if not exists(select 1 from marathon.sedes where nombre=site and estado='ACTIVO')or(therapy is not null and not exists(select 1 from marathon.terapias where id=therapy and estado='ACTIVO'))or(prof is not null and not exists(select 1 from marathon.profesionales where id=prof and estado='ACTIVO'))or(prof is not null and therapy is not null and not exists(select 1 from marathon.profesional_terapias where profesional_id=prof and terapia_id=therapy))then raise sqlstate '22023' using message='Elegí sede, terapia y profesional compatibles y activos.';end if;
  if p_data?'apply_existing' and jsonb_typeof(p_data->'apply_existing') is distinct from 'boolean'then raise sqlstate '22023' using message='Opción de aplicación inválida.';end if;
  amount=marathon.operation_amount(p_data);medium=marathon.master_text(p_data,'medio',13,true);
  if medium not in('EFECTIVO','TRANSFERENCIA')then raise sqlstate '22023' using message='Elegí el medio de pago.';end if;
  aid='ANT-'||gen_random_uuid()::text;mid='MOV-'||gen_random_uuid()::text;
  insert into marathon.anticipos(id,dni,sede,terapia_id,profesional_id,importe,fecha,hora,observaciones,created_by,updated_by)values(aid,dni,site,therapy,prof,amount,d,h,obs,auth.uid(),auth.uid());
  insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,anticipo_id,concepto,categoria,observaciones_legacy,created_by,updated_by)values(mid,d,h,'ANTICIPO','INGRESO',dni,amount,medium,site,aid,'Anticipo clínico','Anticipos',obs,auth.uid(),auth.uid());
  insert into marathon.anticipo_eventos(anticipo_id,tipo,monto,movimiento_id,request_id,actor)values(aid,'DEPOSITO',amount,mid,p_request,auth.uid());
 elsif p_action='advance_refund'then
  select * into a from marathon.anticipos where id=marathon.master_text(p_data,'id',100,true) for update;
  if not found then raise sqlstate 'PT404' using message='Anticipo no encontrado.';end if;
  if a.version<>marathon.operation_version(p_data)then raise sqlstate 'PT409' using message='El anticipo cambió. Volvé a abrirlo.';end if;
  if length(btrim(obs))<3 then raise sqlstate '22023' using message='Indicá el motivo del reintegro (mínimo 3 caracteres).';end if;
  select x.available into available from marathon.daily_advance x where x.id=a.id;
  amount=marathon.operation_amount(p_data);medium=marathon.master_text(p_data,'medio',13,true);
  if amount>available then raise sqlstate '22023' using message='Solo podés reintegrar el saldo del anticipo que todavía no se aplicó.';end if;
  if medium not in('EFECTIVO','TRANSFERENCIA')then raise sqlstate '22023' using message='Elegí el medio de pago.';end if;
  aid=a.id;mid='MOV-'||gen_random_uuid()::text;
  insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,anticipo_id,concepto,categoria,observaciones_legacy,motivo,created_by,updated_by)values(mid,d,h,'ANTICIPO','EGRESO',a.dni,amount,medium,a.sede,aid,'Reintegro de anticipo','Anticipos',obs,obs,auth.uid(),auth.uid());
  insert into marathon.anticipo_eventos(anticipo_id,tipo,monto,movimiento_id,request_id,actor)values(aid,'DEVOLUCION',amount,mid,p_request,auth.uid());
  update marathon.anticipos set observaciones=observaciones where id=aid;
 end if;
 if p_action='advance_apply' or(p_action='advance_deposit'and coalesce((p_data->>'apply_existing')::boolean,false))then
  for t in select id from marathon.turnos where turnos.dni=dni and estado='PRESENTE' and importe>marathon.turn_paid(id) order by fecha,hora,id loop
   applied=applied+marathon.advance_apply(p_request,t.id);
  end loop;
 end if;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,after_data)values(p_request,auth.uid(),'advance',coalesce(aid,dni),p_action,jsonb_build_object('id',aid,'applied',applied,'movement',mid));
 return jsonb_build_object('id',aid,'applied',applied,'message',case p_action when 'advance_deposit'then 'Anticipo recibido. Ingreso registrado en Caja.'when 'advance_refund'then 'Saldo disponible reintegrado. Egreso registrado en Caja.'else 'Anticipos aplicados a las sesiones presentes compatibles con deuda.'end);
end $function$
;

-- Referencia leída de la base vigente: marathon_agenda_plan_command(text,text,jsonb)
CREATE OR REPLACE FUNCTION public.marathon_agenda_plan_command(p_request_id text, p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '3s'
AS $function$
#variable_conflict use_variable
declare reply jsonb;p marathon.agenda_planes%rowtype;h marathon.agenda_horarios%rowtype;pause marathon.agenda_pausas%rowtype;q marathon.agenda_cuotas%rowtype;
 raw jsonb;cov jsonb;slot jsonb;dt date;dt2 date;kind text;fee numeric;quantity int;pid uuid;sid uuid;root text;mid text;amount numeric;reason text;medium text;before_data jsonb;w marathon.espera%rowtype;bonus jsonb;
begin
 reply=marathon.operation_begin(p_request_id,'agenda-plan:'||coalesce(p_action,''),p_data);if reply is not null then return reply;end if;
 if p_action not in('create','pause','resume','end','authorize','quota_pay','quota_waive','quota_refund')or p_action is null then raise sqlstate '22023' using message='Acción inválida.';end if;
 if p_action='create' then
  if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['dni','therapy','mode','billing','amount','start','total','coverage','notes','schedules','bonus_amount','bonus_paid','bonus_medium','wait_id','wait_version']))then raise sqlstate '22023'using message='Campos de reserva inválidos.';end if;
  dt=marathon.agenda_date(p_data->>'start');kind=p_data->>'mode';fee=(p_data->>'amount')::numeric;quantity=coalesce((p_data->>'total')::int,0);
  if dt<marathon.agenda_hoy() or dt>marathon.agenda_hoy()+366 or kind not in('sessions','monthly','fixed')or kind is null or p_data->>'billing' not in('class','bonus_class','monthly','none')or p_data->>'billing' is null or fee is null or fee<0 or fee>9999999999.99 or fee<>round(fee,2)or(kind='sessions'and quantity not between 1 and 1000)or(p_data->>'billing'='none'and fee<>0)or(p_data->>'billing'='monthly'and fee<=0)then raise sqlstate '22023'using message='Revisá inicio, modalidad, cantidad e importe.';end if;
  cov=marathon.normalize_turn_coverage(p_data->>'dni',p_data->'coverage');
  if jsonb_typeof(p_data->'schedules')is distinct from'array'or jsonb_array_length(p_data->'schedules')not between 1 and 5 then raise sqlstate '22023'using message='Elegí uno o más días hábiles.';end if;
  if p_data->>'billing'='bonus_class' and coalesce((p_data->>'bonus_amount')::numeric,0)<=0 then raise sqlstate '22023'using message='Indicá el importe del bono inicial.';end if;
  if p_data->>'billing'<>'bonus_class'and coalesce((p_data->>'bonus_amount')::numeric,0)<>0 then raise sqlstate '22023'using message='El bono solo corresponde a bono inicial más clase.';end if;
  insert into marathon.agenda_planes(dni,terapia_id,modalidad,facturacion,importe,inicio,coverage,observaciones,created_by,updated_by)values(p_data->>'dni',p_data->>'therapy',kind,p_data->>'billing',fee,dt,cov,coalesce(p_data->>'notes',''),auth.uid(),auth.uid())returning id into pid;
  if kind='sessions'then insert into marathon.agenda_autorizaciones(plan_id,cantidad,fecha,created_by)values(pid,quantity,dt,auth.uid());end if;
  for raw in select * from jsonb_array_elements(p_data->'schedules')loop
   if exists(select 1 from jsonb_object_keys(raw)k where k<>all(array['day','site','prof','time']))or(raw->>'day')::int not between 1 and 5 then raise sqlstate '22023'using message='Día u horario inválido.';end if;
   dt2=dt+(((raw->>'day')::int-extract(dow from dt)::int+7)%7);
   slot=marathon.agenda_cupo(dt2,raw->>'site',raw->>'prof',p_data->>'therapy',(raw->>'time')::time,pid);
   if coalesce((slot->>'remaining')::int,0)<1 or coalesce((slot->>'blocked')::boolean,true)then raise sqlstate '22023'using message='Uno de los horarios no está habilitado o no tiene cupo.';end if;
   insert into marathon.agenda_horarios(plan_id,sede,profesional_id,dia,hora,duracion_min,desde)values(pid,raw->>'site',raw->>'prof',(raw->>'day')::int,(raw->>'time')::time,(slot->>'duration_min')::int,dt);
  end loop;
  -- Comprobar todos los cambios futuros de reglas y todos los turnos ya cargados, además de las próximas semanas.
  for h in select * from marathon.agenda_horarios where plan_id=pid loop
   for dt2 in select distinct candidate_date from(
    select g::date candidate_date from generate_series(dt,dt+41,interval '1 day')g
    union select t.fecha from marathon.turnos t where t.fecha>=dt and(t.dni=p_data->>'dni'or t.profesional_id=h.profesional_id)and t.estado<>'CANCELADO'
    union select greatest(dt,x.desde)+((h.dia-extract(dow from greatest(dt,x.desde))::int+7)%7)from marathon.agenda_horarios x where x.profesional_id=h.profesional_id or x.plan_id in(select p.id from marathon.agenda_planes p where p.dni=p_data->>'dni')
   )c where candidate_date>=dt and extract(dow from candidate_date)::int=h.dia loop
    slot=marathon.agenda_cupo(dt2,h.sede,h.profesional_id,p_data->>'therapy',h.hora,pid);
    if coalesce((slot->>'remaining')::int,0)<1 then raise sqlstate '22023'using message='La reserva entra en conflicto con la ocupación del '||dt2::text||'.';end if;
    if exists(select 1 from marathon.agenda_pool(dt2)x where x.dni=p_data->>'dni'and x.plan_id is distinct from pid and x.hora<h.hora+make_interval(mins=>h.duracion_min)and h.hora<x.hora+make_interval(mins=>x.duracion_min))then raise sqlstate '22023'using message='El paciente ya tiene un turno o lugar reservado en uno de los horarios.';end if;
   end loop;
  end loop;
  if p_data->>'billing'='monthly'or kind='monthly'then insert into marathon.agenda_periodos(plan_id,inicio)values(pid,dt);end if;
  perform marathon.agenda_materializar(dt,dt+case when kind='fixed'then 6 else 27 end);
  select id into root from marathon.turnos t where t.plan_id=pid order by t.fecha,t.hora,t.id limit 1;
  bonus=marathon.bonus_create(p_request_id,root,p_data);
  if nullif(p_data->>'wait_id','')is not null then
   select * into w from marathon.espera where id=p_data->>'wait_id'for update;
   if w.id is null or w.estado not in('PENDIENTE','CONTACTADO')or w.version<>(p_data->>'wait_version')::bigint or w.dni<>p_data->>'dni'or w.terapia_id<>p_data->>'therapy'or not exists(select 1 from marathon.agenda_horarios h where h.plan_id=pid and h.sede=w.sede and(w.profesional_id is null or h.profesional_id=w.profesional_id))then raise sqlstate 'PT409'using message='El pedido de espera cambió o la reserva no corresponde.';end if;
   update marathon.espera set estado='RESUELTO',reserved_turn_id=root where id=w.id;
  end if;
 else
  if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['id','version','date','until','reason','total','quota','amount','medium']))then raise sqlstate '22023'using message='Campos de operación inválidos.';end if;
  pid=(p_data->>'id')::uuid;select * into p from marathon.agenda_planes where id=pid for update;
  if not found then raise sqlstate 'PT404'using message='Tratamiento no encontrado.';end if;
  if p.version<>(p_data->>'version')::bigint or p_data->>'version'is null then raise sqlstate 'PT409'using message='El tratamiento cambió. Volvé a abrirlo.';end if;before_data=to_jsonb(p);
  dt=coalesce(nullif(p_data->>'date','')::date,marathon.agenda_hoy());reason=btrim(coalesce(p_data->>'reason',''));
  if p_action in('pause','resume','end','quota_waive','quota_refund')and length(reason)not between 3 and 1000 then raise sqlstate '22023'using message='Indicá un motivo de al menos tres caracteres.';end if;
  if p_action='pause'then
   dt2=nullif(p_data->>'until','')::date;
   if p.baja is not null or dt<greatest(p.inicio,marathon.agenda_hoy())or(dt2 is not null and dt2<=dt)or exists(select 1 from marathon.agenda_pausas x where x.plan_id=pid and coalesce(x.hasta,'infinity'::date)>dt and coalesce(dt2,'infinity'::date)>x.desde)then raise sqlstate '22023'using message='Fechas de pausa inválidas o superpuestas.';end if;
   insert into marathon.agenda_pausas(plan_id,desde,hasta,motivo,created_by)values(pid,dt,dt2,reason,auth.uid());
   update marathon.agenda_periodos set fin=dt where plan_id=pid and not anulado and inicio<=dt and(fin is null or fin>dt);
   if dt2 is not null and(p.facturacion='monthly'or p.modalidad='monthly')then insert into marathon.agenda_periodos(plan_id,inicio)values(pid,dt2);end if;
  elsif p_action='resume'then
   select * into pause from marathon.agenda_pausas x where x.plan_id=pid and x.desde<=dt and(x.hasta is null or dt<x.hasta)order by x.desde desc limit 1 for update;
   if pause.id is null or dt<>marathon.agenda_hoy()or p.baja is not null then raise sqlstate '22023'using message='No hay una pausa activa para reanudar hoy.';end if;
   update marathon.agenda_pausas set hasta=dt where id=pause.id;
   update marathon.agenda_periodos set anulado=true where plan_id=pid and inicio>dt;
   if p.facturacion='monthly'or p.modalidad='monthly'then
    if dt=pause.desde then update marathon.agenda_periodos set fin=null where plan_id=pid and fin=dt and not anulado;
    else insert into marathon.agenda_periodos(plan_id,inicio)values(pid,dt);end if;
   end if;
  elsif p_action='end'then
   if dt<greatest(p.inicio,marathon.agenda_hoy())or p.baja is not null then raise sqlstate '22023'using message='La baja no puede modificar períodos anteriores.';end if;
   if exists(select 1 from marathon.turnos t where t.plan_id=pid and t.fecha>=dt and t.estado='PRESENTE')then raise sqlstate '22023'using message='Hay atenciones presentes posteriores a esa baja. Revisá su fecha antes de continuar.';end if;
   update marathon.agenda_planes set baja=dt where id=pid;
   update marathon.turnos set estado='CANCELADO',agenda_motivo='BAJA'where plan_id=pid and fecha>=dt and estado='PENDIENTE';
  elsif p_action='authorize'then
   quantity=(p_data->>'total')::int;if p.modalidad<>'sessions'or quantity is null or quantity not between 1 and 1000 or p.baja is not null then raise sqlstate '22023'using message='Indicá de 1 a 1000 sesiones para una nueva autorización.';end if;
   insert into marathon.agenda_autorizaciones(plan_id,cantidad,fecha,created_by)values(pid,quantity,marathon.agenda_hoy(),auth.uid());
  else
   perform marathon.agenda_cuotas_generar();select * into q from marathon.agenda_cuotas c where c.id=(p_data->>'quota')::uuid and c.plan_id=pid for update;
   if q.id is null then raise sqlstate 'PT404'using message='Cuota no encontrada.';end if;
   amount=(p_data->>'amount')::numeric;medium=p_data->>'medium';
   if amount is null or amount<=0 or amount<>round(amount,2)then raise sqlstate '22023'using message='Importe inválido.';end if;
   if p_action='quota_waive'then
    if amount>marathon.agenda_cuota_saldo(q.id)then raise sqlstate '22023'using message='La cancelación supera el saldo pendiente.';end if;
    insert into marathon.agenda_ajustes(cuota_id,importe,motivo,created_by)values(q.id,amount,reason,auth.uid());
   else
    if medium not in('EFECTIVO','TRANSFERENCIA')or medium is null then raise sqlstate '22023'using message='Elegí un medio de pago.';end if;
    if p_action='quota_pay'and amount>marathon.agenda_cuota_saldo(q.id)or p_action='quota_refund'and amount>marathon.agenda_cuota_pagado(q.id)then raise sqlstate '22023'using message='El importe supera el saldo disponible.';end if;
    mid='MOV-'||gen_random_uuid()::text;
    insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,concepto,observaciones_legacy,motivo,categoria,profesional_asociado_id,cuota_id,created_by,updated_by)
    values(mid,marathon.agenda_hoy(),(now()at time zone'America/Argentina/Buenos_Aires')::time,'CAJA',case when p_action='quota_pay'then'INGRESO'else'EGRESO'end,p.dni,amount,medium,q.sede,'Cuota mensual '||q.fecha::text,reason,nullif(reason,''),'Cuota mensual',(select h.profesional_id from marathon.agenda_horarios h where h.plan_id=pid order by h.dia,h.hora limit 1),q.id,auth.uid(),auth.uid());
   end if;
  end if;
  update marathon.agenda_planes set updated_at=now()where id=pid;
 end if;
 if mid is not null then insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,after_data)select p_request_id,auth.uid(),'movement',m.id,p_action,to_jsonb(m)from marathon.movimientos m where m.id=mid;end if;
 perform marathon.agenda_cuotas_generar();
 reply=jsonb_build_object('id',pid,'ids',jsonb_build_array(root),'bonus',bonus,'plan',marathon.agenda_plan_info(pid),'message','Operación guardada en la agenda.');
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data)values(p_request_id,auth.uid(),'agenda_plan',pid::text,p_action,before_data,reply->'plan');
 update marathon.solicitudes set resultado=reply where id=p_request_id;return reply;
end$function$
;

-- Referencia leída de la base vigente: marathon.agenda_cuota_pagado(uuid)
CREATE OR REPLACE FUNCTION marathon.agenda_cuota_pagado(q uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select coalesce(sum(case when m.tipo in('PAGO','INGRESO') then m.monto else -m.monto end),0)
 from marathon.movimientos m left join marathon.movimientos original on original.id=m.compensacion_de
 where m.cuota_id=q or original.cuota_id=q
$function$
;

-- Referencia leída de la base vigente: marathon.agenda_cuota_saldo(uuid)
CREATE OR REPLACE FUNCTION marathon.agenda_cuota_saldo(q uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select greatest(0,c.importe-marathon.agenda_cuota_pagado(c.id)-coalesce((select sum(a.importe) from marathon.agenda_ajustes a where a.cuota_id=c.id),0)) from marathon.agenda_cuotas c where c.id=q
$function$
;

-- Referencia leída de la base vigente: marathon.agenda_cuotas_generar(date)
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
 cross join lateral(select x.sede from marathon.agenda_horarios x where x.plan_id=p.id order by x.dia,x.hora limit 1)h
 cross join lateral generate_series(0,greatest(0,(extract(year from p_hoy)::int-extract(year from s.inicio)::int)*12+extract(month from p_hoy)::int-extract(month from s.inicio)::int))g(n)
 where p.facturacion='monthly' and not s.anulado and s.inicio<=p_hoy
 and (s.inicio+make_interval(months=>g.n))::date<=p_hoy
 and(s.fin is null or (s.inicio+make_interval(months=>g.n))::date<s.fin)
 and(p.baja is null or (s.inicio+make_interval(months=>g.n))::date<p.baja)
 on conflict(periodo_id,fecha) do nothing;
 get diagnostics n=row_count;return n;
end$function$
;

-- Referencia leída de la base vigente: marathon_turn_cancel_charge
CREATE OR REPLACE FUNCTION public.marathon_turn_cancel_charge(p_request_id text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '3s'
AS $function$
declare
 reply jsonb; old_row marathon.turnos%rowtype; new_row marathon.turnos%rowtype;
 v_id text; v_reason text; v_paid numeric; v_debt numeric; v_expected numeric;
begin
 reply=marathon.operation_begin(p_request_id,'turn:cancel_charge',p_data);
 if reply is not null then return reply;end if;
 if exists(select 1 from jsonb_object_keys(p_data) k where k not in('id','version','saldo','motivo')) then
  raise sqlstate '22023' using message='Datos de cancelación inválidos.';
 end if;
 v_id=marathon.master_text(p_data,'id',100,true);
 v_reason=btrim(marathon.master_text(p_data,'motivo',1000,true));
 if length(v_reason)<3 then raise sqlstate '22023' using message='Indicá el motivo de la cancelación (3 a 1000 caracteres).';end if;
 if coalesce(p_data->>'saldo','') !~ '^[0-9]{1,12}(\.[0-9]{1,2})?$' then
  raise sqlstate '22023' using message='El saldo esperado es inválido.';
 end if;
 v_expected=(p_data->>'saldo')::numeric;
 select * into old_row from marathon.turnos where id=v_id for update;
 if old_row.id is null then raise sqlstate 'PT404' using message='Turno no encontrado.';end if;
 if old_row.version<>marathon.operation_version(p_data) then
  raise sqlstate 'PT409' using message='La sesión cambió. Volvé a abrir la cancelación.';
 end if;
 v_paid=marathon.turn_paid(v_id);v_debt=greatest(0,old_row.importe-v_paid);
 if old_row.estado<>'PRESENTE' or v_debt<=0 then
  raise sqlstate '22023' using message='Solo se cancela el saldo pendiente de una sesión presente.';
 end if;
 if v_expected<>v_debt then raise sqlstate 'PT409' using message='Cambió el saldo de la sesión. Volvé a abrir la cancelación.';end if;
 -- Mantener pagos y anticipos aplicados; anular solamente la parte adeudada.
 update marathon.turnos set importe=old_row.importe-v_debt where id=v_id returning * into new_row;
 insert into marathon.turn_audit(request_id,actor,turn_id,action,before_data,after_data)
 values(p_request_id,auth.uid(),v_id,'cancel_charge',to_jsonb(old_row),to_jsonb(new_row)||jsonb_build_object(
  'motivo_cancelacion',v_reason,'importe_cancelado',v_debt,'saldo_anterior',v_debt,'saldo_resultante',0,
  'pagos_conservados',v_paid,'tipo_ajuste','CONTRAASIENTO_SALDO_SIN_CAJA'));
 reply=jsonb_build_object('id',v_id,'cancelled_amount',v_debt,'debt',0,'message','Saldo de la sesión cancelado. Presente y pagos conservados; ajuste registrado con su motivo.');
 update marathon.solicitudes set resultado=reply where id=p_request_id;
 return reply;
end $function$
;

-- Referencia leída de la base vigente: operation_amount
CREATE OR REPLACE FUNCTION marathon.operation_amount(data jsonb, key text DEFAULT 'monto'::text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$ begin
 if jsonb_typeof(data->key) is distinct from 'number' or coalesce(data->>key,'') !~ '^[0-9]{1,10}(\.[0-9]{1,2})?$' or (data->>key)::numeric<=0 then raise sqlstate '22023' using message='Ingresá un importe mayor a cero, con hasta dos decimales.';end if;return (data->>key)::numeric;
end $function$
;
