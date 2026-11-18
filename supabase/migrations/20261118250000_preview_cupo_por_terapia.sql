-- Extiende el nuevo modelo de capacidad por terapia (ver 20261118240000) a las funciones
-- de vista previa y validación que todavía usaban el bloqueo cruzado por especialidad
-- y el corte "remaining<1" sin excepción para terapias con capacidad > 1.

create or replace function marathon.agenda_slots(d date, site text, prof text, therapy text)
 returns table(hora text, remaining integer, capacity integer, shared_capacity integer, blocked boolean)
 language sql
 stable
 set search_path to ''
as $function$
 with target as (
  select t.*,marathon.master_norm(t.especialidad) spec from marathon.terapias t
  join marathon.profesional_terapias pt on pt.terapia_id=t.id and pt.profesional_id=prof
  join marathon.profesionales p on p.id=pt.profesional_id and p.estado='ACTIVO'
  join marathon.sedes s on s.nombre=site and s.estado='ACTIVO'
  where t.id=therapy and t.estado='ACTIVO'
 ), config as (
  select t.*,greatest(t.capacidad,coalesce((select max(a.capacidad) from marathon.terapias a
   join marathon.profesional_terapias pt on pt.terapia_id=a.id and pt.profesional_id=prof
   where a.estado='ACTIVO' and t.spec<>'' and marathon.master_norm(a.especialidad)=t.spec),t.capacidad)) shared
  from target t
 ), candidates as (
  select distinct (extract(epoch from h.inicio)/60)::int+g.n m,marathon.session_minutes(d,site,prof,time '00:00'+((extract(epoch from h.inicio)/60)::int+g.n)*interval '1 minute',c.duracion_min) actual_duration,c.* from config c
  join marathon.horarios h on h.profesional_id=prof and h.sede=site and h.dia=extract(dow from d)::int
  cross join lateral generate_series(0,(extract(epoch from(h.fin-h.inicio))/60)::int-15,marathon.professional_step(prof)) g(n)
 ), active as (
  select x.id,x.sede,x.terapia_id,(extract(epoch from x.hora)/60)::int m,marathon.session_minutes(x.fecha,x.sede,x.profesional_id,x.hora,x.duracion_min) duracion_min
  from marathon.agenda_pool(d) x
  where x.profesional_id=prof and x.fecha=d and x.estado<>'CANCELADO'
 )
 select to_char(time '00:00'+c.m*interval '1 minute','HH24:MI'),
  case when b.no then 0 when c.capacidad<=1 then greatest(0,coalesce(r.left_over,c.capacidad)) else greatest(1,coalesce(r.left_over,c.capacidad)) end,
  c.capacidad,c.shared,b.no
 from candidates c
 cross join lateral (select exists(select 1 from active a where a.m<c.m+c.actual_duration and c.m<a.m+a.duracion_min and a.sede<>site) no) b
 cross join lateral (
  select min(c.capacidad-(select count(*)::int from active a where a.terapia_id=therapy and a.m<=cuts.at and cuts.at<a.m+a.duracion_min)) left_over
  from (select c.m at union select a.m from active a where a.terapia_id=therapy and a.m>c.m and a.m<c.m+c.actual_duration
   union select a.m+a.duracion_min from active a where a.terapia_id=therapy and a.m+a.duracion_min>c.m and a.m+a.duracion_min<c.m+c.actual_duration) cuts
 ) r order by c.m;
$function$;

create or replace function marathon.agenda_slots_excluding(d date, site text, prof text, therapy text, excluded text[])
 returns table(hora text, remaining integer, capacity integer, shared_capacity integer, blocked boolean)
 language sql
 stable
 set search_path to ''
