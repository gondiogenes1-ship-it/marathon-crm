-- FacturaciÃ³n por cobertura + checklist compartido de carga en la plataforma de la obra social.
-- AgregaciÃ³n de solo lectura para el listado; la marca se persiste por funciÃ³n SECURITY DEFINER.

-- 1) Tabla de marcas: por paciente + modalidad/obra social + mes.
create table if not exists marathon.facturacion_cargas (
  periodo text not null check (periodo ~ '^(20[0-9]{2}|2100)-(0[1-9]|1[0-2])$'),
  modalidad text not null check (modalidad in ('PARTICULAR','OBRA_SOCIAL','ART','CLUB','SIN_REGISTRO')),
  obra_social_id text not null default '',
  dni text not null,
  cargado_por uuid,
  cargado_en timestamptz not null default now(),
  primary key (periodo, modalidad, obra_social_id, dni)
);
alter table marathon.facturacion_cargas enable row level security;
drop policy if exists active_read on marathon.facturacion_cargas;
create policy active_read on marathon.facturacion_cargas for select to authenticated using (marathon.active_user());
grant select on marathon.facturacion_cargas to authenticated;

-- 2) Marcar / desmarcar como cargado (escritura controlada).
create or replace function public.marathon_billing_mark(p_periodo text, p_modality text, p_os_id text, p_dni text, p_marked boolean)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare uid uuid := (select auth.uid());
begin
  if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.'; end if;
  if coalesce(p_periodo,'') !~ '^(20[0-9]{2}|2100)-(0[1-9]|1[0-2])$' then raise sqlstate '22023' using message='PerÃ­odo invÃ¡lido.'; end if;
  if coalesce(p_modality,'') not in ('PARTICULAR','OBRA_SOCIAL','ART','CLUB','SIN_REGISTRO') then raise sqlstate '22023' using message='Modalidad invÃ¡lida.'; end if;
  if coalesce(p_dni,'')='' then raise sqlstate '22023' using message='Falta el paciente.'; end if;
  if p_marked then
    insert into marathon.facturacion_cargas(periodo,modalidad,obra_social_id,dni,cargado_por)
    values (p_periodo,p_modality,coalesce(p_os_id,''),p_dni,uid)
    on conflict (periodo,modalidad,obra_social_id,dni) do nothing;
    return (select jsonb_build_object('marked',true,'by',coalesce(u.display_name,''),'at',c.cargado_en)
            from marathon.facturacion_cargas c left join marathon.app_users u on u.user_id=c.cargado_por
            where c.periodo=p_periodo and c.modalidad=p_modality and c.obra_social_id=coalesce(p_os_id,'') and c.dni=p_dni);
  else
    delete from marathon.facturacion_cargas where periodo=p_periodo and modalidad=p_modality and obra_social_id=coalesce(p_os_id,'') and dni=p_dni;
    return jsonb_build_object('marked',false);
  end if;
end $body$;
revoke all on function public.marathon_billing_mark(text,text,text,text,boolean) from public,anon;
grant execute on function public.marathon_billing_mark(text,text,text,text,boolean) to authenticated;

-- 3) Listado de facturaciÃ³n por cobertura de cada atenciÃ³n: resumen por paciente + detalle de sesiones + estado de carga.
create or replace function public.marathon_billing(p_filters jsonb)
returns jsonb language plpgsql stable security invoker set search_path='' as $body$
declare
  cut timestamp := statement_timestamp() at time zone 'America/Argentina/Buenos_Aires';
  d date; e date; site text; therapy text; modality text; insurance text; per text;
  summary jsonb; rows jsonb;
