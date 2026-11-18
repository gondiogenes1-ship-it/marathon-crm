-- Cupo de agenda: pasa a calcularse SIEMPRE por terapia, de forma
-- independiente entre terapias del mismo profesional, en vez de agrupar
-- por "especialidad" en un pool compartido.
--
-- Antes: terapias que comparten especialidad (ej. Ondas de choque,
-- Evaluacion clinica, Biobit y Convencional, todas "Kinesiologia" para un
-- profesional) competian por un cupo combinado con techo igual a la mayor
-- capacidad entre ellas. Eso podia bloquear una terapia 1 a 1 (ej. Ondas
-- de choque) solo porque el grupo de Convencional del mismo profesional
-- estaba lleno, aunque fueran atenciones independientes.
--
-- Ahora: el cupo de cada terapia se calcula solo contra turnos de esa
-- misma terapia superpuestos (mismo profesional). Lo unico que sigue
-- bloqueando entre terapias distintas es una sede distinta (no se puede
-- estar en dos sedes a la vez).
--
-- Ademas, el bloqueo DURO por falta de cupo solo aplica a terapias con
-- capacidad 1 (atencion individual, imposibilidad real). Las terapias con
-- capacidad mayor a 1 (grupales) nunca bloquean por cupo: la capacidad
-- configurada queda solo como informacion para el profesional/secretaria.
-- Esto ya regia para crear una serie (Modalidad de agenda); ahora tambien
-- rige para cualquier turno individual, vía el trigger que valida cada
-- inserción/edición de turno.
create or replace function marathon.agenda_cupo(d date, site text, prof text, therapy text, at_hour time without time zone, exclude_plan uuid default null::uuid, exclude_turn text default null::text)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
#variable_conflict use_variable
declare cap int;shared_cap int;dur int;spec text;left_over int;no boolean;people int;own int;by_therapy jsonb;begin
 select t.capacidad,t.duracion_min,marathon.master_norm(t.especialidad) into cap,dur,spec from marathon.terapias t
 join marathon.profesional_terapias pt on pt.terapia_id=t.id and pt.profesional_id=prof
 join marathon.profesionales p on p.id=prof and p.estado='ACTIVO'
 join marathon.sedes s on s.nombre=site and s.estado='ACTIVO' where t.id=therapy and t.estado='ACTIVO';
 if cap is null or not exists(select 1 from marathon.horarios h where h.profesional_id=prof and h.sede=site and h.dia=extract(dow from d)::int and at_hour>=h.inicio and at_hour+interval '15 minutes'<=h.fin and (extract(epoch from(at_hour-h.inicio))/60)::int%marathon.professional_step(prof)=0)then return jsonb_build_object('remaining',0,'capacity',coalesce(cap,0),'blocked',true);end if;
 dur=marathon.session_minutes(d,site,prof,at_hour,dur);
 select greatest(cap,coalesce(max(t.capacidad),cap)) into shared_cap from marathon.terapias t join marathon.profesional_terapias pt on pt.terapia_id=t.id and pt.profesional_id=prof where t.estado='ACTIVO' and spec<>'' and marathon.master_norm(t.especialidad)=spec;
 with pool as materialized(select a.* from marathon.agenda_pool(d)a where a.profesional_id=prof and (exclude_plan is null or a.plan_id is distinct from exclude_plan) and(exclude_turn is null or a.id<>exclude_turn))
 select exists(select 1 from pool a where a.hora<at_hour+make_interval(mins=>dur) and at_hour<a.hora+make_interval(mins=>a.duracion_min) and a.sede<>site),
 coalesce(min(cap-(select count(*)::int from pool a where a.terapia_id=therapy and a.hora<=cut.at and cut.at<a.hora+make_interval(mins=>a.duracion_min))),cap)
 into no,left_over from (select at_hour at union select a.hora from pool a where a.hora>at_hour and a.hora<at_hour+make_interval(mins=>dur))cut;
 select count(*)::int into own from marathon.agenda_pool(d)a where a.profesional_id=prof and a.terapia_id=therapy and (exclude_plan is null or a.plan_id is distinct from exclude_plan) and(exclude_turn is null or a.id<>exclude_turn) and a.hora<at_hour+make_interval(mins=>dur) and at_hour<a.hora+make_interval(mins=>a.duracion_min);
 select coalesce(jsonb_agg(jsonb_build_object('therapy',th.id,'label',th.nombre,'count',coalesce(x.count,0),'capacity',th.capacidad)order by th.nombre),'[]'::jsonb)
 into by_therapy
 from marathon.profesional_terapias pt
 join marathon.terapias th on th.id=pt.terapia_id and th.estado='ACTIVO'
 left join(select a.terapia_id,count(*)::int count from marathon.agenda_pool(d)a where a.profesional_id=prof and (exclude_plan is null or a.plan_id is distinct from exclude_plan) and(exclude_turn is null or a.id<>exclude_turn) and a.hora<at_hour+make_interval(mins=>dur) and at_hour<a.hora+make_interval(mins=>a.duracion_min) group by a.terapia_id)x on x.terapia_id=th.id
 where pt.profesional_id=prof;
 with pool as materialized(select a.* from marathon.agenda_pool(d)a join marathon.shared_space_therapies g on g.therapy_id=a.terapia_id where a.sede=site and a.estado in('PENDIENTE','PRESENTE') and not a.pausado and (exclude_plan is null or a.plan_id is distinct from exclude_plan) and(exclude_turn is null or a.id<>exclude_turn))
 select coalesce(max((select count(distinct a.dni)::int from pool a where a.hora<=cut.at and cut.at<a.hora+make_interval(mins=>a.duracion_min))),0) into people from(select at_hour at union select a.hora from pool a where a.hora>at_hour and a.hora<at_hour+make_interval(mins=>dur))cut;
 return jsonb_build_object('hora',to_char(at_hour,'HH24:MI'),'remaining',case when no then 0 else greatest(0,left_over) end,'capacity',cap,'shared_capacity',shared_cap,'blocked',no,'professional_count',own,'by_therapy',by_therapy,'shared_space_count',people,'duration_min',dur,'end_hour',to_char(at_hour+make_interval(mins=>dur),'HH24:MI'));
