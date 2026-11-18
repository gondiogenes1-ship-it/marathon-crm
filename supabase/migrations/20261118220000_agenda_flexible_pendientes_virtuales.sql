-- Agenda: marathon_agenda_flexible ya reintenta materializar los turnos del
-- rango consultado (perform marathon.agenda_materializar(d,e)), pero si el
-- bloqueo sigue vigente (por ejemplo un cruce de horarios que no se
-- resolvio), el turno queda "virtual" para siempre y nunca aparece en la
-- pantalla principal de la agenda, sin ningun aviso.
--
-- Ahora: la respuesta incluye 'pending_virtual' con los turnos de
-- Modalidad de agenda que correspondian al rango consultado y todavia no
-- se pudieron generar despues del reintento, para que el frontend pueda
-- avisarlo en pantalla en vez de dejarlo invisible.
create or replace function public.marathon_agenda_flexible(p_filters jsonb, p_after jsonb default null::jsonb, p_limit integer default 50)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
 set lock_timeout to '3s'
as $function$
declare r jsonb;d date;e date;pend jsonb;begin
 if not marathon.active_user()then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 d=marathon.agenda_date(p_filters->>'from');e=marathon.agenda_date(p_filters->>'to');
 perform marathon.agenda_materializar(d,e);
 r=public.marathon_agenda_search(p_filters,p_after,p_limit);
 r=jsonb_set(r,'{rows}',coalesce((select jsonb_agg(x||jsonb_build_object('plan',marathon.agenda_plan_info(t.plan_id),'paused',t.estado in('PENDIENTE','AUSENTE')and marathon.agenda_pausado(t.plan_id,t.fecha),'end_hour',to_char(t.hora+make_interval(mins=>t.duracion_min),'HH24:MI')) order by n)from jsonb_array_elements(r->'rows')with ordinality a(x,n)join marathon.turnos t on t.id=x->>'id'),'[]'::jsonb));
 select coalesce(jsonb_agg(jsonb_build_object('fecha',gs::date,'hora',to_char(v.hora,'HH24:MI'),'paciente',btrim(concat_ws(' ',pa.apellido||',',pa.nombre,nullif(pa.segundo_nombre,''))),'terapia',te.nombre,'profesional',btrim(concat_ws(' ',pr.nombre,nullif(pr.segundo_nombre,''),pr.apellido)))order by gs,v.hora),'[]'::jsonb)
 into pend
 from generate_series(d,e,interval '1 day')gs
 cross join lateral marathon.agenda_virtual(gs::date)v
 join marathon.pacientes pa on pa.dni=v.dni
 join marathon.terapias te on te.id=v.terapia_id
 join marathon.profesionales pr on pr.id=v.profesional_id
 where(coalesce(p_filters->>'sede','')=''or v.sede=p_filters->>'sede')and(coalesce(p_filters->>'prof','')=''or v.profesional_id=p_filters->>'prof');
 r=jsonb_set(r,'{pending_virtual}',pend);
 return r;
end$function$;
