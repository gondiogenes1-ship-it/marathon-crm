-- Marathon 0.13.1 · grupo configurable del espacio físico compartido.
create table marathon.shared_space_config (
 singleton boolean primary key default true check(singleton),
 version bigint not null default 1 check(version>0),
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id)
);
create table marathon.shared_space_therapies (
 therapy_id text primary key references marathon.terapias(id)
);
alter table marathon.shared_space_config enable row level security;
alter table marathon.shared_space_therapies enable row level security;
create policy shared_space_config_read on marathon.shared_space_config for select to authenticated using((select marathon.active_user()));
create policy shared_space_therapies_read on marathon.shared_space_therapies for select to authenticated using((select marathon.active_user()));
revoke all on marathon.shared_space_config,marathon.shared_space_therapies from public,anon,authenticated;
grant select on marathon.shared_space_config,marathon.shared_space_therapies to authenticated;
-- Inicialización por nombres verificados del catálogo, sin IDs generados fijados en SQL.
with first_config as(insert into marathon.shared_space_config(singleton) values(true) returning singleton)
insert into marathon.shared_space_therapies(therapy_id)
select t.id from marathon.terapias t cross join first_config
where marathon.master_norm(t.nombre) in ('educacion fisica','ondas de choque','terapia ocupacional')
 or (marathon.master_norm(t.nombre)='convencional' and marathon.master_norm(t.especialidad)='kinesiologia');

create function public.marathon_shared_space_get()
returns jsonb language plpgsql stable security invoker set search_path='' as $fn$
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 return jsonb_build_object('version',(select version from marathon.shared_space_config where singleton),
  'therapy_ids',coalesce((select jsonb_agg(therapy_id order by therapy_id) from marathon.shared_space_therapies),'[]'::jsonb),
  'therapies',coalesce((select jsonb_agg(jsonb_build_object('id',id,'label',nombre,'estado',estado) order by nombre) from marathon.terapias),'[]'::jsonb));
end $fn$;
revoke all on function public.marathon_shared_space_get() from public,anon;
grant execute on function public.marathon_shared_space_get() to authenticated;

create function marathon.shared_space_save(p_therapy_ids jsonb,p_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare wanted text[];existing text[];v bigint;
begin
 if auth.uid() is null or not marathon.is_admin() then raise sqlstate '42501' using message='Solo Administración puede configurar el espacio compartido.';end if;
 if p_therapy_ids is null or jsonb_typeof(p_therapy_ids)<>'array' or jsonb_array_length(p_therapy_ids)>200
  or exists(select 1 from jsonb_array_elements(p_therapy_ids)x where jsonb_typeof(x)<>'string') then
  raise sqlstate '22023' using message='Elegí las terapias que comparten lugar.';
 end if;
 select coalesce(array_agg(distinct x order by x),'{}'::text[]) into wanted from jsonb_array_elements_text(p_therapy_ids)x;
 if exists(select 1 from unnest(wanted)x where not exists(select 1 from marathon.terapias t where t.id=x)) then
  raise sqlstate '22023' using message='La selección incluye una terapia inexistente. Volvé a cargar el catálogo.';
 end if;
 select version into v from marathon.shared_space_config where singleton for update;
 select coalesce(array_agg(therapy_id order by therapy_id),'{}'::text[]) into existing from marathon.shared_space_therapies;
 -- Repetir una petición ya aplicada no vuelve a escribirla.
 if wanted=existing then return public.marathon_shared_space_get();end if;
 if p_version is null or p_version<>v then raise sqlstate '40001' using message='Otra persona cambió la configuración. Volvé a cargarla antes de guardar.';end if;
 delete from marathon.shared_space_therapies;
 insert into marathon.shared_space_therapies(therapy_id) select unnest(wanted);
 update marathon.shared_space_config set version=version+1,updated_at=statement_timestamp(),updated_by=auth.uid() where singleton;
 return public.marathon_shared_space_get();
end $fn$;
revoke all on function marathon.shared_space_save(jsonb,bigint) from public,anon;
grant execute on function marathon.shared_space_save(jsonb,bigint) to authenticated;
create function public.marathon_shared_space_save(p_therapy_ids jsonb,p_version bigint)
returns jsonb language sql security invoker set search_path='' as $fn$
 select marathon.shared_space_save(p_therapy_ids,p_version)
$fn$;
revoke all on function public.marathon_shared_space_save(jsonb,bigint) from public,anon;
grant execute on function public.marathon_shared_space_save(jsonb,bigint) to authenticated;

-- Conserva los cupos existentes. Agrega solo el conteo informativo del espacio físico.
create or replace function public.marathon_agenda_slots(p_fecha text,p_sede text,p_prof text,p_therapy text)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare d date;begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 d=marathon.agenda_date(p_fecha);
 return (
 with slots as materialized (
  select s.*,actual.duration_min,d+s.hora::time starts,d+s.hora::time+make_interval(mins=>actual.duration_min) ends,
   to_jsonb(s)||jsonb_build_object('duration_min',actual.duration_min,
    'end_hour',to_char(s.hora::time+actual.duration_min*interval '1 minute','HH24:MI'),
    'shortened',actual.duration_min<t.duracion_min) payload
  from marathon.agenda_slots(d,p_sede,p_prof,p_therapy)s cross join marathon.terapias t
  cross join lateral(select marathon.session_minutes(d,p_sede,p_prof,s.hora::time,t.duracion_min) duration_min)actual
  where t.id=p_therapy
 ), shared as materialized (
  select x.dni,x.fecha+x.hora starts,x.fecha+x.hora+make_interval(mins=>x.duracion_min) ends
  from marathon.turnos x join marathon.shared_space_therapies g on g.therapy_id=x.terapia_id
  where x.fecha=d and x.sede=p_sede and x.estado in ('PENDIENTE','PRESENTE')
 ), member as(select exists(select 1 from marathon.shared_space_therapies where therapy_id=p_therapy) yes)
 select coalesce(jsonb_agg(s.payload||jsonb_build_object('shared_space',member.yes,
  'shared_space_count',case when member.yes then occupancy.people else null end) order by s.hora),'[]'::jsonb)
 from slots s cross join member
 cross join lateral (
  select coalesce(max((select count(distinct x.dni)::int from shared x where x.starts<=cut.at and cut.at<x.ends)),0) people
  from (select s.starts at union select x.starts from shared x where x.starts>s.starts and x.starts<s.ends)cut
 )occupancy
 );
end $fn$;