end$function$;

create or replace function marathon.excepcion_cupo(d date, site text, prof text, therapy text, at_hour time without time zone, requested integer, exclude_turn text default null::text)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
#variable_conflict use_variable
declare exclude_plan uuid:=null;cap int;shared_cap int;dur int;spec text;left_over int;no boolean;people int;own int;begin
 select t.capacidad,t.duracion_min,marathon.master_norm(t.especialidad) into cap,dur,spec from marathon.terapias t
 join marathon.profesional_terapias pt on pt.terapia_id=t.id and pt.profesional_id=prof
 join marathon.profesionales p on p.id=prof and p.estado='ACTIVO'
 join marathon.sedes s on s.nombre=site and s.estado='ACTIVO' where t.id=therapy and t.estado='ACTIVO';
 if cap is null or requested is null or requested<=0 or extract(epoch from at_hour)/60+requested>1440 then return jsonb_build_object('remaining',0,'capacity',coalesce(cap,0),'blocked',true);end if;
 dur=requested;
 select greatest(cap,coalesce(max(t.capacidad),cap)) into shared_cap from marathon.terapias t join marathon.profesional_terapias pt on pt.terapia_id=t.id and pt.profesional_id=prof where t.estado='ACTIVO' and spec<>'' and marathon.master_norm(t.especialidad)=spec;
 with pool as materialized(select a.* from marathon.agenda_pool(d)a where a.profesional_id=prof and (exclude_plan is null or a.plan_id is distinct from exclude_plan) and(exclude_turn is null or a.id<>exclude_turn))
 select exists(select 1 from pool a where a.hora<at_hour+make_interval(mins=>dur) and at_hour<a.hora+make_interval(mins=>a.duracion_min) and a.sede<>site),
 coalesce(min(cap-(select count(*)::int from pool a where a.terapia_id=therapy and a.hora<=cut.at and cut.at<a.hora+make_interval(mins=>a.duracion_min))),cap)
 into no,left_over from (select at_hour at union select a.hora from pool a where a.hora>at_hour and a.hora<at_hour+make_interval(mins=>dur))cut;
 select count(*)::int into own from marathon.agenda_pool(d)a where a.profesional_id=prof and a.terapia_id=therapy and (exclude_plan is null or a.plan_id is distinct from exclude_plan) and(exclude_turn is null or a.id<>exclude_turn) and a.hora<at_hour+make_interval(mins=>dur) and at_hour<a.hora+make_interval(mins=>a.duracion_min);
 with pool as materialized(select a.* from marathon.agenda_pool(d)a join marathon.shared_space_therapies g on g.therapy_id=a.terapia_id where a.sede=site and a.estado in('PENDIENTE','PRESENTE') and not a.pausado and (exclude_plan is null or a.plan_id is distinct from exclude_plan) and(exclude_turn is null or a.id<>exclude_turn))
 select coalesce(max((select count(distinct a.dni)::int from pool a where a.hora<=cut.at and cut.at<a.hora+make_interval(mins=>a.duracion_min))),0) into people from(select at_hour at union select a.hora from pool a where a.hora>at_hour and a.hora<at_hour+make_interval(mins=>dur))cut;
 return jsonb_build_object('hora',to_char(at_hour,'HH24:MI'),'remaining',case when no then 0 else greatest(0,left_over) end,'capacity',cap,'shared_capacity',shared_cap,'blocked',no,'professional_count',own,'shared_space_count',people,'duration_min',dur,'end_hour',to_char(at_hour+make_interval(mins=>dur),'HH24:MI'));