as $function$
 with target as (
  select t.*,marathon.master_norm(t.especialidad) spec from marathon.terapias t
  join marathon.profesional_terapias pt on pt.terapia_id=t.id and pt.profesional_id=prof
  join marathon.profesionales p on p.id=pt.profesional_id and p.estado='ACTIVO'
  join marathon.sedes s on s.nombre=site and s.estado='ACTIVO'
  where t.id=therapy and t.estado='ACTIVO'
 ), config as (
  select t.*,greatest(t.capacidad,coalesce((select max(a.capacidad) from marathon.terapias a
   join marathon.profesional_terapias pt on pt.terapia_id=a.id and pt.profesional_id=prof
   where a.estado='ACTIVO' and t.spec<>'' and marathon.master_norm(a.especialidad)=t.spec),t.capacidad)) shared
  from target t
 ), candidates as (
  select distinct (extract(epoch from h.inicio)/60)::int+g.n m,marathon.session_minutes(d,site,prof,time '00:00'+((extract(epoch from h.inicio)/60)::int+g.n)*interval '1 minute',c.duracion_min) actual_duration,c.* from config c
  join marathon.horarios h on h.profesional_id=prof and h.sede=site and h.dia=extract(dow from d)::int
  cross join lateral generate_series(0,(extract(epoch from(h.fin-h.inicio))/60)::int-15,marathon.professional_step(prof)) g(n)
 ), active as (
  select x.id,x.sede,x.terapia_id,(extract(epoch from x.hora)/60)::int m,marathon.session_minutes(x.fecha,x.sede,x.profesional_id,x.hora,x.duracion_min) duracion_min
  from marathon.agenda_pool(d) x
  where x.profesional_id=prof and x.fecha=d and x.estado<>'CANCELADO' and not(x.id=any(excluded))
 )
 select to_char(time '00:00'+c.m*interval '1 minute','HH24:MI'),
  case when b.no then 0 when c.capacidad<=1 then greatest(0,coalesce(r.left_over,c.capacidad)) else greatest(1,coalesce(r.left_over,c.capacidad)) end,
  c.capacidad,c.shared,b.no
 from candidates c
 cross join lateral (select exists(select 1 from active a where a.m<c.m+c.actual_duration and c.m<a.m+a.duracion_min and a.sede<>site) no) b
 cross join lateral (
  select min(c.capacidad-(select count(*)::int from active a where a.terapia_id=therapy and a.m<=cuts.at and cuts.at<a.m+a.duracion_min)) left_over
  from (select c.m at union select a.m from active a where a.terapia_id=therapy and a.m>c.m and a.m<c.m+c.actual_duration
   union select a.m+a.duracion_min from active a where a.terapia_id=therapy and a.m+a.duracion_min>c.m and a.m+a.duracion_min<c.m+c.actual_duration) cuts
 ) r order by c.m;
$function$;

create or replace function marathon.agenda_horarios_invalidos()
 returns table(profesional_id text, sede text, dia integer, hora time without time zone, blocked boolean, remaining integer, n_planes bigint, dnis text, proxima_fecha date)
 language sql
 stable
 set search_path to ''
as $function$
  with s as (
    select ah.id, ah.plan_id, ah.sede, ah.profesional_id, ah.dia, ah.hora,
           p.terapia_id, p.dni,
           (current_date + ((ah.dia - extract(dow from current_date)::int + 7) % 7))::date as nd
    from marathon.agenda_horarios ah
    join marathon.agenda_planes p on p.id = ah.plan_id
    where (p.baja is null or p.baja > current_date)
  ),
  c as (
    select s.*, marathon.agenda_cupo(s.nd, s.sede, s.profesional_id, s.terapia_id, s.hora, s.plan_id) q
    from s
  )
  select c.profesional_id, c.sede, c.dia, c.hora,
         (c.q->>'blocked')::boolean,
         (c.q->>'remaining')::int,
         count(*),
         string_agg(distinct c.dni, ', '),
         min(c.nd)
  from c
  where (c.q->>'blocked')::boolean is true
     or (coalesce((c.q->>'capacity')::int,1)<=1 and coalesce((c.q->>'remaining')::int, 0) < 1)
  group by c.profesional_id, c.sede, c.dia, c.hora, (c.q->>'blocked')::boolean, (c.q->>'remaining')::int
  order by c.profesional_id, c.dia, c.hora;
$function$;

