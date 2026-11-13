-- Tendencias: reemplaza el selector "Meses" (6/12/24) por un rango "Desde/Hasta" (mes y año).
-- Correr en el SQL Editor de Supabase (una sola vez). Reemplaza la función completa de
-- marathon_trends: ahora recibe from/to (YYYY-MM) en vez de months. El resto (series
-- mensuales + ausentismo por profesional) queda igual.
create or replace function public.marathon_trends(p_filters jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security invoker set search_path='' as $body$
declare
  cut timestamp := statement_timestamp() at time zone 'America/Argentina/Buenos_Aires';
  v_site text; v_therapy text; n_months int; first_month date; last_month date; current_month date; series jsonb; by_professional jsonb;
begin
  if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.'; end if;
  if p_filters is null or jsonb_typeof(p_filters)<>'object' or length(p_filters::text)>2000
    or exists(select 1 from jsonb_object_keys(p_filters) k where k<>all(array['sede','therapy','from','to'])) then
    raise sqlstate '22023' using message='Filtros de tendencias inválidos.'; end if;
  v_site := coalesce(p_filters->>'sede','');
  v_therapy := coalesce(p_filters->>'therapy','');
  current_month := date_trunc('month', cut)::date;
  if coalesce(p_filters->>'to','') !~ '^(20[0-9]{2}|2100)-(0[1-9]|1[0-2])$' then
    raise sqlstate '22023' using message='Elegí un mes final válido.'; end if;
  last_month := (p_filters->>'to'||'-01')::date;
  if last_month > current_month then raise sqlstate '22023' using message='El mes final no puede ser futuro.'; end if;
  if coalesce(p_filters->>'from','') !~ '^(20[0-9]{2}|2100)-(0[1-9]|1[0-2])$' then
    raise sqlstate '22023' using message='Elegí un mes inicial válido.'; end if;
  first_month := (p_filters->>'from'||'-01')::date;
  if first_month > last_month then raise sqlstate '22023' using message='El mes inicial no puede ser posterior al final.'; end if;
  n_months := (extract(year from last_month)-extract(year from first_month))*12 + (extract(month from last_month)-extract(month from first_month)) + 1;
  if n_months < 2 or n_months > 24 then raise sqlstate '22023' using message='Elegí un rango de entre 2 y 24 meses.'; end if;
  with months as (
    select generate_series(first_month::timestamp, last_month::timestamp, interval '1 month')::date m
  ), turns as (
    select date_trunc('month', t.fecha)::date m,
      count(*) filter(where t.estado='PRESENTE') present,
      count(distinct t.dni) filter(where t.estado='PRESENTE') patients,
      count(*) filter(where t.estado='AUSENTE') absent,
      count(*) filter(where t.estado='AUSENTE' and t.attendance_auto) auto_absent,
      count(*) filter(where t.estado='PENDIENTE') pending
    from marathon.turnos t
    where t.fecha >= first_month and t.fecha + t.hora + make_interval(mins=>t.duracion_min) <= cut
      and (v_site='' or t.sede=v_site) and (v_therapy='' or t.terapia_id=v_therapy)
    group by 1
  ), firsts as (
    select t.dni, min(t.fecha) ff
    from marathon.turnos t
    where t.estado='PRESENTE' and t.fecha + t.hora + make_interval(mins=>t.duracion_min) <= cut
      and (v_site='' or t.sede=v_site) and (v_therapy='' or t.terapia_id=v_therapy)
    group by t.dni
  ), newpat as (
    select date_trunc('month', ff)::date m, count(*) n from firsts where ff >= first_month group by 1
  ), cash as (
    select date_trunc('month', mv.fecha)::date mm,
      coalesce(sum(mv.monto) filter(where mv.tipo in ('INGRESO','PAGO')),0) income,
      coalesce(sum(mv.monto) filter(where mv.tipo in ('EGRESO','REINTEGRO')),0) expense,
      count(*) movimientos
    from marathon.movimientos mv
    left join marathon.turnos t on t.id=mv.turno_id
    left join marathon.bonos_serie b on b.id=mv.bono_id
    left join marathon.anticipos a on a.id=mv.anticipo_id
    where mv.fecha >= first_month and mv.fecha + mv.hora <= cut
      and (v_site='' or mv.sede=v_site)
      and (v_therapy='' or coalesce(t.terapia_id,b.terapia_id,a.terapia_id)=v_therapy)
    group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'month', to_char(mo.m,'YYYY-MM'),
    'present', coalesce(tu.present,0),
    'patients', coalesce(tu.patients,0),
    'new_patients', coalesce(np.n,0),
    'absent', coalesce(tu.absent,0),
    'auto_absent', coalesce(tu.auto_absent,0),
    'pending', coalesce(tu.pending,0),
    'attendance', round(100.0*coalesce(tu.present,0)/nullif(coalesce(tu.present,0)+coalesce(tu.absent,0),0),2),
    'absenteeism', round(100.0*coalesce(tu.absent,0)/nullif(coalesce(tu.present,0)+coalesce(tu.absent,0),0),2),
    'income', coalesce(ca.income,0),
    'expense', coalesce(ca.expense,0),
    'net', coalesce(ca.income,0)-coalesce(ca.expense,0),
    'movimientos', coalesce(ca.movimientos,0),
    'partial', mo.m = current_month
  ) order by mo.m), '[]'::jsonb)
  into series
  from months mo
  left join turns tu on tu.m=mo.m
  left join newpat np on np.m=mo.m
  left join cash ca on ca.mm=mo.m;
  -- Ausentismo por profesional, acumulado en todo el período elegido (mismos filtros de sede/terapia).
  with profs as (
    select t.profesional_id, concat_ws(' ',p.nombre,p.apellido) profesional,
      count(*) filter(where t.estado='PRESENTE') present,
      count(*) filter(where t.estado='AUSENTE') absent,
      count(*) filter(where t.estado='AUSENTE' and t.attendance_auto) auto_absent
    from marathon.turnos t join marathon.profesionales p on p.id=t.profesional_id
    where t.fecha >= first_month and t.fecha + t.hora + make_interval(mins=>t.duracion_min) <= cut
      and (v_site='' or t.sede=v_site) and (v_therapy='' or t.terapia_id=v_therapy)
    group by t.profesional_id, p.nombre, p.apellido
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', profesional_id, 'profesional', profesional,
      'present', present, 'absent', absent, 'auto_absent', auto_absent,
      'total', present+absent,
      'absenteeism', round(100.0*absent/nullif(present+absent,0),2)
    ) order by round(100.0*absent/nullif(present+absent,0),2) desc nulls last, profesional), '[]'::jsonb)
  into by_professional
  from profs where present+absent > 0;
  return jsonb_build_object('generated_at', statement_timestamp(), 'cut_local', cut, 'months', n_months,
    'from', to_char(first_month,'YYYY-MM'), 'to', to_char(last_month,'YYYY-MM'), 'series', series,
    'by_professional', by_professional);
end;
$body$;
revoke all on function public.marathon_trends(jsonb) from public,anon;
grant execute on function public.marathon_trends(jsonb) to authenticated;