end$function$;

create or replace function marathon.agenda_turno_guard()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
declare p marathon.agenda_planes%rowtype;q jsonb;a uuid;begin
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
 if new.excepcional and(new.plan_id is not null or new.original_id is not null or new.fixed_until is not null or new.series_pattern is not null)then raise exception 'La atención excepcional corresponde a un único turno.'using errcode='22023';end if;
 if tg_op='UPDATE'and new.excepcional is distinct from old.excepcional then raise exception 'No se puede cambiar el tipo de una reserva existente.'using errcode='22023';end if;
 if tg_op='INSERT' and new.recovered_from is not null and new.plan_id is null then
  select t.plan_id,t.terapia_override into new.plan_id,new.terapia_override from marathon.turnos t where t.id=new.recovered_from;
  if new.plan_id is not null then new.fecha_habitual=new.fecha;end if;
 end if;
 if new.plan_id is not null then
  select * into strict p from marathon.agenda_planes where id=new.plan_id for update;
  if new.dni<>p.dni or new.terapia_id<>coalesce(new.terapia_override,(select h.terapia_override from marathon.agenda_horarios h where h.id=new.horario_id and h.plan_id=p.id),p.terapia_id) then raise sqlstate '22023' using message='El turno no corresponde al tratamiento.';end if;
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
  if new.excepcional then q=marathon.excepcion_cupo(new.fecha,new.sede,new.profesional_id,new.terapia_id,new.hora,new.duracion_min,new.id);
  else q=marathon.agenda_cupo(new.fecha,new.sede,new.profesional_id,new.terapia_id,new.hora,new.plan_id,new.id);end if;
  if coalesce((q->>'blocked')::boolean,true) or (coalesce((q->>'capacity')::int,1)<=1 and coalesce((q->>'remaining')::int,0)<1) then raise sqlstate '22023' using message='El horario no tiene cupo o dejó de estar habilitado.';end if;
 end if;return new;
end$function$;
