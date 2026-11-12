-- Panel "Horarios a revisar" + validación al cambiar la disponibilidad del profesional.
-- Disponible para ADMIN y SECRETARIA (guarda active_user(), no role='ADMIN').
--
-- Objetos:
--   marathon_agenda_horarios_revision()            -> lista de horarios que hoy no materializan
--   marathon_agenda_horario_reagendar(req,data)    -> mueve un horario (sede/prof/día/hora) + reproyecta
--   marathon_agenda_horario_eliminar(req,data)     -> da de baja un horario (hasta=hoy) y limpia pendientes
--   marathon_profesional_horarios_conflicto(prof)  -> planes que quedarían huérfanos para ese profesional (aviso #2)

-- 1) LISTA ----------------------------------------------------------------
create or replace function public.marathon_agenda_horarios_revision()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;
begin
  if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.'; end if;
  with s as (
    select ah.id horario_id, ah.plan_id, ah.sede, ah.profesional_id, ah.dia, ah.hora,
           p.dni, coalesce(ah.terapia_override,p.terapia_id) terapia_id, p.modalidad,
           (current_date + ((ah.dia - extract(dow from current_date)::int + 7) % 7))::date nd
    from marathon.agenda_horarios ah
    join marathon.agenda_planes p on p.id=ah.plan_id
    where (ah.hasta is null or ah.hasta>current_date) and (p.baja is null or p.baja>current_date)
  ),
  c as (select s.*, marathon.agenda_cupo(s.nd,s.sede,s.profesional_id,s.terapia_id,s.hora,s.plan_id) q from s)
  select coalesce(jsonb_agg(jsonb_build_object(
    'horario_id',c.horario_id,'plan_id',c.plan_id,'dni',c.dni,
    'paciente',btrim(concat_ws(' ',pa.apellido||',',pa.nombre,nullif(pa.segundo_nombre,''))),
    'profesional',btrim(concat_ws(' ',pr.nombre,nullif(pr.segundo_nombre,''),pr.apellido)),
    'sede',c.sede,'dia',c.dia,'hora',to_char(c.hora,'HH24:MI'),'terapia',te.nombre,'modalidad',c.modalidad,
    'blocked',(c.q->>'blocked')::boolean,'remaining',(c.q->>'remaining')::int,
    'pendientes',(select count(*) from marathon.turnos t where t.horario_id=c.horario_id and t.estado='PENDIENTE' and t.fecha>=current_date)
  ) order by pr.apellido, c.dia, c.hora),'[]'::jsonb)
  into rows
  from c
  join marathon.pacientes pa on pa.dni=c.dni
  join marathon.profesionales pr on pr.id=c.profesional_id
  join marathon.terapias te on te.id=c.terapia_id
  where (c.q->>'blocked')::boolean or coalesce((c.q->>'remaining')::int,0)<1;
  return jsonb_build_object('rows',rows,'generated_at',statement_timestamp());
end $$;
revoke all on function public.marathon_agenda_horarios_revision() from public,anon;
grant execute on function public.marathon_agenda_horarios_revision() to authenticated;

