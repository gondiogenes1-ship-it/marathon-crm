-- Informes PPS. Agregacion de solo lectura, sin cambiar registros operativos.
create or replace function public.marathon_patient_dashboard(p_filters jsonb)
returns jsonb language plpgsql stable security invoker set search_path='' as $body$
declare
 cut timestamp:=statement_timestamp() at time zone 'America/Argentina/Buenos_Aires';
 d date; e date; n_days int; prev date; finish timestamp; prev_finish timestamp;
 v_site text; v_therapy text; v_professional text; v_specialty text;
 summary jsonb; previous jsonb; groups jsonb; trend jsonb; coverage_json jsonb; coverage_entities jsonb;
 firsts jsonb; waiting jsonb; capacity jsonb; quality jsonb; flow jsonb; catalog jsonb;
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_filters is null or jsonb_typeof(p_filters)<>'object' or length(p_filters::text)>3000
 or exists(select 1 from jsonb_object_keys(p_filters)k where k<>all(array['from','to','sede','therapy','professional','specialty'])) then
 raise sqlstate '22023' using message='Filtros de pacientes invalidos.';end if;
 if coalesce(p_filters->>'from','')!~'^\d{4}-\d{2}-\d{2}$'or coalesce(p_filters->>'to','')!~'^\d{4}-\d{2}-\d{2}$'then
 raise sqlstate '22023'using message='Elegi fechas validas para el informe.';end if;
 begin d:=(p_filters->>'from')::date;e:=(p_filters->>'to')::date+1;
 exception when invalid_datetime_format or datetime_field_overflow then raise sqlstate '22023'using message='Elegi fechas validas para el informe.';end;
 n_days:=e-d;prev:=d-n_days;
 if n_days<1 or n_days>93 or e-1>cut::date or e-1>date '2100-12-31'or prev<date '2000-01-01' then
 raise sqlstate '22023' using message='Elegi hasta 93 dias, sin fechas futuras y con periodo anterior desde 2000.';end if;
 v_site:=coalesce(p_filters->>'sede','');v_therapy:=coalesce(p_filters->>'therapy','');
 v_professional:=coalesce(p_filters->>'professional','');v_specialty:=coalesce(p_filters->>'specialty','');
 finish:=least(e::timestamp,cut);prev_finish:=finish-make_interval(days=>n_days);
 -- Todas las filas de pacientes quedan dentro del servidor. Solo se devuelven agregados.
 with scoped as materialized (
 select t.*,coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad') specialty
 from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id
 where t.fecha>=prev and t.fecha<e and(v_site=''or t.sede=v_site)
 and(v_therapy=''or t.terapia_id=v_therapy)and(v_professional=''or t.profesional_id=v_professional)
 and(v_specialty=''or coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')=v_specialty)
 ), marked as (
 select *,fecha+hora+make_interval(mins=>duracion_min) ended,
 case when fecha>=d then 'current' else 'previous' end period from scoped
 ), stats as (
 select period,count(*) total,count(*)filter(where estado='PRESENTE') present,
 count(distinct dni)filter(where estado='PRESENTE') patients,
 count(*)filter(where estado='AUSENTE') absent,count(*)filter(where estado='AUSENTE'and attendance_auto) auto_absent,
 count(*)filter(where estado='PENDIENTE') pending,count(*)filter(where estado='CANCELADO') cancelled
 from marked where (period='current'and ended<=finish)or(period='previous'and ended<=prev_finish)group by period
 ), comparisons as (
 select k.period,coalesce(s.total,0) total,coalesce(s.present,0) present,coalesce(s.patients,0) patients,
 coalesce(s.absent,0) absent,coalesce(s.pending,0) pending,coalesce(s.cancelled,0) cancelled,coalesce(s.auto_absent,0) auto_absent,
 round(100.0*s.present/nullif(s.present+s.absent,0),2) attendance,
 round(100.0*(s.present+s.absent)/nullif(s.present+s.absent+s.pending,0),2) completeness,
 round(s.present::numeric/nullif(s.patients,0),2) frequency
 from(values('current'),('previous'))k(period)left join stats s using(period)
 )select(select to_jsonb(b)-'period'from comparisons b where period='current'),
 (select to_jsonb(b)-'period'from comparisons b where period='previous')into summary,previous;
 with finished as materialized (
 select t.*,th.nombre therapy,coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad') specialty,
 concat_ws(' ',pr.nombre,nullif(pr.segundo_nombre,''),pr.apellido)professional
 from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id join marathon.profesionales pr on pr.id=t.profesional_id
 where t.fecha>=d and t.fecha<e and t.fecha+t.hora+make_interval(mins=>t.duracion_min)<=finish
 and(v_site=''or t.sede=v_site)and(v_therapy=''or t.terapia_id=v_therapy)and(v_professional=''or t.profesional_id=v_professional)
 and(v_specialty=''or coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')=v_specialty)
 ), grouped as (
 select g.kind,g.id,g.label,count(*)total,count(*)filter(where estado='PRESENTE')present,
 count(distinct dni)filter(where estado='PRESENTE')patients,count(*)filter(where estado='AUSENTE')absent,
 count(*)filter(where estado='PENDIENTE')pending,count(*)filter(where estado='CANCELADO')cancelled,
 round(100.0*count(*)filter(where estado='PRESENTE')/nullif(count(*)filter(where estado in('PRESENTE','AUSENTE')),0),2)attendance
 from finished f cross join lateral(values('specialty',f.specialty,f.specialty),('therapy',f.terapia_id,f.therapy),
 ('site',f.sede,f.sede),('professional',f.profesional_id,f.professional))g(kind,id,label)group by g.kind,g.id,g.label
 ), series as (
 select fecha date,count(*)filter(where estado='PRESENTE')present,count(*)filter(where estado='AUSENTE')absent,
 count(distinct dni)filter(where estado='PRESENTE')patients from finished group by fecha
 ), types as (
 select case when coverage->>'type'in('PARTICULAR','OBRA_SOCIAL','ART','CLUB')then coverage->>'type'else 'SIN_REGISTRO'end type,
 count(*)attentions,count(distinct dni)patients from finished where estado='PRESENTE'group by 1
 ), entities as (
 select nullif(btrim(coverage->>'obra_social_id'),'') os_id,count(*)attentions,count(distinct dni)patients
 from finished where estado='PRESENTE'and coverage->>'type'='OBRA_SOCIAL'group by 1
 ), entity_total as(select sum(attentions) t from entities)
 select(select coalesce(jsonb_agg(to_jsonb(g)order by kind,patients desc,label),'[]'::jsonb)from grouped g),
 (select coalesce(jsonb_agg(jsonb_build_object('date',g::date,'present',coalesce(s.present,0),'absent',coalesce(s.absent,0),'patients',coalesce(s.patients,0))order by g),'[]'::jsonb)
 from generate_series(d::timestamp,(e-1)::timestamp,interval '1 day')g left join series s on s.date=g::date),
 (select jsonb_agg(jsonb_build_object('type',k.type,'label',k.label,'attentions',coalesce(t.attentions,0),'patients',coalesce(t.patients,0),
 'percent',round(100.0*coalesce(t.attentions,0)/nullif((summary->>'present')::numeric,0),2))order by k.ord)
 from(values('PARTICULAR','Particular',1),('OBRA_SOCIAL','Obra social',2),('ART','ART',3),('CLUB','Club',4),('SIN_REGISTRO','Sin registrar',5))k(type,label,ord)left join types t using(type)),
 (select coalesce(jsonb_agg(jsonb_build_object('id',en.os_id,
 'label',case when en.os_id is null then 'Sin entidad identificada'when o.id is null then 'Entidad fuera de catalogo'else o.nombre end,
 'state',o.estado,'identified',(en.os_id is not null and o.id is not null),
 'attentions',en.attentions,'patients',en.patients,
 'percent',round(100.0*en.attentions/nullif(et.t,0),2))order by(en.os_id is null),en.attentions desc),'[]'::jsonb)
 from entities en left join marathon.obras_sociales o on o.id=en.os_id cross join entity_total et)
 into groups,trend,coverage_json,coverage_entities;
 -- Primera observada: minima atencion real registrada; no usa alta de ficha ni bonos.
 with attended as materialized (
 select t.dni,t.sede,t.terapia_id,coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')specialty,
 t.fecha+t.hora started,t.fecha+t.hora+make_interval(mins=>t.duracion_min)ended,t.profesional_id
 from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id
 where t.estado='PRESENTE'and t.fecha+t.hora+make_interval(mins=>t.duracion_min)<=cut
 ), first_global as(select dni,min(started)first_at from attended group by dni),
 first_site as(select dni,sede,min(started)first_at from attended group by dni,sede),
 first_specialty as(select dni,specialty,min(started)first_at from attended group by dni,specialty),
 current_people as(select distinct dni from attended where started>=d and started<finish and ended<=finish and(v_site=''or sede=v_site)
 and(v_therapy=''or terapia_id=v_therapy)and(v_professional=''or profesional_id=v_professional)and(v_specialty=''or attended.specialty=v_specialty))
 select jsonb_build_object('observed',count(*)filter(where g.first_at>=d and g.first_at<finish),'returning',count(*)filter(where g.first_at<d),
 'first_site',case when v_site=''then null else(select count(*)from current_people c join first_site fs on fs.dni=c.dni and fs.sede=v_site where fs.first_at>=d and fs.first_at<finish)end,
 'first_specialty',case when v_specialty=''then null else(select count(*)from current_people c join first_specialty fs on fs.dni=c.dni and fs.specialty=v_specialty where fs.first_at>=d and fs.first_at<finish)end,
 'confirmed',null,'history_complete',false)into firsts from current_people c join first_global g using(dni);
 with filtered as materialized (
 select w.*,th.nombre therapy,coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')specialty,
 cut::date-w.fecha age from marathon.espera w join marathon.terapias th on th.id=w.terapia_id
 where(v_site=''or w.sede=v_site)and(v_therapy=''or w.terapia_id=v_therapy)and(v_professional=''or w.profesional_id=v_professional)
 and(v_specialty=''or coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')=v_specialty)
 ), active as(select * from filtered where estado in('PENDIENTE','CONTACTADO')),
 wg as(select specialty label,count(*)requests,count(distinct dni)patients,min(fecha)oldest,
 percentile_cont(0.5)within group(order by age)filter(where age>=0)median_days from active group by specialty),
 assigned as(
 select w.id,t.fecha-w.fecha days from filtered w join marathon.turnos t on t.id=w.reserved_turn_id
 where w.fecha>=d and w.fecha<e and w.fecha<=cut::date and w.estado='RESUELTO'and t.estado<>'CANCELADO'and t.fecha>=w.fecha
 )select jsonb_build_object('requests',(select count(*)from active),'patients',(select count(distinct dni)from active),
 'median_days',(select percentile_cont(0.5)within group(order by age)filter(where age>=0)from active),
 'invalid_dates',(select count(*)from active where age<0),'rows',(select coalesce(jsonb_agg(to_jsonb(wg)order by requests desc,label),'[]'::jsonb)from wg),
 'linked_count',(select count(*)from assigned),'linked_median_days',(select percentile_cont(0.5)within group(order by days)from assigned),
 'complete_demand',false,'first_offer_days',null)into waiting;
 -- Tiempo profesional, no cupos fisicos. Dia de horarios: 0 domingo ... 6 sabado.
 with dates as(select g::date date from generate_series(d::timestamp,(e-1)::timestamp,interval '1 day')g),
 offered as(
 select h.profesional_id,h.sede,dt.date,range_agg(tsrange(dt.date+h.inicio,least(dt.date+h.fin,finish),'[)'))ranges
 from dates dt join marathon.horarios h on h.dia=extract(dow from dt.date)
 join marathon.profesionales pr on pr.id=h.profesional_id and pr.estado='ACTIVO'
 join marathon.sedes sd on sd.nombre=h.sede and sd.estado='ACTIVO'
 where dt.date+h.inicio<finish and h.fin>h.inicio and(v_site=''or h.sede=v_site)and(v_professional=''or h.profesional_id=v_professional)
 and(v_therapy=''or exists(select 1 from marathon.profesional_terapias pt where pt.profesional_id=h.profesional_id and pt.terapia_id=v_therapy))
 and(v_specialty=''or exists(select 1 from marathon.profesional_terapias pt join marathon.terapias th on th.id=pt.terapia_id where pt.profesional_id=h.profesional_id and coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')=v_specialty))
 group by h.profesional_id,h.sede,dt.date
 ), booked as(
 select t.profesional_id,t.sede,t.fecha,
 range_agg(tsrange(t.fecha+t.hora,least(t.fecha+t.hora+make_interval(mins=>t.duracion_min),finish),'[)'))reserved,
 range_agg(tsrange(t.fecha+t.hora,t.fecha+t.hora+make_interval(mins=>t.duracion_min),'[)'))filter(where t.estado='PRESENTE'and t.fecha+t.hora+make_interval(mins=>t.duracion_min)<=finish)effective
 from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id
 where t.fecha>=d and t.fecha<e and t.fecha+t.hora<finish and t.estado in('PENDIENTE','PRESENTE')
 and(v_site=''or t.sede=v_site)and(v_therapy=''or t.terapia_id=v_therapy)and(v_professional=''or t.profesional_id=v_professional)
 and(v_specialty=''or coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')=v_specialty)
 group by t.profesional_id,t.sede,t.fecha
 ), inter as(
 select o.*,o.ranges*coalesce(b.reserved,'{}'::tsmultirange)reserved,o.ranges*coalesce(b.effective,'{}'::tsmultirange)effective
 from offered o left join booked b on b.profesional_id=o.profesional_id and b.sede=o.sede and b.fecha=o.date
 ), op as(select profesional_id,range_agg(r)ranges from offered cross join lateral unnest(ranges)r group by profesional_id),
 rp as(select profesional_id,range_agg(r)ranges from inter cross join lateral unnest(reserved)r group by profesional_id),
 ep as(select profesional_id,range_agg(r)ranges from inter cross join lateral unnest(effective)r group by profesional_id),
 mins as(
 select op.profesional_id,concat_ws(' ',pr.nombre,nullif(pr.segundo_nombre,''),pr.apellido)label,
 (select coalesce(sum(extract(epoch from upper(r)-lower(r))/60),0)from unnest(op.ranges)r)available,
 (select coalesce(sum(extract(epoch from upper(r)-lower(r))/60),0)from unnest(rp.ranges)r)reserved,
 (select coalesce(sum(extract(epoch from upper(r)-lower(r))/60),0)from unnest(ep.ranges)r)effective
 from op left join rp using(profesional_id)left join ep using(profesional_id)join marathon.profesionales pr on pr.id=op.profesional_id
 ), rows as(select *,round(100*reserved/nullif(available,0),2)reserved_pct,round(100*effective/nullif(available,0),2)effective_pct from mins)
 select jsonb_build_object('available',coalesce(sum(available),0),'reserved',coalesce(sum(reserved),0),'effective',coalesce(sum(effective),0),
 'reserved_pct',round(100*sum(reserved)/nullif(sum(available),0),2),'effective_pct',round(100*sum(effective)/nullif(sum(available),0),2),
 'rows',coalesce(jsonb_agg(to_jsonb(rows)order by reserved desc,label),'[]'::jsonb),'physical_capacity',null,'current_schedules',true)
 into capacity from rows;
 with current_turns as(
 select t.*from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id where t.fecha>=d and t.fecha<e
 and(v_site=''or t.sede=v_site)and(v_therapy=''or t.terapia_id=v_therapy)and(v_professional=''or t.profesional_id=v_professional)
 and(v_specialty=''or coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')=v_specialty)
 ), heat as(
 select extract(isodow from fecha)::int as weekday,extract(hour from hora)::int as hour_bucket,count(*) as count
 from current_turns where estado in('PENDIENTE','PRESENTE')and fecha+hora<finish group by 1,2
 )select jsonb_build_object('future',(select count(*)from current_turns where fecha+hora>=finish),
 'missing_coverage',(select count(*)from current_turns where estado='PRESENTE'and fecha+hora+make_interval(mins=>duracion_min)<=finish and coalesce(coverage->>'type','')not in('PARTICULAR','OBRA_SOCIAL','ART','CLUB')),
 'scope_turns',(select count(*)from current_turns),'clinical_diagnoses',false,'experience',false),
 (select coalesce(jsonb_agg((to_jsonb(h)-'hour_bucket')||jsonb_build_object('hour',h.hour_bucket)order by h.hour_bucket,h.weekday),'[]'::jsonb)from heat h)into quality,flow;
 select jsonb_build_object(
 'specialties',(select coalesce(jsonb_agg(x.specialty order by x.specialty),'[]'::jsonb)from(select distinct coalesce(nullif(btrim(especialidad),''),'Sin especialidad')specialty from marathon.terapias)x),
 'therapies',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',nombre,'specialty',coalesce(nullif(btrim(especialidad),''),'Sin especialidad'))order by nombre),'[]'::jsonb)from marathon.terapias),
 'professionals',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',concat_ws(' ',nombre,nullif(segundo_nombre,''),apellido)||case when estado='INACTIVO'then ' (inactivo)'else ''end)order by apellido,nombre),'[]'::jsonb)from marathon.profesionales))into catalog;
 return jsonb_build_object('generated_at',statement_timestamp(),'today',cut::date,'filters',p_filters,
 'period',jsonb_build_object('from',d,'to',e-1,'days',n_days,'previous_from',prev,'previous_to',d-1,'cut',finish,'previous_cut',prev_finish,'partial_day',e::timestamp>cut),
 'summary',summary,'previous',previous,'groups',groups,'trend',trend,'coverage',coverage_json,'coverage_entities',coverage_entities,'firsts',firsts,'waiting',waiting,'capacity',capacity,'quality',quality,'flow',flow,'catalog',catalog);
end;
$body$;
revoke all on function public.marathon_patient_dashboard(jsonb) from public,anon;
grant execute on function public.marathon_patient_dashboard(jsonb) to authenticated;
