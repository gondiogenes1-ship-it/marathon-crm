-- Horarios a revisar: ademas de los horarios con un problema estructural
-- (profesional/sede inactivos, terapia no asignada, o el profesional ya no
-- atiende ese dia/hora), ahora tambien detecta horarios con un turno que
-- debia generarse hasta hoy y nunca se pudo crear (por ejemplo, un cruce de
-- horarios que quedo sin resolver). Se reutiliza el mismo "Dar de baja" ya
-- existente en el panel para sacarlos de circulacion.
create or replace function public.marathon_agenda_horarios_revision()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare rows jsonb;
begin
  if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.'; end if;
  with bad as (
    select ah.id horario_id, ah.plan_id, ah.sede, ah.profesional_id, ah.dia, ah.hora,
           p.dni, coalesce(ah.terapia_override,p.terapia_id) terapia_id, p.modalidad,
           case
             when not exists(select 1 from marathon.profesionales pr where pr.id=ah.profesional_id and pr.estado='ACTIVO') then 'Profesional inactivo'
             when not exists(select 1 from marathon.sedes s where s.nombre=ah.sede and s.estado='ACTIVO') then 'Sede inactiva'
             when not exists(select 1 from marathon.profesional_terapias pt where pt.profesional_id=ah.profesional_id and pt.terapia_id=coalesce(ah.terapia_override,p.terapia_id)) then 'La terapia no está asignada al profesional'
             else 'El profesional no atiende ese día u horario'
           end motivo
    from marathon.agenda_horarios ah
    join marathon.agenda_planes p on p.id=ah.plan_id
    where (ah.hasta is null or ah.hasta>current_date) and (p.baja is null or p.baja>current_date)
      and (
        not exists(select 1 from marathon.horarios h where h.profesional_id=ah.profesional_id and h.sede=ah.sede and h.dia=ah.dia and ah.hora>=h.inicio and ah.hora+interval '15 minutes'<=h.fin and (extract(epoch from(ah.hora-h.inicio))/60)::int % marathon.professional_step(ah.profesional_id)=0)
        or not exists(select 1 from marathon.profesionales pr where pr.id=ah.profesional_id and pr.estado='ACTIVO')
        or not exists(select 1 from marathon.sedes s where s.nombre=ah.sede and s.estado='ACTIVO')
        or not exists(select 1 from marathon.profesional_terapias pt where pt.profesional_id=ah.profesional_id and pt.terapia_id=coalesce(ah.terapia_override,p.terapia_id))
      )
    union all
    select ah.id, ah.plan_id, ah.sede, ah.profesional_id, ah.dia, ah.hora,
           p.dni, coalesce(ah.terapia_override,p.terapia_id), p.modalidad,
           'No se pudo generar el turno del '||to_char(stuck.fecha,'DD/MM/YYYY')||' (revisá un cruce de horarios).'
    from marathon.agenda_horarios ah
    join marathon.agenda_planes p on p.id=ah.plan_id
    join lateral(
      select min(gs::date) fecha
      from generate_series(greatest(ah.desde,p.inicio,current_date-60),current_date,interval '1 day')gs
      where extract(dow from gs)::int=ah.dia
        and(ah.hasta is null or gs::date<ah.hasta)
        and(p.baja is null or gs::date<p.baja)
        and(p.modalidad<>'sessions' or marathon.agenda_presentes(p.id)<marathon.agenda_total(p.id))
        and not exists(select 1 from marathon.turnos t where t.horario_id=ah.id and t.fecha_habitual=gs::date)
    )stuck on stuck.fecha is not null
    where (ah.hasta is null or ah.hasta>current_date) and (p.baja is null or p.baja>current_date)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'horario_id',b.horario_id,'plan_id',b.plan_id,'dni',b.dni,
    'paciente',btrim(concat_ws(' ',pa.apellido||',',pa.nombre,nullif(pa.segundo_nombre,''))),
    'profesional',btrim(concat_ws(' ',pr.nombre,nullif(pr.segundo_nombre,''),pr.apellido)),
    'sede',b.sede,'dia',b.dia,'hora',to_char(b.hora,'HH24:MI'),'terapia',te.nombre,'modalidad',b.modalidad,
    'blocked',true,
    'motivo',b.motivo,
    'pendientes',(select count(*) from marathon.turnos t where t.horario_id=b.horario_id and t.estado='PENDIENTE' and t.fecha>=current_date)
  ) order by pr.apellido, b.dia, b.hora),'[]'::jsonb)
  into rows
  from bad b
  join marathon.pacientes pa on pa.dni=b.dni
  join marathon.profesionales pr on pr.id=b.profesional_id
  join marathon.terapias te on te.id=b.terapia_id;
  return jsonb_build_object('rows',rows,'generated_at',statement_timestamp());
end $function$;
