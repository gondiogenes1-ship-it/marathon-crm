-- Corrige el conflicto entre la variable de registro h y el alias SQL h.
-- No cambia reglas de cobro, importes, sede ni medio de pago.
do $migration$
declare
 definition text;
 old_expression text := '(select h.profesional_id from marathon.agenda_horarios h where h.plan_id=pid order by h.dia,h.hora limit 1)';
 new_expression text := '(select quota_schedule.profesional_id from marathon.agenda_horarios quota_schedule where quota_schedule.plan_id=pid order by quota_schedule.dia,quota_schedule.hora limit 1)';
 financial_before text;
 financial_after text;
begin
 select pg_get_functiondef('public.marathon_agenda_plan_command(text,text,jsonb)'::regprocedure) into definition;
 if position(old_expression in definition)=0 then
  raise exception 'La función cambió: revisar antes de aplicar la corrección de profesional.';
 end if;
 execute replace(definition,old_expression,new_expression);

 select md5(coalesce(string_agg(concat_ws('|',m.id,m.fecha,m.hora,m.origen,m.tipo,m.monto,m.medio,m.sede,m.cuota_id,m.compensacion_de),E'\n' order by m.id),''))
 into financial_before from marathon.movimientos m;

 -- Solo completa movimientos sin profesional cuando todos los horarios de la
 -- cuota, en su sede y período, identifican un único profesional. No adivina
 -- asociaciones cuando hay varios profesionales o faltan horarios.
 with candidates as (
  select payment.id,min(schedule.profesional_id) as professional
  from marathon.movimientos payment
  join marathon.agenda_cuotas quota on quota.id=payment.cuota_id
  join marathon.agenda_horarios schedule on schedule.plan_id=quota.plan_id
   and schedule.sede=quota.sede and schedule.desde<quota.hasta
   and (schedule.hasta is null or schedule.hasta>quota.fecha)
  where payment.profesional_asociado_id is null
  group by payment.id
  having count(distinct schedule.profesional_id)=1
 )
 update marathon.movimientos payment
 set profesional_asociado_id=candidates.professional
 from candidates where payment.id=candidates.id
 and payment.profesional_asociado_id is null;

 select md5(coalesce(string_agg(concat_ws('|',m.id,m.fecha,m.hora,m.origen,m.tipo,m.monto,m.medio,m.sede,m.cuota_id,m.compensacion_de),E'\n' order by m.id),''))
 into financial_after from marathon.movimientos m;
 if financial_before is distinct from financial_after then
  raise exception 'Se modificaron datos financieros fuera de la asociación: se revierte la migración.';
 end if;
end $migration$;
