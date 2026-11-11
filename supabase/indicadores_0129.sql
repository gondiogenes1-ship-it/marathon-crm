-- Marathon 0.12.9: indicadores agregados; no modifica registros operativos.
create or replace function public.marathon_management(p_filters jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security invoker set search_path = '' as $body$
declare
  cut timestamp := statement_timestamp() at time zone 'America/Argentina/Buenos_Aires';
  d date; e date; w date; site text; therapy text; professional text;
  activity jsonb; activity_rows jsonb; professional_rows jsonb; cash jsonb;
  balances jsonb; inventory jsonb; capacity jsonb;
begin
  if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.'; end if;
  if p_filters is null or jsonb_typeof(p_filters)<>'object' or length(p_filters::text)>2000
    or exists(select 1 from jsonb_object_keys(p_filters) k where k<>all(array['month','sede','therapy','professional','week_start']))
    or coalesce(p_filters->>'month','') !~ '^(20[0-9]{2}|2100)-(0[1-9]|1[0-2])$'
  then raise sqlstate '22023' using message='Elegí un mes válido y filtros de Gestión.'; end if;
  d := (p_filters->>'month'||'-01')::date; e := (d+interval '1 month')::date;
  site := coalesce(p_filters->>'sede',''); therapy := coalesce(p_filters->>'therapy','');
  professional := coalesce(p_filters->>'professional','');
  w := coalesce(nullif(p_filters->>'week_start','')::date, date_trunc('week',cut)::date-7);
  if extract(isodow from w)<>1 or w+7>cut::date or w<date '2000-01-01' then
    raise sqlstate '22023' using message='Para tiempo profesional elegí un lunes de una semana completa ya terminada.';
  end if;
  with finished as (
    select t.* from marathon.turnos t where t.fecha>=d and t.fecha<e
      and t.fecha+t.hora+make_interval(mins=>t.duracion_min)<=cut
      and (site='' or t.sede=site) and (therapy='' or t.terapia_id=therapy)
      and (professional='' or t.profesional_id=professional)
  ), grouped as (
    select t.terapia_id,th.nombre terapia,count(*) total,
      count(*) filter(where t.estado='PRESENTE') present,
      count(distinct t.dni) filter(where t.estado='PRESENTE') patients,
      count(*) filter(where t.estado='AUSENTE') absent,
      count(*) filter(where t.estado='AUSENTE' and t.attendance_auto) auto_absent,
      count(*) filter(where t.estado='PENDIENTE') pending,
      count(*) filter(where t.estado='CANCELADO') cancelled
    from finished t join marathon.terapias th on th.id=t.terapia_id group by t.terapia_id,th.nombre
  ) select jsonb_build_object('total',count(*),'present',count(*) filter(where estado='PRESENTE'),
      'patients',count(distinct dni) filter(where estado='PRESENTE'),
      'absent',count(*) filter(where estado='AUSENTE'),
      'auto_absent',count(*) filter(where estado='AUSENTE' and attendance_auto),
      'pending',count(*) filter(where estado='PENDIENTE'),'cancelled',count(*) filter(where estado='CANCELADO'),
      'attendance',round(100.0*count(*) filter(where estado='PRESENTE')/nullif(count(*) filter(where estado in ('PRESENTE','AUSENTE')),0),2),
      'coverage',round(100.0*count(*) filter(where estado in ('PRESENTE','AUSENTE'))/nullif(count(*) filter(where estado in ('PRESENTE','AUSENTE','PENDIENTE')),0),2)),
    (select coalesce(jsonb_agg(to_jsonb(g) order by terapia),'[]'::jsonb) from grouped g)
    into activity,activity_rows from finished;
  with finished as (
    select t.* from marathon.turnos t where t.fecha>=d and t.fecha<e
      and t.fecha+t.hora+make_interval(mins=>t.duracion_min)<=cut
      and (site='' or t.sede=site) and (therapy='' or t.terapia_id=therapy)
      and (professional='' or t.profesional_id=professional)
  ) select coalesce(jsonb_agg(to_jsonb(q) order by profesional),'[]'::jsonb) into professional_rows from (
    select p.id,concat_ws(' ',p.nombre,p.apellido) profesional,t.sede,
      count(*) filter(where t.estado='PRESENTE') atenciones,
      count(distinct t.dni) filter(where t.estado='PRESENTE') personas
    from finished t join marathon.profesionales p on p.id=t.profesional_id group by p.id,t.sede
  )q;
  with m as (
    select m.* from marathon.movimientos m
    left join marathon.turnos t on t.id=m.turno_id
    left join marathon.bonos_serie b on b.id=m.bono_id
    left join marathon.anticipos a on a.id=m.anticipo_id
    where m.fecha>=d and m.fecha<e and m.fecha+m.hora<=cut
      and (site='' or m.sede=site) and (therapy='' or coalesce(t.terapia_id,b.terapia_id,a.terapia_id)=therapy)
      and (professional='' or coalesce(t.profesional_id,b.profesional_id,a.profesional_id,m.profesional_asociado_id)=professional)
  ), grouped as (
    select medio,origen,count(*) movimientos,
      coalesce(sum(monto) filter(where tipo in ('INGRESO','PAGO')),0) entradas,
      coalesce(sum(monto) filter(where tipo in ('EGRESO','REINTEGRO')),0) salidas
    from m group by medio,origen
  ) select jsonb_build_object('count',count(*),
    'income',coalesce(sum(monto) filter(where tipo in ('INGRESO','PAGO')),0),
    'expense',coalesce(sum(monto) filter(where tipo in ('EGRESO','REINTEGRO')),0),
    'net',coalesce(sum(case when tipo in ('INGRESO','PAGO') then monto when tipo in ('EGRESO','REINTEGRO') then -monto else 0 end),0),
    'compensations',count(*) filter(where compensacion_de is not null),
    'rows',(select coalesce(jsonb_agg(to_jsonb(g) order by origen,medio),'[]'::jsonb) from grouped g)) into cash from m;
  with payments as (
    select turno_id,bono_id,operacion_id,origen,
      sum(case when tipo in ('REINTEGRO','EGRESO') then -monto when tipo in ('PAGO','INGRESO') then monto else 0 end) paid
    from marathon.movimientos where fecha+hora<=cut group by turno_id,bono_id,operacion_id,origen
  ), turnpayments as (select turno_id,sum(paid) paid from payments where turno_id is not null group by turno_id),
  bonuspayments as (select bono_id,sum(paid) paid from payments where bono_id is not null and origen='BONO' group by bono_id),
  orthopayments as (select operacion_id,sum(paid) paid from payments where operacion_id is not null and origen='ORTOPEDIA' group by operacion_id),
  advances as (
    select turno_id,sum(case when tipo='APLICACION' then monto when tipo='REVERSO' then -monto else 0 end) paid
    from marathon.anticipo_eventos where created_at<=statement_timestamp() group by turno_id
  ), charges as (
    select 'Sesiones' origen,t.fecha, t.importe amount,coalesce(p.paid,0)+coalesce(a.paid,0) paid
    from marathon.turnos t left join turnpayments p on p.turno_id=t.id left join advances a on a.turno_id=t.id
    where t.estado='PRESENTE' and t.fecha+t.hora+make_interval(mins=>t.duracion_min)<=cut
      and (site='' or t.sede=site) and (therapy='' or t.terapia_id=therapy) and (professional='' or t.profesional_id=professional)
    union all
    select 'Bonos',b.fecha,b.importe,coalesce(p.paid,0) from marathon.bonos_serie b left join bonuspayments p on p.bono_id=b.id
    where b.estado='ACTIVO' and b.fecha+b.hora<=cut and (site='' or b.sede=site)
      and (therapy='' or b.terapia_id=therapy) and (professional='' or b.profesional_id=professional)
    union all
    select 'Ortopedia',o.fecha,o.importe_total,coalesce(p.paid,0) from marathon.ortopedia_operaciones o left join orthopayments p on p.operacion_id=o.id
    where o.tipo in ('VENTA','ALQUILER') and o.fecha+o.hora<=cut and (site='' or o.sede=site) and therapy='' and professional=''
  ), debts as (
    select *,greatest(0,amount-paid) balance,case when cut::date-fecha<=30 then '0–30 días' when cut::date-fecha<=60 then '31–60 días' when cut::date-fecha<=90 then '61–90 días' else 'Más de 90 días' end age from charges
  ), grouped as (select origen,age,count(*) cantidad,sum(balance) saldo from debts where balance>0 group by origen,age)
  select jsonb_build_object('total',coalesce(sum(balance),0),'count',count(*) filter(where balance>0),
    'charges',count(*),'overpaid',count(*) filter(where paid>amount),
    'rows',(select coalesce(jsonb_agg(to_jsonb(g) order by origen,age),'[]'::jsonb) from grouped g)) into balances from debts;
  with stock as (
    select producto_id,sede,sum(case when tipo in ('STOCK_INICIAL','COMPRA','AJUSTE_POSITIVO','DEVOLUCION') then cantidad else -cantidad end) stock
    from marathon.ortopedia_operaciones where fecha+hora<=cut group by producto_id,sede
  ), pairs as (
    select c.producto_id,concat_ws(' · ',p.pieza,nullif(p.descripcion,''),nullif(p.codigo,'')) producto,p.modalidad,c.sede,c.minimo,c.initial_loaded,coalesce(s.stock,0) stock
    from marathon.stock_config c join marathon.productos p on p.id=c.producto_id
    join marathon.sedes sd on sd.nombre=c.sede left join stock s on s.producto_id=c.producto_id and s.sede=c.sede
    where p.estado='ACTIVO' and sd.estado='ACTIVO' and (site='' or c.sede=site)
  ), grouped as (
    select sede,count(*) total,count(*) filter(where initial_loaded) initialized,
      count(*) filter(where not initial_loaded) unknown,
      count(*) filter(where initial_loaded and stock<=minimo) alerts,
      count(*) filter(where initial_loaded and stock<=0) empty,
      count(*) filter(where initial_loaded and stock<0) negative from pairs group by sede
  ) select jsonb_build_object('total',count(*),'initialized',count(*) filter(where initial_loaded),
    'unknown',count(*) filter(where not initial_loaded),'alerts',count(*) filter(where initial_loaded and stock<=minimo),
    'empty',count(*) filter(where initial_loaded and stock<=0),'negative',count(*) filter(where initial_loaded and stock<0),
    'percentage',round(100.0*count(*) filter(where initial_loaded and stock<=minimo)/nullif(count(*) filter(where initial_loaded),0),2),
    'rows',(select coalesce(jsonb_agg(to_jsonb(g) order by sede),'[]'::jsonb) from grouped g),
    'details',(select coalesce(jsonb_agg(to_jsonb(x) order by sede,producto),'[]'::jsonb) from pairs x)) into inventory from pairs;
  -- Union of professional minutes, including overlapping/group appointments only once.
  with days as (select w+i as work_date from generate_series(0,6)i),
  offered as (
    select h.profesional_id,h.sede,days.work_date,range_agg(tsrange(days.work_date+h.inicio,days.work_date+h.fin,'[)')) ranges
    from days join marathon.horarios h on h.dia=extract(isodow from days.work_date)
    join marathon.profesionales p on p.id=h.profesional_id join marathon.sedes s on s.nombre=h.sede
    where h.fin>h.inicio and p.estado='ACTIVO' and s.estado='ACTIVO'
      and (site='' or h.sede=site) and (professional='' or h.profesional_id=professional)
    group by h.profesional_id,h.sede,days.work_date
  ), booked as (
    select t.profesional_id,t.sede,t.fecha,
      range_agg(tsrange(t.fecha+t.hora,t.fecha+t.hora+make_interval(mins=>t.duracion_min),'[)')) filter(where estado in ('PENDIENTE','PRESENTE')) ranges,
      range_agg(tsrange(t.fecha+t.hora,t.fecha+t.hora+make_interval(mins=>t.duracion_min),'[)')) filter(where estado='PRESENTE') attended
    from marathon.turnos t where t.fecha>=w and t.fecha<w+7 and t.estado in ('PENDIENTE','PRESENTE')
      and (site='' or t.sede=site) and (professional='' or t.profesional_id=professional) group by t.profesional_id,t.sede,t.fecha
  ), intersections as (
    select o.*,o.ranges*coalesce(b.ranges,'{}'::tsmultirange) used,o.ranges*coalesce(b.attended,'{}'::tsmultirange) attended
    from offered o left join booked b on b.profesional_id=o.profesional_id and b.sede=o.sede and b.fecha=o.work_date
  ), per_professional as (
    select profesional_id,range_agg(r) offered from offered cross join lateral unnest(ranges)r group by profesional_id
  ), per_used as (
    select profesional_id,range_agg(r) used from intersections cross join lateral unnest(used)r group by profesional_id
  ), per_attended as (
    select profesional_id,range_agg(r) attended from intersections cross join lateral unnest(attended)r group by profesional_id
  ), mins as (
    select p.profesional_id,
      (select coalesce(sum(extract(epoch from upper(r)-lower(r))/60),0) from unnest(p.offered)r) available,
      (select coalesce(sum(extract(epoch from upper(r)-lower(r))/60),0) from unnest(u.used)r) used,
      (select coalesce(sum(extract(epoch from upper(r)-lower(r))/60),0) from unnest(a.attended)r) attended
    from per_professional p left join per_used u using(profesional_id) left join per_attended a using(profesional_id)
  ), rows as (
    select m.*,concat_ws(' ',p.nombre,p.apellido) profesional,round(100*used/nullif(available,0),2) usage
    from mins m join marathon.profesionales p on p.id=m.profesional_id
  ) select jsonb_build_object('week_start',w,'week_end',w+6,'available',coalesce(sum(available),0),
    'used',coalesce(sum(used),0),'attended',coalesce(sum(attended),0),'professionals',count(*),
    'usage',round(100*sum(used)/nullif(sum(available),0),2),
    'attendance',round(100*sum(attended)/nullif(sum(available),0),2),
    'rows',coalesce(jsonb_agg(to_jsonb(rows) order by profesional),'[]'::jsonb),
    'outside', (select count(*) from marathon.turnos t where t.fecha>=w and t.fecha<w+7 and t.estado in ('PENDIENTE','PRESENTE')
      and (site='' or t.sede=site) and (professional='' or t.profesional_id=professional)
      and not exists(select 1 from offered o where o.profesional_id=t.profesional_id and o.sede=t.sede and o.work_date=t.fecha
        and o.ranges @> tsrange(t.fecha+t.hora,t.fecha+t.hora+make_interval(mins=>t.duracion_min),'[)'))),
    'site_conflicts',(select count(*) from offered a join offered b on a.profesional_id=b.profesional_id and a.work_date=b.work_date and a.sede<b.sede and a.ranges&&b.ranges)
    ) into capacity from rows;
  return jsonb_build_object('generated_at',statement_timestamp(),'cut_local',cut,'month',to_char(d,'YYYY-MM'),
    'activity',activity,'therapies',activity_rows,'professionals',professional_rows,'cash',cash,'balances',balances,'inventory',inventory,'capacity',capacity);
end;
$body$;
revoke all on function public.marathon_management(jsonb) from public,anon;
grant execute on function public.marathon_management(jsonb) to authenticated;