create or replace function public.marathon_reschedule_preview(p_data jsonb)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare selected jsonb; ids text[]; c jsonb; d date; result jsonb;
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>60000
 or exists(select 1 from jsonb_object_keys(p_data) k where k<>all(array['id','scope','changes']))
 or jsonb_typeof(p_data->'changes') is distinct from 'array' then raise sqlstate '22023' using message='Vista previa inválida.';end if;
 selected=public.marathon_reschedule_get(p_data->>'id',p_data->>'scope');
 select array_agg(x->>'id') into ids from jsonb_array_elements(selected)x;
 if jsonb_array_length(p_data->'changes')<>cardinality(ids)
 or exists(select 1 from jsonb_array_elements(p_data->'changes') x where jsonb_typeof(x)<>'object' or not(coalesce(x->>'id','')=any(ids)))
 or (select count(distinct x->>'id') from jsonb_array_elements(p_data->'changes')x)<>cardinality(ids)
 then raise sqlstate 'PT409' using message='La serie cambió. Volvé a abrir la reprogramación.';end if;
 for c in select value from jsonb_array_elements(p_data->'changes') loop
  if exists(select 1 from jsonb_object_keys(c) k where k<>all(array['id','version','fecha','hora','sede','prof']))
  or jsonb_typeof(c->'version') is distinct from 'number' or coalesce(c->>'version','') !~ '^[1-9][0-9]{0,17}$'
  or coalesce(c->>'fecha','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  or coalesce(c->>'hora','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
  or coalesce(length(c->>'sede'),0) not between 1 and 40 or coalesce(length(c->>'prof'),0) not between 1 and 100
  then raise sqlstate '22023' using message='Completá fecha, hora, sede y profesional de todos los turnos.';end if;
  begin d=(c->>'fecha')::date;exception when datetime_field_overflow or invalid_datetime_format then raise sqlstate '22023' using message='Fecha inválida.';end;
  if d not between date '2000-01-01' and date '2100-12-31' then raise sqlstate '22023' using message='La fecha debe estar entre 2000 y 2100.';end if;
  if not exists(select 1 from jsonb_array_elements(selected)x where x->>'id'=c->>'id' and (x->>'version')::bigint=(c->>'version')::bigint)
  then raise sqlstate 'PT409' using message='El turno cambió. Volvé a abrir la reprogramación.';end if;
 end loop;
 with proposed as materialized (
  select x->>'id' id,(x->>'fecha')::date fecha,(x->>'hora')::time hora,x->>'sede' sede,x->>'prof' prof,
   t.terapia_id therapy,t.dni,marathon.session_minutes((x->>'fecha')::date,x->>'sede',x->>'prof',(x->>'hora')::time,a.duracion_min) duration,marathon.master_norm(a.especialidad) spec,x->>'hora' selected_hour
  from jsonb_array_elements(p_data->'changes')x join marathon.turnos t on t.id=x->>'id' join marathon.terapias a on a.id=t.terapia_id
 ), per_turn as (
  select q.id,q.selected_hour,coalesce(jsonb_agg(jsonb_build_object('hora',s.hora,'remaining',s.remaining,'available',s.available,'reason',s.reason,'duration_min',s.duration_min,'end_hour',s.end_hour) order by s.hora) filter(where s.hora is not null),'[]'::jsonb) slots
  from proposed q
  left join lateral (
   with config as (
    select a.*,greatest(a.capacidad,coalesce((select max(b.capacidad) from marathon.terapias b join marathon.profesional_terapias pt on pt.terapia_id=b.id and pt.profesional_id=q.prof
     where b.estado='ACTIVO' and q.spec<>'' and marathon.master_norm(b.especialidad)=q.spec),a.capacidad)) shared
    from marathon.terapias a join marathon.profesional_terapias pt on pt.terapia_id=a.id and pt.profesional_id=q.prof
    join marathon.profesionales p on p.id=q.prof and p.estado='ACTIVO' join marathon.sedes se on se.nombre=q.sede and se.estado='ACTIVO'
    where a.id=q.therapy and a.estado='ACTIVO'
   ), candidates as (
    select distinct (extract(epoch from h.inicio)/60)::int+g.n m,marathon.session_minutes(q.fecha,q.sede,q.prof,time '00:00'+((extract(epoch from h.inicio)/60)::int+g.n)*interval '1 minute',c.duracion_min) actual_duration,c.* from config c
    join marathon.horarios h on h.profesional_id=q.prof and h.sede=q.sede and h.dia=extract(dow from q.fecha)::int
    cross join lateral generate_series(0,(extract(epoch from(h.fin-h.inicio))/60)::int-15,marathon.professional_step(q.prof))g(n)
   ), busy as materialized (
    select t.dni,t.profesional_id prof,t.sede,t.terapia_id therapy,(extract(epoch from t.hora)/60)::int m,marathon.session_minutes(t.fecha,t.sede,t.profesional_id,t.hora,t.duracion_min) duration
    from marathon.turnos t
    where t.fecha=q.fecha and t.estado<>'CANCELADO' and not(t.id=any(ids)) and (t.profesional_id=q.prof or t.dni=q.dni)
    union all
    select p.dni,p.prof,p.sede,p.therapy,(extract(epoch from p.hora)/60)::int,p.duration from proposed p
    where p.id<>q.id and p.fecha=q.fecha and (p.prof=q.prof or p.dni=q.dni)
   )
   select to_char(time '00:00'+c.m*interval '1 minute','HH24:MI') hora,c.actual_duration duration_min,to_char(time '00:00'+(c.m+c.actual_duration)*interval '1 minute','HH24:MI') end_hour,
    case when conflict.blocked then 0 when c.capacidad<=1 then greatest(0,r.remaining) else greatest(1,r.remaining) end remaining,
    not conflict.patient_overlap and not conflict.blocked and (c.capacidad>1 or r.remaining>0) available,
    case when conflict.patient_overlap then 'El paciente tiene otro turno superpuesto.' when conflict.blocked then 'El profesional atiende en otra sede a esa hora.' when r.remaining<1 then 'Sin cupo.' else '' end reason
   from candidates c
   cross join lateral (select
    exists(select 1 from busy b where b.dni=q.dni and b.m<c.m+c.actual_duration and c.m<b.m+b.duration) patient_overlap,
    exists(select 1 from busy b where b.prof=q.prof and b.m<c.m+c.actual_duration and c.m<b.m+b.duration and b.sede<>q.sede) blocked
   ) conflict
   cross join lateral (
    select min(c.capacidad-(select count(*)::int from busy b where b.prof=q.prof and b.therapy=q.therapy and b.m<=cuts.at and cuts.at<b.m+b.duration)) remaining
    from (select c.m at union select b.m from busy b where b.prof=q.prof and b.therapy=q.therapy and b.m>c.m and b.m<c.m+c.actual_duration
     union select b.m+b.duration from busy b where b.prof=q.prof and b.therapy=q.therapy and b.m+b.duration>c.m and b.m+b.duration<c.m+c.actual_duration) cuts
   )r
  )s on true group by q.id,q.selected_hour
 ), evaluated as (
  select id,slots,coalesce((select (x->>'available')::boolean from jsonb_array_elements(slots)x where x->>'hora'=selected_hour),false) ok,
   coalesce((select nullif(x->>'reason','') from jsonb_array_elements(slots)x where x->>'hora'=selected_hour),'Fuera del horario de atención o combinación no habilitada.') reason from per_turn
 )
 select jsonb_build_object('ok',bool_and(ok),'rows',jsonb_agg(jsonb_build_object('id',id,'slots',slots,'ok',ok,'reason',case when ok then '' else reason end) order by id)) into result from evaluated;
 return result;
end $function$;

create or replace function public.marathon_agenda_horario_reagendar(p_request_id text, p_data jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
#variable_conflict use_variable
declare uid uuid:=auth.uid(); req marathon.solicitudes%rowtype; body_hash text;
 hz marathon.agenda_horarios%rowtype; pl marathon.agenda_planes%rowtype;
 new_dia int; new_hora time; new_sede text; new_prof text; ter text; nd date; q jsonb; moved int; reply jsonb;
begin
  if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.'; end if;
  if p_request_id is null or p_request_id !~ '^[a-zA-Z0-9_-]{12,100}$' or p_data is null or jsonb_typeof(p_data)<>'object' then raise sqlstate '22023' using message='Solicitud inválida.'; end if;
  body_hash=encode(sha256(convert_to(p_data::text,'UTF8')),'hex');
  insert into marathon.solicitudes(id,usuario_id,tipo,payload_hash) values(p_request_id,uid,'agenda:reagendar',body_hash) on conflict on constraint solicitudes_pkey do nothing;
  select * into req from marathon.solicitudes requests where requests.id=p_request_id for update;
  if req.id is null or req.usuario_id<>uid or req.tipo<>'agenda:reagendar' or req.payload_hash<>body_hash then raise sqlstate '22023' using message='Identificador de solicitud utilizado con otros datos.'; end if;
  if req.resultado is not null then return req.resultado; end if;
  perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
  select * into hz from marathon.agenda_horarios where id=(p_data->>'horario_id')::uuid;
  if hz.id is null then raise sqlstate '22023' using message='El horario no existe.'; end if;
  select * into pl from marathon.agenda_planes where id=hz.plan_id;
  new_sede=coalesce(nullif(p_data->>'sede',''),hz.sede);
  new_prof=coalesce(nullif(p_data->>'prof',''),hz.profesional_id);
  new_dia=coalesce((p_data->>'day')::int,hz.dia);
  new_hora=coalesce(nullif(p_data->>'time','')::time,hz.hora);
  if new_dia not between 0 and 6 then raise sqlstate '22023' using message='Día inválido.'; end if;
  ter=coalesce(hz.terapia_override,pl.terapia_id);
  nd=(current_date + ((new_dia - extract(dow from current_date)::int + 7) % 7))::date;
  q=marathon.agenda_cupo(nd,new_sede,new_prof,ter,new_hora,hz.plan_id);
  if coalesce((q->>'blocked')::boolean,true) or (coalesce((q->>'capacity')::int,1)<=1 and coalesce((q->>'remaining')::int,0)<1) then
    raise sqlstate '22023' using message='El horario elegido no está habilitado o no tiene cupo.'; end if;
  update marathon.agenda_horarios set sede=new_sede, profesional_id=new_prof, dia=new_dia, hora=new_hora where id=hz.id;
  delete from marathon.turnos t where t.horario_id=hz.id and t.estado='PENDIENTE' and t.fecha>=current_date;
  get diagnostics moved = row_count;
  perform marathon.agenda_materializar(current_date, current_date+27);
  reply=jsonb_build_object('message','Horario reagendado.','reproyectados',moved);
  update marathon.solicitudes set resultado=reply where solicitudes.id=p_request_id; return reply;
end $function$;

create or replace function marathon.excepcion_run(p_request_id text, p_data jsonb)
 returns jsonb
 language plpgsql
 set search_path to ''
 set lock_timeout to '5s'
as $function$
declare reply jsonb;d date;site text;prof text;therapy text;person text;at_hour time;duration integer;cost numeric;cov jsonb;memo text;tid text;old marathon.turnos%rowtype;after_row jsonb;begin
 reply=marathon.operation_begin(p_request_id,'agenda:excepcion',p_data);if reply is not null then return reply;end if;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['date','site','prof','therapy','dni','time','amount','coverage','notes','id','version']))then raise exception 'La atención excepcional permite un único turno.'using errcode='22023';end if;
 d=marathon.agenda_date(p_data->>'date');site=marathon.master_text(p_data,'site',40,true);prof=marathon.master_text(p_data,'prof',100,true);therapy=marathon.master_text(p_data,'therapy',100,true);person=marathon.master_text(p_data,'dni',12,true);
 if d>marathon.agenda_hoy()+366 then raise exception 'Elegí una fecha hasta un año en adelante.'using errcode='22023';end if;
 if person!~'^[0-9]{1,12}$'or not exists(select 1 from marathon.pacientes where dni=person)then raise exception 'Seleccioná un paciente registrado.'using errcode='22023';end if;
 if coalesce(p_data->>'time','')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$'or jsonb_typeof(p_data->'amount')is distinct from'number'or coalesce(p_data->>'amount','')!~'^[0-9]{1,10}(\.[0-9]{1,2})?$'then raise exception 'Revisá la hora y el importe de la sesión.'using errcode='22023';end if;
 at_hour=(p_data->>'time')::time;cost=(p_data->>'amount')::numeric;
 select duracion_min into duration from marathon.terapias where id=therapy and estado='ACTIVO';
 if duration is null then raise exception 'Seleccioná una terapia activa.'using errcode='22023';end if;
 cov=marathon.normalize_turn_coverage(person,p_data->'coverage');memo=coalesce(marathon.master_text(p_data,'notes',1000),'');
 if nullif(p_data->>'id','')is not null then
  select *into old from marathon.turnos where id=p_data->>'id'for update;
  if old.id is null or not coalesce(old.excepcional,false)or old.estado<>'PENDIENTE'or old.dni<>person or old.version<>marathon.operation_version(p_data)then raise exception 'El turno cambió. Volvé a abrir su edición.'using errcode='PT409';end if;
  if marathon.turn_paid(old.id)>0 then raise exception 'El turno tiene pagos aplicados. Revisalos antes de editar.'using errcode='22023';end if;
  tid=old.id;
 else tid='TUR-'||gen_random_uuid()::text;end if;
 if exists(select 1 from marathon.agenda_pool(d)x where x.dni=person and x.id<>tid and x.hora<at_hour+make_interval(mins=>duration)and at_hour<x.hora+make_interval(mins=>x.duracion_min))then raise exception 'El paciente ya tiene una atención o reserva que se superpone.'using errcode='PT409';end if;
 reply=marathon.excepcion_cupo(d,site,prof,therapy,at_hour,duration,tid);
 if coalesce((reply->>'blocked')::boolean,true)or(coalesce((reply->>'capacity')::int,1)<=1 and coalesce((reply->>'remaining')::int,0)<1) then raise exception 'El profesional no está habilitado para esa terapia o tiene una atención incompatible en ese horario.'using errcode='PT409';end if;
 if memo not like 'Atención excepcional%'then memo='Atención excepcional'||case when memo=''then''else E'\n'||memo end;end if;
 if old.id is null then
  insert into marathon.turnos(id,fecha,sede,hora,duracion_min,terapia_id,profesional_id,dni,importe,estado,coverage,observaciones,booking_notes,excepcional,attendance_manual_date,created_by,updated_by)
  values(tid,d,site,at_hour,duration,therapy,prof,person,cost,'PENDIENTE',cov,memo,memo,true,case when d<marathon.agenda_hoy()then d end,auth.uid(),auth.uid());
 else
  update marathon.turnos set fecha=d,sede=site,hora=at_hour,duracion_min=duration,terapia_id=therapy,profesional_id=prof,importe=cost,coverage=cov,booking_notes=memo,attendance_manual_date=case when d<marathon.agenda_hoy()then d end where id=tid;
 end if;
 select to_jsonb(t)into after_row from marathon.turnos t where id=tid;
 insert into marathon.turn_audit(request_id,actor,turn_id,action,before_data,after_data)values(p_request_id,auth.uid(),tid,case when old.id is null then'book_exception'else'edit_exception'end,case when old.id is null then null else to_jsonb(old)end,after_row);
 reply=jsonb_build_object('ids',jsonb_build_array(tid),'exceptional',true,'turn',after_row,'message',case when old.id is null then'Atención excepcional reservada. Se conservó el horario habitual.'else'Atención excepcional actualizada.'end);
 update marathon.solicitudes set resultado=reply where id=p_request_id;return reply;
