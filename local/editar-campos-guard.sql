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
