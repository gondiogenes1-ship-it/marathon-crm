CREATE OR REPLACE FUNCTION public.marathon_agenda_search(p_filters jsonb, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d date;e date;rows jsonb;nxt jsonb;summary jsonb;state text;layout text;groups jsonb;show_cancelled boolean;
begin
 if not marathon.active_user()then raise sqlstate '42501'using message='Acceso no autorizado.';end if;
 perform marathon.daily_validate(p_filters,array['from','to','sede','prof','therapy','query','state','layout'],least(p_limit,100),p_after);
 d=marathon.agenda_date(p_filters->>'from');e=marathon.agenda_date(p_filters->>'to');state=coalesce(p_filters->>'state','');
 if p_limit is null or p_limit not between 1 and 10000 or e<d or e-d>31 or(p_after is not null and not(p_after?&array['fecha','hora','id']))then raise sqlstate '22023'using message='Elegí un período de hasta 32 días y una página válida.';end if;
 if state not in('','PENDIENTE','PRESENTE','AUSENTE','CANCELADO','PAUSADO')then raise sqlstate '22023'using message='Estado de turno inválido.';end if;

 show_cancelled=marathon.is_admin();
 layout=coalesce(p_filters->>'layout','');
 if layout not in('','blocks')or(layout='blocks'and p_limit>50)then raise sqlstate '22023'using message='Vista o cantidad de bloques inválida.';end if;
 if layout='blocks'then
  with base as(
  select jsonb_build_array(t.sede,t.profesional_id,t.terapia_id)::text group_id,t.*,b.plan_id,(b.estado in('PENDIENTE','AUSENTE')and marathon.agenda_pausado(b.plan_id,b.fecha))paused,b.coverage,b.fixed_until,b.attendance_auto,p.telefono,p.observaciones patient_notes,coalesce(b.booking_notes,marathon.reservation_notes(b.observaciones)) booking_notes,exists(select 1 from marathon.turnos r where r.recovered_from=b.id) has_recovery from marathon.daily_turns t
  join marathon.turnos b on b.id=t.id join marathon.pacientes p on p.dni=t.dni
  where (show_cancelled or t.estado<>'CANCELADO') and t.fecha between d and e and(coalesce(p_filters->>'sede','')=''or t.sede=p_filters->>'sede')
  and(coalesce(p_filters->>'prof','')=''or t.profesional_id=p_filters->>'prof')
  and(coalesce(p_filters->>'therapy','')=''or t.terapia_id=p_filters->>'therapy')
  and(coalesce(p_filters->>'query','')=''or strpos(marathon.master_norm(t.paciente||' '||t.dni),marathon.master_norm(p_filters->>'query'))>0)

 ), chosen as(select * from base where state=''or(state='PAUSADO'and paused)or(estado=state and not paused)),
 keys as(
  select fecha,hora,group_id from chosen where p_after is null or(fecha,hora,group_id)>(marathon.agenda_date(p_after->>'fecha'),(p_after->>'hora')::time,p_after->>'id')
  group by fecha,hora,group_id order by fecha,hora,group_id limit p_limit+1
 ), wanted as(select * from keys order by fecha,hora,group_id limit p_limit),
 paged as(select c.* from chosen c join wanted k using(fecha,hora,group_id)),
 metadata as(
  select fecha,hora,group_id,min(sede) sede,min(profesional_id) profesional_id,min(terapia_id) terapia_id,min(profesional) profesional,min(terapia) terapia,count(*) listed
  from paged group by fecha,hora,group_id
 )
 select coalesce((select jsonb_agg(to_jsonb(x)-'group_id'order by fecha,hora,group_id,id)from paged x),'[]'::jsonb),
 (select jsonb_build_object('total',count(*),'patients',count(distinct dni),'PAUSADO',count(*)filter(where paused),'PENDIENTE',count(*)filter(where estado='PENDIENTE'and not paused),'PRESENTE',count(*)filter(where estado='PRESENTE'),'AUSENTE',count(*)filter(where estado='AUSENTE'and not paused),'CANCELADO',count(*)filter(where estado='CANCELADO'),'debt',coalesce(sum(debt),0)+coalesce((select sum(marathon.agenda_cuota_saldo(q.id))from marathon.agenda_cuotas q where q.plan_id in(select plan_id from base)),0))from base),
 coalesce((select jsonb_agg(jsonb_build_object('fecha',m.fecha,'hora',m.hora,'key',m.group_id,'sede',m.sede,'profesional_id',m.profesional_id,'terapia_id',m.terapia_id,'profesional',m.profesional,'terapia',m.terapia,'listed',m.listed,'availability_known',s.hora is not null,'capacity',s.capacity,'remaining',s.remaining,'blocked',s.blocked)order by m.fecha,m.hora,m.group_id)
 from metadata m left join lateral(select * from marathon.agenda_slots(m.fecha,m.sede,m.profesional_id,m.terapia_id)s where s.hora=to_char(m.hora,'HH24:MI'))s on true),'[]'::jsonb),
 (select case when(select count(*)from keys)>p_limit then jsonb_build_object('fecha',fecha,'hora',hora,'id',group_id)end from wanted order by fecha desc,hora desc,group_id desc limit 1)
 into rows,summary,groups,nxt;
 return jsonb_build_object('rows',rows,'next',nxt,'summary',summary,'blocks',groups,'generated_at',statement_timestamp(),'layout','blocks');
 end if;
 with base as(
  select t.*,b.plan_id,(b.estado in('PENDIENTE','AUSENTE')and marathon.agenda_pausado(b.plan_id,b.fecha))paused,b.coverage,b.fixed_until,b.attendance_auto,p.telefono,p.observaciones patient_notes,coalesce(b.booking_notes,marathon.reservation_notes(b.observaciones)) booking_notes,exists(select 1 from marathon.turnos r where r.recovered_from=b.id) has_recovery from marathon.daily_turns t
  join marathon.turnos b on b.id=t.id join marathon.pacientes p on p.dni=t.dni
  where (show_cancelled or t.estado<>'CANCELADO') and t.fecha between d and e and(coalesce(p_filters->>'sede','')=''or t.sede=p_filters->>'sede')
  and(coalesce(p_filters->>'prof','')=''or t.profesional_id=p_filters->>'prof')
  and(coalesce(p_filters->>'therapy','')=''or t.terapia_id=p_filters->>'therapy')
  and(coalesce(p_filters->>'query','')=''or strpos(marathon.master_norm(t.paciente||' '||t.dni),marathon.master_norm(p_filters->>'query'))>0)
 ), paged as(
  select * from base where(state=''or(state='PAUSADO'and paused)or(estado=state and not paused))and(p_after is null or(fecha,hora,id)>(marathon.agenda_date(p_after->>'fecha'),(p_after->>'hora')::time,p_after->>'id'))
  order by fecha,hora,id limit p_limit+1
 )
 select coalesce((select jsonb_agg(to_jsonb(x)order by fecha,hora,id)from paged x),'[]'::jsonb),
 (select jsonb_build_object('total',count(*),'patients',count(distinct dni),'PAUSADO',count(*)filter(where paused),'PENDIENTE',count(*)filter(where estado='PENDIENTE'and not paused),'PRESENTE',count(*)filter(where estado='PRESENTE'),'AUSENTE',count(*)filter(where estado='AUSENTE'and not paused),'CANCELADO',count(*)filter(where estado='CANCELADO'),'debt',coalesce(sum(debt),0)+coalesce((select sum(marathon.agenda_cuota_saldo(q.id))from marathon.agenda_cuotas q where q.plan_id in(select plan_id from base)),0))from base)
 into rows,summary;
 if p_limit=10000 and jsonb_array_length(rows)>10000 then raise sqlstate '22023'using message='Hay más de 10.000 turnos. Reducí el período o los filtros para exportar el listado completo.';end if;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('fecha',rows->(p_limit-1)->>'fecha','hora',rows->(p_limit-1)->>'hora','id',rows->(p_limit-1)->>'id');end if;
 return jsonb_build_object('rows',rows,'next',nxt,'summary',summary,'generated_at',statement_timestamp());
end $function$;
NOTIFY pgrst, 'reload schema';