begin
  if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.'; end if;
  if p_filters is null or jsonb_typeof(p_filters)<>'object' or length(p_filters::text)>2000
    or exists(select 1 from jsonb_object_keys(p_filters) k where k<>all(array['month','sede','therapy','modality','insurance']))
    or coalesce(p_filters->>'month','') !~ '^(20[0-9]{2}|2100)-(0[1-9]|1[0-2])$' then
    raise sqlstate '22023' using message='Filtros de facturaciÃ³n invÃ¡lidos.'; end if;
  per := p_filters->>'month'; d := (per||'-01')::date; e := (d+interval '1 month')::date;
  site := coalesce(p_filters->>'sede',''); therapy := coalesce(p_filters->>'therapy','');
  modality := coalesce(p_filters->>'modality',''); insurance := coalesce(p_filters->>'insurance','');
  if modality<>'' and modality not in ('PARTICULAR','OBRA_SOCIAL','ART','CLUB','SIN_REGISTRO') then raise sqlstate '22023' using message='Modalidad invÃ¡lida.'; end if;
  with base as (
    select t.dni, t.fecha, t.hora, t.sede, th.nombre terapia,
      concat_ws(' ',pr.nombre,nullif(pr.segundo_nombre,''),pr.apellido) professional,
      case when t.coverage->>'type' in ('PARTICULAR','OBRA_SOCIAL','ART','CLUB') then t.coverage->>'type' else 'SIN_REGISTRO' end cov_type,
      coalesce(nullif(btrim(t.coverage->>'obra_social_id'),''),'') os_id,
      nullif(btrim(t.coverage->>'affiliate'),'') affiliate
    from marathon.turnos t
    join marathon.terapias th on th.id=t.terapia_id
    join marathon.profesionales pr on pr.id=t.profesional_id
    where t.estado='PRESENTE' and t.fecha>=d and t.fecha<e
      and (site='' or t.sede=site) and (therapy='' or t.terapia_id=therapy)
  ), scoped as (
    select * from base where (modality='' or cov_type=modality) and (insurance='' or os_id=insurance)
  ), labeled as (
    select s.*, p.apellido surname, concat_ws(' ',p.nombre,nullif(p.segundo_nombre,'')) name,
      case s.cov_type when 'OBRA_SOCIAL' then coalesce((select o.nombre from marathon.obras_sociales o where o.id=s.os_id),'Obra social sin identificar')
        when 'PARTICULAR' then 'Particular' when 'ART' then 'ART' when 'CLUB' then 'Club' else 'Sin registrar' end cobertura
    from scoped s join marathon.pacientes p on p.dni=s.dni
  ), grouped as (
    select dni, name, surname, cov_type, os_id, cobertura, max(affiliate) affiliate, count(*) done,
      jsonb_agg(jsonb_build_object('fecha',fecha,'terapia',terapia,'profesional',professional,'sede',sede) order by fecha,hora) sessions
    from labeled group by dni, name, surname, cov_type, os_id, cobertura
  ), withmark as (
    select g.*, (m.dni is not null) marked, u.display_name marked_by, m.cargado_en marked_at
    from grouped g
    left join marathon.facturacion_cargas m on m.periodo=per and m.modalidad=g.cov_type and m.obra_social_id=g.os_id and m.dni=g.dni
    left join marathon.app_users u on u.user_id=m.cargado_por
  )
  select
    jsonb_build_object(
      'patients',(select count(distinct dni) from grouped),
      'lines',(select count(*) from grouped),
      'sessions',(select coalesce(sum(done),0) from grouped),
      'marked',(select count(*) from withmark where marked),
      'missing_affiliate',(select count(*) from grouped where affiliate is null and cov_type in ('OBRA_SOCIAL','ART')),
      'modality',case when modality='' then 'Todas las modalidades' else modality end,
      'insurance',case when insurance='' then '' else coalesce((select o.nombre from marathon.obras_sociales o where o.id=insurance),insurance) end
    ),
    (select coalesce(jsonb_agg(jsonb_build_object(
      'dni',dni,'name',name,'surname',surname,'affiliate',coalesce(affiliate,''),
      'modality',cov_type,'os_id',os_id,'cobertura',cobertura,'done',done,'sessions',sessions,
      'marked',marked,'marked_by',coalesce(marked_by,''),'marked_at',marked_at
    ) order by cobertura, surname, name),'[]'::jsonb) from withmark)
    into summary, rows;
  return jsonb_build_object('rows',rows,'summary',summary,'generated_at',statement_timestamp(),'month',per,'next_month',to_char(e,'YYYY-MM'),'cut_local',cut);
end $body$;
revoke all on function public.marathon_billing(jsonb) from public,anon;
grant execute on function public.marathon_billing(jsonb) to authenticated;

