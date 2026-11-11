CREATE OR REPLACE FUNCTION marathon.agenda_materializar(d date, e date)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v record;n int:=0;root text;begin
 if e<d or e-d>31 then raise sqlstate '22023' using message='Consultá hasta 32 días.';end if;
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
 for v in select virtual_row.*,dt::date fecha from generate_series(d,e,interval '1 day')dt cross join lateral marathon.agenda_virtual(dt::date)virtual_row order by dt,virtual_row.hora,virtual_row.id loop
  select t.id into root from marathon.turnos t where t.plan_id=v.plan_id order by t.created_at,t.id limit 1;
  insert into marathon.turnos(id,original_id,fecha,sede,hora,duracion_min,terapia_id,profesional_id,dni,importe,estado,coverage,booking_notes,plan_id,horario_id,fecha_habitual,created_by,updated_by)
  select 'TUR-'||gen_random_uuid()::text,root,v.fecha,v.sede,v.hora,v.duracion_min,v.terapia_id,v.profesional_id,v.dni,case when p.facturacion in('class','bonus_class') then coalesce(h.importe_override,p.importe)else 0 end,'PENDIENTE',coalesce(h.coverage_override,p.coverage),coalesce(h.observaciones_override,p.observaciones),p.id,v.horario_id,v.fecha,auth.uid(),auth.uid() from marathon.agenda_planes p join marathon.agenda_horarios h on h.id=v.horario_id where p.id=v.plan_id
  on conflict(horario_id,fecha_habitual)where horario_id is not null do nothing;n=n+1;
 end loop;
 -- Una corrección de asistencia puede reabrir el saldo. Las cancelaciones manuales no se restauran.
 for v in select t.* from marathon.turnos t join marathon.agenda_planes p on p.id=t.plan_id where t.fecha between d and e and t.agenda_motivo='SESIONES_COMPLETAS' and t.estado='CANCELADO' and(p.baja is null or t.fecha<p.baja) and marathon.agenda_presentes(p.id)<marathon.agenda_total(p.id) loop
  update marathon.turnos set estado='PENDIENTE',agenda_motivo=null where id=v.id;
 end loop;
 if not exists(select 1 from marathon.saldo_config where activo)or marathon.active_user()then perform marathon.agenda_cuotas_generar();end if;return n;
end$function$