-- 2) REAGENDAR ------------------------------------------------------------
create or replace function public.marathon_agenda_horario_reagendar(p_request_id text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
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
  if coalesce((q->>'remaining')::int,0)<1 or coalesce((q->>'blocked')::boolean,true) then
    raise sqlstate '22023' using message='El horario elegido no está habilitado o no tiene cupo.'; end if;
  update marathon.agenda_horarios set sede=new_sede, profesional_id=new_prof, dia=new_dia, hora=new_hora where id=hz.id;
  delete from marathon.turnos t where t.horario_id=hz.id and t.estado='PENDIENTE' and t.fecha>=current_date;
  get diagnostics moved = row_count;
  perform marathon.agenda_materializar(current_date, current_date+27);
  reply=jsonb_build_object('message','Horario reagendado.','reproyectados',moved);
  update marathon.solicitudes set resultado=reply where solicitudes.id=p_request_id; return reply;
end $$;
revoke all on function public.marathon_agenda_horario_reagendar(text,jsonb) from public,anon;
grant execute on function public.marathon_agenda_horario_reagendar(text,jsonb) to authenticated;

-- 3) ELIMINAR (dar de baja el horario) ------------------------------------
create or replace function public.marathon_agenda_horario_eliminar(p_request_id text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare uid uuid:=auth.uid(); req marathon.solicitudes%rowtype; body_hash text; hz marathon.agenda_horarios%rowtype; removed int; reply jsonb;
begin
  if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.'; end if;
  if p_request_id is null or p_request_id !~ '^[a-zA-Z0-9_-]{12,100}$' or p_data is null or jsonb_typeof(p_data)<>'object' then raise sqlstate '22023' using message='Solicitud inválida.'; end if;
  body_hash=encode(sha256(convert_to(p_data::text,'UTF8')),'hex');
  insert into marathon.solicitudes(id,usuario_id,tipo,payload_hash) values(p_request_id,uid,'agenda:horario-baja',body_hash) on conflict on constraint solicitudes_pkey do nothing;
  select * into req from marathon.solicitudes requests where requests.id=p_request_id for update;
  if req.id is null or req.usuario_id<>uid or req.tipo<>'agenda:horario-baja' or req.payload_hash<>body_hash then raise sqlstate '22023' using message='Identificador de solicitud utilizado con otros datos.'; end if;
  if req.resultado is not null then return req.resultado; end if;
  perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
  select * into hz from marathon.agenda_horarios where id=(p_data->>'horario_id')::uuid;
  if hz.id is null then raise sqlstate '22023' using message='El horario no existe.'; end if;
  update marathon.agenda_horarios set hasta=current_date where id=hz.id;
  delete from marathon.turnos t where t.horario_id=hz.id and t.estado='PENDIENTE' and t.fecha>=current_date;
  get diagnostics removed = row_count;
  reply=jsonb_build_object('message','Horario dado de baja.','turnos_eliminados',removed);
  update marathon.solicitudes set resultado=reply where solicitudes.id=p_request_id; return reply;
end $$;
revoke all on function public.marathon_agenda_horario_eliminar(text,jsonb) from public,anon;
grant execute on function public.marathon_agenda_horario_eliminar(text,jsonb) to authenticated;

-- 4) AVISO #2: planes que quedarían huérfanos para un profesional ---------
create or replace function public.marathon_profesional_horarios_conflicto(p_prof text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;
begin
  if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.'; end if;
  with s as (
    select ah.id horario_id, ah.plan_id, ah.dia, ah.hora, ah.sede, p.dni,
           coalesce(ah.terapia_override,p.terapia_id) ter,
           (current_date + ((ah.dia - extract(dow from current_date)::int + 7) % 7))::date nd
    from marathon.agenda_horarios ah join marathon.agenda_planes p on p.id=ah.plan_id
    where ah.profesional_id=p_prof and (ah.hasta is null or ah.hasta>current_date) and (p.baja is null or p.baja>current_date)
  ),
  c as (select s.*, marathon.agenda_cupo(s.nd,s.sede,p_prof,s.ter,s.hora,s.plan_id) q from s)
  select coalesce(jsonb_agg(jsonb_build_object(
    'dni',c.dni,'paciente',btrim(concat_ws(' ',pa.apellido||',',pa.nombre,nullif(pa.segundo_nombre,''))),
    'dia',c.dia,'hora',to_char(c.hora,'HH24:MI')) order by c.dia,c.hora),'[]'::jsonb)
  into rows from c join marathon.pacientes pa on pa.dni=c.dni
  where (c.q->>'blocked')::boolean or coalesce((c.q->>'remaining')::int,0)<1;
  return jsonb_build_object('rows',rows);
end $$;
revoke all on function public.marathon_profesional_horarios_conflicto(text) from public,anon;
grant execute on function public.marathon_profesional_horarios_conflicto(text) to authenticated;
