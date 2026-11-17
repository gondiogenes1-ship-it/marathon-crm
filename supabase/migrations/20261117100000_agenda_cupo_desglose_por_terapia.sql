-- Agenda: desglosar por terapia el contador "Profesional (X/Y)" que se ve
-- al armar una reserva. Antes ese numero mezclaba turnos de terapias
-- distintas (ej. Convencional y Ondas de choque) contra la capacidad de
-- una sola terapia, lo que generaba numeros confusos tipo "3/1" sin decir
-- de donde salian esos 3 turnos.
--
-- Ahora marathon.agenda_cupo devuelve ademas 'by_therapy': un arreglo con
-- la cantidad de turnos superpuestos de CADA terapia que tiene el
-- profesional en esa franja, junto a la capacidad propia de esa terapia.
-- Aditivo: no cambia ninguna clave existente del jsonb que ya devuelve, asi
-- que no rompe a ningun llamador actual (marathon_agenda_slots,
-- marathon_agenda_grilla, marathon_agenda_plan_command, etc.).
create or replace function marathon.agenda_cupo(d date, site text, prof text, therapy text, at_hour time without time zone, exclude_plan uuid DEFAULT NULL::uuid, exclude_turn text DEFAULT NULL::text)
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
 with pool as materialized(select a.*,marathon.master_norm(t.especialidad) spec from marathon.agenda_pool(d)a join marathon.terapias t on t.id=a.terapia_id where a.profesional_id=prof and (exclude_plan is null or a.plan_id is distinct from exclude_plan) and(exclude_turn is null or a.id<>exclude_turn))
 select exists(select 1 from pool a where a.hora<at_hour+make_interval(mins=>dur) and at_hour<a.hora+make_interval(mins=>a.duracion_min) and(a.sede<>site or not(a.terapia_id=therapy or(spec<>'' and a.spec=spec)))),
 coalesce(min(least(cap-(select count(*)::int from pool a where a.terapia_id=therapy and a.hora<=cut.at and cut.at<a.hora+make_interval(mins=>a.duracion_min)),shared_cap-(select count(*)::int from pool a where a.hora<=cut.at and cut.at<a.hora+make_interval(mins=>a.duracion_min)))),cap)
 into no,left_over from (select at_hour at union select a.hora from pool a where a.hora>at_hour and a.hora<at_hour+make_interval(mins=>dur))cut;
 select count(*)::int into own from marathon.agenda_pool(d)a where a.profesional_id=prof and (exclude_plan is null or a.plan_id is distinct from exclude_plan) and(exclude_turn is null or a.id<>exclude_turn) and a.hora<at_hour+make_interval(mins=>dur) and at_hour<a.hora+make_interval(mins=>a.duracion_min);
 select coalesce(jsonb_agg(jsonb_build_object('therapy',x.terapia_id,'label',th.nombre,'count',x.count,'capacity',th.capacidad)order by th.nombre),'[]'::jsonb)
 into by_therapy
 from(select a.terapia_id,count(*)::int count from marathon.agenda_pool(d)a where a.profesional_id=prof and (exclude_plan is null or a.plan_id is distinct from exclude_plan) and(exclude_turn is null or a.id<>exclude_turn) and a.hora<at_hour+make_interval(mins=>dur) and at_hour<a.hora+make_interval(mins=>a.duracion_min) group by a.terapia_id)x
 join marathon.terapias th on th.id=x.terapia_id;
 with pool as materialized(select a.* from marathon.agenda_pool(d)a join marathon.shared_space_therapies g on g.therapy_id=a.terapia_id where a.sede=site and a.estado in('PENDIENTE','PRESENTE') and not a.pausado and (exclude_plan is null or a.plan_id is distinct from exclude_plan) and(exclude_turn is null or a.id<>exclude_turn))
 select coalesce(max((select count(distinct a.dni)::int from pool a where a.hora<=cut.at and cut.at<a.hora+make_interval(mins=>a.duracion_min))),0) into people from(select at_hour at union select a.hora from pool a where a.hora>at_hour and a.hora<at_hour+make_interval(mins=>dur))cut;
 return jsonb_build_object('hora',to_char(at_hour,'HH24:MI'),'remaining',case when no then 0 else greatest(0,left_over) end,'capacity',cap,'shared_capacity',shared_cap,'blocked',no,'professional_count',own,'by_therapy',by_therapy,'shared_space_count',people,'duration_min',dur,'end_hour',to_char(at_hour+make_interval(mins=>dur),'HH24:MI'));
end$function$;