end$function$;

create or replace function marathon.turn_series_run(p_request_id text, p_data jsonb)
 returns jsonb
 language plpgsql
 set search_path to ''
 set lock_timeout to '5s'
as $function$
declare result jsonb;info jsonb;t marathon.turnos%rowtype;member marathon.turnos%rowtype;rule marathon.agenda_horarios%rowtype;
 p marathon.agenda_planes%rowtype;before_plan jsonb;changes jsonb;maps jsonb:='{}';ids text[];kind text;scope text;reason text;delta int;new_date date;new_hour time;site text;prof text;new_rule uuid;
 d date;candidate record;occ record;slot jsonb;duration int;count_changed int:=0;after_row jsonb;config jsonb;schedules jsonb;fee numeric;cov jsonb;memo text;qrow marathon.agenda_cuotas%rowtype;quotes_changed int:=0;quotes_kept int:=0;new_therapy text;therapy_minutes int;
begin
 result=marathon.operation_begin(p_request_id,'turn-series',p_data);if result is not null then return result;end if;
 if p_data is null or jsonb_typeof(p_data)<>'object'or exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['id','action','scope','huella','date','time','site','prof','reason','schedules','amount','coverage','notes','therapy']))then raise exception 'Solicitud inválida.'using errcode='22023';end if;
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
 select p_request_id,auth.uid(),'agenda-plan',t.plan_id::text,'turn_series_'||kind,before_plan,to_jsonb(x)||jsonb_build_object('motivo',reason,'desde',t.fecha,'horarios',maps)from marathon.agenda_planes x where x.id=t.plan_id;
 else insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,after_data)values(p_request_id,auth.uid(),'turn',t.id,'turn_series_'||kind,jsonb_build_object('desde',t.fecha,'alcance',scope,'motivo',reason));end if;
 result=jsonb_build_object('ids',ids,'count',count_changed,'recurring',t.plan_id is not null and scope='following','cuotas_actualizadas',quotes_changed,'cuotas_conservadas',quotes_kept,'message',case when kind='cancel'then count_changed||' turno(s) cancelados.'else count_changed||' turno(s) editados.'end||case when t.plan_id is not null and scope='following'then case when kind='cancel'then' La asignación quedó dada de baja desde la fecha elegida.'else' Se actualizó también la repetición futura.'end else''end||case when quotes_changed>0 then' Se actualizó la cuota sin pagos.'else''end||case when quotes_kept>0 then' Las cuotas con pagos o ajustes conservaron su importe; el nuevo valor se aplica a las próximas.'else''end);
 update marathon.solicitudes set resultado=result where id=p_request_id;return result;
end$function$;
